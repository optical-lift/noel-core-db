-- Atlas transplant bed-weeding gate v1
--
-- A planting/transplant task must stay visible when its biological window arrives,
-- but it is not an execution warrant until every linked destination bed is weed-ready.
-- Bed-readiness pressure also bypasses ordinary weeding backlog timing: the canonical
-- bed need is promoted into Anna's serial Weed Card queue as soon as its ready-by date
-- arrives, while the queue still exposes only one current Weed Card at a time.

create or replace function atlas.task_bed_weeding_readiness_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_dependency_count integer := 0;
  v_blocking_count integer := 0;
  v_blocking_beds jsonb := '[]'::jsonb;
  v_blocking_labels jsonb := '[]'::jsonb;
  v_label_text text;
  v_ready boolean := true;
  v_waiting_text text;
  v_next_due date;
  v_ready_by date;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then
    raise exception 'Task not found.' using errcode='P0002';
  end if;

  select
    count(*)::integer,
    count(*) filter(where md.satisfied_at is null)::integer,
    coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'maintenanceDependencyId',md.id,
        'maintenanceObjectId',mo.id,
        'objectId',go.id,
        'objectKey',go.stable_key,
        'objectLabel',go.label,
        'condition',mo.condition,
        'readyByDate',nullif(md.metadata->>'ready_by_date','')::date,
        'dependentDueDate',v_task.due_date
      )) order by go.label,go.id
    ) filter(where md.satisfied_at is null),'[]'::jsonb),
    coalesce(jsonb_agg(to_jsonb(go.label) order by go.label,go.id)
      filter(where md.satisfied_at is null),'[]'::jsonb),
    min(nullif(md.metadata->>'ready_by_date','')::date) filter(where md.satisfied_at is null)
  into v_dependency_count,v_blocking_count,v_blocking_beds,v_blocking_labels,v_ready_by
  from atlas.maintenance_dependencies md
  join atlas.maintenance_objects mo on mo.id=md.maintenance_object_id
  join atlas.growing_objects go on go.id=mo.object_id
  where md.dependent_task_id=v_task.id
    and md.active
    and md.metadata->>'source'='automatic_bed_readiness'
    and mo.maintenance_type='weed';

  v_ready := v_blocking_count=0;
  v_next_due := v_task.due_date;

  if not v_ready then
    select string_agg(value, ', ' order by value)
    into v_label_text
    from jsonb_array_elements_text(v_blocking_labels) labels(value);
    v_waiting_text := 'Weed '||coalesce(v_label_text,'the destination bed')||' before transplanting.';
  end if;

  return jsonb_build_object(
    'contractVersion','task_bed_weeding_readiness_v1',
    'taskId',v_task.id,
    'applicable',v_dependency_count>0,
    'ready',v_ready,
    'dependencyCount',v_dependency_count,
    'blockingBedCount',v_blocking_count,
    'blockingBeds',v_blocking_beds,
    'blockingBedLabels',v_blocking_labels,
    'waitingText',v_waiting_text,
    'dependentDueDate',v_next_due,
    'readyByDate',v_ready_by,
    'dueNow',v_next_due is not null and v_next_due <= (now() at time zone 'America/Chicago')::date,
    'truthBoundary',jsonb_build_object(
      'bedNeedRemainsMaintenanceOwned',true,
      'blockedTaskRemainsVisible',true,
      'dueDateIsNotMovedByReadiness',true,
      'maintainedBedSatisfiesWeedingGate',true
    )
  );
end;
$function$;

