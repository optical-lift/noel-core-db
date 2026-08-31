BEGIN;

-- Normalize jsonb_array_elements aliasing before any live lease cutover occurs.
create or replace function atlas.worker_day_feed_plan_live_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_packet jsonb;
  v_capacity jsonb;
  v_target integer:=0;
  v_real jsonb:='[]'::jsonb;
  v_committed integer:=0;
  v_interrupted integer:=0;
begin
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  v_packet:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if not coalesce((v_packet->>'liveLeaseMode')::boolean,false) then
    return atlas.worker_day_feed_plan_planner_v1(p_farm_id,p_membership_id,p_day);
  end if;

  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass' in ('recovery','explicit_override')
    then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0) end;

  select
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id','lease:'||(lease.value->>'leaseId'),'kind','real','sourceKind','execution_lease','sourceId',lease.value->>'leaseId',
      'leaseId',lease.value->>'leaseId','leaseState',lease.value->>'state','actionable',coalesce((lease.value->>'actionable')::boolean,false),
      'taskId',lease.value->>'executionId','title',lease.value->>'title','status',t.status,
      'expectedActiveMinutes',coalesce(nullif(lease.value#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes),
      'dayWindow',resolved.placement->>'dayWindow',
      'workOrderNumber',coalesce(nullif(lease.value#>>'{metadata,admissionRank}','')::numeric,(resolved.placement->>'sortOrder')::numeric),
      'placementAuthority','execution_lease','automatic',false,'requiresOwnerApproval',false,
      'reason',case when lease.value->>'state'='interrupted' then 'execution_lease_interrupted' else 'execution_lease' end,
      'interruptionReason',case when lease.value->>'state'='interrupted' then lease.value->>'lastEventReason' else null end,
      'presentationAuthority','execution_lease','admissionWarrant',lease.value->'admissionWarrant'
    )) order by coalesce(nullif(lease.value#>>'{metadata,admissionRank}','')::integer,2147483647),lease.value->>'leaseId'),'[]'::jsonb),
    coalesce(sum(case when coalesce((lease.value->>'actionable')::boolean,false)
      then coalesce(nullif(lease.value#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer,
    coalesce(sum(case when lease.value->>'state'='interrupted'
      then coalesce(nullif(lease.value#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer
  into v_real,v_committed,v_interrupted
  from jsonb_array_elements(coalesce(v_packet->'leases','[]'::jsonb)) as lease(value)
  left join atlas.tasks t on (lease.value->>'executionKind')='task' and t.id=(lease.value->>'executionId')::uuid
  left join lateral atlas.task_capacity_plan_v1(t,p_day) cp on t.id is not null
  left join lateral (select atlas.worker_task_effective_placement_v1(p_farm_id,p_membership_id,t.id,p_day) as placement) resolved on t.id is not null
  where lease.value->>'state' in ('leased','started','interrupted');

  return jsonb_build_object(
    'contractVersion','worker_day_feed_plan_execution_lease_v1','farmId',p_farm_id,'membershipId',p_membership_id,
    'serviceDate',p_day,'availableWorkerDay',true,'paidTargetMinutes',v_target,
    'committedPaidMinutes',v_committed,'interruptedPaidMinutes',v_interrupted,'automaticPaidMinutes',0,
    'remainingPaidMinutes',greatest(v_target-v_committed,0),'realWork',v_real,'automaticWork','[]'::jsonb,
    'suggestions','[]'::jsonb,'warnings','[]'::jsonb,'presentationAuthority','execution_lease',
    'executionLeasePacket',v_packet
  );
end;
$$;

COMMIT;
