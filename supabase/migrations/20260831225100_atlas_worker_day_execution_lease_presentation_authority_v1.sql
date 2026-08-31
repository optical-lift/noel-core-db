BEGIN;

-- Worker Day presentation/action cutover v1.
-- A day with zero live leases keeps the compatibility planner. The first live
-- lease atomically switches that recipient/day to lease-mode: presentation and
-- state-transition authorization both come from the same execution handoff.

create or replace function atlas.worker_task_live_execution_lease_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_mode boolean:=false;
  v_result jsonb;
begin
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then return null; end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  select exists(
    select 1 from atlas.execution_leases l
    where l.custody_kind='organization'
      and l.organization_id=v_org_id
      and l.recipient_kind='farm_membership'
      and l.recipient_id=p_membership_id
      and l.lease_kind='work_execution'
      and l.shadow_only=false
      and l.lease_start<v_end and l.lease_end>v_start
  ) into v_mode;

  if not v_mode then
    return jsonb_build_object('contractVersion','worker_task_live_execution_lease_v1','liveLeaseMode',false);
  end if;

  select jsonb_build_object(
    'contractVersion','worker_task_live_execution_lease_v1',
    'liveLeaseMode',true,
    'leaseId',l.id,
    'leaseKey',l.lease_key,
    'leaseState',e.resulting_state,
    'actionable',e.resulting_state in ('leased','started'),
    'interrupted',e.resulting_state='interrupted',
    'terminal',e.resulting_state in ('completed','withdrawn','expired'),
    'lastEventKind',e.event_kind,
    'lastEventReason',e.reason,
    'lastEventAt',e.occurred_at,
    'admissionWarrant',l.admission_warrant,
    'metadata',l.metadata
  ) into v_result
  from atlas.execution_leases l
  join lateral (
    select x.event_kind,x.resulting_state,x.reason,x.occurred_at
    from atlas.execution_lease_events x
    where x.lease_id=l.id
    order by x.occurred_at desc,x.id desc
    limit 1
  ) e on true
  where l.custody_kind='organization'
    and l.organization_id=v_org_id
    and l.recipient_kind='farm_membership'
    and l.recipient_id=p_membership_id
    and l.lease_kind='work_execution'
    and l.shadow_only=false
    and l.execution_kind='task'
    and l.execution_id=p_task_id
    and l.lease_start<v_end and l.lease_end>v_start
  order by l.created_at desc,l.id desc
  limit 1;

  return coalesce(v_result,jsonb_build_object(
    'contractVersion','worker_task_live_execution_lease_v1',
    'liveLeaseMode',true,
    'leaseId',null,
    'leaseState','not_leased',
    'actionable',false
  ));
end;
$$;