create or replace function atlas.reconcile_bed_weeding_gate_v1(
  p_task_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_readiness jsonb;
  v_restore jsonb;
  v_waiting_text text;
  v_current_gate_text text;
  v_restore_status text;
  v_restore_blocker text;
  v_metadata jsonb;
begin
  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then
    return jsonb_build_object('taskId',p_task_id,'state','missing');
  end if;
  if v_task.status not in ('open','blocked') then
    return jsonb_build_object('taskId',v_task.id,'state','terminal','status',v_task.status);
  end if;

  v_readiness := atlas.task_bed_weeding_readiness_v1(v_task.id);

  if coalesce((v_readiness->>'applicable')::boolean,false)
     and not coalesce((v_readiness->>'ready')::boolean,false)
  then
    v_waiting_text := coalesce(nullif(v_readiness->>'waitingText',''),'Weed the destination bed before transplanting.');
    v_restore := v_task.metadata->'bed_readiness_gate_restore';
    if v_restore is null or jsonb_typeof(v_restore)<>'object' then
      v_restore := jsonb_strip_nulls(jsonb_build_object(
        'status',v_task.status,
        'blocker_text',v_task.blocker_text
      ));
    end if;

    v_metadata := coalesce(v_task.metadata,'{}'::jsonb)
      || jsonb_build_object(
        'bed_readiness_gate_restore',v_restore,
        'bed_readiness_gate_state','blocked_visible',
        'bed_readiness_gate_waiting_text',v_waiting_text,
        'bed_readiness_gate_updated_at',p_as_of,
        'execution_locked',true,
        'execution_lock_kind','bed_weeding',
        'bed_readiness_blocking_beds',coalesce(v_readiness->'blockingBedLabels','[]'::jsonb),
        'bed_readiness_blocking_bed_count',coalesce((v_readiness->>'blockingBedCount')::integer,0),
        'bed_readiness_due_now',coalesce((v_readiness->>'dueNow')::boolean,false)
      );

    update atlas.tasks
    set status='blocked',
        blocker_text=v_waiting_text,
        metadata=v_metadata,
        updated_at=p_as_of
    where id=v_task.id;

    return jsonb_build_object(
      'taskId',v_task.id,
      'state','blocked_visible',
      'blockerText',v_waiting_text,
      'blockingBeds',v_readiness->'blockingBedLabels'
    );
  end if;

  if coalesce(v_task.metadata->>'execution_lock_kind','')='bed_weeding'
     or coalesce(v_task.metadata->>'bed_readiness_gate_state','')='blocked_visible'
  then
    v_restore := coalesce(v_task.metadata->'bed_readiness_gate_restore','{}'::jsonb);
    v_current_gate_text := nullif(v_task.metadata->>'bed_readiness_gate_waiting_text','');

    if v_task.status='blocked'
       and v_current_gate_text is not null
       and v_task.blocker_text is not distinct from v_current_gate_text
    then
      v_restore_status := case
        when coalesce(v_restore->>'status','open') in ('open','blocked') then coalesce(v_restore->>'status','open')
        else 'open' end;
      v_restore_blocker := nullif(v_restore->>'blocker_text','');
    else
      -- Another operational fact changed the task while the bed gate was active.
      -- Remove only the bed gate and preserve that newer task state.
      v_restore_status := v_task.status;
      v_restore_blocker := v_task.blocker_text;
    end if;

    v_metadata := coalesce(v_task.metadata,'{}'::jsonb)
      - 'bed_readiness_gate_restore'
      - 'bed_readiness_gate_waiting_text'
      - 'execution_locked'
      - 'execution_lock_kind'
      - 'bed_readiness_blocking_beds'
      - 'bed_readiness_blocking_bed_count'
      - 'bed_readiness_due_now';
    v_metadata := v_metadata || jsonb_build_object(
      'bed_readiness_gate_state','ready',
      'bed_readiness_gate_satisfied_at',p_as_of,
      'bed_readiness_gate_updated_at',p_as_of
    );

    update atlas.tasks
    set status=v_restore_status,
        blocker_text=v_restore_blocker,
        metadata=v_metadata,
        updated_at=p_as_of
    where id=v_task.id;
  end if;

  return jsonb_build_object('taskId',v_task.id,'state','ready','readiness',v_readiness);
end;
$function$;

create or replace function atlas.reconcile_bed_weeding_gate_from_dependency_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if tg_op='DELETE' then
    perform atlas.reconcile_bed_weeding_gate_v1(old.dependent_task_id,now());
    return old;
  end if;
  perform atlas.reconcile_bed_weeding_gate_v1(new.dependent_task_id,now());
  return new;
end;
$function$;

drop trigger if exists reconcile_bed_weeding_gate_from_dependency_v1 on atlas.maintenance_dependencies;
drop trigger if exists reconcile_bed_weeding_gate_from_dependency_insert_update_v1 on atlas.maintenance_dependencies;
drop trigger if exists reconcile_bed_weeding_gate_from_dependency_delete_v1 on atlas.maintenance_dependencies;

create trigger reconcile_bed_weeding_gate_from_dependency_insert_update_v1
after insert or update of active,satisfied_at on atlas.maintenance_dependencies
for each row
when (new.metadata->>'source'='automatic_bed_readiness')
execute function atlas.reconcile_bed_weeding_gate_from_dependency_v1();

create trigger reconcile_bed_weeding_gate_from_dependency_delete_v1
after delete on atlas.maintenance_dependencies
for each row
when (old.metadata->>'source'='automatic_bed_readiness')
execute function atlas.reconcile_bed_weeding_gate_from_dependency_v1();

create or replace function atlas.sync_bed_weeding_dependency_from_maintenance_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.maintenance_type<>'weed' then return new; end if;

  if new.condition='maintained' then
    update atlas.maintenance_dependencies md
    set satisfied_at=coalesce(md.satisfied_at,new.last_completed_at,now()),
        metadata=coalesce(md.metadata,'{}'::jsonb)||jsonb_build_object(
          'satisfaction_source','maintenance_condition_maintained',
          'satisfied_from_maintenance_object_at',now()
        ),
        updated_at=now()
    where md.maintenance_object_id=new.id
      and md.active
      and md.metadata->>'source'='automatic_bed_readiness'
      and md.satisfied_at is null;
  elsif old.condition='maintained' or new.condition is distinct from old.condition then
    update atlas.maintenance_dependencies md
    set satisfied_at=null,
        metadata=coalesce(md.metadata,'{}'::jsonb)||jsonb_build_object(
          'reopened_source','maintenance_condition_not_ready',
          'reopened_condition',new.condition,
          'reopened_at',now()
        ),
        updated_at=now()
    where md.maintenance_object_id=new.id
      and md.active
      and md.metadata->>'source'='automatic_bed_readiness'
      and exists(
        select 1 from atlas.tasks t
        where t.id=md.dependent_task_id and t.status in ('open','blocked')
      );
  end if;

  return new;
end;
$function$;

drop trigger if exists sync_bed_weeding_dependency_from_maintenance_v1 on atlas.maintenance_objects;
create trigger sync_bed_weeding_dependency_from_maintenance_v1
after update of condition,last_completed_at on atlas.maintenance_objects
for each row
when (new.maintenance_type='weed')
execute function atlas.sync_bed_weeding_dependency_from_maintenance_v1();

create or replace function atlas.ensure_due_bed_readiness_weeding_v1(
  p_farm_id uuid,
  p_as_of date default current_date
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_anna uuid;
  v_card_id uuid;
  v_occurrence_id uuid;
  v_count integer := 0;
  v_existing_task_id uuid;
  r record;
begin
  select id into v_anna
  from atlas.farm_memberships
  where farm_id=p_farm_id and worker_key='anna' and active=true
  order by created_at
  limit 1;
  if v_anna is null then return 0; end if;

  for r in
    select
      mo.id as maintenance_object_id,
      mo.object_id,
      mo.zone_id,
      mo.condition,
      greatest(5,coalesce(mo.remaining_effort_minutes,mo.current_effort_minutes,mo.maintenance_effort_minutes,30)) as estimated_minutes,
      go.stable_key as object_key,
      go.label as object_label,
      coalesce(z.label,'Elm Farm') as zone_label,
      min(nullif(md.metadata->>'ready_by_date','')::date) as ready_by,
      min(t.due_date) as dependent_due,
      array_agg(distinct t.id order by t.id) as dependent_task_ids,
      array_agg(distinct t.title order by t.title) as dependent_task_labels
    from atlas.maintenance_dependencies md
    join atlas.maintenance_objects mo on mo.id=md.maintenance_object_id
    join atlas.growing_objects go on go.id=mo.object_id
    left join atlas.zones z on z.id=mo.zone_id
    join atlas.tasks t on t.id=md.dependent_task_id
    where md.farm_id=p_farm_id
      and md.active
      and md.satisfied_at is null
      and md.metadata->>'source'='automatic_bed_readiness'
      and mo.maintenance_type='weed'
      and mo.condition<>'maintained'
      and t.status in ('open','blocked')
    group by mo.id,mo.object_id,mo.zone_id,mo.condition,mo.remaining_effort_minutes,
      mo.current_effort_minutes,mo.maintenance_effort_minutes,go.stable_key,go.label,z.label
    having min(nullif(md.metadata->>'ready_by_date','')::date)<=p_as_of
    order by min(t.due_date), max(mo.planting_block_score) desc, max(mo.owner_priority) desc, go.label
  loop
    select t.id into v_existing_task_id
    from atlas.tasks t
    where t.farm_id=p_farm_id
      and t.assigned_membership_id=v_anna
      and t.status in ('open','blocked')
      and t.action_key='weed'
      and (
        t.generated_from_id=r.maintenance_object_id
        or t.metadata->>'maintenance_object_id'=r.maintenance_object_id::text
        or exists(select 1 from atlas.task_objects x where x.task_id=t.id and x.object_id=r.object_id)
      )
    order by t.due_date nulls last,t.created_at
    limit 1;

    if v_existing_task_id is not null then
      update atlas.tasks
      set due_date=least(coalesce(due_date,p_as_of),p_as_of),
          priority='high',
          unlock_text='Prepares for '||array_to_string(r.dependent_task_labels,' · '),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'bed_readiness_deadline_pressure',true,
            'bed_ready_by_date',r.ready_by,
            'next_planting_due_date',r.dependent_due,
            'blocking_task_count',cardinality(r.dependent_task_ids),
            'dependent_task_ids',to_jsonb(r.dependent_task_ids),
            'dependent_task_labels',to_jsonb(r.dependent_task_labels),
            'blocking_due_now',r.dependent_due<=p_as_of,
            'release_reason','bed_readiness_deadline_pressure'
          ),
          updated_at=now()
      where id=v_existing_task_id;
      continue;
    end if;

    -- Repeated dependency sync must not retire an urgent blocker that has already
    -- entered the serial Weed Card queue and is waiting its turn there.
    if exists(
      select 1
      from atlas.task_release_queue_items qi
      join atlas.planned_work_occurrences o on o.id=qi.planned_occurrence_id
      where qi.farm_id=p_farm_id
        and qi.queue_key='anna_weeding_rotation'
        and qi.maintenance_object_id=r.maintenance_object_id
        and qi.state in ('active','queued')
        and o.source_kind='maintenance_weeding_bed_readiness'
        and o.source_id=r.maintenance_object_id
        and o.state in ('planned','eligible','released')
    ) then
      continue;
    end if;

    -- If this bed is sitting in the ordinary serial backlog, retire that stale queue
    -- carrier. The deadline-pressure occurrence below will re-enter the same serial
    -- queue and therefore receives need-aware promotion instead of keeping its old date.
    update atlas.planned_work_occurrences o
    set state='cancelled',
        metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object(
          'cancelled_by','bed_readiness_deadline_pressure',
          'cancelled_at',now()
        ),
        updated_at=now()
    from atlas.task_release_queue_items qi
    where qi.farm_id=p_farm_id
      and qi.queue_key='anna_weeding_rotation'
      and qi.maintenance_object_id=r.maintenance_object_id
      and qi.state='queued'
      and qi.planned_occurrence_id=o.id
      and o.state in ('planned','eligible','failed');

    update atlas.task_release_queue_items qi
    set state='skipped',
        completed_at=coalesce(qi.completed_at,now()),
        metadata=coalesce(qi.metadata,'{}'::jsonb)||jsonb_build_object(
          'skipped_by','bed_readiness_deadline_pressure',
          'skipped_at',now()
        ),
        updated_at=now()
    where qi.farm_id=p_farm_id
      and qi.queue_key='anna_weeding_rotation'
      and qi.maintenance_object_id=r.maintenance_object_id
      and qi.state='queued';

    v_card_id := atlas.ensure_weed_card_for_object_v1(r.object_id,null);

    v_occurrence_id := atlas.plan_work_occurrence_v1(
      p_farm_id,
      'maintenance:weeding:bed-readiness',
      'maintenance:weeding:bed-readiness:deadline',
      'bed-readiness:'||r.maintenance_object_id::text||':'||r.dependent_due::text,
      'Weed '||r.object_label,
      'maintenance',
      p_as_of,
      'maintenance_weeding_bed_readiness',
      r.maintenance_object_id,
      'time_window',
      14,
      99,
      jsonb_build_object(
        'farm_id',p_farm_id,
        'zone_id',r.zone_id,
        'title','Weed '||r.object_label,
        'task_type','maintenance',
        'status','open',
        'priority','high',
        'due_date',p_as_of,
        'unlock_text','Prepares for '||array_to_string(r.dependent_task_labels,' · '),
        'generated_from','maintenance_weeding_bed_readiness',
        'generated_from_id',r.maintenance_object_id,
        'metadata',jsonb_build_object(
          'anna_task',true,
          'owner_task',false,
          'assigned_to','Anna',
          'assignee_key','anna',
          'work_route','weed',
          'work_rhythm','Weeding',
          'display_action','Weed',
          'display_title','Weed '||r.object_label,
          'display_subject',r.object_label,
          'display_detail',r.estimated_minutes::text||' min · transplant bed needed now',
          'collection_zone',r.zone_label,
          'collection_label',r.object_label,
          'maintenance_object_id',r.maintenance_object_id,
          'maintenance_type','weed',
          'target_object_id',r.object_id,
          'weed_card_id',v_card_id,
          'weed_card_managed',true,
          'weed_card_session_task',true,
          'persistent_weed_card',true,
          'bed_readiness_deadline_pressure',true,
          'bed_ready_by_date',r.ready_by,
          'next_planting_due_date',r.dependent_due,
          'blocking_task_count',cardinality(r.dependent_task_ids),
          'dependent_task_ids',to_jsonb(r.dependent_task_ids),
          'dependent_task_labels',to_jsonb(r.dependent_task_labels),
          'blocking_due_now',r.dependent_due<=p_as_of,
          'estimated_minutes',r.estimated_minutes,
          'condition',r.condition,
          'release_reason','bed_readiness_deadline_pressure',
          'day_order',600,
          'day_work_order',600,
          'run_sheet_order',600
        ),
        'action_key','weed',
        'work_class','standard',
        'visibility_scope','assigned_worker',
        'assigned_membership_id',v_anna,
        'task_series_key','bed-readiness:'||r.maintenance_object_id::text,
        'engine_instance_key','bed-readiness:'||r.maintenance_object_id::text||':'||r.dependent_due::text
      ),
      jsonb_build_object(
        'task_objects',jsonb_build_array(jsonb_build_object('object_id',r.object_id,'role','target'))
      ),
      jsonb_build_object('maintenance_object_id',r.maintenance_object_id,'deadline_pressure',true),
      p_as_of-14,
      jsonb_build_object(
        'planned_by','ensure_due_bed_readiness_weeding_v1',
        'maintenance_object_id',r.maintenance_object_id,
        'dependent_due_date',r.dependent_due,
        'bed_ready_by_date',r.ready_by
      )
    );
    v_count:=v_count+1;
  end loop;

  if v_count>0 then
    perform atlas.release_eligible_work_v1(p_farm_id,p_as_of,null);
    perform atlas.reconcile_anna_serial_weeding_v1(p_farm_id);
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,'anna_weeding_rotation');
  end if;

  return v_count;
