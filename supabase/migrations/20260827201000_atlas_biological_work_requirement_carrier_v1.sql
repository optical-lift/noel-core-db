-- Atlas biological work requirement carrier v1
--
-- Governing boundary:
--   * biological_work_requirements owns whether a biological operation is still owed;
--   * tasks are human execution / decision / preparation / observation projections;
--   * execution readiness may block a task but may not resolve the biological requirement.
--
-- This migration is intentionally additive. It does not backfill live crops, alter
-- Home/Day selection, or change existing crop/production release functions.

create table atlas.biological_work_requirements (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  requirement_key text not null,
  subject_kind text not null,
  subject_id uuid not null,
  operation_key text not null,
  status text not null default 'active',
  protection_class text not null default 'standard',
  visibility_start_date date,
  earliest_lawful_date date,
  preferred_start_date date,
  preferred_end_date date,
  latest_safe_date date,
  recheck_date date,
  source_policy_key text,
  projected_task_id uuid references atlas.tasks(id) on delete set null,
  resolution_kind text,
  resolved_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint biological_work_requirements_id_farm_key unique(id,farm_id),
  constraint biological_work_requirements_requirement_key_nonempty
    check (btrim(requirement_key) <> ''),
  constraint biological_work_requirements_operation_key_nonempty
    check (btrim(operation_key) <> ''),
  constraint biological_work_requirements_subject_kind_check
    check (subject_kind in ('crop_cycle','production_lot','production_succession')),
  constraint biological_work_requirements_status_check
    check (status in ('active','resolved','terminated')),
  constraint biological_work_requirements_protection_class_check
    check (protection_class in ('protected','standard','resilient')),
  constraint biological_work_requirements_resolution_consistency
    check (
      (status='active' and resolution_kind is null and resolved_at is null)
      or (status in ('resolved','terminated') and resolution_kind is not null and resolved_at is not null)
    )
);

create unique index biological_work_requirements_farm_key_uidx
  on atlas.biological_work_requirements(farm_id, requirement_key);
create index biological_work_requirements_subject_idx
  on atlas.biological_work_requirements(subject_kind, subject_id, status);
create index biological_work_requirements_attention_idx
  on atlas.biological_work_requirements(farm_id, status, visibility_start_date, latest_safe_date, recheck_date);

alter table atlas.biological_work_requirements enable row level security;

create policy biological_work_requirements_read_operations
  on atlas.biological_work_requirements
  for select
  to authenticated
  using (atlas.can_read_farm_operations(farm_id));

grant select on atlas.biological_work_requirements to authenticated;
grant select, insert, update, delete on atlas.biological_work_requirements to service_role;

comment on table atlas.biological_work_requirements is
  'Canonical durable carrier that a biological operation is still owed. Execution readiness, capacity, weather, resources, destination, and UI presentation do not resolve this row.';
comment on column atlas.biological_work_requirements.subject_kind is
  'Canonical biological subject type. v1 supports crop_cycle, production_lot, and production_succession.';
comment on column atlas.biological_work_requirements.protection_class is
  'Continuity/escalation class; never a substitute for whether the requirement exists.';
comment on column atlas.biological_work_requirements.projected_task_id is
  'Current authoritative human execution projection when one exists; task state does not own requirement existence.';

alter table atlas.tasks
  add column biological_requirement_id uuid,
  add column biological_requirement_role text;

alter table atlas.tasks
  add constraint tasks_biological_requirement_pair_check
  check (
    (biological_requirement_id is null and biological_requirement_role is null)
    or (
      biological_requirement_id is not null
      and biological_requirement_role in ('execution','decision','preparation','observation')
    )
  ),
  add constraint tasks_biological_requirement_farm_fk
  foreign key (biological_requirement_id,farm_id)
  references atlas.biological_work_requirements(id,farm_id);

create index tasks_biological_requirement_idx
  on atlas.tasks(biological_requirement_id, biological_requirement_role)
  where biological_requirement_id is not null;