revoke all on function atlas.worker_task_live_execution_lease_v1(uuid,uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_task_live_execution_lease_v1(uuid,uuid,uuid,date) to service_role;

create or replace function atlas.worker_state_transition_lease_bridge_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date,
  p_card jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_card jsonb:=coalesce(p_card,'{}'::jsonb);
  v_lease jsonb;
  v_readiness jsonb;
  v_fit jsonb;
  v_task atlas.tasks%rowtype;
  v_state text;
  v_capacity record;
begin
  v_lease:=atlas.worker_task_live_execution_lease_v1(p_farm_id,p_membership_id,p_task_id,p_service_date);
  if not coalesce((v_lease->>'liveLeaseMode')::boolean,false) then
    return v_card;
  end if;

  select * into v_task from atlas.tasks t where t.id=p_task_id and t.farm_id=p_farm_id;
  v_card:=jsonb_set(v_card,'{executionLease}',v_lease,true);
  v_card:=jsonb_set(v_card,'{truthBoundary,leaseMode}',jsonb_build_object(
    'plannerIsAdvisory',true,
    'leaseIsRoutingAuthority',true,
    'leaseIsWorkerActionAuthority',true,
    'plannerSelectionCannotAuthorizeWithoutLease',true
  ),true);

  if v_lease->>'leaseId' is null then
    v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('not_leased_for_worker_day'::text),true);
    v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('execution_lease_required'::text),true);
    v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}','null'::jsonb,true);
    return v_card;
  end if;

  v_state:=coalesce(v_lease->>'leaseState','not_leased');
  if v_state='interrupted' then
    v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('leased_but_interrupted'::text),true);
    v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('execution_lease_interrupted'::text),true);
    v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}','null'::jsonb,true);
    return v_card;
  elsif v_state in ('completed','withdrawn','expired') then
    v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('lease_terminal'::text),true);
    v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('execution_lease_'||v_state),true);
    v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}','null'::jsonb,true);
    return v_card;
  elsif v_state not in ('leased','started') then
    v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('execution_lease_required'::text),true);
    v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}','null'::jsonb,true);
    return v_card;
  end if;

  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  v_fit:=atlas.task_operation_fit_warrant_v1(p_task_id);
  if v_task.id is null or v_task.status<>'open'
     or not coalesce((v_readiness->>'executionReady')::boolean,false)
     or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false) then
    v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('leased_interruption_required'::text),true);
    v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('execution_lease_interruption_required'::text),true);
    v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}','null'::jsonb,true);
    return v_card;
  end if;

  select * into v_capacity from atlas.task_capacity_plan_v1(v_task,p_service_date);
  v_card:=jsonb_set(v_card,'{routing,state}',to_jsonb('leased_to_membership'::text),true);
  v_card:=jsonb_set(v_card,'{jurisdiction,state}',to_jsonb('leased_body_established'::text),true);
  v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('authorized_for_routed_day'::text),true);
  v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}',jsonb_strip_nulls(jsonb_build_object(
    'actionKey',v_task.action_key,
    'operationClass',v_task.operation_class,
    'do',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
    'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
    'dayWindow',atlas.worker_task_day_window_v1(v_task.action_key,v_task.task_type,v_task.metadata),
    'plannedStartAt',null,
    'plannedDurationMinutes',v_capacity.expected_active_minutes,
    'executionLeaseId',v_lease->>'leaseId'
  )),true);
  return v_card;
end;
$$;

revoke all on function atlas.worker_state_transition_lease_bridge_v1(uuid,uuid,uuid,date,jsonb) from public,anon,authenticated;
grant execute on function atlas.worker_state_transition_lease_bridge_v1(uuid,uuid,uuid,date,jsonb) to service_role;

create or replace function atlas.worker_day_feed_plan_planner_v1(
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
  v_capacity jsonb;
  v_target integer:=0;
  v_real jsonb:='[]'::jsonb;
  v_committed integer:=0;
begin
  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass' in ('recovery','explicit_override')
    then greatest(coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0),0)
    else greatest(coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0),0) end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id','task:'||t.id::text,'kind','real','sourceKind','task','sourceId',t.id,'taskId',t.id,
    'title',t.title,'status',t.status,'expectedActiveMinutes',cp.expected_active_minutes,
    'dayWindow',resolved.placement->>'dayWindow','workOrderNumber',(resolved.placement->>'sortOrder')::numeric,
    'placementAuthority',resolved.placement->>'source','automatic',false,'requiresOwnerApproval',false,
    'reason',case when p.presentation_state='presented' then p.presentation_reason else p.visibility_reason end,
    'commitmentKind',p.commitment_kind,'visibilityState',p.visibility_state,
    'visibilityReason',p.visibility_reason,'presentationState',p.presentation_state,
    'presentationReason',p.presentation_reason,'presentationAuthority','planner_compatibility'
  ) order by p.selection_rank,t.id),'[]'::jsonb),
  coalesce(sum(cp.expected_active_minutes),0)::integer
  into v_real,v_committed
  from atlas.worker_day_work_projection_v1(p_farm_id,p_membership_id,p_day) p
  join atlas.tasks t on t.id=p.task_id
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) cp
  cross join lateral (select atlas.worker_task_effective_placement_v1(p_farm_id,p_membership_id,t.id,p_day) as placement) resolved;

  return jsonb_build_object(
    'contractVersion','worker_day_feed_plan_planner_v1','farmId',p_farm_id,'membershipId',p_membership_id,
    'serviceDate',p_day,'availableWorkerDay',atlas.worker_day_available_v1(p_farm_id,p_membership_id,p_day),
    'paidTargetMinutes',v_target,'committedPaidMinutes',v_committed,'automaticPaidMinutes',0,
    'remainingPaidMinutes',greatest(v_target-v_committed,0),'realWork',v_real,'automaticWork','[]'::jsonb,
    'suggestions','[]'::jsonb,'warnings','[]'::jsonb,'presentationAuthority','planner_compatibility',
    'workProjectionContractVersion','worker_day_work_projection_v1'
  );
