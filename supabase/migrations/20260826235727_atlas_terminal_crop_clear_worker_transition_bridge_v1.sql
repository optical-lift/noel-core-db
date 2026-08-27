create or replace function atlas.worker_state_transition_terminal_crop_bridge_v1(
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
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_card jsonb := coalesce(p_card,'{}'::jsonb);
  v_task atlas.tasks%rowtype;
  v_readiness jsonb;
  v_cycle_id uuid;
  v_cycle_object_id uuid;
  v_distinct_cycle_count integer := 0;
  v_confirmed_clear_count integer := 0;
  v_work_carrier_count integer := 0;
  v_selected_cycle_id uuid;
  v_cycles jsonb := '[]'::jsonb;
  v_routing_state text;
begin
  if p_service_date is null
     or coalesce(v_card#>>'{transition,state}','')='authorized_for_routed_day' then
    return v_card;
  end if;

  select * into v_task
  from atlas.tasks task
  where task.id=p_task_id
    and task.farm_id=p_farm_id
    and task.status='open'
    and (
      task.assigned_membership_id=p_membership_id
      or task.metadata->>'executor_membership_id'=p_membership_id::text
    );

  if v_task.id is null
     or coalesce(v_task.action_key,'')<>'clear'
     or coalesce(v_task.operation_class,'')<>'remove_uproot'
     or coalesce(v_task.task_type,'')<>'crop_clear' then
    return v_card;
  end if;

  v_routing_state:=coalesce(v_card#>>'{routing,state}','');
  if v_routing_state not in ('routed_to_membership','selected_for_worker_day') then
    return v_card;
  end if;

  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  if not coalesce((v_readiness->>'ready')::boolean,false)
     or coalesce((v_card#>>'{clock,definiteCapacityConflict}')::boolean,false) then
    return v_card;
  end if;

  select
    count(distinct cycle.id)::integer,
    count(*) filter (where link.role='clears' and link.confidence='confirmed')::integer,
    (array_agg(distinct cycle.id order by cycle.id))[1],
    (array_agg(distinct cycle.object_id order by cycle.object_id))[1]
  into v_distinct_cycle_count,v_confirmed_clear_count,v_cycle_id,v_cycle_object_id
  from atlas.task_crop_cycles link
  join atlas.crop_cycles cycle on cycle.id=link.crop_cycle_id
  where link.task_id=p_task_id
    and cycle.farm_id=p_farm_id
    and cycle.lifecycle_status='active';

  if v_distinct_cycle_count<>1
     or v_confirmed_clear_count<1
     or v_cycle_id is null
     or v_cycle_object_id is null then
    return v_card;
  end if;

  if nullif(v_task.metadata->>'selected_crop_cycle_id','') is not null then
    begin
      v_selected_cycle_id:=(v_task.metadata->>'selected_crop_cycle_id')::uuid;
    exception when invalid_text_representation then
      return v_card;
    end;
    if v_selected_cycle_id is distinct from v_cycle_id then
      return v_card;
    end if;
  end if;

  select count(*)::integer into v_work_carrier_count
  from atlas.task_objects link
  where link.task_id=p_task_id
    and link.role='work_carrier'
    and link.object_id=v_cycle_object_id;

  if v_work_carrier_count<>1 then
    return v_card;
  end if;

  select coalesce(jsonb_agg(
    jsonb_set(
      jsonb_set(subject,'{fittingOperation}',jsonb_build_object(
        'state','available',
        'source','confirmed_selected_crop_clear_task',
        'currentTaskId',p_task_id,
        'operationClass','remove_uproot',
        'cropCycleId',v_cycle_id,
        'objectId',v_cycle_object_id
      ),true),
      '{operationIdentity}',jsonb_build_object(
        'state','canonical_selected_crop_clear_task_match',
        'source','task_crop_cycles.confirmed_clears + task_objects.work_carrier',
        'currentTaskId',p_task_id,
        'cropCycleId',v_cycle_id,
        'objectId',v_cycle_object_id
      ),true
    ) order by subject->>'id'
  ),'[]'::jsonb)
  into v_cycles
  from (
    select distinct on (elem->>'id') elem as subject
    from jsonb_array_elements(coalesce(v_card#>'{currentReality,cropCycles}','[]'::jsonb)) elem
    where elem->>'id'=v_cycle_id::text
    order by elem->>'id'
  ) exact_subject;

  if jsonb_array_length(v_cycles)<>1 then
    return v_card;
  end if;

  v_card:=jsonb_set(v_card,'{currentReality,cropCycles}',v_cycles,true);
  v_card:=jsonb_set(v_card,'{currentReality,subjectCount}','1'::jsonb,true);
  v_card:=jsonb_set(v_card,'{currentReality,resolutionRequiredSubjectCount}','0'::jsonb,true);
  v_card:=jsonb_set(v_card,'{fittingFunction,state}',to_jsonb('exact_identity_supported'::text),true);
  v_card:=jsonb_set(v_card,'{fittingFunction,exactIdentityMismatchCount}','0'::jsonb,true);
  v_card:=jsonb_set(v_card,'{fittingFunction,operationIdentity}',jsonb_build_object(
    'state','canonical_selected_crop_clear_task_match',
    'source','task_crop_cycles.confirmed_clears + task_objects.work_carrier',
    'currentTaskId',p_task_id,
    'cropCycleId',v_cycle_id,
    'objectId',v_cycle_object_id
  ),true);
  v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('authorized_for_routed_day'::text),true);
  v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}',jsonb_strip_nulls(jsonb_build_object(
    'actionKey',v_task.action_key,
    'operationClass',v_task.operation_class,
    'do',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
    'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
    'dayWindow',nullif(v_card#>>'{routing,dayWindow}',''),
    'plannedStartAt',nullif(v_card#>>'{routing,plannedStartAt}',''),
    'plannedDurationMinutes',nullif(v_card#>>'{routing,plannedDurationMinutes}','')::integer
  )),true);
  v_card:=jsonb_set(v_card,'{truthBoundary,terminalCropClearBridge}',jsonb_build_object(
    'requiresConfirmedClearsLink',true,
    'requiresExactWorkCarrierObject',true,
    'requiresExactSelectedCropCycleWhenDeclared',true,
    'requiresExecutionReadiness',true,
    'requiresWorkerDayRouting',true,
    'authorizesOnlyNamedCropRemoval',true,
    'doesNotInferPlantingClaim',true,
    'doesNotInferSpatialExtent',true,
    'doesNotResolveCooccupantRelation',true,
    'doesNotInferPhysicalCompletion',true,
    'preservesHistoricalUnknowns',true
  ),true);

  return v_card;
end;
$function$;

revoke all on function atlas.worker_state_transition_terminal_crop_bridge_v1(uuid,uuid,uuid,date,jsonb) from public,anon,authenticated,service_role;

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
set search_path to 'pg_catalog','atlas','auth'
as $function$
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

  select * into v_task from atlas.tasks where id=p_task_id and farm_id=p_farm_id;
  if v_task.id is not null then
    v_is_germination:=atlas.is_germination_task_v1(v_task);
    v_is_direct_sow_seed:=coalesce(v_task.metadata->>'seed_governance_required','false')='true'
      and coalesce(v_task.metadata->>'seed_inventory_report_required','false')='true'
      and (coalesce(v_task.action_key,'')='sow' or coalesce(v_task.metadata->>'work_route','')='sow');
    v_requires_structured:=atlas.worker_task_requires_structured_result_v1(v_task.id);
    v_has_execution_checklist:=nullif(btrim(coalesce(v_task.metadata->>'execution_checklist_template_key','')),'') is not null;
  end if;
  v_authorized:=coalesce(v_card #>> '{transition,state}','')='authorized_for_routed_day';

  v_result_contract:=case
    when not v_authorized then jsonb_build_object(
      'state','operation_result_not_authorized','contractVersion','worker_record_state_transition_result_v1',
      'choices',jsonb_build_array('inspect'),'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb,
      'principle','No result may be returned for an operation Reality Expression has not authorized.'
    )
    when v_is_germination then jsonb_build_object(
      'state','structured_result_v1_available','contractVersion','worker_record_state_transition_result_v1','domainAdapter','germination_observation_v2',
      'choices',jsonb_build_array('not_yet','beginning','germinated','failed_or_uncertain','problem_found'),
      'requiredFields',jsonb_build_array('actualMinutes','idempotencyKey'),
      'conditionalFields',jsonb_build_object('germinated',jsonb_build_array('resultPayload.spacingOutcome'),'spacingOutcomeChoices',jsonb_build_array('thin','on_target','patch')),
      'optionalFields',jsonb_build_array('quantity','unit','note','resultPayload.targetSpacingInches'),
      'doneInvariant','Germinated closes the task only inside the same transaction that records the operation actual and reclassifies the canonical crop-cycle state.',
      'observationInvariant','The worker returns the physical observation; Atlas derives task status, rhythm satisfaction, continuation, and any handoff from that observation.'
    )
    when v_is_direct_sow_seed then jsonb_build_object(
      'state','structured_result_v1_available','contractVersion','record_direct_sow_seed_result_for_member_v1','domainAdapter','direct_sow_seed_v1',
      'choices',jsonb_build_array('depleted','exact_remaining','some_left_unknown'),
      'requiredFields',jsonb_build_array('actualMinutes','idempotencyKey'),
      'conditionalFields',jsonb_build_object('exact_remaining',jsonb_build_array('remainingQuantity')),
      'optionalFields',jsonb_build_array('note'),
      'doneInvariant','The sowing task closes only after the seed remainder event is recorded and the canonical seed state is reclassified in the same transaction.',
      'observationInvariant','Report only what is physically known after sowing: none left, an exact remaining count, or some left but unmeasured. Atlas must not infer an exact balance from task completion.'
    )
    when coalesce(v_task.metadata->>'task_style','')='farm_round' or coalesce(v_task.action_key,'')='farm_round' then jsonb_build_object(
      'state','aggregate_member_completion_only','contractVersion','farm_round_member_completion_v1',
      'choices',jsonb_build_array('complete_members'),
      'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb,
      'principle','Farm Round parent completion is derived from terminal member tasks; the parent has no direct Done result.'
    )
    when v_requires_structured and v_has_execution_checklist then jsonb_build_object(
      'state','execution_checklist_v1_available','contractVersion','execution_checklist_completion_v1','domainAdapter','execution_checklist_v1',
      'choices',jsonb_build_array('check_items','done','partial','blocked'),
      'requiredFields',jsonb_build_array('idempotencyKey'),
      'optionalFields',jsonb_build_array('note'),
      'principle','The task card checklist is the structured execution surface. Required physical components are recorded there; the final task transition closes the parent work without requiring a second domain adapter.',
      'doneInvariant','Required checklist components must be satisfied by the checklist-aware card before Done is offered; final completion reconciles task execution components through the canonical task transition.'
    )
    when v_requires_structured then jsonb_build_object(
      'state','structured_result_adapter_required','contractVersion','worker_record_state_transition_result_v1',
      'choices',jsonb_build_array('inspect'),'requiredFields','[]'::jsonb,'optionalFields','[]'::jsonb,
      'principle','This authorized operation needs a domain result adapter before generic Done is allowed.'
    )
    else jsonb_build_object(
      'state','quick_complete_v1_available','contractVersion','worker_quick_complete_v1',
      'choices',jsonb_build_array('done'),'requiredFields',jsonb_build_array('idempotencyKey'),'optionalFields',jsonb_build_array('note'),
      'transition','done','principle','This authorized operation may close through the canonical task transition because no additional domain witness fields are required.'
    )
  end;

  v_card:=jsonb_set(v_card,'{contractVersion}',to_jsonb('worker_state_transition_card_v2'::text),true);
  v_card:=jsonb_set(v_card,'{resultReturn}',v_result_contract,true);
  v_card:=jsonb_set(v_card,'{truthBoundary,resultContractDeferredToPhase6}','false'::jsonb,true);
  v_card:=jsonb_set(v_card,'{truthBoundary,quickCompleteAuthority}',to_jsonb('canonical_result_return'::text),true);
  return v_card;
end;
$function$;

revoke all on function atlas.worker_state_transition_card_v2(uuid,uuid,uuid,date) from public,anon;
grant execute on function atlas.worker_state_transition_card_v2(uuid,uuid,uuid,date) to authenticated,service_role;