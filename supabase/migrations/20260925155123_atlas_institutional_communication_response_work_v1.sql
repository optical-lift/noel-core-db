create or replace function atlas.resolve_institutional_communication_operation_self_v1(
  p_communication_endpoint_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_entity_id uuid;
  v_operation text:=btrim(coalesce(p_operation_key,''));
  v_authority_operation text;
  v_responsibility_key text;
  v_legacy_capability text;
  v_company_work_required boolean:=false;
  v_migration_state text:='active';
  v_relation_id uuid;
  v_membership_id uuid;
  v_carrier_ok boolean:=false;
  v_allowed boolean:=false;
  v_reason text;
begin
  if auth.uid() is null then
    return jsonb_build_object('operationKey',v_operation,'allowed',false,'reason','sign_in_required');
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    return jsonb_build_object('operationKey',v_operation,'allowed',false,'reason','reality_person_required');
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null;

  if v_endpoint.id is null then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,
      'reason','active_institutional_endpoint_required'
    );
  end if;

  v_entity_id:=atlas.reality_entity_for_legacy_organization_internal_v1(v_endpoint.organization_id);
  if v_entity_id is null then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,'reason','canonical_institution_required'
    );
  end if;

  if v_operation in ('conversation.handoff','collaborator.manage') then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,
      'reason','receiver_uptake_required',
      'migrationState','deferred_receiver_uptake',
      'personEntityId',v_person_id,
      'institutionEntityId',v_entity_id,
      'communicationEndpointId',v_endpoint.id,
      'companyWorkAuthorityRequired',true,
      'truthBoundary',jsonb_build_object(
        'directAssignmentForbidden',true,
        'receiverMustEstablishOwnResponsibility',true,
        'legacyHandoffCapabilityIsNotTransferAuthority',true
      )
    );
  end if;

  if v_operation in ('response.transition','response.complete') then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,
      'reason','exact_work_responsibility_required',
      'migrationState','requires_exact_work_context',
      'personEntityId',v_person_id,
      'institutionEntityId',v_entity_id,
      'communicationEndpointId',v_endpoint.id,
      'companyWorkAuthorityRequired',true,
      'truthBoundary',jsonb_build_object(
        'endpointContextCannotAuthorizeExactWorkMutation',true,
        'activeResponsibleAllocationGoverns',true
      )
    );
  end if;

  case v_operation
    when 'correspondence_identity.read' then
      v_responsibility_key:='institutional_correspondence_administration';
      v_authority_operation:='correspondence_identity.read';
      v_legacy_capability:='view';
    when 'correspondence_identity.admin' then
      v_responsibility_key:='institutional_correspondence_administration';
      v_authority_operation:='correspondence_identity.admin';
      v_legacy_capability:='admin';
    when 'conversation.read' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='conversation.read';
      v_legacy_capability:='view';
    when 'draft.read' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='draft.read';
      v_legacy_capability:='view';
    when 'draft.write' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='draft.write';
      v_legacy_capability:='send';
    when 'draft.authorize' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='draft.authorize';
      v_legacy_capability:='send';
    when 'message.send' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='message.send';
      v_legacy_capability:='send';
    when 'attachment.prepare' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='attachment.prepare';
      v_legacy_capability:='send';
    when 'attachment.confirm' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='attachment.confirm';
      v_legacy_capability:='send';
    when 'attachment.storage.insert' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='attachment.storage.insert';
      v_legacy_capability:='send';
    when 'attachment.storage.delete' then
      v_responsibility_key:='institutional_communication_operations';
      v_authority_operation:='attachment.storage.delete';
      v_legacy_capability:='send';
    when 'conversation.claim' then
      v_responsibility_key:='institutional_communication_response_work';
      v_authority_operation:='response_work.claim_self';
      v_legacy_capability:='claim';
      v_company_work_required:=true;
    when 'conversation.close' then
      return jsonb_build_object(
        'operationKey',v_operation,'allowed',false,
        'reason','response_disposition_authority_required',
        'migrationState','deferred_response_adjudication',
        'personEntityId',v_person_id,
        'institutionEntityId',v_entity_id,
        'communicationEndpointId',v_endpoint.id,
        'companyWorkAuthorityRequired',true
      );
    else
      return jsonb_build_object(
        'operationKey',v_operation,'allowed',false,
        'reason','unsupported_operation','migrationState','unsupported'
      );
  end case;

  v_membership_id:=atlas.communication_legacy_membership_carrier_self_v1(v_endpoint.id);

  if v_membership_id is not null then
    v_carrier_ok:=exists(
      select 1
      from atlas.communication_endpoint_member_grants g
      where g.communication_endpoint_id=v_endpoint.id
        and g.membership_id=v_membership_id
        and g.capability=v_legacy_capability
        and g.grant_state='active'
    );
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,v_responsibility_key,v_authority_operation,
    'entity',v_entity_id,null,
    jsonb_build_object('communicationEndpointIds',jsonb_build_array(v_endpoint.id::text))
  );

  v_allowed:=v_relation_id is not null and v_carrier_ok;

  if v_allowed then
    v_reason:='authorized';
  elsif v_relation_id is null then
    v_reason:='reality_responsibility_required';
  elsif not v_carrier_ok then
    v_reason:='legacy_endpoint_carrier_unavailable';
  else
    v_reason:='not_authorized';
  end if;

  return jsonb_build_object(
    'operationKey',v_operation,
    'authorityOperationKey',v_authority_operation,
    'allowed',v_allowed,
    'reason',v_reason,
    'migrationState',v_migration_state,
    'personEntityId',v_person_id,
    'institutionEntityId',v_entity_id,
    'communicationEndpointId',v_endpoint.id,
    'responsibilityKey',v_responsibility_key,
    'responsibilityRelationId',v_relation_id,
    'requiredLegacyCapability',v_legacy_capability,
    'legacyCarrierMembershipId',v_membership_id,
    'legacyCarrierSatisfied',v_carrier_ok,
    'companyWorkAuthorityRequired',v_company_work_required,
    'truthBoundary',jsonb_build_object(
      'responsibilityEstablishesAuthority',true,
      'legacyGrantIsCarrierConstraintOnly',true,
      'organizationMembershipIsNotAuthority',true,
      'genericRoleIsNotAuthority',true
    )
  );