end;
$$;

revoke all on function atlas.worker_day_feed_plan_planner_v1(uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_day_feed_plan_planner_v1(uuid,uuid,date) to service_role;

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
      'id','lease:'||(l->>'leaseId'),'kind','real','sourceKind','execution_lease','sourceId',l->>'leaseId',
      'leaseId',l->>'leaseId','leaseState',l->>'state','actionable',coalesce((l->>'actionable')::boolean,false),
      'taskId',l->>'executionId','title',l->>'title','status',t.status,
      'expectedActiveMinutes',coalesce(nullif(l#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes),
      'dayWindow',resolved.placement->>'dayWindow',
      'workOrderNumber',coalesce(nullif(l#>>'{metadata,admissionRank}','')::numeric,(resolved.placement->>'sortOrder')::numeric),
      'placementAuthority','execution_lease','automatic',false,'requiresOwnerApproval',false,
      'reason',case when l->>'state'='interrupted' then 'execution_lease_interrupted' else 'execution_lease' end,
      'interruptionReason',case when l->>'state'='interrupted' then l->>'lastEventReason' else null end,
      'presentationAuthority','execution_lease','admissionWarrant',l->'admissionWarrant'
    )) order by coalesce(nullif(l#>>'{metadata,admissionRank}','')::integer,2147483647),l->>'leaseId'),'[]'::jsonb),
    coalesce(sum(case when coalesce((l->>'actionable')::boolean,false)
      then coalesce(nullif(l#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer,
    coalesce(sum(case when l->>'state'='interrupted'
      then coalesce(nullif(l#>>'{metadata,expectedActiveMinutes}','')::integer,cp.expected_active_minutes,0) else 0 end),0)::integer
  into v_real,v_committed,v_interrupted
  from jsonb_array_elements(coalesce(v_packet->'leases','[]'::jsonb)) l
  left join atlas.tasks t on (l->>'executionKind')='task' and t.id=(l->>'executionId')::uuid
  left join lateral atlas.task_capacity_plan_v1(t,p_day) cp on t.id is not null
  left join lateral (select atlas.worker_task_effective_placement_v1(p_farm_id,p_membership_id,t.id,p_day) as placement) resolved on t.id is not null
  where l->>'state' in ('leased','started','interrupted');

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

create or replace function atlas.worker_day_operational_task_cards_v3(
  p_farm_id uuid,
  p_membership_id uuid,
  p_service_date date,
  p_task_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_cards jsonb:='[]'::jsonb;
  v_result jsonb:='[]'::jsonb;
  v_card jsonb;
  v_task_id uuid;
  v_readiness jsonb;
  v_status text;
  v_transition_card jsonb;
  v_result_state text;
  v_metadata jsonb;
  v_lease jsonb;
  v_keep boolean;
begin
  v_cards:=atlas.worker_day_operational_task_cards_v2(p_farm_id,p_membership_id,p_service_date,p_task_ids);
  for v_card in select value from jsonb_array_elements(v_cards)
  loop
    v_task_id:=nullif(v_card->>'task_id','')::uuid;
    v_status:=coalesce(v_card->>'status','');
    v_readiness:=atlas.task_execution_readiness_v1(v_task_id);
    v_lease:=atlas.worker_task_live_execution_lease_v1(p_farm_id,p_membership_id,v_task_id,p_service_date);
    v_keep:=v_status='done'
      or coalesce((v_readiness->>'executionReady')::boolean,false)
      or (coalesce((v_lease->>'liveLeaseMode')::boolean,false) and v_lease->>'leaseId' is not null and coalesce(v_lease->>'leaseState','') not in ('withdrawn','expired'));

    if v_keep then
      v_transition_card:=case when v_status='done' then null else atlas.worker_state_transition_card_v2(p_farm_id,p_membership_id,v_task_id,p_service_date) end;
      v_result_state:=coalesce(v_transition_card#>>'{resultReturn,state}','');
      v_metadata:=coalesce(v_card->'metadata','{}'::jsonb)||jsonb_build_object(
        'quick_complete_allowed',v_result_state='quick_complete_v1_available',
        'structured_result_required',v_result_state in ('structured_result_v1_available','structured_result_adapter_required'),
        'worker_result_return_state',nullif(v_result_state,''),
        'worker_transition_state',nullif(v_transition_card#>>'{transition,state}',''),
        'worker_result_authority','worker_state_transition_card_v2',
        'execution_lease_id',v_lease->>'leaseId',
        'execution_lease_state',v_lease->>'leaseState',
        'execution_lease_actionable',coalesce((v_lease->>'actionable')::boolean,false)
      );
      v_result:=v_result||jsonb_build_array(v_card||jsonb_build_object(
        'metadata',v_metadata,'worker_transition_card',v_transition_card,
        'resource_requirements',atlas.task_resource_requirement_packet_v1(v_task_id),
        'execution_readiness',v_readiness,'state_consequence_gate',v_readiness->'stateConsequenceGate',
        'preparation_required',coalesce((v_readiness->>'preparationRequired')::boolean,false),
        'execution_lease',v_lease
      ));
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function atlas.worker_state_transition_card_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_card jsonb;
  v_task atlas.tasks%rowtype;
  v_authorized boolean;
  v_is_germination boolean:=false;
  v_is_direct_sow_seed boolean:=false;
  v_requires_structured boolean:=true;
  v_has_execution_checklist boolean:=false;
  v_result_contract jsonb;
begin
  v_card:=atlas.worker_state_transition_card_pre_or4_v2(p_farm_id,p_membership_id,p_task_id,p_service_date);
  v_card:=atlas.worker_state_transition_planned_establishment_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);
  v_card:=atlas.worker_state_transition_followup_crop_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);
  v_card:=atlas.worker_state_transition_selection_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);
  v_card:=atlas.worker_state_transition_terminal_crop_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);
  -- Final authority membrane. In lease-mode this may revoke any authorization
  -- produced by compatibility bridges unless the exact task has a live lease.
  v_card:=atlas.worker_state_transition_lease_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);

  select * into v_task from atlas.tasks where id=p_task_id and farm_id=p_farm_id;
  if v_task.id is not null then
    v_is_germination:=atlas.is_germination_task_v1(v_task);
    v_is_direct_sow_seed:=coalesce(v_task.metadata->>'seed_governance_required','false')='true'
      and coalesce(v_task.metadata->>'seed_inventory_report_required','false')='true'
      and (coalesce(v_task.action_key,'')='sow' or coalesce(v_task.metadata->>'work_route','')='sow');
    v_requires_structured:=atlas.worker_task_requires_structured_result_v1(v_task.id);
    v_has_execution_checklist:=nullif(btrim(coalesce(v_task.metadata->>'execution_checklist_template_key','')),'') is not null;
  end if;
  v_authorized:=coalesce(v_card#>>'{transition,state}','')='authorized_for_routed_day';

  v_result_contract:=case
    when not v_authorized then jsonb_build_object(
      'state','operation_result_not_authorized','contractVersion','worker_record_state_transition_result_v1',
      'choices',jsonb_build_array('inspect'),'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb,
      'principle','No result may be returned for an operation that the current execution lease + Reality warrant do not authorize.'
    )
    when v_is_germination then jsonb_build_object(
      'state','structured_result_v1_available','contractVersion','worker_record_state_transition_result_v1','domainAdapter','germination_observation_v2',
      'choices',jsonb_build_array('not_yet','beginning','germinated','failed_or_uncertain','problem_found'),
      'requiredFields',jsonb_build_array('actualMinutes','idempotencyKey'),
      'conditionalFields',jsonb_build_object('germinated',jsonb_build_array('resultPayload.spacingOutcome'),'spacingOutcomeChoices',jsonb_build_array('thin','on_target','patch')),
      'optionalFields',jsonb_build_array('quantity','unit','note','resultPayload.targetSpacingInches')
    )
    when v_is_direct_sow_seed then jsonb_build_object(
      'state','structured_result_v1_available','contractVersion','record_direct_sow_seed_result_for_member_v1','domainAdapter','direct_sow_seed_v1',
      'choices',jsonb_build_array('depleted','exact_remaining','some_left_unknown'),'requiredFields',jsonb_build_array('actualMinutes','idempotencyKey'),
      'conditionalFields',jsonb_build_object('exact_remaining',jsonb_build_array('remainingQuantity')),'optionalFields',jsonb_build_array('note')
    )
    when coalesce(v_task.metadata->>'task_style','')='farm_round' or coalesce(v_task.action_key,'')='farm_round' then jsonb_build_object(
      'state','aggregate_member_completion_only','contractVersion','farm_round_member_completion_v1','choices',jsonb_build_array('complete_members'),
      'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb
    )
    when v_requires_structured and v_has_execution_checklist then jsonb_build_object(
      'state','execution_checklist_v1_available','contractVersion','execution_checklist_completion_v1','domainAdapter','execution_checklist_v1',
      'choices',jsonb_build_array('check_items','done','partial','blocked'),'requiredFields',jsonb_build_array('idempotencyKey'),'optionalFields',jsonb_build_array('note')
    )
    when v_requires_structured then jsonb_build_object(
      'state','structured_result_adapter_required','contractVersion','worker_record_state_transition_result_v1','choices',jsonb_build_array('inspect'),
      'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb
    )
    else jsonb_build_object(
      'state','quick_complete_v1_available','contractVersion','worker_quick_complete_v1','choices',jsonb_build_array('done'),
      'requiredFields',jsonb_build_array('idempotencyKey'),'optionalFields',jsonb_build_array('note'),'transition','done'
    )
  end;

  v_card:=jsonb_set(v_card,'{contractVersion}',to_jsonb('worker_state_transition_card_v2'::text),true);
  v_card:=jsonb_set(v_card,'{resultReturn}',v_result_contract,true);
  v_card:=jsonb_set(v_card,'{truthBoundary,resultContractDeferredToPhase6}','false'::jsonb,true);
  v_card:=jsonb_set(v_card,'{truthBoundary,quickCompleteAuthority}',to_jsonb('execution_lease_plus_canonical_result_return'::text),true);
  return v_card;
end;
$$;

create or replace function atlas.worker_self_day_bundle_api_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_timezone text:='America/Chicago';
  v_today date;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
  v_packet jsonb;
  v_reconciliation jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.farm_memberships m where m.id=p_membership_id and m.farm_id=p_farm_id and m.user_id=auth.uid() and m.active=true and m.role='farm_hand') then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone from atlas.farms f where f.id=p_farm_id;
  v_today:=(now() at time zone coalesce(v_timezone,'America/Chicago'))::date;
  if p_day<>v_today then return atlas.worker_self_day_bundle_api_v1(p_farm_id,p_membership_id,p_day); end if;

  v_packet:=atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day);
  if not coalesce((v_packet->>'liveLeaseMode')::boolean,false) then
    v_packet:=atlas.open_worker_day_execution_leases_v1(
      p_farm_id,p_membership_id,p_day,'Worker opened current Worker Day.',auth.uid()
    );
  end if;

  v_reconciliation:=atlas.reconcile_worker_day_execution_leases_v1(p_farm_id,p_membership_id,p_day,auth.uid());
  v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)
    || jsonb_build_object('clockTimeline',null,'suggestions','[]'::jsonb);

  select coalesce(array_agg(distinct x.task_id) filter(where x.task_id is not null),array[]::uuid[])
  into v_task_ids
  from (
    select nullif(row->>'taskId','')::uuid task_id
    from jsonb_array_elements(coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)) row
  ) x;

  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(jsonb_agg(card-'move_context' order by ord),'[]'::jsonb)
  into v_safe_cards
  from jsonb_array_elements(v_cards) with ordinality as cards(card,ord);

  return jsonb_build_object(
    'contractVersion','worker_self_day_bundle_execution_lease_v1',
    'plan',v_plan,
    'taskCards',v_safe_cards,
    'executionLeaseReconciliation',v_reconciliation,
    'trustBoundary',jsonb_build_object(
      'dayOpeningCreatesLeases',true,
      'feedReadsLeases',true,
      'doneAuthorityReadsSameLease',true,
      'interruptedLeaseRemainsVisible',true
    )
  );
end;
$$;

comment on function atlas.worker_self_day_bundle_api_v2(uuid,uuid,date) is
  'Current-day Farm Hand bundle. First open atomically establishes live execution leases; subsequent reads reconcile reality and present the durable leases rather than recomputing the human day.';

COMMIT;