end;
$function$;

create or replace function atlas.sync_weeding_planting_dependencies(
  p_farm_key text default 'elm_farm'::text,
  p_as_of date default current_date
)
returns integer
language plpgsql
set search_path to 'atlas','public'
as $function$
declare
  v_farm_id uuid;
  v_count integer := 0;
  r record;
begin
  select id into v_farm_id from atlas.farms where stable_key=p_farm_key;
  if v_farm_id is null then raise exception 'Unknown farm key: %',p_farm_key; end if;

  update atlas.maintenance_dependencies md
  set active=false,
      metadata=coalesce(md.metadata,'{}'::jsonb)||jsonb_build_object(
        'deactivated_reason','dependent task no longer active','deactivated_at',now()
      ),
      updated_at=now()
  where md.farm_id=v_farm_id
    and md.metadata->>'source'='automatic_bed_readiness'
    and not exists(
      select 1 from atlas.tasks t
      where t.id=md.dependent_task_id and t.status in ('open','blocked')
    );

  insert into atlas.maintenance_dependencies(
    farm_id,maintenance_object_id,dependent_task_id,dependency_type,active,satisfied_at,metadata
  )
  select distinct
    v_farm_id,
    mo.id,
    t.id,
    'blocks_task',
    true,
    case when mo.condition='maintained' then coalesce(mo.last_completed_at,now()) else null end,
    jsonb_build_object(
      'source','automatic_bed_readiness',
      'ready_by_date',t.due_date-1,
      'dependent_due_date',t.due_date,
      'dependent_action',coalesce(t.action_key,t.metadata->>'work_route',t.task_type),
      'synced_at',now(),
      'current_weed_condition',mo.condition
    )
  from atlas.maintenance_objects mo
  join atlas.task_objects mt on mt.object_id=mo.object_id
  join atlas.tasks t on t.id=mt.task_id
  where mo.farm_id=v_farm_id
    and mo.maintenance_type='weed'
    and t.status in ('open','blocked')
    and t.due_date is not null
    and (
      lower(coalesce(t.action_key,'')) in ('sow','seed','plant','planting','transplant','prep')
      or lower(coalesce(t.task_type,'')) ~ '(sow|seed|plant|transplant|succession)'
      or lower(coalesce(t.metadata->>'work_route','')) ~ '(sow|seed|plant|transplant|prep)'
    )
    and not (
      lower(coalesce(t.metadata->>'maintenance_method',''))='spray'
      or lower(coalesce(t.metadata->>'work_route',''))='weed_and_sow'
    )
  on conflict (maintenance_object_id,dependent_task_id) do update
  set active=true,
      satisfied_at=case
        when excluded.satisfied_at is not null then coalesce(atlas.maintenance_dependencies.satisfied_at,excluded.satisfied_at)
        else null end,
      dependency_type=excluded.dependency_type,
      metadata=atlas.maintenance_dependencies.metadata||excluded.metadata,
      updated_at=now();

  get diagnostics v_count=row_count;

  update atlas.maintenance_objects mo
  set active=case
        when exists(
          select 1 from atlas.maintenance_dependencies md
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        ) and not exists(
          select 1 from atlas.tasks t
          where t.farm_id=mo.farm_id and t.status in ('open','blocked') and t.action_key='weed'
            and (t.generated_from_id=mo.id or t.metadata->>'maintenance_object_id'=mo.id::text)
        ) then true
        when mo.condition='maintained' and not exists(
          select 1 from atlas.maintenance_dependencies md
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        ) then false
        else mo.active end,
      must_precede_task=exists(
        select 1 from atlas.maintenance_dependencies md
        where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
      ),
      planting_block_score=case
        when exists(
          select 1 from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null and t.due_date<=p_as_of+2
        ) then 100
        when exists(
          select 1 from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null and t.due_date<=p_as_of+7
        ) then 75
        when exists(
          select 1 from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        ) then 45
        else 0 end,
      metadata=coalesce(mo.metadata,'{}'::jsonb)||jsonb_build_object(
        'bed_readiness_synced_at',now(),
        'next_planting_due_date',(
          select min(t.due_date)
          from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        ),
        'weed_ready_by_date',(
          select min(nullif(md.metadata->>'ready_by_date','')::date)
          from atlas.maintenance_dependencies md
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        )
      ),
      updated_at=now()
  where mo.farm_id=v_farm_id and mo.maintenance_type='weed';

  for r in
    select distinct md.dependent_task_id
    from atlas.maintenance_dependencies md
    where md.farm_id=v_farm_id
      and md.active
      and md.metadata->>'source'='automatic_bed_readiness'
  loop
    perform atlas.reconcile_bed_weeding_gate_v1(r.dependent_task_id,now());
  end loop;

  perform atlas.ensure_due_bed_readiness_weeding_v1(v_farm_id,p_as_of);
  return v_count;