end
$function$;

with lex as (
  select id from reality.entities
  where stable_key='lex' and entity_kind='person' and identity_state='canonical'
),
elm as (
  select id from reality.entities
  where stable_key='elm-farm' and identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,responsibility_key,title,relation_state,
  jurisdiction_kind,jurisdiction_entity_id,permitted_operations,scope,
  establishment_kind,establishment_basis
)
select
  lex.id,
  'institutional_communication_response_work',
  'Self-adopt Elm Farm communication response work',
  'active',
  'entity',
  elm.id,
  array['response_work.claim_self']::text[],
  jsonb_build_object(
    'communicationEndpointIds',
    jsonb_build_array('7617a7b1-8713-4520-923f-51a15c6b2d7f')
  ),
  'legacy_adjudicated_migration',
  jsonb_build_object(
    'basis','Existing explicit Elm endpoint claim carrier was adjudicated only into self-claim response-work intake.',
    'legacyOrganizationId','fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    'legacyCommunicationEndpointId','7617a7b1-8713-4520-923f-51a15c6b2d7f',
    'legacyCapability','claim',
    'deliberatelyNotPromoted',jsonb_build_array(
      'handoff as assignment',
      'collaborator assignment',
      'close as completion authority',
      'close as cancellation authority'
    ),
    'exactWorkResponsibilityAfterClaim',true
  )
from lex,elm
on conflict do nothing;

