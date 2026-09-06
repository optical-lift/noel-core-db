create or replace function atlas.company_work_task_operation_fit_warrant_v1(p_task_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
  v_assignment atlas.production_bed_assignments%rowtype;
  v_occ atlas.planned_work_occurrences%rowtype;
  v_governed boolean:=false;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then
    return jsonb_build_object('recognized',false,'exactIdentitySupported',false,'state','missing_task');
  end if;

  select a.* into v_adapter
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
  where a.task_id=v_task.id
    and a.state='active'
    and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
  order by a.created_at desc
  limit 1;
  if v_adapter.id is null then
    return jsonb_build_object('recognized',false,'exactIdentitySupported',false,'state','not_governed_company_work');
  end if;
  v_governed:=true;

  select * into v_work from atlas.work_items
  where id=v_adapter.work_item_id and organization_id=v_adapter.organization_id;
  if v_work.id is null or v_work.work_state<>'open' then
    return jsonb_build_object('recognized',true,'governedCompanyWork',true,'exactIdentitySupported',false,'state','company_work_not_open');
  end if;
  if v_adapter.planned_occurrence_id is null
     or v_task.planned_occurrence_id is distinct from v_adapter.planned_occurrence_id then
    return jsonb_build_object('recognized',true,'governedCompanyWork',true,'exactIdentitySupported',false,'state','carrier_occurrence_mismatch');
  end if;
  select * into v_occ from atlas.planned_work_occurrences where id=v_adapter.planned_occurrence_id;
  if v_occ.id is null or v_occ.farm_id<>v_task.farm_id then
    return jsonb_build_object('recognized',true,'governedCompanyWork',true,'exactIdentitySupported',false,'state','occurrence_provenance_missing');
  end if;

  if v_work.source_object_type='production_bed_assignment'
     and v_work.result_contract_key='production_bed_preparation_v1' then
    select * into v_assignment from atlas.production_bed_assignments
    where id=v_work.source_object_id and farm_id=v_task.farm_id;
    if v_assignment.id is null or v_assignment.assignment_status<>'assigned' then
      return jsonb_build_object(
        'recognized',true,'governedCompanyWork',true,'exactIdentitySupported',false,
        'state','production_bed_assignment_not_active',
        'workItemId',v_work.id,'sourceObjectId',v_work.source_object_id
      );
    end if;
    if v_assignment.object_id is null or v_assignment.production_lot_id is null then
      return jsonb_build_object(
        'recognized',true,'governedCompanyWork',true,'exactIdentitySupported',false,
        'state','production_bed_assignment_incomplete',
        'workItemId',v_work.id,'sourceObjectId',v_work.source_object_id
      );
    end if;

    return jsonb_build_object(
      'contractVersion','company_work_task_operation_fit_warrant_v1',
      'recognized',true,
      'governedCompanyWork',true,
      'exactIdentitySupported',true,
      'state','canonical_company_work_source_identity',
      'taskId',v_task.id,
      'workItemId',v_work.id,
      'resultContractKey',v_work.result_contract_key,
      'sourceDomain','production',
      'sourceObjectType',v_work.source_object_type,
      'sourceObjectId',v_work.source_object_id,
      'productionLotId',v_assignment.production_lot_id,
      'destinationObjectId',v_assignment.object_id,
      'operationFunction',coalesce(nullif(v_task.action_key,''),'prepare'),
      'truthBoundary',jsonb_build_object(
        'companyWorkIsOperationIdentityNotSourceReality',true,
        'productionAssignmentRemainsSourceAuthority',true,
        'bedPreparationMayProceedBeforeSeedReadiness',true,
        'doesNotAssertNextBiologicalTransitionAvailable',true,
        'doesNotAssertBedPreparationCompleted',true,
        'doesNotReplaceExecutionReadiness',true,
        'doesNotReplaceResponsibilityOrWorkerDayLease',true
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_task_operation_fit_warrant_v1',
    'recognized',true,'governedCompanyWork',v_governed,'exactIdentitySupported',false,
    'state','governed_company_work_contract_not_adapted',
    'taskId',v_task.id,'workItemId',v_work.id,'resultContractKey',v_work.result_contract_key,
    'sourceObjectType',v_work.source_object_type,'sourceObjectId',v_work.source_object_id
  );
end;
$$;

create or replace function atlas.task_operation_fit_warrant_v1(p_task_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_rec record;
  v_packet jsonb;
  v_company jsonb;
  v_subject_count integer:=0;
  v_mismatch_count integer:=0;
  v_state text;
  v_function text;
  v_current_task_id uuid;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;

  v_company:=atlas.company_work_task_operation_fit_warrant_v1(p_task_id);
  if coalesce((v_company->>'recognized')::boolean,false) then
    return jsonb_build_object(
      'contractVersion','task_operation_fit_warrant_v2',
      'taskId',p_task_id,
      'subjectCount',case when coalesce((v_company->>'exactIdentitySupported')::boolean,false) then 1 else 0 end,
      'identityMismatchCount',case when coalesce((v_company->>'exactIdentitySupported')::boolean,false) then 0 else 1 end,
      'exactIdentitySupported',coalesce((v_company->>'exactIdentitySupported')::boolean,false),
      'state',case when coalesce((v_company->>'exactIdentitySupported')::boolean,false) then 'supported_by_company_work_source' else 'unresolved_company_work_source' end,
      'companyWorkWarrant',v_company,
      'truthBoundary',jsonb_build_object(
        'taskLabelIsNotIdentityProof',true,
        'companyWorkCarrierRequiresCanonicalSourceIdentity',true,
        'companyWorkIdentityDoesNotAdvanceSourceDomainState',true,
        'subjectBearingTaskRequiresExactRealityIdentity',true
      )
    );
  end if;

  for v_rec in
    select cc.id from atlas.task_crop_cycles l join atlas.crop_cycles cc on cc.id=l.crop_cycle_id where l.task_id=p_task_id
  loop
    v_subject_count:=v_subject_count+1;
    v_packet:=atlas.crop_cycle_reality_expression_v3(v_rec.id);
    v_state:=coalesce(v_packet#>>'{fittingOperation,state}','unresolved');
    begin v_current_task_id:=nullif(v_packet#>>'{fittingOperation,currentTaskId}','')::uuid;
    exception when invalid_text_representation then v_current_task_id:=null; end;
    if v_state not in ('available','required') or v_current_task_id is distinct from p_task_id then v_mismatch_count:=v_mismatch_count+1; end if;
  end loop;

  for v_rec in
    select lot.id from atlas.production_lot_tasks l join atlas.production_lots lot on lot.id=l.production_lot_id where l.task_id=p_task_id
  loop
    v_subject_count:=v_subject_count+1;
    v_packet:=atlas.reality_expression_packet_v2(v_rec.id);
    v_state:=coalesce(v_packet#>>'{flowBufferClaim,nextTransitionAvailability,state}','not_available');
    v_function:=nullif(v_packet#>>'{flowBufferClaim,nextTransitionAvailability,operationFunction}','');
    if v_state not in ('available_for_routing_unclaimed','claimed_for_execution_capacity_fit_unverified') or v_function is distinct from v_task.action_key then
      v_mismatch_count:=v_mismatch_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','task_operation_fit_warrant_v1','taskId',p_task_id,'subjectCount',v_subject_count,
    'identityMismatchCount',v_mismatch_count,'exactIdentitySupported',v_mismatch_count=0,
    'state',case when v_mismatch_count=0 then 'supported' else 'unresolved' end,
    'truthBoundary',jsonb_build_object(
      'taskLabelIsNotIdentityProof',true,'zeroSubjectTaskUsesExecutionRequirements',true,
      'subjectBearingTaskRequiresExactRealityIdentity',true
    )
  );
end;
$$;

create or replace function atlas.worker_state_transition_company_work_bridge_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_task_id uuid,
  p_service_date date,
  p_card jsonb
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_card jsonb:=coalesce(p_card,'{}'::jsonb);
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_fit jsonb;
  v_readiness jsonb;
  v_placement atlas.worker_day_task_placements%rowtype;
begin
  if p_service_date is null then return v_card; end if;
  if coalesce(v_card#>>'{transition,state}','')='authorized_for_routed_day' then return v_card; end if;

  select * into v_task from atlas.tasks
  where id=p_task_id and farm_id=p_farm_id and status='open' and assigned_membership_id=p_membership_id;
  if v_task.id is null then return v_card; end if;
  select * into v_member from atlas.farm_memberships
  where id=p_membership_id and farm_id=p_farm_id and active and role='farm_hand';
  if v_member.id is null then return v_card; end if;

  select a.* into v_adapter
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
  where a.task_id=v_task.id and a.state='active'
    and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
  order by a.created_at desc limit 1;
  if v_adapter.id is null then return v_card; end if;
  select * into v_work from atlas.work_items where id=v_adapter.work_item_id and organization_id=v_adapter.organization_id and work_state='open';
  if v_work.id is null then return v_card; end if;

  select * into v_allocation from atlas.work_allocations
  where organization_id=v_work.organization_id and work_item_id=v_work.id and state='active' and allocation_role='responsible' limit 1;
  if v_allocation.id is null then return v_card; end if;
  select * into v_org_member from atlas.organization_memberships
  where id=v_allocation.assignee_membership_id and organization_id=v_work.organization_id and active;
  if v_org_member.id is null or v_org_member.user_id<>v_member.user_id then return v_card; end if;

  select * into v_plan from atlas.work_execution_plans
  where organization_id=v_work.organization_id and work_item_id=v_work.id
    and plan_state='active' and responsible_allocation_id=v_allocation.id
    and assignee_membership_id=v_org_member.id and exposure_service_date=p_service_date
  limit 1;
  if v_plan.id is null then return v_card; end if;

  select * into v_placement from atlas.worker_day_task_placements
  where task_id=v_task.id and membership_id=p_membership_id and farm_id=p_farm_id
    and state='placed' and service_date=p_service_date;
  if v_placement.id is null then return v_card; end if;

  v_fit:=atlas.company_work_task_operation_fit_warrant_v1(v_task.id);
  if not coalesce((v_fit->>'exactIdentitySupported')::boolean,false) then return v_card; end if;
  v_readiness:=atlas.task_execution_readiness_v1(v_task.id);
  if not coalesce((v_readiness->>'executionReady')::boolean,false) then return v_card; end if;

  v_card:=jsonb_set(v_card,'{currentReality,companyWork}',jsonb_build_object(
    'state','canonical_operation_established',
    'workItemId',v_work.id,
    'sourceDomain',v_fit->>'sourceDomain',
    'sourceObjectType',v_work.source_object_type,
    'sourceObjectId',v_work.source_object_id,
    'resultContractKey',v_work.result_contract_key,
    'responsibleAllocationId',v_allocation.id,
    'executionPlanId',v_plan.id,
    'operationWarrant',v_fit
  ),true);
  v_card:=jsonb_set(v_card,'{fittingFunction}',jsonb_build_object(
    'state','exact_identity_supported',
    'source','company_work_canonical_source_warrant',
    'taskProposedActionKey',v_task.action_key,
    'taskProposedOperationClass',v_task.operation_class,
    'exactIdentityMismatchCount',0,
    'companyWorkItemId',v_work.id
  ),true);
  v_card:=jsonb_set(v_card,'{transition,state}',to_jsonb('authorized_for_routed_day'::text),true);
  v_card:=jsonb_set(v_card,'{transition,authorizedInstruction}',jsonb_strip_nulls(jsonb_build_object(
    'actionKey',v_task.action_key,
    'operationClass',v_task.operation_class,
    'do',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
    'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
    'dayWindow',coalesce(nullif(v_card#>>'{routing,dayWindow}',''),v_placement.day_window),
    'plannedStartAt',v_placement.planned_start_at,
    'plannedDurationMinutes',v_placement.planned_duration_minutes
  )),true);
  v_card:=jsonb_set(v_card,'{truthBoundary,companyWorkOperationBridge}',jsonb_build_object(
    'companyWorkSourceEstablishesThisOperationIdentity',true,
    'requiresCanonicalResponsibility',true,
    'requiresActiveManagerPlanForThisDay',true,
    'requiresWorkerDayPlacement',true,
    'requiresExecutionReadiness',true,
    'doesNotAssertProductionLotNextTransitionReady',true,
    'doesNotResolveUnrelatedProductionReadiness',true,
    'doesNotRecordCompletion',true,
    'finalLeaseStillRequired',true
  ),true);
  return v_card;
end;
$$;

create or replace function atlas.worker_state_transition_card_v2(
  p_farm_id uuid,p_membership_id uuid,p_task_id uuid,p_service_date date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
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
  v_card:=atlas.worker_state_transition_company_work_bridge_v1(p_farm_id,p_membership_id,p_task_id,p_service_date,v_card);
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