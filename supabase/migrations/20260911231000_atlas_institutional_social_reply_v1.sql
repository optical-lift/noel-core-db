begin;

alter table atlas.communication_outbound_operations
  drop constraint communication_outbound_operations_operation_kind_check;
alter table atlas.communication_outbound_operations
  add constraint communication_outbound_operations_operation_kind_check
  check (operation_kind in ('email_send','social_reply'));

create or replace function atlas.guard_communication_outbound_transport_relay_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_transport_kind text:=lower(btrim(coalesce(new.transport_kind,'')));
begin
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  if v_source.id is null or v_endpoint.id is null then
    raise exception 'Outbound transport relay requires a connected source and communication endpoint.' using errcode='23514';
  end if;

  if v_endpoint.endpoint_kind='email' then
    if v_transport_kind='facebook_messenger' then
      raise exception 'Facebook Messenger transport requires a social endpoint.' using errcode='23514';
    end if;
  elsif v_endpoint.endpoint_kind='social' then
    if v_source.provider_key<>'facebook' or v_transport_kind<>'facebook_messenger' then
      raise exception 'Social outbound relay currently requires a Facebook source and facebook_messenger transport.' using errcode='23514';
    end if;
  else
    raise exception 'Outbound transport relay requires an email or supported social endpoint.' using errcode='23514';
  end if;

  if v_source.custodian_organization_id is distinct from v_endpoint.organization_id
     or v_source.custodian_organization_unit_id is distinct from v_endpoint.organization_unit_id then
    raise exception 'Outbound transport relay source and endpoint must share organization/unit custody.' using errcode='23514';
  end if;
  if not exists (
    select 1
    from atlas.communication_endpoint_source_bindings binding
    where binding.communication_endpoint_id=new.communication_endpoint_id
      and binding.connected_source_id=new.connected_source_id
      and binding.binding_state='active'
      and binding.binding_role in ('send','send_receive')
  ) then
    raise exception 'Outbound transport relay source must be actively bound as a send transport for endpoint.' using errcode='23514';
  end if;
  new.relay_key:=btrim(new.relay_key);
  new.secret_sha256:=lower(btrim(new.secret_sha256));
  new.transport_kind:=v_transport_kind;
  new.updated_at:=now();
  return new;
end;
$function$;

