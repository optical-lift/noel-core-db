create or replace function atlas.communication_legacy_membership_carrier_self_v1(
  p_communication_endpoint_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select m.id
  from atlas.communication_endpoints ep
  join atlas.organization_memberships m
    on m.organization_id=ep.organization_id
   and m.user_id=auth.uid()
   and m.active
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null
    and atlas.organization_membership_present_effective_at_v1(
      m.id,m.organization_id,now()
    )
  order by m.created_at,m.id
  limit 1;
$function$;

revoke all on function atlas.communication_legacy_membership_carrier_self_v1(uuid)
  from public,anon,authenticated;

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
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,'reason','sign_in_required'
    );
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,'reason','reality_person_required'
    );
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

  v_entity_id:=atlas.reality_entity_for_legacy_organization_internal_v1(
    v_endpoint.organization_id
  );
  if v_entity_id is null then
    return jsonb_build_object(
      'operationKey',v_operation,'allowed',false,
      'reason','canonical_institution_required'
    );
  end if;

  case v_operation
    when 'correspondence_identity.read' then
      v_responsibility_key:='institutional_correspondence_administration';
      v_legacy_capability:='view';
    when 'correspondence_identity.admin' then
      v_responsibility_key:='institutional_correspondence_administration';
      v_legacy_capability:='admin';
    when 'conversation.read' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='view';
    when 'draft.read' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='view';
    when 'draft.write' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'draft.authorize' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'message.send' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'attachment.prepare' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'attachment.confirm' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'attachment.storage.insert' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'attachment.storage.delete' then
      v_responsibility_key:='institutional_communication_operations';
      v_legacy_capability:='send';
    when 'conversation.claim' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='claim';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    when 'conversation.handoff' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='handoff';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    when 'collaborator.manage' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='handoff';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    when 'response.transition' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='claim';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    when 'response.complete' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='close';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    when 'conversation.close' then
      v_responsibility_key:='institutional_communication_response_work';
      v_legacy_capability:='close';
      v_company_work_required:=true;
      v_migration_state:='deferred_company_work';
    else
      return jsonb_build_object(
        'operationKey',v_operation,'allowed',false,
        'reason','unsupported_operation','migrationState','unsupported'
      );
  end case;

  v_membership_id:=atlas.communication_legacy_membership_carrier_self_v1(
    v_endpoint.id
  );

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
    v_person_id,
    v_responsibility_key,
    v_operation,
    'entity',
    v_entity_id,
    null,
    jsonb_build_object(
      'communicationEndpointIds',
      jsonb_build_array(v_endpoint.id::text)
    )
  );

  v_allowed:=v_relation_id is not null and v_carrier_ok;

  if v_allowed then
    v_reason:='authorized';
  elsif v_company_work_required and v_relation_id is null then
    v_reason:='company_work_authority_required';
  elsif v_relation_id is null then
    v_reason:='reality_responsibility_required';
  elsif not v_carrier_ok then
    v_reason:='legacy_endpoint_carrier_unavailable';
  else
    v_reason:='not_authorized';
  end if;

  return jsonb_build_object(
    'operationKey',v_operation,
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

revoke all on function atlas.resolve_institutional_communication_operation_self_v1(uuid,text)
  from public,anon,authenticated;

create or replace function atlas.current_institutional_communication_context_self_api_v1(
  p_communication_endpoint_id uuid
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
  v_entity reality.entities%rowtype;
  v_membership_id uuid;
  v_operations jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','institutional_communication_context_v1',
      'state','person_binding_required',
      'operations','{}'::jsonb
    );
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null;

  if v_endpoint.id is null then
    raise exception 'Active institutional communication endpoint required.'
      using errcode='P0002';
  end if;

  select e.* into v_entity
  from reality.entities e
  where e.id=atlas.reality_entity_for_legacy_organization_internal_v1(
    v_endpoint.organization_id
  )
    and e.identity_state='canonical';

  if v_entity.id is null then
    raise exception 'Canonical institution Reality Entity required.'
      using errcode='42501';
  end if;

  v_membership_id:=atlas.communication_legacy_membership_carrier_self_v1(
    v_endpoint.id
  );

  select jsonb_object_agg(
    q.operation_key,
    atlas.resolve_institutional_communication_operation_self_v1(
      v_endpoint.id,q.operation_key
    )
    order by q.ordinal
  )
  into v_operations
  from (
    values
      (1,'correspondence_identity.read'),
      (2,'correspondence_identity.admin'),
      (3,'conversation.read'),
      (4,'draft.read'),
      (5,'draft.write'),
      (6,'draft.authorize'),
      (7,'message.send'),
      (8,'attachment.prepare'),
      (9,'attachment.confirm'),
      (10,'attachment.storage.insert'),
      (11,'attachment.storage.delete'),
      (20,'conversation.claim'),
      (21,'conversation.handoff'),
      (22,'collaborator.manage'),
      (23,'response.transition'),
      (24,'response.complete'),
      (25,'conversation.close')
  ) q(ordinal,operation_key);

  return jsonb_build_object(
    'contractVersion','institutional_communication_context_v1',
    'state','ready',
    'personEntityId',v_person_id,
    'institution',jsonb_build_object(
      'entityId',v_entity.id,
      'stableKey',v_entity.stable_key,
      'entityKind',v_entity.entity_kind,
      'displayName',v_entity.display_name
    ),
    'endpoint',jsonb_build_object(
      'communicationEndpointId',v_endpoint.id,
      'endpointKind',v_endpoint.endpoint_kind,
      'address',v_endpoint.address,
      'displayName',v_endpoint.display_name,
      'endpointState',v_endpoint.endpoint_state
    ),
    'operations',coalesce(v_operations,'{}'::jsonb),
    'legacyCarrier',jsonb_build_object(
      'membershipId',v_membership_id,
      'routingOnly',true
    ),
    'truthBoundary',jsonb_build_object(
      'contextDoesNotCreateAuthority',true,
      'responsibilityEstablishesAuthority',true,
      'legacyEndpointGrantIsCarrierConstraintOnly',true,
      'organizationMembershipIsNotAuthority',true,
      'genericRoleIsNotAuthority',true,
      'communicationAuthorityDoesNotEstablishCompanyWork',true,
      'workCoupledOperationsRequireSeparateAuthority',true
    )
  );
end
$function$;

revoke all on function atlas.current_institutional_communication_context_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.current_institutional_communication_context_self_api_v1(uuid)
  to authenticated;

with lex as (
  select id
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical'
),
elm as (
  select id
  from reality.entities
  where stable_key='elm-farm'
    and identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,responsibility_key,title,relation_state,
  jurisdiction_kind,jurisdiction_entity_id,permitted_operations,scope,
  establishment_kind,establishment_basis
)
select
  lex.id,
  'institutional_communication_operations',
  'Operate Elm Farm institutional communications',
  'active',
  'entity',
  elm.id,
  array[
    'conversation.read','draft.read','draft.write','draft.authorize',
    'message.send','attachment.prepare','attachment.confirm',
    'attachment.storage.insert','attachment.storage.delete'
  ]::text[],
  jsonb_build_object(
    'communicationEndpointIds',
    jsonb_build_array('7617a7b1-8713-4520-923f-51a15c6b2d7f')
  ),
  'legacy_adjudicated_migration',
  jsonb_build_object(
    'basis','Existing explicit Elm endpoint view/send carrier grants were adjudicated into bounded non-Company-Work communication operations.',
    'legacyOrganizationId','fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    'legacyCommunicationEndpointId','7617a7b1-8713-4520-923f-51a15c6b2d7f',
    'deliberatelyExcluded',jsonb_build_array(
      'conversation.claim','conversation.handoff','collaborator.manage',
      'response.transition','response.complete','conversation.close'
    ),
    'exclusionReason','Those operations establish, transfer, mutate, complete, or cancel Company Work and require a separate authority cutover.',
    'doesNotPreserve',jsonb_build_array(
      'organization owner role','Organization Membership as authority',
      'endpoint capability as authority'
    )
  )
from lex,elm
on conflict do nothing;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.current_institutional_communication_context_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,false,0,0,
  jsonb_build_object(
    'purpose','Project the signed-in Person institutional communication operations for one endpoint.',
    'authoritySource','reality.responsibility_relations',
    'legacyEndpointGrantRole','compatibility carrier constraint only',
    'companyWorkBoundary','Claim, handoff, collaboration, response transition/completion, and close remain deferred.'
  ),
  now(),false
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

comment on function atlas.resolve_institutional_communication_operation_self_v1(uuid,text) is
  'Internal operation resolver for institutional communications. Reality responsibility establishes authority; the legacy endpoint grant only confirms a usable compatibility carrier.';
comment on function atlas.current_institutional_communication_context_self_api_v1(uuid) is
  'Authenticated institutional communication context for one endpoint. It distinguishes ordinary communication operations from Company-Work-coupled response operations.';
