create or replace function atlas.worker_day_visibility_floor_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(task_id uuid, visibility_reason text)
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with member as (
    select fm.user_id, nullif(lower(btrim(fm.worker_key)), '') as worker_key
    from atlas.farm_memberships fm
    where fm.id = p_membership_id
      and fm.farm_id = p_farm_id
      and fm.active = true
  ), candidates as (
    select
      t.id,
      case
        when exists (
          select 1
          from atlas.worker_day_task_placements p
          where p.farm_id = p_farm_id
            and p.membership_id = p_membership_id
            and p.task_id = t.id
            and p.service_date = p_day
            and p.state = 'placed'
        ) then 'explicit_placement_today'
        when t.due_date = p_day then 'assigned_due_today'
        else 'assigned_execution_date_today'
      end as reason
    from atlas.tasks t
    cross join member m
    where t.farm_id = p_farm_id
      and t.task_scope = 'farm_operation'
      and t.status in ('open','blocked')
      and coalesce(t.visibility_scope,'assigned_worker') <> 'system_internal'
      and t.parent_task_id is null
      and t.metadata ->> 'parent_task_id' is null
      and coalesce((t.metadata ->> 'is_child_task')::boolean,false) = false
      and (
        t.assigned_membership_id = p_membership_id
        or t.assigned_user_id = m.user_id
        or t.metadata ->> 'executor_membership_id' = p_membership_id::text
        or (
          m.worker_key is not null
          and lower(coalesce(
            nullif(t.metadata ->> 'executor_worker_key',''),
            nullif(t.metadata ->> 'assignee_key',''),
            nullif(t.metadata ->> 'assigned_to',''),
            nullif(t.metadata ->> 'work_route','')
          )) = m.worker_key
        )
      )
      and (
        t.due_date = p_day
        or exists (
          select 1
          from atlas.worker_day_task_placements p
          where p.farm_id = p_farm_id
            and p.membership_id = p_membership_id
            and p.task_id = t.id
            and p.service_date = p_day
            and p.state = 'placed'
        )
        or (
          coalesce(t.metadata ->> 'execution_date','') ~ '^\d{4}-\d{2}-\d{2}$'
          and (t.metadata ->> 'execution_date')::date = p_day
        )
      )
  )
  select c.id, c.reason
  from candidates c
  order by c.id;
$function$;

revoke all on function atlas.worker_day_visibility_floor_v1(uuid,uuid,date) from public, anon, authenticated;

create or replace function atlas.worker_day_work_projection_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  visibility_state text,
  visibility_reason text,
  presentation_state text,
  presentation_reason text,
  selection_rank bigint,
  work_lane text,
  commitment_kind text,
  effort_units numeric,
  budget_units numeric,
  notification_planned boolean,
  overload boolean
)
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with selected as materialized (
    select *
    from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_day)
  ), floor as materialized (
    select *
    from atlas.worker_day_visibility_floor_v1(p_farm_id,p_membership_id,p_day)
  ), ids as (
    select s.task_id from selected s
    union
    select f.task_id from floor f
  )
  select
    i.task_id,
    'visible'::text as visibility_state,
    coalesce(f.visibility_reason,'presentation_selected') as visibility_reason,
    coalesce(s.presentation_state,'held') as presentation_state,
    coalesce(s.presentation_reason,'presentation_did_not_select_today') as presentation_reason,
    coalesce(s.selection_rank,9223372036854775807::bigint) as selection_rank,
    coalesce(s.work_lane,t.work_lane,'required') as work_lane,
    coalesce(s.commitment_kind,t.commitment_kind,'none') as commitment_kind,
    coalesce(s.effort_units,t.effort_units,0::numeric) as effort_units,
    coalesce(s.budget_units,0::numeric) as budget_units,
    coalesce(s.notification_planned,false) as notification_planned,
    coalesce(s.overload,false) as overload
  from ids i
  join atlas.tasks t on t.id=i.task_id
  left join selected s on s.task_id=i.task_id
  left join floor f on f.task_id=i.task_id
  order by coalesce(s.selection_rank,9223372036854775807::bigint),i.task_id;