create unique index tasks_one_active_biological_execution_uidx
  on atlas.tasks(biological_requirement_id)
  where biological_requirement_id is not null
    and biological_requirement_role='execution'
    and status in ('open','blocked');

create unique index tasks_active_biological_projection_series_uidx
  on atlas.tasks(biological_requirement_id, biological_requirement_role, task_series_key)
  where biological_requirement_id is not null
    and biological_requirement_role <> 'execution'
    and task_series_key is not null
    and status in ('open','blocked');

comment on column atlas.tasks.biological_requirement_id is
  'Durable biological requirement represented by this human task. The task may block/hold without resolving the requirement.';
comment on column atlas.tasks.biological_requirement_role is
  'Role of this task relative to the biological requirement: execution, decision, preparation, or observation.';

alter table atlas.planned_work_occurrences
  add column biological_requirement_id uuid,
  add constraint planned_work_occurrences_biological_requirement_farm_fk
  foreign key (biological_requirement_id,farm_id)
  references atlas.biological_work_requirements(id,farm_id);

create index planned_work_occurrences_biological_requirement_idx
  on atlas.planned_work_occurrences(biological_requirement_id)
  where biological_requirement_id is not null;

comment on column atlas.planned_work_occurrences.biological_requirement_id is
  'Biological requirement whose schedule projection this occurrence represents. Cancelling/releasing the occurrence does not itself resolve the requirement.';