end;
$function$;

create or replace function atlas.task_execution_requirement_inputs_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_prereq boolean;
  v_resources boolean;
  v_destination jsonb;
  v_seed jsonb;
  v_state_gate jsonb;
  v_state_clear boolean;
  v_bed_readiness jsonb;
begin
  if not exists(select 1 from atlas.tasks where id=p_task_id) then
    raise exception 'Task not found.' using errcode='P0002';
  end if;

  v_prereq:=atlas.task_prerequisites_ready_v1(p_task_id);
  v_resources:=atlas.task_required_resources_available_v1(p_task_id);
  v_destination:=atlas.task_execution_destination_readiness_v1(p_task_id);
  v_seed:=atlas.task_seed_readiness_v1(p_task_id);
  v_state_gate:=atlas.task_state_consequence_gate_v1(p_task_id);
  v_state_clear:=not coalesce((v_state_gate->>'blocking')::boolean,false);
  v_bed_readiness:=atlas.task_bed_weeding_readiness_v1(p_task_id);

  return jsonb_build_array(
    jsonb_build_object(
      'requirementKey','prerequisites','satisfied',v_prereq,
      'provider','task_prerequisites_ready_v1','providerState',case when v_prereq then 'satisfied' else 'open' end,
      'evidence',jsonb_build_object('ready',v_prereq)
    ),
    jsonb_build_object(
      'requirementKey','resources','satisfied',v_resources,
      'provider','task_required_resources_available_v1','providerState',case when v_resources then 'satisfied' else 'open' end,
      'evidence',jsonb_build_object('ready',v_resources)
    ),
    jsonb_build_object(
      'requirementKey','destination','satisfied',coalesce((v_destination->>'ready')::boolean,false),
      'provider','task_execution_destination_readiness_v1','providerState',coalesce(v_destination->>'state','unknown'),
      'evidence',v_destination
    ),
    jsonb_build_object(
      'requirementKey','seed','satisfied',coalesce((v_seed->>'ready')::boolean,false),
      'provider','task_seed_readiness_v1','providerState',coalesce(v_seed->>'state','unknown'),
      'evidence',v_seed
    ),
    jsonb_build_object(
      'requirementKey','state_consequence','satisfied',v_state_clear,
      'provider','task_state_consequence_gate_v1','providerState',coalesce(v_state_gate->>'state','unknown'),
      'evidence',v_state_gate
    ),
    jsonb_build_object(
      'requirementKey','bed_readiness','satisfied',coalesce((v_bed_readiness->>'ready')::boolean,false),
      'provider','task_bed_weeding_readiness_v1',
      'providerState',case when coalesce((v_bed_readiness->>'ready')::boolean,false) then 'satisfied' else 'open' end,
      'evidence',v_bed_readiness
    )
  );
