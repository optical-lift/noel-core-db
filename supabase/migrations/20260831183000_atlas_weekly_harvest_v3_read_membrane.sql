BEGIN;

create or replace function atlas.weekly_harvest_task_state_core_v2(
  p_task_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_rows jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_resolved integer:=0;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Weekly Harvest task not found.' using errcode='P0002'; end if;
  if v_task.task_type<>'harvest' or v_task.task_series_key<>'anna_harvest_thursday_weekly' then raise exception 'Task is not the canonical weekly Harvest card.' using errcode='22023'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_task.farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  if p_effective_role not in ('owner','manager','farm_hand') then raise exception 'Harvest access denied.' using errcode='42501'; end if;
  if p_effective_role='farm_hand' and v_task.assigned_membership_id is distinct from p_effective_membership_id then raise exception 'Weekly Harvest is not assigned to this worker.' using errcode='42501'; end if;

  with current_candidates as (
    select c.*,coalesce(nullif(z.label,''),'Elm Farm') zone_label
    from atlas.weekly_harvest_candidate_cycles_v1(v_task.id)c
    join atlas.growing_objects go on go.id=c.object_id
    left join atlas.zones z on z.id=go.zone_id
  ), historical_results as (
    select cc.id crop_cycle_id,coalesce(nullif(cc.crop_label,''),'Crop') crop_label,nullif(cc.variety,'') variety,
           go.id object_id,coalesce(nullif(go.label,''),'Growing area') object_label,
           cc.expected_harvest_watch_start window_start,coalesce(cc.expected_harvest_watch_end,cc.expected_harvest_watch_start+21) window_end,
           coalesce(nullif(cc.cycle_state,''),'growing') cycle_state,cha.status availability_status,
           coalesce(nullif(z.label,''),'Elm Farm') zone_label
    from atlas.weekly_harvest_task_results wr
    join atlas.crop_cycles cc on cc.id=wr.crop_cycle_id
    join atlas.growing_objects go on go.id=cc.object_id
    left join atlas.zones z on z.id=go.zone_id
    left join atlas.crop_harvest_availability cha on cha.crop_cycle_id=cc.id
    where wr.task_id=v_task.id and wr.result_kind not in ('crop_exhausted','crop_loss')
  ), rows_union as (
    select * from current_candidates union select * from historical_results
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cropCycleId',u.crop_cycle_id,'cropLabel',u.crop_label,'variety',u.variety,
      'zoneLabel',u.zone_label,'objectId',u.object_id,'objectLabel',u.object_label,
      'windowStart',u.window_start,'windowEnd',u.window_end,'cycleState',u.cycle_state,
      'availabilityStatus',u.availability_status,
      'originalPotentialStems',yf.original_potential_stems,
      'knownRemovedStems',yf.known_removed_stems,
      'remainingExpectedStems',yf.remaining_expected_stems,
      'harvestDepletionState',yf.harvest_depletion_state,
      'unresolvedHarvestDepletionEvents',yf.unresolved_harvest_depletion_events,
      'forecastState',yf.forecast_state,
      'forecastQuantityKind',coalesce(cp.metadata->>'forecast_quantity_kind','expected_seasonal_stems'),
      'forecastConfidence',coalesce(cp.metadata->>'forecast_confidence',case when yf.original_potential_stems is null then 'unresolved' else 'profile_based' end),
      'resolved',wr.id is not null,'resultKind',wr.result_kind,'harvestGrade',wr.harvest_grade,
      'bucketHalves',wr.bucket_halves,'resolvedAt',wr.resolved_at
    )) order by u.zone_label,u.object_label,u.crop_label,u.variety,u.crop_cycle_id),'[]'::jsonb),
    count(*)::integer,count(wr.id)::integer
  into v_rows,v_total,v_resolved
  from rows_union u
  left join atlas.weekly_harvest_task_results wr on wr.task_id=v_task.id and wr.crop_cycle_id=u.crop_cycle_id
  left join atlas.crop_cycle_yield_forecast yf on yf.crop_cycle_id=u.crop_cycle_id
  left join atlas.crop_cycles cc on cc.id=u.crop_cycle_id
  left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id;

  return jsonb_build_object(
    'contractVersion','weekly_harvest_round_v3','taskId',v_task.id,'status',v_task.status,'dueDate',v_task.due_date,
    'rows',v_rows,'totalRows',v_total,'resolvedRows',v_resolved,'complete',v_total>0 and v_total=v_resolved,'operatorMode',p_operator_mode,
    'truthBoundary',jsonb_build_object(
      'oneWorkerFacingHarvestCard',true,'cropRowsAreNotTasks',true,'cropCycleTruthRemainsCanonical',true,
      'cutFlowerUseTagRequired',true,'cropLossLeavesCard',true,'positiveBucketCountIsHarvestResult',true,
      'usableHarvestRequiresGrade',true,'harvestGrades',jsonb_build_array('florist_grade','event_grade'),
      'remainingSupplyComesFromYieldForecast',true,'unresolvedBucketQuantityNeverInventsStems',true,
      'onlySelectableExceptions',jsonb_build_array('not_ready','deadheaded','crop_loss'),'bucketIncrement',0.5
    )
  );
end;
$function$;

create or replace function atlas.weekly_harvest_task_state_for_member_v2(
  p_farm_id uuid,
  p_task_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.weekly_harvest_task_state_core_v2(p_task_id,v_membership,v_role,false);
end;
$function$;

create or replace function atlas.owner_operator_weekly_harvest_task_state_v2(
  p_effective_membership_id uuid,
  p_task_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_context jsonb;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  return atlas.weekly_harvest_task_state_core_v2(
    p_task_id,(v_context#>>'{effective,membershipId}')::uuid,v_context#>>'{effective,role}',true
  );
end;
$function$;

revoke all on function atlas.weekly_harvest_task_state_core_v2(uuid,uuid,text,boolean) from public;
revoke all on function atlas.weekly_harvest_task_state_for_member_v2(uuid,uuid) from public;
revoke all on function atlas.owner_operator_weekly_harvest_task_state_v2(uuid,uuid) from public;

grant execute on function atlas.weekly_harvest_task_state_for_member_v2(uuid,uuid) to authenticated;
grant execute on function atlas.owner_operator_weekly_harvest_task_state_v2(uuid,uuid) to authenticated;
grant execute on function atlas.weekly_harvest_task_state_core_v2(uuid,uuid,text,boolean) to service_role;
grant execute on function atlas.weekly_harvest_task_state_for_member_v2(uuid,uuid) to service_role;
grant execute on function atlas.owner_operator_weekly_harvest_task_state_v2(uuid,uuid) to service_role;

COMMIT;