create or replace function atlas.claim_institutional_conversation_self_api_v1(
  p_institutional_conversation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_endpoint_id uuid;
  v_authorization jsonb;
  v_member_id uuid;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_work atlas.work_items%rowtype;
  v_assignment jsonb;
  v_from text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id=p_institutional_conversation_id and conversation_state='open';

  if v_conv.id is null then
    raise exception 'Open institutional conversation not found.' using errcode='P0002';
  end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at
  limit 1;

  if v_endpoint_id is null then
    raise exception 'Communication response requires an institutional endpoint.' using errcode='23514';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_endpoint_id,'conversation.claim'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1
  for update;

  if v_case.id is null then
    raise exception 'This conversation has no active response case to claim.' using errcode='22023';
  end if;

  select * into v_binding
  from atlas.institutional_conversation_response_work_bindings
  where response_case_id=v_case.id;

  if v_binding.id is null then
    insert into atlas.work_items(
      organization_id,organization_unit_id,title,instructions,work_state,
      operation_class,jurisdiction_key,source_object_type,source_object_id,
      stable_key,result_contract_key,metadata
    ) values(
      v_conv.organization_id,v_conv.organization_unit_id,
      'Respond: '||coalesce(nullif(v_conv.subject,''),'institutional conversation'),
      'Handle the unresolved communication consequence for this institutional conversation. Reading alone never establishes responsibility.',
      'open','communication_response',
      'communication:endpoint:'||v_endpoint_id::text,
      'institutional_conversation_response_case',v_case.id,
      'communication-response:'||v_case.id::text,
      'institutional_communication_response_v1',
      jsonb_build_object(
        'institutionalConversationId',v_conv.id,
        'responseCaseId',v_case.id,
        'communicationEndpointId',v_endpoint_id,
        'establishmentAuthoritySource','institutional_communication_response_work',
        'establishmentPersonEntityId',v_authorization->>'personEntityId',
        'establishmentResponsibilityRelationId',v_authorization->>'responsibilityRelationId'
      )
    )
    returning * into v_work;

    insert into atlas.institutional_conversation_response_work_bindings(
      response_case_id,work_item_id
    ) values(v_case.id,v_work.id)
    returning * into v_binding;
  else
    select * into v_work from atlas.work_items where id=v_binding.work_item_id;
  end if;

  if v_work.work_state<>'open' then
    raise exception 'Communication response Work is not open.' using errcode='22023';
  end if;

  v_assignment:=atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work.id,v_member_id,v_member_id,'self_claim',
    jsonb_build_object(
      'institutionalConversationId',v_conv.id,
      'responseCaseId',v_case.id,
      'communicationEndpointId',v_endpoint_id,
      'personEntityId',v_authorization->>'personEntityId',
      'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
    ),
    coalesce(nullif(btrim(p_reason),''),'conversation_claimed'),
    jsonb_build_object(
      'source','claim_institutional_conversation_self_api_v2',
      'authoritySource','institutional_communication_response_work'
    )
  );

  v_from:=v_case.case_state;

  update atlas.institutional_conversation_response_cases
  set case_state='needs_response',updated_at=now()
  where id=v_case.id;

  insert into atlas.institutional_conversation_response_events(
    response_case_id,institutional_conversation_id,event_kind,from_state,to_state,
    actor_membership_id,target_membership_id,work_item_id,reason,metadata
  ) values(
    v_case.id,v_conv.id,'claimed',v_from,'needs_response',
    v_member_id,v_member_id,v_work.id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'assignment',v_assignment,
      'authoritySource','institutional_communication_response_work',
      'personEntityId',v_authorization->>'personEntityId',
      'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
    )
  );

  return jsonb_build_object(
    'contractVersion','institutional_conversation_claim_v2',
    'institutionalConversationId',v_conv.id,
    'responseCaseId',v_case.id,
    'workItemId',v_work.id,
    'responsibleMembershipId',v_member_id,
    'responsiblePersonEntityId',v_authorization->>'personEntityId',
    'responsibilityRelationId',v_authorization->>'responsibilityRelationId',
    'responsibilityEstablishmentBasis','self_claim',
    'responseState','needs_response'
  );
end
$function$;