end;
$function$;

create or replace function atlas.task_execution_readiness_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_canonical jsonb;
  v_requirements jsonb;
  v_ready boolean := false;
  v_prereq boolean := false;
  v_resources boolean := false;
  v_destination_ready boolean := false;
  v_seed_ready boolean := false;
  v_state_gate_clear boolean := false;
  v_bed_ready boolean := false;
  v_destination jsonb := '{}'::jsonb;
  v_seed jsonb := '{}'::jsonb;
  v_state_gate jsonb := '{}'::jsonb;
  v_bed_readiness jsonb := '{}'::jsonb;
begin
  v_canonical:=atlas.task_execution_requirement_evaluation_v1(p_task_id);
  v_requirements:=coalesce(v_canonical->'requirements','[]'::jsonb);
  v_ready:=coalesce((v_canonical->>'executionReady')::boolean,false);

  select coalesce((node->>'satisfied')::boolean,false) into v_prereq
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='prerequisites' limit 1;
  select coalesce((node->>'satisfied')::boolean,false) into v_resources
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='resources' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_destination_ready,v_destination
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='destination' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_seed_ready,v_seed
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='seed' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_state_gate_clear,v_state_gate
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='state_consequence' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_bed_ready,v_bed_readiness
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='bed_readiness' limit 1;

  v_prereq:=coalesce(v_prereq,false);
  v_resources:=coalesce(v_resources,false);
  v_destination_ready:=coalesce(v_destination_ready,false);
  v_seed_ready:=coalesce(v_seed_ready,false);
  v_state_gate_clear:=coalesce(v_state_gate_clear,false);
  v_bed_ready:=coalesce(v_bed_ready,false);
  v_destination:=coalesce(v_destination,'{}'::jsonb);
  v_seed:=coalesce(v_seed,'{}'::jsonb);
  v_state_gate:=coalesce(v_state_gate,'{}'::jsonb);
  v_bed_readiness:=coalesce(v_bed_readiness,'{}'::jsonb);

  return jsonb_build_object(
    'contractVersion','task_execution_warrant_v1',
    'contractRole','execution_warrant',
    'taskId',p_task_id,
    'ready',v_ready,
    'executionReady',v_ready,
    'prerequisitesReady',v_prereq,
    'resourcesReady',v_resources,
    'destinationReady',v_destination_ready,
    'seedReady',v_seed_ready,
    'stateConsequenceClear',v_state_gate_clear,
    'bedReadinessReady',v_bed_ready,
    'bedReadiness',v_bed_readiness,
    'preparationRequired',coalesce((v_state_gate->>'preparationRequired')::boolean,false),
    'destination',v_destination,
    'seed',v_seed,
    'stateConsequenceGate',v_state_gate,
    'truthBoundary',jsonb_build_object(
      'requirementAuthority',false,
      'compatibilityProjection',true,
      'canonicalEvaluation','task_execution_requirement_evaluation_v1',
      'requirementExistenceNotInferredFromReady',true,
      'notReadyDoesNotMeanNotRequired',true,
      'thisContractOnlyAnswersWhetherRepresentedTaskMayExecuteNow',true
    )
  );
