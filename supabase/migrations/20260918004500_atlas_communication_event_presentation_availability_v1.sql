begin;

create or replace function atlas.organization_correspondence_conversation_self_api_v4(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_events jsonb;
begin
  v_base:=atlas.organization_correspondence_conversation_self_api_v3(
    p_communication_conversation_id
  );

  if coalesce(v_base->>'identityRoot','') <> 'communication_conversation'
     or nullif(v_base->>'communicationConversationId','')::uuid is distinct from p_communication_conversation_id then
    raise exception 'Common Correspondence detail lost Communication Conversation custody.' using errcode='23514';
  end if;

  select coalesce(jsonb_agg(
    event || jsonb_build_object(
      'presentationAvailable',
      exists(
        select 1
        from atlas.communication_raw_message_custody custody
        where custody.communication_event_id=nullif(event->>'communicationEventId','')::uuid
          and custody.custody_state='stored'
          and custody.storage_locator is not null
          and custody.raw_mime_sha256 is not null
      )
    )
    order by
      coalesce((event->>'occurredAt')::timestamptz,(event->>'capturedAt')::timestamptz),
      event->>'communicationEventId'
  ),'[]'::jsonb)
  into v_events
  from jsonb_array_elements(coalesce(v_base->'events','[]'::jsonb)) event;

  return (v_base-'events') || jsonb_build_object(
    'contractVersion','organization_correspondence_conversation_v4',
    'events',v_events
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_conversation_self_api_v4(uuid) from public,anon;
grant execute on function atlas.organization_correspondence_conversation_self_api_v4(uuid) to authenticated,service_role;

comment on function atlas.organization_correspondence_conversation_self_api_v4(uuid) is
'Common Communication Conversation detail projection adding only a bounded presentationAvailable flag per Event when governed stored raw-message custody exists. Raw MIME hashes and storage locators are not exposed.';

commit;
