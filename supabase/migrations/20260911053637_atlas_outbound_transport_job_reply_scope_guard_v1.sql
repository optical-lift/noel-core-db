create or replace function atlas.communication_outbound_email_transport_job_service_v1(
  p_outbound_operation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_op atlas.communication_outbound_operations%rowtype;
  v_payload jsonb;
  v_attachments jsonb;
  v_reply atlas.communication_events%rowtype;
  v_reply_message_id text;
  v_reply_refs jsonb:='[]'::jsonb;
  v_reply_thread_ref text;
begin
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;
  if v_op.operation_state<>'leased' then raise exception 'Outbound operation must be leased before transport payload is read.' using errcode='42501'; end if;

  v_payload:=atlas.communication_outbound_transport_payload_service_v1(v_op.id);
  v_attachments:=atlas.communication_outbound_attachment_transport_service_v1(v_op.id);

  if v_op.reply_to_communication_event_id is not null then
    select * into v_reply
    from atlas.communication_events
    where id=v_op.reply_to_communication_event_id
      and organization_id=v_op.organization_id
      and organization_unit_id is not distinct from v_op.organization_unit_id;
    if v_reply.id is null then raise exception 'Reply target communication event not found in outbound operation scope.' using errcode='42501'; end if;
    if not exists (
      select 1
      from atlas.institutional_conversation_messages m
      where m.institutional_conversation_id=v_op.institutional_conversation_id
        and m.communication_event_id=v_reply.id
    ) then
      raise exception 'Reply target communication event is outside the institutional conversation.' using errcode='42501';
    end if;
    v_reply_message_id:=nullif(btrim(v_reply.canonical_event#>>'{sourcePayload,messageId}'),'');
    if v_reply_message_id is null and v_reply.source_event_ref like 'rfc-message-id:%' then
      v_reply_message_id:=substr(v_reply.source_event_ref,length('rfc-message-id:')+1);
    end if;
    if jsonb_typeof(v_reply.canonical_event#>'{sourcePayload,references}')='array' then
      v_reply_refs:=v_reply.canonical_event#>'{sourcePayload,references}';
    end if;
    if v_reply_message_id is not null and not (v_reply_refs @> jsonb_build_array(v_reply_message_id)) then
      v_reply_refs:=v_reply_refs||jsonb_build_array(v_reply_message_id);
    end if;
    v_reply_thread_ref:=nullif(btrim(v_reply.canonical_event#>>'{source,threadRef}'),'');
  end if;

  return v_payload||jsonb_build_object(
    'contractVersion','communication_outbound_email_transport_job_v1',
    'attachments',coalesce(v_attachments->'items','[]'::jsonb),
    'replyMessageId',v_reply_message_id,
    'replyReferences',v_reply_refs,
    'replyThreadRef',v_reply_thread_ref
  );
end;
$function$;

revoke all on function atlas.communication_outbound_email_transport_job_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.communication_outbound_email_transport_job_service_v1(uuid) to service_role;