end;
$function$;

create or replace function atlas.record_task_transition_v1(
  p_task_id uuid,
  p_transition text,
  p_idempotency_key text,
  p_target_date date default null,
  p_note text default null,
  p_reason text default null,
  p_lane_key text default null,
  p_work_key text default null,
  p_payload jsonb default '{}'::jsonb,
  p_existing_field_log_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_scoped_key text;
  v_bed_readiness jsonb;
begin
  if p_task_id is null then
    raise exception 'Task id is required.' using errcode='22023';
  end if;

  if p_transition in ('done','checklist_done') then
    v_bed_readiness:=atlas.task_bed_weeding_readiness_v1(p_task_id);
    if coalesce((v_bed_readiness->>'applicable')::boolean,false)
       and not coalesce((v_bed_readiness->>'ready')::boolean,false)
    then
      raise exception '%',coalesce(nullif(v_bed_readiness->>'waitingText',''),'Weed the destination bed before transplanting.')
        using errcode='23514';
    end if;
  end if;

  v_scoped_key:=p_task_id::text||':'||md5(coalesce(p_idempotency_key,''));
  return atlas.record_task_transition_v1_internal(
    p_task_id,p_transition,v_scoped_key,p_target_date,p_note,p_reason,p_lane_key,p_work_key,
    coalesce(p_payload,'{}'::jsonb),p_existing_field_log_id
  );
end;
$function$;

-- Reconcile existing farms that already have automatic bed-readiness relationships.
do $migration$
declare r record;
begin
  for r in
    select distinct f.stable_key
    from atlas.farms f
    join atlas.maintenance_objects mo on mo.farm_id=f.id and mo.maintenance_type='weed'
    where exists(
      select 1 from atlas.tasks t
      where t.farm_id=f.id and t.status in ('open','blocked') and t.due_date is not null
        and (
          lower(coalesce(t.action_key,'')) in ('sow','seed','plant','planting','transplant','prep')
          or lower(coalesce(t.task_type,'')) ~ '(sow|seed|plant|transplant|succession)'
          or lower(coalesce(t.metadata->>'work_route','')) ~ '(sow|seed|plant|transplant|prep)'
        )
    )
  loop
    perform atlas.sync_weeding_planting_dependencies(r.stable_key,(now() at time zone 'America/Chicago')::date);
  end loop;
end;
$migration$;