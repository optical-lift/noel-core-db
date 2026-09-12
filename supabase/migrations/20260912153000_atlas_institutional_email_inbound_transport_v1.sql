begin;

-- Generic IMAP is transport evidence only. This seam accepts physical mailbox/RFC facts,
-- resolves only explicit reply-reference continuity against existing Communication Events,
-- constructs the canonical event inside Atlas, and then delegates all durable admission,
-- deduplication, relationship reconciliation, and response-state consequences to the
-- existing organization communication ingestion kernel.

create or replace function atlas.institutional_email_capture_cursor_service_v1(
  p_connected_source_id uuid,
  p_mailbox text default 'INBOX'
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_mailbox text:=btrim(coalesce(nullif(p_mailbox,''),'INBOX'));
  v_state atlas.communication_source_sync_states%rowtype;
begin
  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id
    and custodian_organization_id is not null
    and provider_key='imap_smtp_email'
    and authorization_state='connected'
    and capabilities @> '{"communicationCapture":true}'::jsonb;
  if v_source.id is null then
    raise exception 'Connected institutional IMAP capture source required.' using errcode='42501';
  end if;

  select * into v_state
  from atlas.communication_source_sync_states
  where connected_source_id=v_source.id
    and sync_role='capture'
    and state_key='imap_uid:'||v_mailbox;

  return jsonb_build_object(
    'contractVersion','institutional_email_capture_cursor_v1',
    'connectedSourceId',v_source.id,
    'mailbox',v_mailbox,
    'uidValidity',case when v_state.id is null then null else (v_state.state_payload->>'uidValidity')::bigint end,
    'lastUid',case when v_state.id is null then 0 else coalesce((v_state.state_payload->>'lastUid')::bigint,0) end,
    'checkpointAt',v_state.checkpoint_at,
    'syncState',coalesce(v_state.sync_state,'active')
  );
end;
$function$;

create or replace function atlas.record_institutional_email_capture_cursor_service_v1(
  p_connected_source_id uuid,
  p_mailbox text,
  p_uid_validity bigint,
  p_last_uid bigint
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_mailbox text:=btrim(coalesce(nullif(p_mailbox,''),'INBOX'));
  v_state atlas.communication_source_sync_states%rowtype;
  v_existing_validity bigint;
  v_existing_uid bigint;
begin
  if p_uid_validity is null or p_uid_validity<1 or p_last_uid is null or p_last_uid<1 then
    raise exception 'Positive IMAP UIDVALIDITY and UID are required.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id
    and custodian_organization_id is not null
    and provider_key='imap_smtp_email'
    and authorization_state='connected'
    and capabilities @> '{"communicationCapture":true}'::jsonb;
  if v_source.id is null then
    raise exception 'Connected institutional IMAP capture source required.' using errcode='42501';
  end if;

  select * into v_state
  from atlas.communication_source_sync_states
  where connected_source_id=v_source.id
    and sync_role='capture'
    and state_key='imap_uid:'||v_mailbox
  for update;

  if v_state.id is null then
    insert into atlas.communication_source_sync_states(
      connected_source_id,sync_role,state_key,state_kind,sync_state,state_payload,checkpoint_at,observed_at
    ) values (
      v_source.id,'capture','imap_uid:'||v_mailbox,'imap_uid_cursor','active',
      jsonb_build_object('mailbox',v_mailbox,'uidValidity',p_uid_validity,'lastUid',p_last_uid),
      now(),now()
    ) returning * into v_state;
  else
    v_existing_validity:=nullif(v_state.state_payload->>'uidValidity','')::bigint;
    v_existing_uid:=coalesce(nullif(v_state.state_payload->>'lastUid','')::bigint,0);
    if v_existing_validity=p_uid_validity and p_last_uid<v_existing_uid then
      raise exception 'IMAP UID cursor cannot move backward within one UIDVALIDITY epoch.' using errcode='23514';
    end if;
    update atlas.communication_source_sync_states
    set state_kind='imap_uid_cursor',
        sync_state='active',
        state_payload=jsonb_build_object('mailbox',v_mailbox,'uidValidity',p_uid_validity,'lastUid',p_last_uid),
        checkpoint_at=now(),
        observed_at=now(),
        updated_at=now()
    where id=v_state.id
    returning * into v_state;
  end if;

  return jsonb_build_object(
    'contractVersion','institutional_email_capture_cursor_v1',
    'connectedSourceId',v_source.id,
    'mailbox',v_mailbox,
    'uidValidity',(v_state.state_payload->>'uidValidity')::bigint,
    'lastUid',(v_state.state_payload->>'lastUid')::bigint,
    'checkpointAt',v_state.checkpoint_at,
    'syncState',v_state.sync_state
  );
end;
$function$;

create or replace function atlas.ingest_institutional_email_transport_service_v1(
  p_connected_source_id uuid,
  p_mailbox text,
  p_uid_validity bigint,
  p_uid bigint,
  p_message_id text,
  p_in_reply_to text,
  p_references jsonb,
  p_from jsonb,
  p_to jsonb,
  p_cc jsonb,
  p_bcc jsonb,
  p_subject text,
  p_occurred_at timestamptz,
  p_body_text text,
  p_body_html text,
  p_attachments jsonb,
  p_raw_mime_sha256 text,
  p_raw_byte_length bigint,
  p_captured_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_endpoint_id uuid;
  v_endpoint_count int;
  v_mailbox text:=btrim(coalesce(nullif(p_mailbox,''),'INBOX'));
  v_message_id text:=nullif(btrim(coalesce(p_message_id,'')),'');
  v_in_reply_to text:=nullif(btrim(coalesce(p_in_reply_to,'')),'');
  v_source_event_ref text;
  v_thread_ref text;
  v_thread_count int:=0;
  v_thread_resolution text;
  v_candidates jsonb:='[]'::jsonb;
  v_ref text;
  v_item jsonb;
  v_role text;
  v_address text;
  v_name text;
  v_normalized text;
  v_is_self boolean;
  v_has_self boolean:=false;
  v_participants jsonb:='[]'::jsonb;
  v_attachments jsonb:=coalesce(p_attachments,'[]'::jsonb);
  v_body text;
  v_body_state text;
  v_source_payload jsonb;
  v_hash_basis jsonb;
  v_content_hash text;
  v_canonical_event jsonb;
  v_receipt jsonb;
  v_event_id uuid;
  v_conversation_id uuid;
  v_raw_receipt jsonb;
  v_from_address text;
  v_from_name text;
begin
  if p_uid_validity is null or p_uid_validity<1 or p_uid is null or p_uid<1 then
    raise exception 'Positive IMAP UIDVALIDITY and UID are required.' using errcode='22023';
  end if;
  if lower(coalesce(p_raw_mime_sha256,'')) !~ '^[0-9a-f]{64}$' or p_raw_byte_length is null or p_raw_byte_length<0 then
    raise exception 'Raw MIME SHA-256 and nonnegative byte length are required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_references,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_from,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_to,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_cc,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_bcc,'[]'::jsonb))<>'array'
     or jsonb_typeof(v_attachments)<>'array' then
    raise exception 'Email references, address collections, and attachments must use the expected JSON shapes.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id
    and custodian_organization_id is not null
    and provider_key='imap_smtp_email'
    and authorization_state='connected'
    and capabilities @> '{"communicationCapture":true}'::jsonb;
  if v_source.id is null then
    raise exception 'Connected institutional IMAP capture source required.' using errcode='42501';
  end if;

  select count(*),min(ep.id) into v_endpoint_count,v_endpoint_id
  from atlas.communication_endpoint_source_bindings b
  join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
  where b.connected_source_id=v_source.id
    and b.binding_state='active'
    and b.binding_role in ('receive','send_receive')
    and ep.endpoint_state='active'
    and ep.endpoint_kind='email';
  if v_endpoint_count<>1 then
    raise exception 'Exactly one active institutional email receive endpoint is required for this IMAP source; found %.',v_endpoint_count using errcode='55000';
  end if;
  select * into v_endpoint from atlas.communication_endpoints where id=v_endpoint_id;
  if v_endpoint.organization_id is distinct from v_source.custodian_organization_id
     or v_endpoint.organization_unit_id is distinct from v_source.custodian_organization_unit_id then
    raise exception 'Inbound email endpoint/source custody no longer matches.' using errcode='23514';
  end if;

  v_source_event_ref:='imap:'||lower(v_mailbox)||':'||p_uid_validity::text||':'||p_uid::text;

  -- Resolve only explicit RFC reply evidence to a thread already in Atlas custody.
  -- Multiple distinct thread matches fail closed into a standalone source thread.
  if v_in_reply_to is not null then
    v_candidates:=v_candidates||jsonb_build_array(v_in_reply_to);
  end if;
  for v_ref in select btrim(value) from jsonb_array_elements_text(coalesce(p_references,'[]'::jsonb)) loop
    if v_ref<>'' then v_candidates:=v_candidates||jsonb_build_array(v_ref); end if;
  end loop;

  select count(distinct t.source_thread_ref),min(t.source_thread_ref)
  into v_thread_count,v_thread_ref
  from atlas.communication_events e
  join atlas.communication_threads t on t.id=e.thread_id
  where e.connected_source_id=v_source.id
    and e.canonical_event#>>'{sourcePayload,messageId}' in (
      select distinct value from jsonb_array_elements_text(v_candidates)
    );

  if v_thread_count=1 then
    v_thread_resolution:='explicit_rfc_reply_reference';
  elsif v_thread_count>1 then
    v_thread_ref:=coalesce('rfc822-message:'||v_message_id,'imap-message:'||lower(v_mailbox)||':'||p_uid_validity::text||':'||p_uid::text);
    v_thread_resolution:='ambiguous_explicit_reply_references_standalone';
  else
    v_thread_ref:=coalesce('rfc822-message:'||v_message_id,'imap-message:'||lower(v_mailbox)||':'||p_uid_validity::text||':'||p_uid::text);
    v_thread_resolution:='standalone_source_message';
  end if;

  v_from_address:=nullif(btrim(p_from->>'address'),'');
  v_from_name:=nullif(btrim(p_from->>'name'),'');
  if v_from_address is null then
    raise exception 'Inbound email requires an RFC From address.' using errcode='22023';
  end if;
  v_normalized:=atlas.normalize_communication_endpoint_address_v1('email',v_from_address);
  v_is_self:=v_normalized=v_endpoint.address_normalized;
  v_has_self:=v_is_self;
  v_participants:=v_participants||jsonb_build_array(jsonb_build_object(
    'role','sender','addressKind','email','address',v_from_address,'isSelf',v_is_self,
    'metadata',jsonb_strip_nulls(jsonb_build_object('displayName',v_from_name))
  ));

  for v_role in select role from (values ('to'),('cc'),('bcc')) roles(role) loop
    for v_item in
      select value from jsonb_array_elements(
        case v_role when 'to' then coalesce(p_to,'[]'::jsonb) when 'cc' then coalesce(p_cc,'[]'::jsonb) else coalesce(p_bcc,'[]'::jsonb) end
      )
    loop
      if jsonb_typeof(v_item)<>'object' then
        raise exception 'Inbound email address entries must be JSON objects.' using errcode='22023';
      end if;
      v_address:=nullif(btrim(v_item->>'address'),'');
      v_name:=nullif(btrim(v_item->>'name'),'');
      if v_address is null then raise exception 'Inbound email participant address is required.' using errcode='22023'; end if;
      v_normalized:=atlas.normalize_communication_endpoint_address_v1('email',v_address);
      v_is_self:=v_normalized=v_endpoint.address_normalized;
      v_has_self:=v_has_self or v_is_self;
      v_participants:=v_participants||jsonb_build_array(jsonb_build_object(
        'role',v_role,'addressKind','email','address',v_address,'isSelf',v_is_self,
        'metadata',jsonb_strip_nulls(jsonb_build_object('displayName',v_name))
      ));
    end loop;
  end loop;

  if not v_has_self then
    v_participants:=v_participants||jsonb_build_array(jsonb_build_object(
      'role','participant','addressKind','email','address',v_endpoint.address,'isSelf',true,
      'metadata',jsonb_build_object('mailboxDeliveryObserved',true,'headerRecipientRoleUnknown',true)
    ));
  end if;

  if nullif(p_body_text,'') is not null then
    v_body:=p_body_text;
    v_body_state:='exact_text';
  elsif nullif(p_body_html,'') is not null then
    v_body:=p_body_html;
    v_body_state:='attributed_body_preserved';
  else
    v_body:=null;
    v_body_state:='empty';
  end if;

  v_source_payload:=jsonb_strip_nulls(jsonb_build_object(
    'mailbox',v_mailbox,
    'uidValidity',p_uid_validity,
    'uid',p_uid,
    'messageId',v_message_id,
    'inReplyTo',v_in_reply_to,
    'references',coalesce(p_references,'[]'::jsonb),
    'subject',p_subject,
    'bodyHtml',p_body_html,
    'rawMimeSha256',lower(p_raw_mime_sha256),
    'rawByteLength',p_raw_byte_length,
    'threadResolutionState',v_thread_resolution
  ));

  v_hash_basis:=jsonb_build_object(
    'source',jsonb_build_object(
      'kind',v_source.provider_key,
      'accountRef',v_source.provider_account_key,
      'eventRef',v_source_event_ref,
      'threadRef',v_thread_ref
    ),
    'direction','incoming',
    'speaker',jsonb_build_object('isSelf',v_from_address is not null and atlas.normalize_communication_endpoint_address_v1('email',v_from_address)=v_endpoint.address_normalized,'address',v_from_address),
    'occurredAt',p_occurred_at,
    'body',v_body,
    'bodyState',v_body_state,
    'participants',v_participants,
    'attachments',v_attachments,
    'sourcePayload',v_source_payload
  );
  v_content_hash:=encode(extensions.digest(convert_to(v_hash_basis::text,'UTF8'),'sha256'),'hex');

  v_canonical_event:=jsonb_build_object(
    'schemaVersion','atlas_communication_event_v1',
    'sourceAuthority','evidence_only',
    'permittedStateEffect','append_source_attributed_evidence_only',
    'governingStateChanged',false,
    'captureMode','generic_imap_transport',
    'source',v_hash_basis->'source',
    'direction','incoming',
    'speaker',v_hash_basis->'speaker',
    'occurredAt',p_occurred_at,
    'capturedAt',coalesce(p_captured_at,now()),
    'subject',p_subject,
    'body',v_body,
    'bodyState',v_body_state,
    'participants',v_participants,
    'attachments',v_attachments,
    'sourcePayload',v_source_payload,
    'contentHash',v_content_hash
  );

  v_receipt:=atlas.ingest_organization_communication_events_service_v3(
    v_source.id,
    jsonb_build_array(v_canonical_event),
    jsonb_build_object(
      'source','generic_imap_transport',
      'mailbox',v_mailbox,
      'uidValidity',p_uid_validity,
      'lastUid',p_uid,
      'rawMimeSha256',lower(p_raw_mime_sha256)
    )
  );

  select id into v_event_id
  from atlas.communication_events
  where connected_source_id=v_source.id and source_event_ref=v_source_event_ref;
  if v_event_id is null then
    raise exception 'Inbound email did not enter Communication Event custody.' using errcode='55000';
  end if;

  v_raw_receipt:=atlas.record_communication_raw_message_custody_service_v1(
    v_event_id,
    lower(p_raw_mime_sha256),
    p_raw_byte_length,
    null,
    'hash_only',
    jsonb_build_object('source','generic_imap_transport','mailbox',v_mailbox,'uidValidity',p_uid_validity,'uid',p_uid)
  );

  select institutional_conversation_id into v_conversation_id
  from atlas.institutional_conversation_messages
  where communication_event_id=v_event_id;

  return jsonb_build_object(
    'contractVersion','institutional_email_inbound_transport_v1',
    'connectedSourceId',v_source.id,
    'communicationEndpointId',v_endpoint.id,
    'communicationEventId',v_event_id,
    'institutionalConversationId',v_conversation_id,
    'sourceEventRef',v_source_event_ref,
    'sourceThreadRef',v_thread_ref,
    'threadResolutionState',v_thread_resolution,
    'rawMimeCustody',v_raw_receipt,
    'ingestReceipt',v_receipt,
    'canonicalEventConstructed',true,
    'canonicalEventSource','atlas_database'
  );
end;
$function$;

revoke all on function atlas.institutional_email_capture_cursor_service_v1(uuid,text) from public,anon,authenticated;
revoke all on function atlas.record_institutional_email_capture_cursor_service_v1(uuid,text,bigint,bigint) from public,anon,authenticated;
revoke all on function atlas.ingest_institutional_email_transport_service_v1(uuid,text,bigint,bigint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text,timestamptz,text,text,jsonb,text,bigint,timestamptz) from public,anon,authenticated;

grant execute on function atlas.institutional_email_capture_cursor_service_v1(uuid,text) to service_role;
grant execute on function atlas.record_institutional_email_capture_cursor_service_v1(uuid,text,bigint,bigint) to service_role;
grant execute on function atlas.ingest_institutional_email_transport_service_v1(uuid,text,bigint,bigint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text,timestamptz,text,text,jsonb,text,bigint,timestamptz) to service_role;

comment on function atlas.ingest_institutional_email_transport_service_v1(uuid,text,bigint,bigint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text,timestamptz,text,text,jsonb,text,bigint,timestamptz) is
  'Transport-only generic IMAP ingestion seam. The worker reports physical RFC/MIME and mailbox facts; Atlas constructs canonical Communication Event evidence, resolves only explicit reply-reference continuity, delegates durable admission to the existing communication kernel, and records raw MIME hash custody.';

commit;