$function$;

revoke all on function atlas.worker_day_work_projection_v1(uuid,uuid,date) from public, anon, authenticated;

create or replace function atlas.worker_day_feed_plan_live_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_capacity jsonb;
  v_target integer := 0;
  v_real jsonb := '[]'::jsonb;
  v_committed integer := 0;
begin
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(
    select 1
    from atlas.farm_memberships fm
    where fm.id=p_membership_id
      and fm.farm_id=p_farm_id
      and fm.active=true
      and fm.role='farm_hand'
  ) then
    raise exception 'Active Farm Hand membership required.' using errcode='42501';
  end if;

  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass'='recovery'
    then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0) end;

  if not atlas.worker_day_available_v1(p_farm_id,p_membership_id,p_day) then
    return jsonb_build_object(
      'contractVersion','owner_worker_day_feed_plan_v1',
      'farmId',p_farm_id,
      'membershipId',p_membership_id,
      'serviceDate',p_day,
      'availableWorkerDay',false,
      'paidTargetMinutes',v_target,
      'committedPaidMinutes',0,
      'automaticPaidMinutes',0,
      'remainingPaidMinutes',v_target,
      'realWork','[]'::jsonb,
      'automaticWork','[]'::jsonb,
      'suggestions','[]'::jsonb,
      'warnings','[]'::jsonb,
      'workProjectionContractVersion','worker_day_work_projection_v1'
    );
  end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id','task:'||t.id::text,
      'kind','real',
      'sourceKind','task',
      'sourceId',t.id,
      'taskId',t.id,
      'title',t.title,
      'status',t.status,
      'expectedActiveMinutes',capacity.expected_active_minutes,
      'dayWindow',resolved.placement->>'dayWindow',
      'workOrderNumber',(resolved.placement->>'sortOrder')::numeric,
      'placementAuthority',resolved.placement->>'source',
      'environment',nullif(t.metadata->>'environment',''),
      'location',coalesce(
        nullif(t.metadata->>'display_location',''),
        nullif(t.metadata->>'collection_zone',''),
        nullif(t.metadata->>'collection_label','')
      ),
      'automatic',false,
      'requiresOwnerApproval',false,
      'reason',case
        when projection.presentation_state='presented' then projection.presentation_reason
        else projection.visibility_reason
      end,
      'commitmentKind',projection.commitment_kind,
      'visibilityState',projection.visibility_state,
      'visibilityReason',projection.visibility_reason,
      'presentationState',projection.presentation_state,
      'presentationReason',projection.presentation_reason
    ) order by
      case resolved.placement->>'dayWindow' when 'morning' then 0 when 'afternoon' then 1 else 2 end,
      (resolved.placement->>'sortOrder')::numeric,
      projection.selection_rank,
      t.title,
      t.id
    ),'[]'::jsonb),
    coalesce(sum(capacity.expected_active_minutes),0)::integer
  into v_real,v_committed
  from atlas.worker_day_work_projection_v1(p_farm_id,p_membership_id,p_day) projection
  join atlas.tasks t on t.id=projection.task_id
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) capacity
  cross join lateral (
    select atlas.worker_task_effective_placement_v1(
      p_farm_id,p_membership_id,t.id,p_day
    ) as placement
  ) resolved
  where projection.visibility_state='visible';

  return jsonb_build_object(
    'contractVersion','owner_worker_day_feed_plan_v1',
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_day,
    'availableWorkerDay',true,
    'paidTargetMinutes',v_target,
    'committedPaidMinutes',v_committed,
    'automaticPaidMinutes',0,
    'remainingPaidMinutes',greatest(v_target-v_committed,0),
    'realWork',v_real,
    'automaticWork','[]'::jsonb,
    'suggestions','[]'::jsonb,
    'warnings','[]'::jsonb,
    'selectionContractVersion','presented_work_selection_rows_live_v1',
    'visibilityFloorContractVersion','worker_day_visibility_floor_v1',
    'workProjectionContractVersion','worker_day_work_projection_v1',
    'placementContractVersion','worker_task_effective_placement_v1'
  );
end;
$function$;