create or replace function atlas.assert_biological_requirement_subject_v1(
  p_farm_id uuid,
  p_subject_kind text,
  p_subject_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_exists boolean := false;
begin
  if p_farm_id is null or p_subject_id is null then
    raise exception 'Farm and biological subject are required.' using errcode='22023';
  end if;

  case p_subject_kind
    when 'crop_cycle' then
      select exists(
        select 1
        from atlas.crop_cycles cycle
        where cycle.id=p_subject_id
          and cycle.farm_id=p_farm_id
          and cycle.lifecycle_status in ('active','planned')
      ) into v_exists;
    when 'production_lot' then
      select exists(
        select 1
        from atlas.production_lots lot
        where lot.id=p_subject_id
          and lot.farm_id=p_farm_id
          and lot.lifecycle_status in ('active','planned')
      ) into v_exists;
    when 'production_succession' then
      select exists(
        select 1
        from atlas.production_successions succession
        join atlas.production_plans plan on plan.id=succession.production_plan_id
        where succession.id=p_subject_id
          and plan.farm_id=p_farm_id
          and succession.state not in ('skipped','cancelled','completed','complete','terminated','archived')
      ) into v_exists;
    else
      raise exception 'Unsupported biological requirement subject kind: %', p_subject_kind using errcode='22023';
  end case;

  if not v_exists then
    raise exception 'Biological requirement subject is missing, terminal, or belongs to another farm.' using errcode='23503';
  end if;
end;
$$;

revoke all on function atlas.assert_biological_requirement_subject_v1(uuid,text,uuid) from public, anon, authenticated;
grant execute on function atlas.assert_biological_requirement_subject_v1(uuid,text,uuid) to service_role;

create or replace function atlas.enforce_biological_requirement_subject_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  perform atlas.assert_biological_requirement_subject_v1(new.farm_id,new.subject_kind,new.subject_id);
  return new;
end;
$$;

revoke all on function atlas.enforce_biological_requirement_subject_v1() from public, anon, authenticated, service_role;

create trigger biological_work_requirements_subject_guard
before insert or update of farm_id,subject_kind,subject_id
on atlas.biological_work_requirements
for each row execute function atlas.enforce_biological_requirement_subject_v1();

create or replace function atlas.enforce_biological_requirement_projected_task_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  if new.projected_task_id is null then return new; end if;
  if not exists(
    select 1
    from atlas.tasks task
    where task.id=new.projected_task_id
      and task.farm_id=new.farm_id
      and task.biological_requirement_id=new.id
      and task.biological_requirement_role='execution'
  ) then
    raise exception 'Projected task must be the execution task linked back to this biological requirement.' using errcode='23503';
  end if;
  return new;
end;
$$;

revoke all on function atlas.enforce_biological_requirement_projected_task_v1() from public, anon, authenticated, service_role;

create trigger biological_work_requirements_projected_task_guard
before insert or update of farm_id,projected_task_id
on atlas.biological_work_requirements
for each row execute function atlas.enforce_biological_requirement_projected_task_v1();

create trigger biological_work_requirements_set_updated_at
before update on atlas.biological_work_requirements
for each row execute function atlas.set_updated_at();

create or replace function atlas.ensure_biological_work_requirement_v1(
  p_farm_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_operation_key text,
  p_requirement_key text default null,
  p_protection_class text default 'standard',
  p_visibility_start_date date default null,
  p_earliest_lawful_date date default null,
  p_preferred_start_date date default null,
  p_preferred_end_date date default null,
  p_latest_safe_date date default null,
  p_recheck_date date default null,
  p_source_policy_key text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_key text;
  v_requirement atlas.biological_work_requirements%rowtype;
  v_protection text;
  v_created boolean := false;
begin
  if p_operation_key is null or btrim(p_operation_key)='' then
    raise exception 'Biological operation key is required.' using errcode='22023';
  end if;
  if p_protection_class is null or p_protection_class not in ('protected','standard','resilient') then
    raise exception 'Unsupported biological protection class: %',p_protection_class using errcode='22023';
  end if;

  perform atlas.assert_biological_requirement_subject_v1(p_farm_id,p_subject_kind,p_subject_id);
  v_key:=coalesce(nullif(btrim(p_requirement_key),''),p_subject_kind||':'||p_subject_id::text||':'||btrim(p_operation_key));

  select * into v_requirement
  from atlas.biological_work_requirements requirement
  where requirement.farm_id=p_farm_id
    and requirement.requirement_key=v_key
  for update;

  if v_requirement.id is null then
    insert into atlas.biological_work_requirements(
      farm_id,requirement_key,subject_kind,subject_id,operation_key,status,protection_class,
      visibility_start_date,earliest_lawful_date,preferred_start_date,preferred_end_date,
      latest_safe_date,recheck_date,source_policy_key,metadata
    ) values (
      p_farm_id,v_key,p_subject_kind,p_subject_id,btrim(p_operation_key),'active',p_protection_class,
      p_visibility_start_date,p_earliest_lawful_date,p_preferred_start_date,p_preferred_end_date,
      p_latest_safe_date,p_recheck_date,nullif(btrim(p_source_policy_key),''),coalesce(p_metadata,'{}'::jsonb)
    )
    on conflict (farm_id,requirement_key) do nothing
    returning * into v_requirement;

    if v_requirement.id is not null then
      v_created:=true;
    else
      select * into v_requirement
      from atlas.biological_work_requirements requirement
      where requirement.farm_id=p_farm_id
        and requirement.requirement_key=v_key
      for update;
    end if;
  end if;

  if not v_created then
    if v_requirement.id is null then
      raise exception 'Biological requirement could not be established.' using errcode='P0001';
    end if;
    if v_requirement.subject_kind<>p_subject_kind
       or v_requirement.subject_id<>p_subject_id
       or v_requirement.operation_key<>btrim(p_operation_key) then
      raise exception 'Biological requirement key % is already bound to different subject/operation truth.',v_key using errcode='23505';
    end if;

    if v_requirement.status<>'active' then
      return jsonb_build_object(
        'contractVersion','biological_work_requirement_v1',
        'requirementId',v_requirement.id,
        'requirementKey',v_requirement.requirement_key,
        'status',v_requirement.status,
        'created',false,
        'reactivated',false,
        'truthBoundary','A resolved/terminated requirement is not silently reopened. Create a new stable requirement key for a genuinely new biological operation.'
      );
    end if;

    v_protection:=case
      when v_requirement.protection_class='protected' or p_protection_class='protected' then 'protected'
      when v_requirement.protection_class='standard' or p_protection_class='standard' then 'standard'
      else 'resilient'
    end;

    update atlas.biological_work_requirements
    set protection_class=v_protection,
        visibility_start_date=coalesce(p_visibility_start_date,visibility_start_date),
        earliest_lawful_date=coalesce(p_earliest_lawful_date,earliest_lawful_date),
        preferred_start_date=coalesce(p_preferred_start_date,preferred_start_date),
        preferred_end_date=coalesce(p_preferred_end_date,preferred_end_date),
        latest_safe_date=coalesce(p_latest_safe_date,latest_safe_date),
        recheck_date=coalesce(p_recheck_date,recheck_date),
        source_policy_key=coalesce(nullif(btrim(p_source_policy_key),''),source_policy_key),
        metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)
    where id=v_requirement.id
    returning * into v_requirement;
  end if;

  return jsonb_build_object(
    'contractVersion','biological_work_requirement_v1',
    'requirementId',v_requirement.id,
    'requirementKey',v_requirement.requirement_key,
    'farmId',v_requirement.farm_id,
    'subjectKind',v_requirement.subject_kind,
    'subjectId',v_requirement.subject_id,
    'operationKey',v_requirement.operation_key,
    'status',v_requirement.status,
    'protectionClass',v_requirement.protection_class,
    'visibilityStartDate',v_requirement.visibility_start_date,
    'earliestLawfulDate',v_requirement.earliest_lawful_date,
    'preferredStartDate',v_requirement.preferred_start_date,
    'preferredEndDate',v_requirement.preferred_end_date,
    'latestSafeDate',v_requirement.latest_safe_date,
    'recheckDate',v_requirement.recheck_date,
    'created',v_created,
    'truthBoundary','Requirement existence is independent from task execution readiness.'
  );
end;
$$;

revoke all on function atlas.ensure_biological_work_requirement_v1(uuid,text,uuid,text,text,text,date,date,date,date,date,date,text,jsonb) from public, anon, authenticated;
grant execute on function atlas.ensure_biological_work_requirement_v1(uuid,text,uuid,text,text,text,date,date,date,date,date,date,text,jsonb) to service_role;

create or replace function atlas.project_biological_requirement_task_v1(
  p_requirement_id uuid,
  p_role text,
  p_title text,
  p_task_type text,
  p_assigned_membership_id uuid default null,
  p_projection_key text default null,
  p_action_key text default null,
  p_operation_class text default null,
  p_work_class text default 'standard',
  p_due_date date default null,
  p_priority text default null,
  p_execution_ready boolean default true,
  p_blocker_text text default null,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_visibility_scope text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_requirement atlas.biological_work_requirements%rowtype;
  v_task atlas.tasks%rowtype;
  v_organization_id uuid;
  v_projection_key text;
  v_series_key text;
  v_status text;
  v_due date;
  v_priority text;
  v_visibility text;
  v_execution_ready boolean:=coalesce(p_execution_ready,true);
  v_created boolean:=false;
begin
  if p_role is null or p_role not in ('execution','decision','preparation','observation') then
    raise exception 'Unsupported biological task projection role: %',p_role using errcode='22023';
  end if;
  if p_title is null or btrim(p_title)='' or p_task_type is null or btrim(p_task_type)='' then
    raise exception 'Projected biological task title and task type are required.' using errcode='22023';
  end if;

  select * into v_requirement
  from atlas.biological_work_requirements requirement
  where requirement.id=p_requirement_id
  for update;
  if v_requirement.id is null then
    raise exception 'Biological work requirement was not found.' using errcode='P0002';
  end if;
  if v_requirement.status<>'active' then
    raise exception 'Only active biological work requirements may project active human tasks.' using errcode='22023';
  end if;

  if p_assigned_membership_id is not null and not exists(
    select 1 from atlas.farm_memberships membership
    where membership.id=p_assigned_membership_id
      and membership.farm_id=v_requirement.farm_id
      and membership.active=true
  ) then
    raise exception 'Projected task assignee must be an active membership on the requirement farm.' using errcode='23503';
  end if;

  select farm.organization_id into v_organization_id
  from atlas.farms farm
  where farm.id=v_requirement.farm_id;

  v_projection_key:=coalesce(nullif(btrim(p_projection_key),''),p_role);
  v_series_key:='bwr:'||v_requirement.id::text||':'||p_role||':'||v_projection_key;
  v_status:=case when v_execution_ready then 'open' else 'blocked' end;
  v_due:=coalesce(p_due_date,v_requirement.recheck_date,v_requirement.preferred_start_date,v_requirement.earliest_lawful_date,v_requirement.visibility_start_date,v_requirement.latest_safe_date);
  v_priority:=coalesce(nullif(btrim(p_priority),''),case when v_requirement.protection_class='protected' then 'high' else 'normal' end);
  v_visibility:=coalesce(nullif(btrim(p_visibility_scope),''),case when p_role='decision' then 'management' else 'assigned_worker' end);

  if p_role='execution' and v_visibility='system_internal' then
    raise exception 'Biological execution projections may not be system_internal.' using errcode='22023';
  end if;

  if p_role='execution' then
    select * into v_task
    from atlas.tasks task
    where task.biological_requirement_id=v_requirement.id
      and task.biological_requirement_role='execution'
      and task.status in ('open','blocked')
    order by task.created_at,task.id
    for update
    limit 1;
  else
    select * into v_task
    from atlas.tasks task
    where task.biological_requirement_id=v_requirement.id
      and task.biological_requirement_role=p_role
      and task.task_series_key=v_series_key
      and task.status in ('open','blocked')
    order by task.created_at,task.id
    for update
    limit 1;
  end if;

  if v_task.id is null then
    insert into atlas.tasks(
      farm_id,organization_id,title,task_type,status,priority,due_date,blocker_text,note,metadata,
      generated_from,generated_from_id,action_key,operation_class,operation_class_source,work_class,
      task_series_key,engine_instance_key,visibility_scope,assigned_membership_id,origin_kind,
      work_lane,commitment_kind,task_scope,biological_requirement_id,biological_requirement_role
    ) values (
      v_requirement.farm_id,v_organization_id,btrim(p_title),btrim(p_task_type),v_status,v_priority,v_due,
      case when v_execution_ready then null else coalesce(nullif(btrim(p_blocker_text),''),'Execution requirements are not yet satisfied.') end,
      p_note,
      coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
        'biological_requirement_id',v_requirement.id,
        'biological_requirement_key',v_requirement.requirement_key,
        'biological_operation_key',v_requirement.operation_key,
        'biological_protection_class',v_requirement.protection_class,
        'bwr_projection',true,
        'bwr_execution_ready',v_execution_ready,
        'bwr_truth_boundary','Task state may block/hold without resolving the biological requirement.'
      ),
      'biological_work_requirement',v_requirement.id,p_action_key,p_operation_class,
      case when p_operation_class is null then null else 'biological_work_requirement' end,
      p_work_class,v_series_key,v_series_key,v_visibility,p_assigned_membership_id,'generated',
      case when p_role='decision' then 'required' else 'process_continuation' end,
      'dependency','farm_operation',v_requirement.id,p_role
    ) returning * into v_task;
    v_created:=true;
  else
    update atlas.tasks
    set title=btrim(p_title),
        task_type=btrim(p_task_type),
        status=v_status,
        priority=v_priority,
        due_date=coalesce(v_due,due_date),
        blocker_text=case when v_execution_ready then null else coalesce(nullif(btrim(p_blocker_text),''),'Execution requirements are not yet satisfied.') end,
        note=coalesce(p_note,note),
        metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
          'biological_requirement_id',v_requirement.id,
          'biological_requirement_key',v_requirement.requirement_key,
          'biological_operation_key',v_requirement.operation_key,
          'biological_protection_class',v_requirement.protection_class,
          'bwr_projection',true,
          'bwr_execution_ready',v_execution_ready,
          'bwr_truth_boundary','Task state may block/hold without resolving the biological requirement.'
        ),
        action_key=coalesce(p_action_key,action_key),
        operation_class=coalesce(p_operation_class,operation_class),
        operation_class_source=case when coalesce(p_operation_class,operation_class) is null then operation_class_source else 'biological_work_requirement' end,
        work_class=coalesce(nullif(btrim(p_work_class),''),work_class),
        visibility_scope=v_visibility,
        assigned_membership_id=coalesce(p_assigned_membership_id,assigned_membership_id),
        work_lane=case when p_role='decision' then 'required' else 'process_continuation' end,
        commitment_kind='dependency',
        biological_requirement_id=v_requirement.id,
        biological_requirement_role=p_role,
        updated_at=now()
    where id=v_task.id
    returning * into v_task;
  end if;

  if p_role='execution' and v_requirement.projected_task_id is distinct from v_task.id then
    update atlas.biological_work_requirements
    set projected_task_id=v_task.id
    where id=v_requirement.id;
  end if;

  return jsonb_build_object(
    'contractVersion','biological_requirement_task_projection_v1',
    'requirementId',v_requirement.id,
    'taskId',v_task.id,
    'role',p_role,
    'status',v_task.status,
    'executionReady',v_execution_ready,
    'created',v_created,
    'taskSeriesKey',v_task.task_series_key,
    'truthBoundary','This task is a projection of durable biological requirement truth.'
  );