create or replace function atlas.complete_institutional_communication_response_work_service_v1(
  p_work_item_id uuid,
  p_response_case_id uuid,
  p_actor_membership_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_actor atlas.organization_memberships%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_result_id uuid;
  v_acceptance_id uuid;
  v_key text;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  select * into v_case from atlas.institutional_conversation_response_cases where id=p_response_case_id;
  select * into v_actor from atlas.organization_memberships where id=p_actor_membership_id and active;

  if v_work.id is null or v_case.id is null or v_actor.id is null then
    raise exception 'Communication response completion requires work, response case, and active actor.'
      using errcode='P0002';
  end if;

  if v_work.organization_id is distinct from v_case.organization_id
     or v_actor.organization_id is distinct from v_work.organization_id
     or v_work.source_object_type is distinct from 'institutional_conversation_response_case'
     or v_work.source_object_id is distinct from v_case.id then
    raise exception 'Communication response completion scope mismatch.' using errcode='23514';
  end if;

  if v_work.result_contract_key is distinct from 'institutional_communication_response_v1' then
    raise exception 'Communication response Work must use the institutional communication result contract.'
      using errcode='23514';
  end if;

  if v_work.work_state='completed' then
    return jsonb_build_object(
      'contractVersion','institutional_communication_response_completion_v2',
      'state','already_completed','workItemId',v_work.id,'responseCaseId',v_case.id
    );
  end if;

  if v_work.work_state<>'open' then
    raise exception 'Only open communication response Work can complete.' using errcode='22023';
  end if;

  select * into v_allocation
  from atlas.work_allocations
  where work_item_id=v_work.id
    and allocation_role='responsible'
    and state='active'
  order by allocated_at desc,id desc
  limit 1;

  if v_allocation.id is null then
    raise exception 'Communication response Work requires active responsibility before completion.'
      using errcode='23514';
  end if;

  if v_allocation.assignee_membership_id is distinct from v_actor.id then
    raise exception 'Only the current exact Work responsibility carrier may complete this response Work.'
      using errcode='42501';
  end if;

  v_key:='institutional-communication-response:'||v_case.id::text||':complete';

  select * into v_result
  from atlas.work_execution_results
  where organization_id=v_work.organization_id
    and idempotency_key=v_key;

  if v_result.id is null then
    insert into atlas.work_execution_results(
      organization_id,work_item_id,responsible_allocation_id,
      reported_by_user_id,reported_by_organization_membership_id,
      result_kind,result_contract_key,idempotency_key,payload,metadata
    ) values(
      v_work.organization_id,v_work.id,v_allocation.id,v_actor.user_id,v_actor.id,
      'completed','institutional_communication_response_v1',v_key,
      jsonb_build_object(
        'responseCaseId',v_case.id,
        'institutionalConversationId',v_case.institutional_conversation_id,
        'terminalResponseState','complete',
        'reason',nullif(btrim(coalesce(p_reason,'')),'')
      ),
      jsonb_build_object(
        'source','complete_institutional_communication_response_work_service_v2',
        'authorityBasis','exact_work_responsibility'
      )
    )
    returning * into v_result;
  end if;

  v_result_id:=v_result.id;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,
    acceptance_kind,accepted_by_domain,evidence,metadata
  ) values(
    v_work.organization_id,v_work.id,v_result_id,'accepted',
    'domain_adapter','communication',
    jsonb_build_object(
      'responseCaseId',v_case.id,
      'terminalResponseState','complete',
      'responsibleAllocationId',v_allocation.id,
      'responsibleMembershipId',v_actor.id
    ),
    jsonb_build_object(
      'source','institutional_communication_response_v1',
      'authorityBasis','exact_work_responsibility'
    )
  )
  on conflict(execution_result_id) do nothing;

  select id into v_acceptance_id
  from atlas.work_result_acceptances
  where execution_result_id=v_result_id;

  update atlas.work_allocations
  set state='completed',completed_at=now(),updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'completionResultId',v_result_id,
        'completionAcceptanceId',v_acceptance_id
      )
  where id=v_allocation.id and state='active';

  update atlas.work_items
  set work_state='completed',completed_at=now(),updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'completionResultId',v_result_id,
        'completionAcceptanceId',v_acceptance_id
      )
  where id=v_work.id and work_state='open';

  return jsonb_build_object(
    'contractVersion','institutional_communication_response_completion_v2',
    'state','completed','workItemId',v_work.id,'responseCaseId',v_case.id,
    'executionResultId',v_result_id,'acceptanceId',v_acceptance_id,
    'authorityBasis','exact_work_responsibility'
  );
end
$function$;

