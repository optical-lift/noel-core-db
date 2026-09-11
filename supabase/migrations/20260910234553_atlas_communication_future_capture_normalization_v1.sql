begin;

create or replace function atlas.materialize_person_communication_event_details_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_participants jsonb:=coalesce(new.canonical_event->'participants','[]'::jsonb);
  v_fallback jsonb:='[]'::jsonb;
  v_address text;
  v_attachment jsonb;
  v_attachment_ref text;
begin
  if new.principal_id is null then return new; end if;
  if jsonb_typeof(v_participants)='array' and jsonb_array_length(v_participants)>0 then
    perform atlas.record_communication_event_participants_service_v1(new.id,v_participants);
  else
    if nullif(btrim(new.canonical_event#>>'{speaker,address}'),'') is not null then
      v_fallback:=v_fallback||jsonb_build_array(jsonb_build_object('role','sender','address',new.canonical_event#>>'{speaker,address}','isSelf',coalesce((new.canonical_event#>>'{speaker,isSelf}')::boolean,false)));
    end if;
    for v_address in select nullif(btrim(x),'') from regexp_split_to_table(coalesce(new.canonical_event#>>'{sourcePayload,participantAddresses}',''),'[;,]') x loop
      if v_address is not null then v_fallback:=v_fallback||jsonb_build_array(jsonb_build_object('role',case when new.direction='incoming' and not new.speaker_is_self and new.speaker_address is not null and v_address=new.speaker_address then 'sender' else 'participant' end,'address',v_address,'isSelf',false)); end if;
    end loop;
    if jsonb_array_length(v_fallback)>0 then perform atlas.record_communication_event_participants_service_v1(new.id,v_fallback); end if;
  end if;

  if jsonb_typeof(coalesce(new.canonical_event->'attachments','[]'::jsonb))='array' then
    for v_attachment in select value from jsonb_array_elements(coalesce(new.canonical_event->'attachments','[]'::jsonb)) loop
      v_attachment_ref:=nullif(btrim(v_attachment->>'sourceAttachmentRef'),'');
      if v_attachment_ref is not null then
        insert into atlas.communication_attachments(principal_id,organization_id,organization_unit_id,event_id,source_attachment_ref,mime_type,transfer_name,source_content_hash,custody_locator,metadata)
        values(new.principal_id,null,null,new.id,v_attachment_ref,nullif(lower(btrim(v_attachment->>'mimeType')),''),nullif(btrim(v_attachment->>'transferName'),''),nullif(lower(btrim(v_attachment->>'sourceContentHash')),''),nullif(btrim(v_attachment->>'custodyLocator'),''),coalesce(v_attachment->'metadata','{}'::jsonb))
        on conflict (event_id,source_attachment_ref) do nothing;
      end if;
    end loop;
  end if;
  return new;
end;$function$;

drop trigger if exists communication_events_materialize_person_details_v1 on atlas.communication_events;
create trigger communication_events_materialize_person_details_v1
after insert on atlas.communication_events
for each row when (new.principal_id is not null)
execute function atlas.materialize_person_communication_event_details_v1();

create or replace view atlas.v_flower_buyer_correspondence_events_v1 as
select
  o.farm_id,o.organization_id,o.organization_unit_id,r.external_relationship_id,
  ('availability_outreach_recipient:'||r.id::text) as event_key,
  o.sent_at as occurred_at,'outgoing'::text as direction,'email'::text as channel,
  o.subject,o.body_text as body,r.recipient_address as participant_address,
  'flower_availability_outreach'::text as source_kind,o.id as source_id,r.interaction_id,
  jsonb_build_object('outreachRoundId',o.id,'availabilitySnapshotId',o.availability_snapshot_id,'recipientId',r.id,'bodySha256',o.body_sha256,'sourceKind',o.source_kind,'sourceRef',o.source_ref)||o.metadata||r.metadata as metadata
from atlas.flower_availability_outreach_recipients r
join atlas.flower_availability_outreach_rounds o on o.id=r.outreach_round_id
union all
select
  f.id as farm_id,e.organization_id,e.organization_unit_id,e.external_relationship_id,
  ('communication_event:'||e.communication_event_id::text) as event_key,
  e.occurred_at,e.direction,e.channel,e.subject,e.body,e.participant_address,
  'communication_event'::text as source_kind,e.communication_event_id as source_id,null::uuid as interaction_id,
  e.metadata||jsonb_build_object('connectedSourceId',e.connected_source_id,'threadId',e.thread_id,'sourceEventRef',e.source_event_ref,'participantRole',e.participant_role,'addressKind',e.address_kind) as metadata
from atlas.v_external_relationship_communication_events_v1 e
join atlas.farms f on f.organization_id=e.organization_id and f.organization_unit_id is not distinct from e.organization_unit_id;

comment on view atlas.v_flower_buyer_correspondence_events_v1 is 'Flower buyer correspondence combines documented legacy availability outreach with the universal External Relationship communication projection. New provider channels do not require flower-specific identity logic.';

revoke all on function atlas.materialize_person_communication_event_details_v1() from public,anon,authenticated;
grant execute on function atlas.materialize_person_communication_event_details_v1() to service_role;

commit;