end;
$$;

revoke all on function atlas.project_biological_requirement_task_v1(uuid,text,text,text,uuid,text,text,text,text,date,text,boolean,text,text,jsonb,text) from public, anon, authenticated;
grant execute on function atlas.project_biological_requirement_task_v1(uuid,text,text,text,uuid,text,text,text,text,date,text,boolean,text,text,jsonb,text) to service_role;

create or replace function atlas.refresh_biological_requirement_execution_v1(
  p_requirement_id uuid,
  p_blocker_text text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_requirement atlas.biological_work_requirements%rowtype;
  v_task atlas.tasks%rowtype;
  v_evaluation jsonb;
  v_ready boolean:=false;
begin
  select * into v_requirement
  from atlas.biological_work_requirements requirement
  where requirement.id=p_requirement_id
  for update;
  if v_requirement.id is null then
    raise exception 'Biological work requirement was not found.' using errcode='P0002';
  end if;
  if v_requirement.status<>'active' then
    return jsonb_build_object(
      'contractVersion','biological_requirement_execution_refresh_v1',
      'requirementId',v_requirement.id,
      'status',v_requirement.status,
      'refreshed',false,
      'reason','requirement_not_active'
    );
  end if;

  select * into v_task
  from atlas.tasks task
  where task.biological_requirement_id=v_requirement.id
    and task.biological_requirement_role='execution'
    and task.status in ('open','blocked')
  order by case when task.id=v_requirement.projected_task_id then 0 else 1 end,task.created_at,task.id
  for update
  limit 1;

  if v_task.id is null then
    return jsonb_build_object(
      'contractVersion','biological_requirement_execution_refresh_v1',
      'requirementId',v_requirement.id,
      'refreshed',false,
      'reason','no_active_execution_projection'
    );
  end if;

  if v_task.generated_from is distinct from 'biological_work_requirement'
     or v_task.generated_from_id is distinct from v_requirement.id
     or coalesce((v_task.metadata->>'bwr_projection')::boolean,false)=false then
    raise exception 'Execution projection is not owned by the biological requirement projector.' using errcode='42501';
  end if;

  v_evaluation:=atlas.task_execution_requirement_evaluation_v1(v_task.id);
  v_ready:=coalesce((v_evaluation->>'executionReady')::boolean,false);

  update atlas.tasks
  set status=case when v_ready then 'open' else 'blocked' end,
      due_date=coalesce(due_date,v_requirement.recheck_date,v_requirement.preferred_start_date,v_requirement.earliest_lawful_date,v_requirement.visibility_start_date,v_requirement.latest_safe_date),
      blocker_text=case when v_ready then null else coalesce(nullif(btrim(p_blocker_text),''),'Execution requirements are not yet satisfied.') end,
      visibility_scope=case when visibility_scope='system_internal' then 'assigned_worker' else visibility_scope end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'bwr_execution_ready',v_ready,
        'bwr_execution_evaluation',v_evaluation,
        'bwr_execution_refreshed_at',now()
      ),
      updated_at=now()
  where id=v_task.id
  returning * into v_task;

  update atlas.biological_work_requirements
  set projected_task_id=v_task.id
  where id=v_requirement.id;

  return jsonb_build_object(
    'contractVersion','biological_requirement_execution_refresh_v1',
    'requirementId',v_requirement.id,
    'taskId',v_task.id,
    'requirementStatus','active',
    'taskStatus',v_task.status,
    'executionReady',v_ready,
    'refreshed',true,
    'truthBoundary','Execution readiness changed the task projection only; the biological requirement remained active.'
  );