create or replace function atlas.set_institutional_conversation_response_state_self_api_v1(
  p_institutional_conversation_id uuid,
  p_to_state text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_endpoint_id uuid;
  v_actor_id uuid;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_to text:=lower(btrim(coalesce(p_to_state,'')));
  v_from text;
  v_completion jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  if v_to not in (
    'needs_response','waiting_external','waiting_internal',
    'scheduled_follow_up','complete','informational'
  ) then
    raise exception 'Unsupported response state.' using errcode='22023';
  end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id=p_institutional_conversation_id and conversation_state='open';

  if v_conv.id is null then
    raise exception 'Open institutional conversation not found.' using errcode='P0002';
  end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at
  limit 1;

  v_actor_id:=atlas.communication_legacy_membership_carrier_self_v1(v_endpoint_id);
  if v_actor_id is null then
    raise exception 'Communication response carrier unavailable.' using errcode='42501';
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1
  for update;

  if v_case.id is null then
    raise exception 'No active response case exists.' using errcode='22023';
  end if;

  select * into v_binding
  from atlas.institutional_conversation_response_work_bindings
  where response_case_id=v_case.id;

  if v_binding.id is null then
    raise exception 'Response state mutation requires established Company Work responsibility. Claim the conversation first.'
      using errcode='42501';
  end if;

  select * into v_current
  from atlas.work_allocations
  where work_item_id=v_binding.work_item_id
    and allocation_role='responsible'
    and state='active'
  limit 1;

  if v_current.id is null or v_current.assignee_membership_id is distinct from v_actor_id then
    raise exception 'Current exact Work responsibility is required to change response state.'
      using errcode='42501';
  end if;

  v_from:=v_case.case_state;

  if v_to='complete' then
    v_completion:=atlas.complete_institutional_communication_response_work_service_v1(
      v_binding.work_item_id,v_case.id,v_actor_id,p_reason
    );
  elsif v_to='informational' then
    update atlas.work_allocations
    set state='released',released_at=now(),
        release_reason='responsible_classified_communication_informational',
        updated_at=now(),
        metadata=metadata||jsonb_build_object(
          'responseCaseId',v_case.id,
          'releaseAuthorityBasis','exact_work_responsibility'
        )
    where id=v_current.id and state='active';

    update atlas.work_items
    set work_state='cancelled',cancelled_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object(
          'cancellationSource','responsible_classified_communication_informational',
          'responseCaseId',v_case.id,
          'cancellationAuthorityBasis','exact_work_responsibility'
        )
    where id=v_binding.work_item_id and work_state='open';
  end if;

  update atlas.institutional_conversation_response_cases
  set case_state=v_to,
      closed_at=case when v_to in ('complete','informational') then now() else null end,
      updated_at=now()
  where id=v_case.id;

  insert into atlas.institutional_conversation_response_events(
    response_case_id,institutional_conversation_id,event_kind,
    from_state,to_state,actor_membership_id,target_membership_id,
    work_item_id,reason,metadata
  ) values(
    v_case.id,v_conv.id,
    case
      when v_to='complete' then 'completed'
      when v_to='informational' then 'marked_informational'
      else 'state_changed'
    end,
    v_from,v_to,v_actor_id,v_actor_id,v_binding.work_item_id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'completion',coalesce(v_completion,'{}'::jsonb),
      'authorityBasis','exact_work_responsibility',
      'responsibleAllocationId',v_current.id
    )
  );

  return jsonb_build_object(
    'contractVersion','institutional_conversation_response_state_v3',
    'institutionalConversationId',v_conv.id,
    'responseCaseId',v_case.id,
    'fromState',v_from,'toState',v_to,
    'workItemId',v_binding.work_item_id,
    'responsibleMembershipId',
      case when v_to in ('complete','informational') then null else v_actor_id end,
    'authorityBasis','exact_work_responsibility',
    'completion',v_completion
  );
end
$function$;

create or replace function atlas.handoff_institutional_conversation_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  raise exception 'Direct response-work handoff is disabled. Responsibility transfer requires a governed receiver-uptake contract.'
    using errcode='0A000';
end
$function$;

create or replace function atlas.add_institutional_conversation_collaborator_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_allocation_role text default 'participant'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  raise exception 'Direct collaborator assignment is disabled. Participation requires a governed receiver-uptake contract.'
    using errcode='0A000';
end
$function$;

