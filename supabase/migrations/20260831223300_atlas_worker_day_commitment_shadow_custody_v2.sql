BEGIN;

create or replace function atlas.capture_worker_day_commitment_shadow_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_reason text,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_org_id uuid;
  v_timezone text;
  v_items jsonb;
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_day is null or nullif(btrim(p_reason),'') is null then
    raise exception 'Worker Day shadow capture requires day and explicit reason.' using errcode='22023';
  end if;

  -- Domain adapter resolves organization custody through the farm. Membership
  -- identifies the recipient relationship; it does not own the organization.
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
  into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id
    and fm.farm_id=p_farm_id
    and fm.active=true;

  if v_org_id is null then
    raise exception 'Active membership on farm is required.' using errcode='42501';
  end if;
  if not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Farm timezone is not recognized by PostgreSQL.' using errcode='22023';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  select coalesce(jsonb_agg(jsonb_build_object(
    'stableItemKey','task:'||t.id::text,
    'sourceKind','task',
    'sourceId',t.id,
    'executionKind','task',
    'executionId',t.id,
    'title',t.title,
    'windowKey',resolved.placement->>'dayWindow',
    'expectedActiveMinutes',capacity.expected_active_minutes,
    'physicalLoad',capacity.physical_load,
    'admissionReason',projection.presentation_reason,
    'executionWarrant',jsonb_build_object(
      'executionReadiness',atlas.task_execution_readiness_v1(t.id),
      'operationFit',atlas.task_operation_fit_warrant_v1(t.id),
      'projectionContract','worker_day_work_projection_v1'
    ),
    'metadata',jsonb_build_object(
      'selectionRank',projection.selection_rank,
      'workLane',projection.work_lane,
      'commitmentKind',projection.commitment_kind,
      'visibilityReason',projection.visibility_reason,
      'presentationReason',projection.presentation_reason
    )
  ) order by projection.selection_rank,t.id),'[]'::jsonb)
  into v_items
  from atlas.worker_day_work_projection_v1(p_farm_id,p_membership_id,p_day) projection
  join atlas.tasks t on t.id=projection.task_id
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) capacity
  cross join lateral (
    select atlas.worker_task_effective_placement_v1(p_farm_id,p_membership_id,t.id,p_day) as placement
  ) resolved;

  if jsonb_array_length(v_items)=0 then
    raise exception 'Worker Day projection has no presentable items to commit.' using errcode='22023';
  end if;

  return atlas.commit_plan_generation_v1(
    'worker_day:'||p_farm_id::text||':'||p_membership_id::text||':'||p_day::text,
    'worker_day',
    'organization',
    v_org_id,
    null,
    'farm_membership',
    p_membership_id,
    v_start,
    v_end,
    v_items,
    p_reason,
    'worker_day_shadow_adapter',
    null,
    'worker_day_work_projection_v1',
    p_actor_user_id,
    jsonb_build_object(
      'farmId',p_farm_id,
      'serviceDate',p_day,
      'timezone',v_timezone,
      'shadowOnly',true,
      'doesNotDrivePresentation',true
    )
  );
end;
$function$;

comment on function atlas.capture_worker_day_commitment_shadow_v1(uuid,uuid,date,text,uuid) is
  'Shadow-only farm adapter proving the neutral Commitment Ledger. Organization custody and local day boundary are resolved through farm authority; membership identifies the recipient relationship. Does not alter worker-facing behavior.';

COMMIT;