end;
$$;

revoke all on function atlas.refresh_biological_requirement_execution_v1(uuid,text) from public, anon, authenticated;
grant execute on function atlas.refresh_biological_requirement_execution_v1(uuid,text) to service_role;

create or replace function atlas.resolve_biological_work_requirement_v1(
  p_requirement_id uuid,
  p_resolution_kind text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_requirement atlas.biological_work_requirements%rowtype;
  v_terminal_status text;
begin
  if p_resolution_kind not in (
    'operation_completed',
    'crop_terminated',
    'production_lot_terminated',
    'production_succession_terminated',
    'harvest_reconciled',
    'lifecycle_superseded',
    'owner_terminated',
    'subject_lost'
  ) then
    raise exception 'Resolution kind % is not a lawful biological resolution in v1.',p_resolution_kind using errcode='22023';
  end if;

  select * into v_requirement
  from atlas.biological_work_requirements requirement
  where requirement.id=p_requirement_id
  for update;
  if v_requirement.id is null then
    raise exception 'Biological work requirement was not found.' using errcode='P0002';
  end if;

  if v_requirement.status<>'active' then
    return jsonb_build_object(
      'contractVersion','biological_work_requirement_resolution_v1',
      'requirementId',v_requirement.id,
      'status',v_requirement.status,
      'resolutionKind',v_requirement.resolution_kind,
      'resolvedAt',v_requirement.resolved_at,
      'resolved',false,
      'alreadyFinal',true
    );
  end if;

  v_terminal_status:=case
    when p_resolution_kind in ('crop_terminated','production_lot_terminated','production_succession_terminated','owner_terminated','subject_lost') then 'terminated'
    else 'resolved'
  end;

  update atlas.biological_work_requirements
  set status=v_terminal_status,
      resolution_kind=p_resolution_kind,
      resolved_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)
  where id=v_requirement.id
  returning * into v_requirement;

  return jsonb_build_object(
    'contractVersion','biological_work_requirement_resolution_v1',
    'requirementId',v_requirement.id,
    'status',v_requirement.status,
    'resolutionKind',v_requirement.resolution_kind,
    'resolvedAt',v_requirement.resolved_at,
    'resolved',true,
    'truthBoundary','Only an explicit governed biological outcome resolved the durable requirement.'
  );
end;
$$;

revoke all on function atlas.resolve_biological_work_requirement_v1(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function atlas.resolve_biological_work_requirement_v1(uuid,text,jsonb) to service_role;
