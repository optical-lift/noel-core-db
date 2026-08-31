BEGIN;

-- Automatic weed-free-bed dependencies belong only to operations that actually
-- place seed/plants into a bed. Legacy task identity changes must not leave
-- planting prerequisites attached to spray, weed-control, planning, completed,
-- or otherwise non-planting work.

create or replace function atlas.task_requires_weed_free_bed_readiness_v1(p_task_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select coalesce((
    select
      t.status in ('open','blocked')
      and t.due_date is not null
      and lower(coalesce(t.metadata->>'bed_readiness_required','')) <> 'false'
      and not (
        lower(coalesce(t.action_key,'')) in ('spray','weed','clear')
        or lower(coalesce(t.task_type,'')) in ('weed_control','weeding','maintenance')
        or lower(coalesce(t.operation_class,'')) in ('apply_treatment','cut_separate')
        or lower(coalesce(t.metadata->>'maintenance_method',''))='spray'
        or lower(coalesce(t.metadata->>'work_route','')) in ('spray','weed','weed_and_sow')
      )
      and (
        lower(coalesce(t.metadata->>'bed_readiness_required',''))='true'
        or lower(coalesce(t.action_key,'')) in ('sow','seed','plant','transplant')
        or lower(coalesce(t.task_type,'')) in (
          'sow','sowing','direct_sow','plant','planting','transplant','transplanting','succession_sowing'
        )
        or lower(coalesce(t.metadata->>'work_route','')) in ('sow','seed','plant','transplant')
      )
    from atlas.tasks t
    where t.id=p_task_id
  ),false);
$function$;

create or replace function atlas.guard_automatic_bed_readiness_semantics_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if coalesce(new.metadata->>'source','')='automatic_bed_readiness'
     and coalesce(new.active,false)
     and not atlas.task_requires_weed_free_bed_readiness_v1(new.dependent_task_id) then
    new.active:=false;
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object(
      'deactivated_reason','dependent_task_no_longer_requires_weed_free_planting_bed',
      'deactivated_by','atlas_bed_readiness_dependency_semantic_cleanup_v1',
      'deactivated_at',now()
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_automatic_bed_readiness_semantics_v1 on atlas.maintenance_dependencies;
create trigger guard_automatic_bed_readiness_semantics_v1
before insert or update on atlas.maintenance_dependencies
for each row execute function atlas.guard_automatic_bed_readiness_semantics_v1();

create or replace function atlas.reconcile_task_automatic_bed_readiness_semantics_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if not atlas.task_requires_weed_free_bed_readiness_v1(new.id) then
    update atlas.maintenance_dependencies md
    set active=false,
        metadata=coalesce(md.metadata,'{}'::jsonb)||jsonb_build_object(
          'deactivated_reason','dependent_task_no_longer_requires_weed_free_planting_bed',
          'deactivated_by','atlas_bed_readiness_dependency_semantic_cleanup_v1',
          'deactivated_at',now()
        ),
        updated_at=now()
    where md.dependent_task_id=new.id
      and md.active
      and md.metadata->>'source'='automatic_bed_readiness';
  end if;
  return new;
end;
$function$;

drop trigger if exists reconcile_task_automatic_bed_readiness_semantics_v1 on atlas.tasks;
create trigger reconcile_task_automatic_bed_readiness_semantics_v1
after insert or update of action_key,task_type,operation_class,status,due_date,metadata on atlas.tasks
for each row execute function atlas.reconcile_task_automatic_bed_readiness_semantics_v1();

create or replace function atlas.task_bed_weeding_readiness_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
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
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;

  -- Defense in depth: even if a legacy dependency row somehow survives, a task
  -- that is not semantically a planting operation cannot acquire a planting-bed
  -- execution requirement from that stale row.
  if not atlas.task_requires_weed_free_bed_readiness_v1(v_task.id) then
    return jsonb_build_object(
      'contractVersion','task_bed_weeding_readiness_v2',
      'taskId',v_task.id,
      'applicable',false,
      'ready',true,
      'dependencyCount',0,
      'blockingBedCount',0,
      'blockingBeds','[]'::jsonb,
      'blockingBedLabels','[]'::jsonb,
      'waitingText',null,
      'dependentDueDate',v_task.due_date,
      'readyByDate',null,
      'dueNow',v_task.due_date is not null and v_task.due_date <= (now() at time zone 'America/Chicago')::date,
      'truthBoundary',jsonb_build_object(
        'semanticApplicabilityAuthoritative',true,
        'staleAutomaticDependenciesCannotCreateReadinessRequirement',true,
        'bedNeedRemainsMaintenanceOwned',true,
        'dueDateIsNotMovedByReadiness',true
      )
    );
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

  v_ready:=v_blocking_count=0;
  v_next_due:=v_task.due_date;
  if not v_ready then
    select string_agg(value,', ' order by value)
    into v_label_text
    from jsonb_array_elements_text(v_blocking_labels) labels(value);
    v_waiting_text:='Weed '||coalesce(v_label_text,'the destination bed')||' before planting.';
  end if;

  return jsonb_build_object(
    'contractVersion','task_bed_weeding_readiness_v2',
    'taskId',v_task.id,
    'applicable',true,
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
      'semanticApplicabilityAuthoritative',true,
      'staleAutomaticDependenciesCannotCreateReadinessRequirement',true,
      'bedNeedRemainsMaintenanceOwned',true,
      'dueDateIsNotMovedByReadiness',true,
      'maintainedBedSatisfiesWeedingGate',true
    )
  );
end;
$function$;

-- Reconcile every historical/current automatic dependency through the new
-- semantic predicate. Rows remain in custody; they simply cease to govern when
-- their dependent task no longer represents a planting operation.
update atlas.maintenance_dependencies md
set active=false,
    metadata=coalesce(md.metadata,'{}'::jsonb)||jsonb_build_object(
      'deactivated_reason','dependent_task_no_longer_requires_weed_free_planting_bed',
      'deactivated_by','atlas_bed_readiness_dependency_semantic_cleanup_v1',
      'deactivated_at',now()
    ),
    updated_at=now()
where md.active
  and md.metadata->>'source'='automatic_bed_readiness'
  and not atlas.task_requires_weed_free_bed_readiness_v1(md.dependent_task_id);

-- Recompute the derived maintenance pressure from dependencies that still have
-- governing force. This removes legacy planting pressure without erasing the
-- underlying weed-condition observation.
update atlas.maintenance_objects mo
set must_precede_task=exists(
      select 1
      from atlas.maintenance_dependencies md
      where md.maintenance_object_id=mo.id
        and md.active
        and md.satisfied_at is null
    ),
    planting_block_score=case
      when exists(
        select 1
        from atlas.maintenance_dependencies md
        join atlas.tasks t on t.id=md.dependent_task_id
        where md.maintenance_object_id=mo.id
          and md.active and md.satisfied_at is null
          and t.due_date <= (now() at time zone 'America/Chicago')::date + 2
      ) then 100
      when exists(
        select 1
        from atlas.maintenance_dependencies md
        join atlas.tasks t on t.id=md.dependent_task_id
        where md.maintenance_object_id=mo.id
          and md.active and md.satisfied_at is null
          and t.due_date <= (now() at time zone 'America/Chicago')::date + 7
      ) then 75
      when exists(
        select 1
        from atlas.maintenance_dependencies md
        where md.maintenance_object_id=mo.id
          and md.active and md.satisfied_at is null
      ) then 45
      else 0
    end,
    metadata=coalesce(mo.metadata,'{}'::jsonb)||jsonb_build_object(
      'bed_readiness_semantics_reconciled_at',now(),
      'next_planting_due_date',(
        select min(t.due_date)
        from atlas.maintenance_dependencies md
        join atlas.tasks t on t.id=md.dependent_task_id
        where md.maintenance_object_id=mo.id
          and md.active and md.satisfied_at is null
          and md.metadata->>'source'='automatic_bed_readiness'
      ),
      'weed_ready_by_date',(
        select min(nullif(md.metadata->>'ready_by_date','')::date)
        from atlas.maintenance_dependencies md
        where md.maintenance_object_id=mo.id
          and md.active and md.satisfied_at is null
          and md.metadata->>'source'='automatic_bed_readiness'
      )
    ),
    updated_at=now()
where mo.maintenance_type='weed';

comment on function atlas.task_requires_weed_free_bed_readiness_v1(uuid) is
  'Canonical semantic applicability predicate for automatic weed-free planting-bed prerequisites. Spray, weed control, planning, closed work, and other non-planting operations cannot acquire this requirement.';
comment on function atlas.task_bed_weeding_readiness_v1(uuid) is
  'Execution readiness for a genuinely planting-semantic task whose canonical automatic bed-readiness dependencies remain active. Semantic applicability is checked before dependency rows are read.';
comment on function atlas.guard_automatic_bed_readiness_semantics_v1() is
  'Prevents legacy synchronizers or stale writes from activating automatic planting-bed dependencies on tasks that do not semantically require them.';
comment on function atlas.reconcile_task_automatic_bed_readiness_semantics_v1() is
  'Immediately retires automatic planting-bed dependencies when a task identity/status/due-date mutation makes the requirement semantically inapplicable.';

revoke all on function atlas.task_requires_weed_free_bed_readiness_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.guard_automatic_bed_readiness_semantics_v1() from public,anon,authenticated;
revoke all on function atlas.reconcile_task_automatic_bed_readiness_semantics_v1() from public,anon,authenticated;
grant execute on function atlas.task_requires_weed_free_bed_readiness_v1(uuid) to service_role;
grant execute on function atlas.guard_automatic_bed_readiness_semantics_v1() to service_role;
grant execute on function atlas.reconcile_task_automatic_bed_readiness_semantics_v1() to service_role;

COMMIT;
