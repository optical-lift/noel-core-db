begin;

create table atlas.communication_event_participants (
  id uuid primary key default gen_random_uuid(),
  communication_event_id uuid not null references atlas.communication_events(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  participant_role text not null check (participant_role in ('sender','to','cc','bcc','participant','other')),
  address text not null,
  address_normalized text not null,
  is_self boolean not null default false,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint communication_event_participants_address_nonblank check (btrim(address)<>''),
  constraint communication_event_participants_normalized_nonblank check (btrim(address_normalized)<>'') ,
  unique(communication_event_id,participant_role,address_normalized)
);
create index communication_event_participants_identity_idx on atlas.communication_event_participants(connected_source_id,address_normalized,participant_role,communication_event_id);
create index communication_event_participants_event_idx on atlas.communication_event_participants(communication_event_id);
comment on table atlas.communication_event_participants is 'Provider-neutral participant evidence attached to immutable Communication Events. Sender/to/cc/bcc identities remain source evidence until explicitly resolved to Atlas identity.';

create or replace function atlas.guard_communication_event_participant_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_event atlas.communication_events%rowtype;
begin
  select * into v_event from atlas.communication_events where id=new.communication_event_id;
  if v_event.id is null or v_event.principal_id is distinct from new.principal_id or v_event.connected_source_id is distinct from new.connected_source_id then
    raise exception 'Communication participant must belong to the same event Principal/source.' using errcode='23514';
  end if;
  new.participant_role:=lower(btrim(new.participant_role));
  new.address:=btrim(new.address);
  new.address_normalized:=lower(btrim(new.address_normalized));
  return new;
end;$function$;
create trigger communication_event_participant_guard_v1 before insert or update on atlas.communication_event_participants for each row execute function atlas.guard_communication_event_participant_v1();

create or replace function atlas.prevent_communication_event_participant_mutation_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin raise exception 'Communication participant evidence is append-only.' using errcode='55000'; end;$function$;
create trigger communication_event_participant_append_only_v1 before update or delete on atlas.communication_event_participants for each row execute function atlas.prevent_communication_event_participant_mutation_v1();

create or replace function atlas.record_communication_event_participants_service_v1(p_communication_event_id uuid,p_participants jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_event atlas.communication_events%rowtype; v_participant jsonb; v_role text; v_address text; v_count integer:=0;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if jsonb_typeof(coalesce(p_participants,'[]'::jsonb))<>'array' then raise exception 'Participants must be a JSON array.' using errcode='22023'; end if;
  for v_participant in select value from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
    v_role:=lower(coalesce(nullif(btrim(v_participant->>'role'),''),'participant'));
    v_address:=nullif(btrim(v_participant->>'address'),'');
    if v_address is null then raise exception 'Every communication participant requires an address.' using errcode='22023'; end if;
    insert into atlas.communication_event_participants(communication_event_id,principal_id,connected_source_id,participant_role,address,address_normalized,is_self,metadata)
    values(v_event.id,v_event.principal_id,v_event.connected_source_id,v_role,v_address,lower(v_address),coalesce((v_participant->>'isSelf')::boolean,false),coalesce(v_participant->'metadata','{}'::jsonb))
    on conflict (communication_event_id,participant_role,address_normalized) do nothing;
    if found then v_count:=v_count+1; end if;
  end loop;
  return jsonb_build_object('communicationEventId',v_event.id,'participantsInserted',v_count);
end;$function$;

create or replace function atlas.link_communication_email_identity_to_external_relationship_service_v1(
  p_principal_id uuid,p_connected_source_id uuid,p_external_relationship_id uuid,p_email text,p_thread_id uuid default null,
  p_relation_basis text default 'exact_email_identifier',p_confidence numeric default 1,p_provenance jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_user_id uuid; v_relationship atlas.external_relationships%rowtype; v_email text:=lower(btrim(coalesce(p_email,''))); v_existing atlas.communication_identity_links%rowtype; v_label text; v_link_id uuid;
begin
  if v_email='' then raise exception 'Email is required.' using errcode='22023'; end if;
  if p_confidence is not null and (p_confidence<0 or p_confidence>1) then raise exception 'Confidence must be between 0 and 1.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_provenance,'{}'::jsonb))<>'object' then raise exception 'Provenance must be a JSON object.' using errcode='22023'; end if;
  select user_id into v_user_id from atlas.principals where id=p_principal_id and status='active';
  if v_user_id is null then raise exception 'Active Principal not found.' using errcode='P0002'; end if;
  select * into v_relationship from atlas.external_relationships where id=p_external_relationship_id;
  if v_relationship.id is null then raise exception 'External relationship not found.' using errcode='P0002'; end if;
  if not exists(select 1 from atlas.organization_memberships om where om.organization_id=v_relationship.organization_id and om.user_id=v_user_id and om.active) then raise exception 'Principal is not an active member of the relationship organization.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.connected_sources s where s.id=p_connected_source_id and s.custodian_user_id=v_user_id and s.authorization_state='connected') then raise exception 'Connected source is not owned by this Principal.' using errcode='42501'; end if;
  if p_thread_id is not null and not exists(select 1 from atlas.communication_threads t where t.id=p_thread_id and t.principal_id=p_principal_id and t.connected_source_id=p_connected_source_id) then raise exception 'Thread is outside this Principal/source.' using errcode='23514'; end if;
  if not exists(select 1 from atlas.identity_subject_external_identifiers i where i.organization_id=v_relationship.organization_id and i.subject_id=v_relationship.subject_id and i.identifier_type='email' and i.identifier_normalized=v_email and i.is_current) then raise exception 'Email is not an established identifier for this relationship subject.' using errcode='23514'; end if;
  select * into v_existing from atlas.communication_identity_links l where l.connected_source_id=p_connected_source_id and l.source_identity_kind='email' and lower(l.source_identity_key)=v_email and l.relation_status='active' limit 1;
  if v_existing.id is not null then
    if v_existing.target_domain='atlas' and v_existing.target_kind='external_relationship' and v_existing.target_id=p_external_relationship_id::text then return jsonb_build_object('communicationIdentityLinkId',v_existing.id,'created',false); end if;
    raise exception 'This source email identity is already actively linked to a different Atlas target.' using errcode='23505';
  end if;
  select display_name into v_label from atlas.identity_subject_projections where subject_id=v_relationship.subject_id;
  insert into atlas.communication_identity_links(principal_id,connected_source_id,thread_id,source_identity_kind,source_identity_key,target_domain,target_kind,target_id,target_label,relation_basis,confidence,relation_status,provenance,created_by_user_id)
  values(p_principal_id,p_connected_source_id,p_thread_id,'email',v_email,'atlas','external_relationship',p_external_relationship_id::text,v_label,lower(btrim(coalesce(nullif(p_relation_basis,''),'exact_email_identifier'))),p_confidence,'active',coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('organizationId',v_relationship.organization_id,'identitySubjectId',v_relationship.subject_id),v_user_id)
  returning id into v_link_id;
  return jsonb_build_object('communicationIdentityLinkId',v_link_id,'created',true);
end;$function$;

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
select cr.farm_id,cr.organization_id,cr.organization_unit_id,cr.external_relationship_id,cr.event_key,cr.occurred_at,cr.direction,cr.channel,cr.subject,cr.body,cr.participant_address,cr.source_kind,cr.source_id,cr.interaction_id,cr.metadata
from (
  select distinct on (f.id,rel.id,e.id)
    f.id as farm_id,rel.organization_id,rel.organization_unit_id,rel.id as external_relationship_id,
    ('communication_event:'||e.id::text) as event_key,e.occurred_at,e.direction,
    coalesce(nullif(e.canonical_event#>>'{source,kind}',''),'communication') as channel,
    coalesce(nullif(e.canonical_event->>'subject',''),nullif(e.canonical_event#>>'{sourcePayload,subject}','')) as subject,
    e.body,p.address as participant_address,'communication_event'::text as source_kind,e.id as source_id,null::uuid as interaction_id,
    jsonb_build_object('communicationEventId',e.id,'connectedSourceId',e.connected_source_id,'threadId',e.thread_id,'participantRole',p.participant_role,'sourceEventRef',e.source_event_ref) as metadata,
    case p.participant_role when 'sender' then 0 when 'to' then 1 when 'cc' then 2 when 'bcc' then 3 else 4 end as role_order,
    p.id as participant_id
  from atlas.communication_events e
  join atlas.communication_event_participants p on p.communication_event_id=e.id
  join atlas.communication_identity_links l on l.connected_source_id=p.connected_source_id and l.source_identity_kind='email' and lower(l.source_identity_key)=p.address_normalized and l.relation_status='active' and l.target_domain='atlas' and l.target_kind='external_relationship'
  join atlas.external_relationships rel on rel.id::text=l.target_id
  join atlas.farms f on f.organization_id=rel.organization_id and f.organization_unit_id is not distinct from rel.organization_unit_id
  where (e.direction='incoming' and p.participant_role='sender' and not p.is_self)
     or (e.direction='outgoing' and p.participant_role in ('to','cc','bcc','participant') and not p.is_self)
  order by f.id,rel.id,e.id,role_order,p.id
) cr;
comment on view atlas.v_flower_buyer_correspondence_events_v1 is 'Unified flower-buyer correspondence evidence: documented availability outreach plus Communication Events whose participant email has an explicit active link to the External Relationship. No fuzzy identity inference occurs here.';

create or replace view atlas.v_flower_buyer_correspondence_position_v1 as
select
  f.id as farm_id,rel.organization_id,rel.organization_unit_id,rel.id as external_relationship_id,rel.subject_id,
  coalesce(proj.display_name,legacy.business_name,rel.stable_key) as relationship_label,rel.relationship_state,
  last_message.occurred_at as last_message_at,last_message.direction as last_message_direction,last_message.subject as last_message_subject,last_message.body as last_message_body,last_message.participant_address as last_message_address,
  last_outgoing.occurred_at as last_outgoing_at,last_outgoing.subject as last_outgoing_subject,last_outgoing.body as last_outgoing_body,
  last_incoming.occurred_at as last_incoming_at,last_incoming.subject as last_incoming_subject,last_incoming.body as last_incoming_body,
  case when last_interaction.occurred_at is null then last_message.occurred_at when last_message.occurred_at is null then last_interaction.occurred_at else greatest(last_interaction.occurred_at,last_message.occurred_at) end as last_contact_at,
  case when last_message.direction='outgoing' and (last_incoming.occurred_at is null or last_message.occurred_at>last_incoming.occurred_at) then true else false end as awaiting_reply,
  last_interaction.interaction_kind as last_interaction_kind,last_interaction.channel as last_interaction_channel,last_interaction.outcome as last_interaction_outcome,last_interaction.follow_up as last_follow_up
from atlas.external_relationships rel
join atlas.farms f on f.organization_id=rel.organization_id and f.organization_unit_id is not distinct from rel.organization_unit_id
left join atlas.identity_subject_projections proj on proj.subject_id=rel.subject_id
left join atlas.legacy_buyer_relationship_external_mappings lm on lm.external_relationship_id=rel.id
left join atlas.buyer_relationship_reconstruction legacy on legacy.id=lm.buyer_relationship_id
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id order by e.occurred_at desc,e.event_key desc limit 1) last_message on true
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id and e.direction='outgoing' order by e.occurred_at desc,e.event_key desc limit 1) last_outgoing on true
left join lateral (select e.* from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=f.id and e.external_relationship_id=rel.id and e.direction='incoming' order by e.occurred_at desc,e.event_key desc limit 1) last_incoming on true
left join lateral (select i.* from atlas.external_relationship_interactions i where i.external_relationship_id=rel.id order by i.occurred_at desc,i.id desc limit 1) last_interaction on true
where exists(select 1 from atlas.external_relationship_roles rr where rr.external_relationship_id=rel.id and rr.role_key='customer' and rr.role_state='active');
comment on view atlas.v_flower_buyer_correspondence_position_v1 is 'Current correspondence position for flower customer relationships. Last-contact fields are derived from append-only evidence; awaiting_reply means only that the newest linked message is outgoing.';

create or replace function atlas.flower_buyer_correspondence_position_self_v1(p_farm_id uuid) returns setof atlas.v_flower_buyer_correspondence_position_v1 language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_organization_id uuid;
begin
  select organization_id into v_organization_id from atlas.farms where id=p_farm_id;
  if v_organization_id is null then raise exception 'Farm not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_member(v_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  return query select * from atlas.v_flower_buyer_correspondence_position_v1 v where v.farm_id=p_farm_id order by v.last_contact_at desc nulls last,v.relationship_label;
end;$function$;

create or replace function atlas.flower_buyer_correspondence_history_self_v1(p_farm_id uuid,p_external_relationship_id uuid)
returns table(event_key text,occurred_at timestamptz,direction text,channel text,subject text,body text,participant_address text,source_kind text,source_id uuid,interaction_id uuid,metadata jsonb)
language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_organization_id uuid;
begin
  select organization_id into v_organization_id from atlas.farms where id=p_farm_id;
  if v_organization_id is null then raise exception 'Farm not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_member(v_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.v_flower_buyer_correspondence_position_v1 p where p.farm_id=p_farm_id and p.external_relationship_id=p_external_relationship_id) then raise exception 'Buyer relationship is outside this farm.' using errcode='42501'; end if;
  return query select e.event_key,e.occurred_at,e.direction,e.channel,e.subject,e.body,e.participant_address,e.source_kind,e.source_id,e.interaction_id,e.metadata from atlas.v_flower_buyer_correspondence_events_v1 e where e.farm_id=p_farm_id and e.external_relationship_id=p_external_relationship_id order by e.occurred_at desc,e.event_key desc;
end;$function$;

alter table atlas.communication_event_participants enable row level security;
revoke all on atlas.communication_event_participants from public,anon,authenticated;
revoke all on atlas.v_flower_buyer_correspondence_events_v1 from public,anon,authenticated;
revoke all on atlas.v_flower_buyer_correspondence_position_v1 from public,anon,authenticated;
grant select,insert on atlas.communication_event_participants to service_role;
grant select on atlas.v_flower_buyer_correspondence_events_v1 to service_role;
grant select on atlas.v_flower_buyer_correspondence_position_v1 to service_role;
revoke all on function atlas.guard_communication_event_participant_v1() from public,anon,authenticated;
revoke all on function atlas.prevent_communication_event_participant_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.record_communication_event_participants_service_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.link_communication_email_identity_to_external_relationship_service_v1(uuid,uuid,uuid,text,uuid,text,numeric,jsonb) from public,anon,authenticated;
revoke all on function atlas.flower_buyer_correspondence_position_self_v1(uuid) from public,anon;
revoke all on function atlas.flower_buyer_correspondence_history_self_v1(uuid,uuid) from public,anon;
grant execute on function atlas.record_communication_event_participants_service_v1(uuid,jsonb) to service_role;
grant execute on function atlas.link_communication_email_identity_to_external_relationship_service_v1(uuid,uuid,uuid,text,uuid,text,numeric,jsonb) to service_role;
grant execute on function atlas.flower_buyer_correspondence_position_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.flower_buyer_correspondence_history_self_v1(uuid,uuid) to authenticated,service_role;

commit;