create or replace function atlas.remove_institutional_conversation_collaborator_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_allocation_role text default 'participant'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_endpoint_id uuid;
  v_actor_id uuid;
  v_responsible atlas.work_allocations%rowtype;
  v_target_allocation atlas.work_allocations%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  if p_allocation_role not in ('participant','approver') then
    raise exception 'Collaborator role must be participant or approver.' using errcode='22023';
  end if;

  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at
  limit 1;

  v_actor_id:=atlas.communication_legacy_membership_carrier_self_v1(v_endpoint_id);
  if v_actor_id is null then
    raise exception 'Communication response carrier unavailable.' using errcode='42501';
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1;

  select * into v_binding
  from atlas.institutional_conversation_response_work_bindings
  where response_case_id=v_case.id;

  if v_binding.id is null then
    raise exception 'Conversation response work not found.' using errcode='P0002';
  end if;

  select * into v_responsible
  from atlas.work_allocations
  where work_item_id=v_binding.work_item_id
    and allocation_role='responsible'
    and state='active'
  limit 1;

  if v_actor_id is distinct from p_target_membership_id
     and v_responsible.assignee_membership_id is distinct from v_actor_id then
    raise exception 'Only collaborator self-removal or the current exact Work responsibility carrier may release collaboration.'
      using errcode='42501';
  end if;

  select * into v_target_allocation
  from atlas.work_allocations
  where work_item_id=v_binding.work_item_id
    and assignee_membership_id=p_target_membership_id
    and allocation_role=p_allocation_role
    and state='active'
  order by allocated_at desc
  limit 1
  for update;

  if v_target_allocation.id is null then
    return jsonb_build_object(
      'contractVersion','institutional_conversation_collaborator_remove_v2',
      'released',false,'workItemId',v_binding.work_item_id,
      'membershipId',p_target_membership_id,'allocationRole',p_allocation_role,
      'authorityBasis',case
        when v_actor_id=p_target_membership_id then 'self_release'
        else 'exact_work_responsibility'
      end
    );
  end if;

  update atlas.work_allocations
  set state='released',released_at=now(),
      release_reason='conversation_collaborator_removed',updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'releaseAuthorityBasis',
        case
          when v_actor_id=p_target_membership_id then 'self_release'
          else 'exact_work_responsibility'
        end
      )
  where id=v_target_allocation.id;

  return jsonb_build_object(
    'contractVersion','institutional_conversation_collaborator_remove_v2',
    'released',true,'allocationId',v_target_allocation.id,
    'workItemId',v_binding.work_item_id,'membershipId',p_target_membership_id,
    'allocationRole',p_allocation_role,
    'authorityBasis',case
      when v_actor_id=p_target_membership_id then 'self_release'
      else 'exact_work_responsibility'
    end
  );
end
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.claim_institutional_conversation_self_api_v1(uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','reality.responsibility_relations',
    'responsibilityKey','institutional_communication_response_work',
    'operation','response_work.claim_self',
    'truthBoundary','Creates Company Work only from an exact response case and establishes only caller self-claim responsibility.'
  ),now(),false
),
(
  'atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'state','receiver_uptake_required',
    'truthBoundary','Direct transfer is fail-closed. Legacy endpoint handoff capability cannot assign Company Work responsibility.'
  ),now(),false
),
(
  'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'state','receiver_uptake_required',
    'truthBoundary','Direct collaborator assignment is fail-closed until governed participation uptake exists.'
  ),now(),false
),
(
  'atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','exact_work_responsibility',
    'truthBoundary','Endpoint close/handoff capability cannot transition, complete, or cancel another Person''s response Work.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

comment on function atlas.claim_institutional_conversation_self_api_v1(uuid,text) is
  'Response-work intake command. Requires explicit Reality response-work responsibility, creates Work only from the exact response case, and establishes only self-claim responsibility.';
comment on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text) is
  'Compatibility endpoint kept fail-closed. Direct response-work responsibility transfer is unconstitutional without governed receiver uptake.';
comment on function atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) is
  'Compatibility endpoint kept fail-closed. Direct collaborator allocation requires governed receiver uptake.';
comment on function atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text) is
  'Response-state mutation is governed by the current exact Work responsibility allocation after claim; endpoint close/handoff capabilities do not override Work custody.';

do $validation$
begin
  if pg_get_functiondef(
       'atlas.claim_institutional_conversation_self_api_v1(uuid,text)'::regprocedure
     ) ilike '%communication_endpoint_membership_has_capability_v1%'
     or pg_get_functiondef(
       'atlas.claim_institutional_conversation_self_api_v1(uuid,text)'::regprocedure
     ) ilike '%organization_memberships%' then
    raise exception 'Response claim retained legacy authority lookup.';
  end if;

  if pg_get_functiondef(
       'atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)'::regprocedure
     ) ilike '%communication_endpoint_membership_has_capability_v1%'
     or pg_get_functiondef(
       'atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)'::regprocedure
     ) ilike '%communication_endpoint_membership_has_capability_v1%'
     or pg_get_functiondef(
       'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)'::regprocedure
     ) ilike '%communication_endpoint_membership_has_capability_v1%' then
    raise exception 'Response-work mutation retained endpoint capability as authority.';
  end if;
end
$validation$;
