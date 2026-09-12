begin;

-- Keep provider transport outside communication canon. The external worker reports
-- only transport facts; Atlas reconstructs the canonical Communication Event from
-- the already-authorized outbound operation inside the database boundary.
create or replace function atlas.finalize_communication_outbound_transport_service_v1(
  p_outbound_operation_id uuid,
  p_lease_owner text,
  p_result_state text,
  p_provider_message_ref text,
  p_provider_response jsonb,
  p_recipient_results jsonb,
  p_transport_completed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_op atlas.communication_outbound_operations%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_result text:=lower(btrim(coalesce(p_result_state,'')));
  v_reply jsonb:='{}'::jsonb;
  v_thread_ref text;
  v_event_ref text;
  v_message_ref text:=nullif(btrim(coalesce(p_provider_message_ref,'')),'');
  v_occurred_at timestamptz:=coalesce(p_transport_completed_at,now());
  v_body text;
  v_body_state text;
  v_participants jsonb:='[]'::jsonb;
  v_attachments jsonb:='[]'::jsonb;
  v_item jsonb;
  v_address text;
  v_name text;
  v_role text;
  v_attachment_id uuid;
  v_attachment atlas.communication_outbound_attachments%rowtype;
  v_source_payload jsonb;
  v_hash_basis jsonb;
  v_content_hash text;
  v_canonical_event jsonb;
  v_receipt jsonb;
begin
  if v_result not in ('accepted','partially_accepted','temporary_failure','rejected','transport_error','unknown') then
    raise exception 'Unsupported outbound transport result.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_provider_response,'{}'::jsonb))<>'object' then
    raise exception 'Provider response must be a JSON object.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_recipient_results,'[]'::jsonb))<>'array' then
    raise exception 'Recipient results must be a JSON array.' using errcode='22023';
  end if;

  select * into v_op
  from atlas.communication_outbound_operations
  where id=p_outbound_operation_id
  for update;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;

  -- Known failures stay transport evidence only. Canonical communication evidence is
  -- constructed only after the transport has definitively accepted at least one copy.
  if v_result not in ('accepted','partially_accepted') then
    v_receipt:=atlas.record_communication_outbound_result_service_v2(
      p_outbound_operation_id,
      p_lease_owner,
      v_result,
      v_message_ref,
      coalesce(p_provider_response,'{}'::jsonb),
      coalesce(p_recipient_results,'[]'::jsonb),
      null
    );
    return v_receipt||jsonb_build_object(
      'contractVersion','communication_outbound_transport_finalize_v1',
      'canonicalEventConstructed',false
    );
  end if;

  -- Do not let this helper widen the existing lease authority membrane. The v2 result
  -- contract validates the same lease again when it records the attempt atomically.
  if v_op.operation_state<>'leased'
     or v_op.lease_owner is distinct from p_lease_owner
     or v_op.lease_expires_at<now() then
    raise exception 'Valid outbound transport lease required.' using errcode='42501';
  end if;

  select * into v_endpoint from atlas.communication_endpoints where id=v_op.communication_endpoint_id;
  select * into v_source from atlas.connected_sources where id=v_op.connected_source_id;
  if v_endpoint.id is null or v_source.id is null then
    raise exception 'Outbound operation endpoint/source custody is missing.' using errcode='55000';
  end if;
  if v_endpoint.organization_id is distinct from v_op.organization_id
     or v_endpoint.organization_unit_id is distinct from v_op.organization_unit_id
     or v_source.custodian_organization_id is distinct from v_op.organization_id
     or v_source.custodian_organization_unit_id is distinct from v_op.organization_unit_id then
    raise exception 'Outbound operation endpoint/source custody no longer matches.' using errcode='23514';
  end if;

  v_event_ref:='atlas-outbound-operation:'||v_op.id::text;
  if v_op.reply_to_communication_event_id is not null then
    v_reply:=atlas.communication_reply_transport_context_service_v1(v_op.reply_to_communication_event_id);
  end if;
  if nullif(v_reply->>'connectedSourceId','') is null
     or (v_reply->>'connectedSourceId')::uuid is distinct from v_op.connected_source_id then
    v_reply:='{}'::jsonb;
  end if;
  v_thread_ref:=coalesce(
    nullif(btrim(v_reply->>'sourceThreadRef'),''),
    'atlas-institutional-conversation:'||v_op.institutional_conversation_id::text
  );

  v_participants:=jsonb_build_array(jsonb_build_object(
    'role','sender',
    'addressKind','email',
    'address',v_endpoint.address,
    'isSelf',true,
    'metadata',jsonb_strip_nulls(jsonb_build_object('displayName',v_endpoint.display_name))
  ));

  for v_role in select role from (values ('to'),('cc'),('bcc')) roles(role) loop
    for v_item in
      select value from jsonb_array_elements(
        case v_role
          when 'to' then coalesce(v_op.to_recipients,'[]'::jsonb)
          when 'cc' then coalesce(v_op.cc_recipients,'[]'::jsonb)
          else coalesce(v_op.bcc_recipients,'[]'::jsonb)
        end
      )
    loop
      if jsonb_typeof(v_item)='object' then
        v_address:=nullif(btrim(v_item->>'address'),'');
        v_name:=nullif(btrim(v_item->>'name'),'');
      elsif jsonb_typeof(v_item)='string' then
        v_address:=nullif(btrim(trim(both '"' from v_item::text)),'');
        v_name:=null;
      else
        raise exception 'Outbound recipient must be an address object or string.' using errcode='22023';
      end if;
      if v_address is null then raise exception 'Outbound recipient address is required.' using errcode='22023'; end if;
      v_participants:=v_participants||jsonb_build_array(jsonb_build_object(
        'role',v_role,
        'addressKind','email',
        'address',v_address,
        'isSelf',false,
        'metadata',jsonb_strip_nulls(jsonb_build_object('displayName',v_name))
      ));
    end loop;
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(v_op.attachment_refs,'[]'::jsonb)) loop
    begin
      v_attachment_id:=trim(both '"' from v_item::text)::uuid;
    exception when invalid_text_representation then
      raise exception 'Outbound attachment reference is invalid.' using errcode='22023';
    end;
    select * into v_attachment from atlas.communication_outbound_attachments where id=v_attachment_id;
    if v_attachment.id is null
       or v_attachment.organization_id is distinct from v_op.organization_id
       or v_attachment.organization_unit_id is distinct from v_op.organization_unit_id
       or v_attachment.communication_endpoint_id is distinct from v_op.communication_endpoint_id
       or v_attachment.attachment_state<>'ready' then
      raise exception 'Outbound attachment is missing, unready, or outside operation scope.' using errcode='42501';
    end if;
    v_attachments:=v_attachments||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'sourceAttachmentRef',v_attachment.id::text,
      'mimeType',v_attachment.mime_type,
      'transferName',v_attachment.file_name,
      'sourceContentHash',v_attachment.sha256,
      'custodyLocator','storage://'||v_attachment.storage_bucket||'/'||v_attachment.storage_object_path,
      'metadata',jsonb_build_object('byteLength',v_attachment.byte_length)
    )));
  end loop;

  if nullif(v_op.body_text,'') is not null then
    v_body:=v_op.body_text;
    v_body_state:='exact_text';
  elsif nullif(v_op.body_html,'') is not null then
    v_body:=v_op.body_html;
    v_body_state:='attributed_body_preserved';
  else
    v_body:=null;
    v_body_state:='empty';
  end if;

  v_source_payload:=jsonb_strip_nulls(jsonb_build_object(
    'messageId',v_message_ref,
    'inReplyTo',nullif(v_reply->>'messageId',''),
    'references',coalesce(v_reply->'references','[]'::jsonb),
    'subject',v_op.subject,
    'bodyHtml',v_op.body_html,
    'transportResult',v_result,
    'recipientResults',coalesce(p_recipient_results,'[]'::jsonb),
    'providerResponse',coalesce(p_provider_response,'{}'::jsonb),
    'outboundOperationId',v_op.id
  ));

  v_hash_basis:=jsonb_build_object(
    'source',jsonb_build_object(
      'kind',v_source.provider_key,
      'accountRef',v_source.provider_account_key,
      'eventRef',v_event_ref,
      'threadRef',v_thread_ref
    ),
    'direction','outgoing',
    'speaker',jsonb_build_object('isSelf',true,'address',v_endpoint.address),
    'occurredAt',v_occurred_at,
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
    'captureMode','atlas_outbound_transport',
    'source',v_hash_basis->'source',
    'direction','outgoing',
    'speaker',v_hash_basis->'speaker',
    'occurredAt',v_occurred_at,
    'capturedAt',now(),
    'subject',v_op.subject,
    'body',v_body,
    'bodyState',v_body_state,
    'participants',v_participants,
    'attachments',v_attachments,
    'sourcePayload',v_source_payload,
    'contentHash',v_content_hash
  );

  v_receipt:=atlas.record_communication_outbound_result_service_v2(
    p_outbound_operation_id,
    p_lease_owner,
    v_result,
    v_message_ref,
    coalesce(p_provider_response,'{}'::jsonb),
    coalesce(p_recipient_results,'[]'::jsonb),
    v_canonical_event
  );

  return v_receipt||jsonb_build_object(
    'contractVersion','communication_outbound_transport_finalize_v1',
    'canonicalEventConstructed',true,
    'canonicalEventSource','atlas_database',
    'sourceEventRef',v_event_ref,
    'sourceThreadRef',v_thread_ref
  );
end;$function$;

revoke all on function atlas.finalize_communication_outbound_transport_service_v1(uuid,text,text,text,jsonb,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function atlas.finalize_communication_outbound_transport_service_v1(uuid,text,text,text,jsonb,jsonb,timestamptz) to service_role;

comment on function atlas.finalize_communication_outbound_transport_service_v1(uuid,text,text,text,jsonb,jsonb,timestamptz) is
  'Transport-only finalization seam. External gateways report SMTP/provider facts; Atlas reconstructs canonical outbound Communication Event evidence from the already-authorized operation. Ambiguous post-DATA outcomes must not call this function and instead expire into transport_uncertain.';

commit;
