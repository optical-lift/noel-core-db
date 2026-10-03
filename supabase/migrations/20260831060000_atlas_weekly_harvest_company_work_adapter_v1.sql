-- Atlas Weekly Harvest Company Work adapter v1
--
-- Governing boundary:
--   institutional requirement/work exists first;
--   a legacy planned occurrence/task is only an execution carrier;
--   allocation is downstream custody, not work identity;
--   retiring a carrier does not erase or satisfy institutional work.

begin;

alter table atlas.work_requirements
  add column if not exists stable_key text;

alter table atlas.work_items
  add column if not exists stable_key text;

create unique index if not exists work_requirements_org_stable_key_uq
  on atlas.work_requirements (organization_id, stable_key)
  where stable_key is not null;

create unique index if not exists work_items_org_stable_key_uq
  on atlas.work_items (organization_id, stable_key)
  where stable_key is not null;

comment on column atlas.work_requirements.stable_key is
  'Optional durable institutional identity for idempotent requirement materialization. It must not encode assignee or portal identity.';

comment on column atlas.work_items.stable_key is
  'Optional durable institutional work identity. Execution carriers and assignees are separate downstream relations.';

create table if not exists atlas.work_execution_adapters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  organization_unit_id uuid,
  work_item_id uuid not null,
  adapter_kind text not null,
  planned_occurrence_id uuid references atlas.planned_work_occurrences(id) on delete restrict,
  task_id uuid references atlas.tasks(id) on delete restrict,
  state text not null default 'active'
    check (state in ('active','completed','retired','failed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  retired_at timestamptz,
  check (btrim(adapter_kind) <> ''),
  check (planned_occurrence_id is not null or task_id is not null),
  check (completed_at is null or state = 'completed'),
  check (retired_at is null or state = 'retired')
);

comment on table atlas.work_execution_adapters is
  'Transitional execution-carrier links from canonical Company Work to legacy planning/task surfaces. Adapters may disappear or be replaced without changing work identity.';

alter table atlas.work_execution_adapters
  drop constraint if exists work_execution_adapters_work_org_fk,
  add constraint work_execution_adapters_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items (organization_id, id)
    on delete restrict;

alter table atlas.work_execution_adapters
  drop constraint if exists work_execution_adapters_unit_org_fk,
  add constraint work_execution_adapters_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

create unique index if not exists work_execution_adapters_occurrence_uq
  on atlas.work_execution_adapters (planned_occurrence_id)
  where planned_occurrence_id is not null;

create unique index if not exists work_execution_adapters_task_uq
  on atlas.work_execution_adapters (task_id)
  where task_id is not null;

create index if not exists work_execution_adapters_work_idx
  on atlas.work_execution_adapters (organization_id, work_item_id, state);

revoke all on table atlas.work_execution_adapters from public, anon, authenticated;
grant select, insert, update, delete on table atlas.work_execution_adapters to service_role;

create or replace function atlas.ensure_weekly_harvest_company_work_v1(
  p_occurrence_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_farm atlas.farms%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_work atlas.work_items%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_time atlas.work_time_contracts%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_assignee_user_id uuid;
  v_assignee_org_membership_id uuid;
  v_work_key text;
  v_requirement_key text;
  v_day_start timestamptz;
  v_day_end timestamptz;
begin
  select * into v_occurrence
  from atlas.planned_work_occurrences
  where id = p_occurrence_id;

  if v_occurrence.id is null then
    raise exception 'Weekly Harvest occurrence not found.' using errcode = 'P0002';
  end if;

  if coalesce(v_occurrence.task_payload->>'task_series_key','') <> 'anna_harvest_thursday_weekly'
     and coalesce(v_occurrence.occurrence_key,'') not like 'recurring:anna_harvest_thursday_weekly:%' then
    raise exception 'Occurrence is not the transitional weekly Harvest carrier.' using errcode = '22023';
  end if;

  if coalesce(v_occurrence.task_payload->>'task_type','') <> 'harvest' then
    raise exception 'Weekly Harvest carrier must retain harvest task semantics.' using errcode = '22023';
  end if;

  if v_occurrence.planned_due_date is null then
    raise exception 'Weekly Harvest occurrence requires a service date.' using errcode = '22023';
  end if;

  select * into v_farm
  from atlas.farms
  where id = v_occurrence.farm_id;

  if v_farm.id is null then
    raise exception 'Weekly Harvest farm not found.' using errcode = 'P0002';
  end if;

  if v_farm.organization_id is null or v_farm.organization_unit_id is null then
    raise exception 'Weekly Harvest requires institutional organization and Organization Unit custody.' using errcode = '23514';
  end if;

  v_work_key := 'weekly_harvest:' || v_farm.stable_key || ':' || v_occurrence.planned_due_date::text;
  v_requirement_key := v_work_key || ':requirement';
  v_day_start := (v_occurrence.planned_due_date::timestamp at time zone 'America/Chicago');
  v_day_end := ((v_occurrence.planned_due_date + 1)::timestamp at time zone 'America/Chicago');

  insert into atlas.work_requirements (
    organization_id,
    organization_unit_id,
    stable_key,
    requirement_kind,
    summary,
    source_object_type,
    source_object_id,
    state,
    established_at,
    requirement_began_at,
    earliest_relevant_at,
    latest_satisfactory_at,
    consequence_of_delay,
    jurisdiction_key,
    metadata
  ) values (
    v_farm.organization_id,
    v_farm.organization_unit_id,
    v_requirement_key,
    'operational',
    'Harvest stems',
    'planned_work_occurrence',
    v_occurrence.id,
    'active',
    now(),
    v_day_start,
    v_day_start,
    v_day_end,
    jsonb_build_object(
      'kind','perishable_harvest_window',
      'statement','Harvestable crop condition changes with time; the institutional requirement persists independently of its worker-facing carrier.'
    ),
    'operations.harvest',
    jsonb_build_object(
      'institutionalWork',true,
      'organizationUnitId',v_farm.organization_unit_id,
      'farmId',v_farm.id,
      'serviceDate',v_occurrence.planned_due_date,
      'legacyCarrierKind','weekly_harvest_occurrence'
    )
  )
  on conflict (organization_id, stable_key) where stable_key is not null
  do update set
    organization_unit_id = excluded.organization_unit_id,
    source_object_type = excluded.source_object_type,
    source_object_id = excluded.source_object_id,
    requirement_began_at = excluded.requirement_began_at,
    earliest_relevant_at = excluded.earliest_relevant_at,
    latest_satisfactory_at = excluded.latest_satisfactory_at,
    jurisdiction_key = excluded.jurisdiction_key,
    metadata = atlas.work_requirements.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_requirement;

  insert into atlas.work_items (
    organization_id,
    organization_unit_id,
    stable_key,
    title,
    instructions,
    work_state,
    operation_class,
    jurisdiction_key,
    source_object_type,
    source_object_id,
    result_contract_key,
    metadata
  ) values (
    v_farm.organization_id,
    v_farm.organization_unit_id,
    v_work_key,
    'Harvest Stems',
    'Resolve the crop rows earned by current field truth. The worker-facing task is an execution adapter, not the source of this work.',
    'open',
    'harvest',
    'operations.harvest',
    'planned_work_occurrence',
    v_occurrence.id,
    'weekly_harvest_round_v2',
    jsonb_build_object(
      'institutionalWork',true,
      'organizationUnitId',v_farm.organization_unit_id,
      'farmId',v_farm.id,
      'serviceDate',v_occurrence.planned_due_date,
      'legacyCarrierSeries','anna_harvest_thursday_weekly',
      'legacyCarrierIsAuthority',false
    )
  )
  on conflict (organization_id, stable_key) where stable_key is not null
  do update set
    organization_unit_id = excluded.organization_unit_id,
    source_object_type = excluded.source_object_type,
    source_object_id = excluded.source_object_id,
    jurisdiction_key = excluded.jurisdiction_key,
    metadata = atlas.work_items.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_work;

  insert into atlas.work_requirement_links (
    organization_id,
    requirement_id,
    work_item_id,
    link_role,
    active,
    metadata
  ) values (
    v_farm.organization_id,
    v_requirement.id,
    v_work.id,
    'resolves',
    true,
    jsonb_build_object('source','weekly_harvest_company_work_adapter_v1')
  )
  on conflict (requirement_id, work_item_id, link_role)
  do update set active = true,
                metadata = atlas.work_requirement_links.metadata || excluded.metadata;

  if v_work.work_state = 'open' then
    select * into v_time
    from atlas.work_time_contracts
    where organization_id = v_farm.organization_id
      and work_item_id = v_work.id
      and contract_state = 'active'
    order by created_at desc
    limit 1;

    if v_time.id is null then
      insert into atlas.work_time_contracts (
        organization_id,
        work_item_id,
        contract_state,
        earliest_lawful_at,
        latest_lawful_at,
        hard_finish_at,
        movement_policy,
        consequence_of_delay,
        source_kind,
        source_id,
        source_confidence,
        metadata
      ) values (
        v_farm.organization_id,
        v_work.id,
        'active',
        v_day_start,
        v_day_end,
        v_day_end,
        'bounded',
        jsonb_build_object('kind','perishable_harvest_window'),
        'legacy_planned_occurrence',
        v_occurrence.id,
        1,
        jsonb_build_object('serviceDate',v_occurrence.planned_due_date,'clockTimeSpecified',false)
      ) returning * into v_time;
    else
      update atlas.work_time_contracts
      set earliest_lawful_at = v_day_start,
          latest_lawful_at = v_day_end,
          hard_finish_at = v_day_end,
          movement_policy = 'bounded',
          source_kind = 'legacy_planned_occurrence',
          source_id = v_occurrence.id,
          source_confidence = 1,
          metadata = metadata || jsonb_build_object('serviceDate',v_occurrence.planned_due_date,'clockTimeSpecified',false),
          updated_at = now()
      where id = v_time.id
      returning * into v_time;
    end if;
  end if;

  begin
    v_assignee_user_id := nullif(v_occurrence.task_payload->>'assigned_user_id','')::uuid;
  exception when others then
    v_assignee_user_id := null;
  end;

  if v_assignee_user_id is not null then
    select om.id into v_assignee_org_membership_id
    from atlas.organization_memberships om
    where om.organization_id = v_farm.organization_id
      and om.user_id = v_assignee_user_id
      and om.active
    order by om.created_at
    limit 1;
  end if;

  if v_work.work_state = 'open' then
    select * into v_allocation
    from atlas.work_allocations
    where organization_id = v_farm.organization_id
      and work_item_id = v_work.id
      and state = 'active'
      and allocation_role = 'responsible'
    order by allocated_at desc
    limit 1;

    if v_assignee_org_membership_id is null then
      if v_allocation.id is not null then
        update atlas.work_allocations
        set state = 'released',
            released_at = now(),
            release_reason = 'Legacy execution carrier currently has no institutionally resolvable assignee.',
            updated_at = now()
        where id = v_allocation.id;
      end if;
      v_allocation := null;
    elsif v_allocation.id is null then
      insert into atlas.work_allocations (
        organization_id,
        work_item_id,
        assignee_membership_id,
        allocation_role,
        state,
        allocated_at,
        metadata
      ) values (
        v_farm.organization_id,
        v_work.id,
        v_assignee_org_membership_id,
        'responsible',
        'active',
        now(),
        jsonb_build_object(
          'source','legacy_weekly_harvest_occurrence_assignment',
          'assignmentIsWorkIdentity',false,
          'plannedOccurrenceId',v_occurrence.id
        )
      ) returning * into v_allocation;
    elsif v_allocation.assignee_membership_id is distinct from v_assignee_org_membership_id then
      update atlas.work_allocations
      set state = 'released',
          released_at = now(),
          release_reason = 'Legacy execution carrier assignment changed.',
          updated_at = now()
      where id = v_allocation.id;

      insert into atlas.work_allocations (
        organization_id,
        work_item_id,
        assignee_membership_id,
        allocation_role,
        state,
        allocated_at,
        metadata
      ) values (
        v_farm.organization_id,
        v_work.id,
        v_assignee_org_membership_id,
        'responsible',
        'active',
        now(),
        jsonb_build_object(
          'source','legacy_weekly_harvest_occurrence_assignment',
          'assignmentIsWorkIdentity',false,
          'plannedOccurrenceId',v_occurrence.id
        )
      ) returning * into v_allocation;
    end if;
  end if;

  select * into v_adapter
  from atlas.work_execution_adapters
  where planned_occurrence_id = v_occurrence.id
  limit 1;

  if v_adapter.id is null then
    insert into atlas.work_execution_adapters (
      organization_id,
      organization_unit_id,
      work_item_id,
      adapter_kind,
      planned_occurrence_id,
      task_id,
      state,
      metadata
    ) values (
      v_farm.organization_id,
      v_farm.organization_unit_id,
      v_work.id,
      'legacy_planned_occurrence_task',
      v_occurrence.id,
      v_occurrence.released_task_id,
      case when v_work.work_state = 'completed' then 'completed' else 'active' end,
      jsonb_build_object(
        'legacySeries','anna_harvest_thursday_weekly',
        'carrierCreatesWork',false,
        'serviceDate',v_occurrence.planned_due_date
      )
    ) returning * into v_adapter;
  else
    update atlas.work_execution_adapters
    set organization_id = v_farm.organization_id,
        organization_unit_id = v_farm.organization_unit_id,
        work_item_id = v_work.id,
        task_id = coalesce(v_occurrence.released_task_id, task_id),
        state = case
          when v_work.work_state = 'completed' then 'completed'
          else 'active'
        end,
        completed_at = case when v_work.work_state = 'completed' then coalesce(completed_at,now()) else null end,
        retired_at = null,
        metadata = metadata || jsonb_build_object(
          'legacySeries','anna_harvest_thursday_weekly',
          'carrierCreatesWork',false,
          'serviceDate',v_occurrence.planned_due_date
        ),
        updated_at = now()
    where id = v_adapter.id
    returning * into v_adapter;
  end if;

  if v_work.work_state = 'open' and v_adapter.task_id is not null then
    update atlas.work_planning_conflicts
    set state = 'resolved',
        resolution_kind = 'replacement_execution_carrier_bound',
        resolution_note = 'A worker-facing execution carrier is bound again; canonical work identity never changed.',
        resolved_at = now(),
        updated_at = now()
    where organization_id = v_farm.organization_id
      and work_item_id = v_work.id
      and state = 'open'
      and conflict_kind = 'other'
      and metadata->>'companyWorkAdapterId' = v_adapter.id::text;
  end if;

  return jsonb_build_object(
    'contractVersion','weekly_harvest_company_work_adapter_v1',
    'organizationId',v_farm.organization_id,
    'organizationUnitId',v_farm.organization_unit_id,
    'requirementId',v_requirement.id,
    'workItemId',v_work.id,
    'workState',v_work.work_state,
    'allocationId',v_allocation.id,
    'assigneeOrganizationMembershipId',v_allocation.assignee_membership_id,
    'adapterId',v_adapter.id,
    'plannedOccurrenceId',v_occurrence.id,
    'taskId',v_adapter.task_id,
    'serviceDate',v_occurrence.planned_due_date
  );
end;
$function$;

comment on function atlas.ensure_weekly_harvest_company_work_v1(uuid) is
  'Ensures institutional Company Work for a transitional weekly Harvest occurrence. Organization + Organization Unit define custody; allocation and legacy task/occurrence are downstream adapters.';

revoke all on function atlas.ensure_weekly_harvest_company_work_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.ensure_weekly_harvest_company_work_v1(uuid) to service_role;

create or replace function atlas.retire_weekly_harvest_company_work_adapter_v1(
  p_occurrence_id uuid,
  p_task_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
begin
  select a.* into v_adapter
  from atlas.work_execution_adapters a
  where (p_task_id is not null and a.task_id = p_task_id)
     or (p_occurrence_id is not null and a.planned_occurrence_id = p_occurrence_id)
  order by a.updated_at desc
  limit 1;

  if v_adapter.id is null then
    return;
  end if;

  select * into v_work
  from atlas.work_items
  where organization_id = v_adapter.organization_id
    and id = v_adapter.work_item_id;

  if v_work.id is null or v_work.work_state <> 'open' then
    return;
  end if;

  update atlas.work_execution_adapters
  set state = 'retired',
      retired_at = now(),
      metadata = metadata || jsonb_build_object('retireReason',coalesce(nullif(btrim(p_reason),''),'Legacy execution carrier retired.')),
      updated_at = now()
  where id = v_adapter.id;

  update atlas.work_allocations
  set state = 'released',
      released_at = now(),
      release_reason = coalesce(nullif(btrim(p_reason),''),'Legacy execution carrier retired.'),
      updated_at = now()
  where organization_id = v_adapter.organization_id
    and work_item_id = v_adapter.work_item_id
    and state = 'active'
    and allocation_role = 'responsible';

  if not exists (
    select 1
    from atlas.work_planning_conflicts c
    where c.organization_id = v_adapter.organization_id
      and c.work_item_id = v_adapter.work_item_id
      and c.state = 'open'
      and c.conflict_kind = 'other'
      and c.metadata->>'companyWorkAdapterId' = v_adapter.id::text
  ) then
    insert into atlas.work_planning_conflicts (
      organization_id,
      work_item_id,
      conflict_kind,
      detected_at,
      required_by,
      reason,
      state,
      metadata
    )
    select
      v_adapter.organization_id,
      v_adapter.work_item_id,
      'other',
      now(),
      tc.hard_finish_at,
      coalesce(nullif(btrim(p_reason),''),'Legacy execution carrier retired while institutional work remains open.'),
      'open',
      jsonb_build_object(
        'companyWorkAdapterId',v_adapter.id,
        'carrierRetirementDoesNotCancelWork',true
      )
    from (select 1) seed
    left join lateral (
      select t.hard_finish_at
      from atlas.work_time_contracts t
      where t.organization_id = v_adapter.organization_id
        and t.work_item_id = v_adapter.work_item_id
        and t.contract_state = 'active'
      order by t.created_at desc
      limit 1
    ) tc on true;
  end if;
end;
$function$;

revoke all on function atlas.retire_weekly_harvest_company_work_adapter_v1(uuid,uuid,text) from public, anon, authenticated;
grant execute on function atlas.retire_weekly_harvest_company_work_adapter_v1(uuid,uuid,text) to service_role;

create or replace function atlas.sync_weekly_harvest_company_work_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  if coalesce(new.task_payload->>'task_series_key','') <> 'anna_harvest_thursday_weekly'
     and coalesce(new.occurrence_key,'') not like 'recurring:anna_harvest_thursday_weekly:%' then
    return new;
  end if;

  if new.state = 'cancelled' then
    perform atlas.retire_weekly_harvest_company_work_adapter_v1(
      new.id,
      new.released_task_id,
      'Legacy weekly Harvest occurrence was cancelled; institutional Harvest work remains unsatisfied until separately adjudicated.'
    );
    return new;
  end if;

  perform atlas.ensure_weekly_harvest_company_work_v1(new.id);
  return new;
end;
$function$;

create or replace function atlas.sync_weekly_harvest_company_work_task_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  select a.* into v_adapter
  from atlas.work_execution_adapters a
  where a.task_id = new.id
  order by a.updated_at desc
  limit 1;

  if v_adapter.id is null then
    return new;
  end if;

  select * into v_work
  from atlas.work_items
  where organization_id = v_adapter.organization_id
    and id = v_adapter.work_item_id;

  if v_work.id is null then
    return new;
  end if;

  if new.status = 'done' then
    update atlas.work_items
    set work_state = 'completed',
        completed_at = coalesce(completed_at,now()),
        metadata = metadata || jsonb_build_object(
          'completionSource','legacy_harvest_execution_adapter',
          'legacyTaskId',new.id
        ),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and id = v_adapter.work_item_id
      and work_state = 'open';

    update atlas.work_requirements r
    set state = 'satisfied',
        satisfied_at = coalesce(satisfied_at,now()),
        metadata = metadata || jsonb_build_object(
          'satisfactionSource','company_work_item_completion',
          'workItemId',v_adapter.work_item_id
        ),
        updated_at = now()
    from atlas.work_requirement_links l
    where l.organization_id = v_adapter.organization_id
      and l.work_item_id = v_adapter.work_item_id
      and l.requirement_id = r.id
      and l.active
      and l.link_role = 'resolves'
      and r.state = 'active';

    update atlas.work_allocations
    set state = 'completed',
        completed_at = coalesce(completed_at,now()),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and state = 'active';

    update atlas.work_time_contracts
    set contract_state = 'satisfied',
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and contract_state = 'active';

    update atlas.work_execution_adapters
    set state = 'completed',
        completed_at = coalesce(completed_at,now()),
        retired_at = null,
        updated_at = now()
    where id = v_adapter.id;

    update atlas.work_planning_conflicts
    set state = 'resolved',
        resolution_kind = 'work_completed',
        resolution_note = 'The institutional work was completed through a worker-facing execution carrier.',
        resolved_at = now(),
        updated_at = now()
    where organization_id = v_adapter.organization_id
      and work_item_id = v_adapter.work_item_id
      and state = 'open';

    return new;
  end if;

  if new.status in ('archived','skipped') and v_work.work_state = 'open' then
    perform atlas.retire_weekly_harvest_company_work_adapter_v1(
      v_adapter.planned_occurrence_id,
      new.id,
      'Legacy weekly Harvest task became ' || new.status || ' while institutional Harvest work remains open.'
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists sync_weekly_harvest_company_work_occurrence_v1 on atlas.planned_work_occurrences;
create trigger sync_weekly_harvest_company_work_occurrence_v1
after insert or update of farm_id, planned_due_date, state, released_task_id, task_payload
on atlas.planned_work_occurrences
for each row
execute function atlas.sync_weekly_harvest_company_work_occurrence_v1();

drop trigger if exists sync_weekly_harvest_company_work_task_v1 on atlas.tasks;
create trigger sync_weekly_harvest_company_work_task_v1
after update of status on atlas.tasks
for each row
when (old.status is distinct from new.status)
execute function atlas.sync_weekly_harvest_company_work_task_v1();

-- Materialize institutional work for the already-planned remaining Harvest season.
do $seed$
declare
  r record;
begin
  for r in
    select id
    from atlas.planned_work_occurrences
    where planned_due_date >= (now() at time zone 'America/Chicago')::date
      and state in ('planned','eligible','releasing','released')
      and (
        coalesce(task_payload->>'task_series_key','') = 'anna_harvest_thursday_weekly'
        or coalesce(occurrence_key,'') like 'recurring:anna_harvest_thursday_weekly:%'
      )
    order by planned_due_date,id
  loop
    perform atlas.ensure_weekly_harvest_company_work_v1(r.id);
  end loop;
end;
$seed$;

-- Migration invariants: every current/future weekly Harvest execution carrier has
-- institutional Company Work, and every seeded Harvest Work Item is scoped to the same
-- Organization Unit as its farm rather than to a person or portal.
do $verify$
begin
  if exists (
    select 1
    from atlas.planned_work_occurrences o
    where o.planned_due_date >= (now() at time zone 'America/Chicago')::date
      and o.state in ('planned','eligible','releasing','released')
      and (
        coalesce(o.task_payload->>'task_series_key','') = 'anna_harvest_thursday_weekly'
        or coalesce(o.occurrence_key,'') like 'recurring:anna_harvest_thursday_weekly:%'
      )
      and not exists (
        select 1
        from atlas.work_execution_adapters a
        join atlas.work_items w
          on w.organization_id = a.organization_id
         and w.id = a.work_item_id
        join atlas.farms f on f.id = o.farm_id
        where a.planned_occurrence_id = o.id
          and a.organization_id = f.organization_id
          and a.organization_unit_id = f.organization_unit_id
          and w.organization_unit_id = f.organization_unit_id
          and w.operation_class = 'harvest'
      )
  ) then
    raise exception 'A current/future weekly Harvest carrier lacks institutional Company Work custody.';
  end if;

  if exists (
    select 1
    from atlas.work_items w
    where w.stable_key like 'weekly_harvest:%'
      and (
        w.organization_unit_id is null
        or w.metadata ? 'assigned_to'
        or w.metadata ? 'assignee_key'
        or w.stable_key ilike '%anna%'
      )
  ) then
    raise exception 'Weekly Harvest Company Work leaked person assignment into institutional identity.';
  end if;
end;
$verify$;

commit;