create or replace function atlas.prepare_institutional_social_reply_self_api_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
  p_reply_to_communication_event_id uuid,
  p_body_text text,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_conv atlas.institutional_conversations%rowtype;
  v_message atlas.institutional_conversation_messages%rowtype;
  v_event atlas.communication_events%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_operation_id uuid:=gen_random_uuid();
  v_key text:=coalesce(nullif(btrim(p_idempotency_key),''),v_operation_id::text);
  v_body text:=btrim(coalesce(p_body_text,''));
  v_recipient text;
  v_thread_ref text;
  v_hash text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_institutional_conversation_id is null or p_reply_to_communication_event_id is null then
    raise exception 'Social reply requires an existing institutional conversation and source message.' using errcode='22023';
  end if;
  if v_body='' then raise exception 'Social reply body is required.' using errcode='22023'; end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'social' then
    raise exception 'Active social communication endpoint required.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then
    raise exception 'Communication endpoint send authority required.' using errcode='42501';
  end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id=p_institutional_conversation_id
    and organization_id=v_endpoint.organization_id
    and organization_unit_id is not distinct from v_endpoint.organization_unit_id
    and conversation_state='open';
  if v_conv.id is null then raise exception 'Institutional conversation is outside endpoint scope or not open.' using errcode='42501'; end if;

  select * into v_message
  from atlas.institutional_conversation_messages
  where institutional_conversation_id=v_conv.id
    and communication_event_id=p_reply_to_communication_event_id
    and communication_endpoint_id=v_endpoint.id;
  if v_message.id is null then raise exception 'Reply source event is not part of this endpoint conversation.' using errcode='42501'; end if;

  select * into v_event
  from atlas.communication_events
  where id=p_reply_to_communication_event_id;
  if v_event.id is null or v_event.direction<>'incoming' then
    raise exception 'Social reply requires an incoming source communication event.' using errcode='42501';
  end if;

  select * into v_source
  from atlas.connected_sources s
  where s.id=v_event.connected_source_id
    and s.authorization_state='connected'
    and s.custodian_organization_id=v_endpoint.organization_id
    and s.custodian_organization_unit_id is not distinct from v_endpoint.organization_unit_id
    and s.provider_key='facebook'
    and (s.capabilities @> '{"communicationSend":true}'::jsonb)
    and exists (
      select 1 from atlas.communication_endpoint_source_bindings b
      where b.communication_endpoint_id=v_endpoint.id
        and b.connected_source_id=s.id
        and b.binding_state='active'
        and b.binding_role in ('send','send_receive')
    );
  if v_source.id is null then
    raise exception 'The conversation source is not an active Facebook send transport for this endpoint.' using errcode='42501';
  end if;

  v_recipient:=nullif(btrim(v_event.speaker_address),'');
  v_thread_ref:=nullif(btrim(v_event.canonical_event#>>'{source,threadRef}'),'');
  if v_recipient is null or v_thread_ref is null then
    raise exception 'Provider recipient and source thread continuity are required for social reply.' using errcode='55000';
  end if;
  if v_recipient=v_source.provider_account_key then
    raise exception 'Social reply recipient cannot be the sending provider account.' using errcode='23514';
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational')
  order by case_number desc limit 1;
  if v_case.id is not null then
    select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
    if v_binding.id is not null then
      select * into v_current from atlas.work_allocations
      where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active'
      limit 1;
    end if;
    if v_current.id is not null
       and v_current.assignee_membership_id is distinct from v_member.id
       and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'admin') then
      raise exception 'Another member currently owns this conversation response. Hand it off before sending.' using errcode='42501';
    end if;
    if v_current.id is null and v_case.case_state='unclaimed'
       and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'claim') then
      raise exception 'Claim authority is required to answer an unclaimed conversation.' using errcode='42501';
    end if;
  end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'operationKind','social_reply',
    'endpointId',v_endpoint.id,
    'conversationId',v_conv.id,
    'sourceId',v_source.id,
    'recipient',v_recipient,
    'sourceThreadRef',v_thread_ref,
    'bodyText',v_body,
    'replyToCommunicationEventId',v_event.id
  )::text,'UTF8'),'sha256'),'hex');

  insert into atlas.communication_outbound_operations(
    id,organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,
    connected_source_id,initiated_by_membership_id,operation_kind,to_recipients,cc_recipients,bcc_recipients,
    subject,body_text,body_html,attachment_refs,reply_to_communication_event_id,idempotency_key,content_sha256,
    operation_state,metadata
  ) values (
    v_operation_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,v_conv.id,
    v_source.id,v_member.id,'social_reply',
    jsonb_build_array(jsonb_build_object('addressKind','social','address',v_recipient,'role','to','provider','facebook')),
    '[]'::jsonb,'[]'::jsonb,null,v_body,null,'[]'::jsonb,v_event.id,v_key,v_hash,'authorized',
    jsonb_build_object(
      'authorizationSource','explicit_authenticated_social_reply',
      'actorUserId',auth.uid(),
      'provider','facebook',
      'sourceThreadRef',v_thread_ref,
      'replySourceEventRef',v_event.source_event_ref
    )
  ) on conflict (organization_id,idempotency_key) do nothing;

  select id into strict v_operation_id
  from atlas.communication_outbound_operations
  where organization_id=v_endpoint.organization_id and idempotency_key=v_key;

  return jsonb_build_object(
    'contractVersion','institutional_social_reply_intent_v1',
    'outboundOperationId',v_operation_id,
    'institutionalConversationId',v_conv.id,
    'communicationEndpointId',v_endpoint.id,
    'connectedSourceId',v_source.id,
    'operationState','authorized',
    'operationKind','social_reply',
    'initiatedByMembershipId',v_member.id,
    'contentSha256',v_hash,
    'provider','facebook'
  );
