create or replace function atlas.communication_realization_provider_state_self_v1(p_draft_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_draft atlas.communication_email_drafts%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_auth jsonb;
  v_op atlas.communication_outbound_operations%rowtype;
  v_event_id uuid;
  v_state text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_draft_id is null then
    raise exception 'Draft id is required.' using errcode='22023';
  end if;

  select * into v_draft
  from atlas.communication_email_drafts
  where id=p_draft_id;
  if v_draft.id is null then
    raise exception 'Draft not found.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where id=v_draft.author_membership_id
    and user_id=v_uid;
  if v_member.id is null then
    raise exception 'Only the draft author may inspect provider state.' using errcode='42501';
  end if;

  v_auth:=atlas.resolve_institutional_communication_operation_self_v1(
    v_draft.communication_endpoint_id,'draft.authorize'
  );

  if v_draft.authorized_outbound_operation_id is not null then
    select * into v_op
    from atlas.communication_outbound_operations
    where id=v_draft.authorized_outbound_operation_id;

    if v_op.id is null then
      raise exception 'Authorized draft is missing its outbound operation.' using errcode='55000';
    end if;

    select l.communication_event_id into v_event_id
    from atlas.communication_outbound_event_links l
    where l.outbound_operation_id=v_op.id
    order by l.created_at,l.id
    limit 1;
  end if;

  v_state:=case
    when v_draft.draft_state='authorized'
         and v_op.operation_state='accepted'
         and v_event_id is not null then 'fulfilled'
    when v_draft.draft_state='authorized' then 'authorized_pending'
    when v_draft.draft_state in ('active','scheduled')
         and coalesce((v_auth->>'allowed')::boolean,false) then 'eligible'
    else 'unavailable'
  end;

  return jsonb_build_object(
    'contractVersion','institutional_communication_realization_provider_state_v1',
    'state',v_state,
    'draftId',v_draft.id,
    'draftState',v_draft.draft_state,
    'communicationEndpointId',v_draft.communication_endpoint_id,
    'communicationConversationId',v_draft.communication_conversation_id,
    'institutionalConversationId',v_draft.institutional_conversation_id,
    'outboundOperationId',v_op.id,
    'outboundOperationState',v_op.operation_state,
    'authorizedAt',v_op.authorized_at,
    'acceptedAt',v_op.accepted_at,
    'communicationEventId',v_event_id,
    'operatorUserId',v_uid,
    'personEntityId',v_auth->>'personEntityId',
    'responsibilityRelationId',v_auth->>'responsibilityRelationId',
    'authorizationAllowed',coalesce((v_auth->>'allowed')::boolean,false),
    'authorizationReason',v_auth->>'reason',
    'observedAt',clock_timestamp(),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'communicationAuthorityOwnsFulfillmentTruth',true,
      'partialAcceptanceIsNotFulfillment',true,
      'providerAdapterCreatesNoCommunicationAuthority',true
    )
  );
end;
$function$;

revoke all on function atlas.communication_realization_provider_state_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.communication_realization_provider_state_self_v1(uuid) to authenticated,service_role;

create or replace function public.communication_realization_provider_state_self_v1(p_draft_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select atlas.communication_realization_provider_state_self_v1(p_draft_id);
$function$;

revoke all on function public.communication_realization_provider_state_self_v1(uuid) from public,anon;
grant execute on function public.communication_realization_provider_state_self_v1(uuid) to authenticated,service_role;