end;
$function$;
revoke all on function atlas.prepare_institutional_social_reply_self_api_v1(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function atlas.prepare_institutional_social_reply_self_api_v1(uuid,uuid,uuid,text,text) to authenticated;

create or replace function public.prepare_institutional_social_reply_self_api_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
  p_reply_to_communication_event_id uuid,
  p_body_text text,
  p_idempotency_key text default null
) returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.prepare_institutional_social_reply_self_api_v1(
    p_communication_endpoint_id,p_institutional_conversation_id,p_reply_to_communication_event_id,p_body_text,p_idempotency_key
  );
$function$;
revoke all on function public.prepare_institutional_social_reply_self_api_v1(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.prepare_institutional_social_reply_self_api_v1(uuid,uuid,uuid,text,text) to authenticated;

create or replace function public.authenticate_communication_outbound_transport_relay_service_v1(p_relay_key text,p_secret_sha256 text)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.authenticate_communication_outbound_transport_relay_service_v1(p_relay_key,p_secret_sha256);
$function$;
revoke all on function public.authenticate_communication_outbound_transport_relay_service_v1(text,text) from public,anon,authenticated;
grant execute on function public.authenticate_communication_outbound_transport_relay_service_v1(text,text) to service_role;

create or replace function public.lease_communication_outbound_operations_service_v1(p_connected_source_id uuid,p_lease_owner text,p_limit integer default 20,p_lease_seconds integer default 120)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.lease_communication_outbound_operations_service_v1(p_connected_source_id,p_lease_owner,p_limit,p_lease_seconds);
$function$;
revoke all on function public.lease_communication_outbound_operations_service_v1(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.lease_communication_outbound_operations_service_v1(uuid,text,integer,integer) to service_role;

create or replace function public.communication_outbound_transport_payload_service_v1(p_outbound_operation_id uuid)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.communication_outbound_transport_payload_service_v1(p_outbound_operation_id);
$function$;
revoke all on function public.communication_outbound_transport_payload_service_v1(uuid) from public,anon,authenticated;
grant execute on function public.communication_outbound_transport_payload_service_v1(uuid) to service_role;

create or replace function public.communication_reply_transport_context_service_v1(p_communication_event_id uuid)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.communication_reply_transport_context_service_v1(p_communication_event_id);
$function$;
revoke all on function public.communication_reply_transport_context_service_v1(uuid) from public,anon,authenticated;
grant execute on function public.communication_reply_transport_context_service_v1(uuid) to service_role;

create or replace function public.record_communication_outbound_result_service_v1(
  p_outbound_operation_id uuid,p_lease_owner text,p_result_state text,p_provider_message_ref text,p_provider_response jsonb,p_canonical_event jsonb default null
) returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.record_communication_outbound_result_service_v1(p_outbound_operation_id,p_lease_owner,p_result_state,p_provider_message_ref,p_provider_response,p_canonical_event);
$function$;
revoke all on function public.record_communication_outbound_result_service_v1(uuid,text,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.record_communication_outbound_result_service_v1(uuid,text,text,text,jsonb,jsonb) to service_role;

create or replace function public.read_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text)
returns text language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.read_connected_source_secret_service_v1(p_connected_source_id,p_credential_kind);
$function$;
revoke all on function public.read_connected_source_secret_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.read_connected_source_secret_service_v1(uuid,text) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.prepare_institutional_social_reply_self_api_v1(uuid, uuid, uuid, text, text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_institutional_social_reply_v1',
    'purpose','Authorize one institutional social reply from an existing governed conversation event.',
    'boundary','Requires endpoint send authority, existing institutional conversation continuity, incoming source event, active Facebook send binding, and existing response responsibility rules. Recipient is derived from source evidence rather than caller-supplied.',
    'truthBoundary','Creates an authorized outbound intent only. Provider transport acceptance is required before Atlas records the message as sent.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
) on conflict (signature) do update set
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

commit;
