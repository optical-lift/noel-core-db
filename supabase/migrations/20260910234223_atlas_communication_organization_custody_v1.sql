begin;

alter table atlas.communication_threads
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_threads alter column principal_id drop not null;
alter table atlas.communication_threads
  add constraint communication_threads_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_threads_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_ingest_batches
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_ingest_batches alter column principal_id drop not null;
alter table atlas.communication_ingest_batches
  add constraint communication_ingest_batches_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_ingest_batches_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_events
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_events alter column principal_id drop not null;
alter table atlas.communication_events drop constraint communication_events_thread_id_connected_source_id_princip_fkey;
alter table atlas.communication_events
  add constraint communication_events_thread_id_fkey foreign key (thread_id) references atlas.communication_threads(id) on delete restrict,
  add constraint communication_events_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_events_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_event_conflicts
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_event_conflicts alter column principal_id drop not null;
alter table atlas.communication_event_conflicts
  add constraint communication_event_conflicts_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_event_conflicts_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_event_source_observations
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_event_source_observations alter column principal_id drop not null;
alter table atlas.communication_event_source_observations
  add constraint communication_event_source_observations_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_event_source_observations_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_attachments
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_attachments alter column principal_id drop not null;
alter table atlas.communication_attachments
  add constraint communication_attachments_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_attachments_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_event_participants
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid,
  add column address_kind text not null default 'unknown' check (address_kind in ('email','phone','provider_identity','unknown'));
alter table atlas.communication_event_participants alter column principal_id drop not null;
alter table atlas.communication_event_participants
  add constraint communication_event_participants_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_event_participants_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

alter table atlas.communication_identity_links
  add column organization_id uuid references atlas.organizations(id) on delete cascade,
  add column organization_unit_id uuid;
alter table atlas.communication_identity_links alter column principal_id drop not null;
alter table atlas.communication_identity_links
  add constraint communication_identity_links_custody_root_check check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  add constraint communication_identity_links_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict;

create index communication_threads_org_time_idx on atlas.communication_threads(organization_id,organization_unit_id,last_event_at desc,id) where organization_id is not null;
create index communication_events_org_time_idx on atlas.communication_events(organization_id,organization_unit_id,occurred_at desc,id) where organization_id is not null;
create index communication_batches_org_time_idx on atlas.communication_ingest_batches(organization_id,organization_unit_id,created_at desc,id) where organization_id is not null;
create index communication_participants_kind_identity_idx on atlas.communication_event_participants(connected_source_id,address_kind,address_normalized,communication_event_id);
create index communication_identity_links_org_target_idx on atlas.communication_identity_links(organization_id,organization_unit_id,target_domain,target_kind,target_id) where organization_id is not null and relation_status='active';

create or replace function atlas.guard_communication_source_principal_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_row jsonb:=to_jsonb(new);
  v_principal_id uuid:=nullif(v_row->>'principal_id','')::uuid;
  v_organization_id uuid:=nullif(v_row->>'organization_id','')::uuid;
  v_organization_unit_id uuid:=nullif(v_row->>'organization_unit_id','')::uuid;
  v_source atlas.connected_sources%rowtype;
  v_principal_user_id uuid;
begin
  select * into v_source from atlas.connected_sources where id=new.connected_source_id and authorization_state<>'revoked';
  if v_source.id is null then raise exception 'Communication source is missing or revoked.' using errcode='42501'; end if;

  if v_source.custodian_user_id is not null then
    if v_principal_id is null or v_organization_id is not null then raise exception 'Person-owned communication source requires Principal custody only.' using errcode='42501'; end if;
    select p.user_id into v_principal_user_id from atlas.principals p where p.id=v_principal_id and p.status='active';
    if v_principal_user_id is null or v_principal_user_id is distinct from v_source.custodian_user_id then raise exception 'Communication source is outside the Principal custody root.' using errcode='42501'; end if;
  else
    if v_organization_id is null or v_principal_id is not null then raise exception 'Organization-owned communication source requires Organization custody only.' using errcode='42501'; end if;
    if v_organization_id is distinct from v_source.custodian_organization_id or v_organization_unit_id is distinct from v_source.custodian_organization_unit_id then raise exception 'Communication source is outside the Organization/source unit custody root.' using errcode='42501'; end if;
  end if;
  return new;
end;$function$;

create or replace function atlas.guard_communication_event_participant_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_event atlas.communication_events%rowtype;
begin
  select * into v_event from atlas.communication_events where id=new.communication_event_id;
  if v_event.id is null
     or v_event.principal_id is distinct from new.principal_id
     or v_event.organization_id is distinct from new.organization_id
     or v_event.organization_unit_id is distinct from new.organization_unit_id
     or v_event.connected_source_id is distinct from new.connected_source_id then
    raise exception 'Communication participant must share its event custody/source.' using errcode='23514';
  end if;
  new.participant_role:=lower(btrim(new.participant_role));
  new.address_kind:=lower(btrim(coalesce(nullif(new.address_kind,''),'unknown')));
  new.address:=btrim(new.address);
  new.address_normalized:=case when new.address_kind in ('email','phone') then atlas.normalize_external_party_identifier_v1(new.address_kind,new.address) else btrim(new.address_normalized) end;
  return new;
end;$function$;

create or replace function atlas.guard_communication_event_source_observation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_event atlas.communication_events%rowtype;
begin
  select * into v_event from atlas.communication_events where id=new.event_id;
  if v_event.id is null
     or v_event.principal_id is distinct from new.principal_id
     or v_event.organization_id is distinct from new.organization_id
     or v_event.organization_unit_id is distinct from new.organization_unit_id
     or v_event.connected_source_id is distinct from new.connected_source_id
     or v_event.source_event_ref is distinct from new.source_event_ref then
    raise exception 'Communication source observation does not match its parent event.' using errcode='42501';
  end if;
  return new;
end;$function$;

create or replace function atlas.communication_identity_links_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_principal_user_id uuid;
  v_thread atlas.communication_threads%rowtype;
  v_relationship atlas.external_relationships%rowtype;
begin
  select * into v_source from atlas.connected_sources where id=new.connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Communication identity source is not connected.' using errcode='23514'; end if;

  if v_source.custodian_user_id is not null then
    if new.principal_id is null or new.organization_id is not null then raise exception 'Person-owned identity links require Principal custody.' using errcode='23514'; end if;
    select user_id into v_principal_user_id from atlas.principals where id=new.principal_id and status='active';
    if v_principal_user_id is null or v_principal_user_id is distinct from v_source.custodian_user_id then raise exception 'Communication identity source is not owned by the Principal.' using errcode='23514'; end if;
  else
    if new.principal_id is not null or new.organization_id is distinct from v_source.custodian_organization_id or new.organization_unit_id is distinct from v_source.custodian_organization_unit_id then raise exception 'Organization communication identity link is outside source custody.' using errcode='23514'; end if;
  end if;

  if new.thread_id is not null then
    select * into v_thread from atlas.communication_threads where id=new.thread_id;
    if v_thread.id is null or v_thread.connected_source_id is distinct from new.connected_source_id or v_thread.principal_id is distinct from new.principal_id or v_thread.organization_id is distinct from new.organization_id or v_thread.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Communication identity thread is outside source custody.' using errcode='23514'; end if;
  end if;

  new.source_identity_kind:=lower(btrim(new.source_identity_kind));
  new.source_identity_key:=case when new.source_identity_kind in ('email','phone') then atlas.normalize_external_party_identifier_v1(new.source_identity_kind,new.source_identity_key) else btrim(new.source_identity_key) end;
  new.target_domain:=lower(btrim(new.target_domain));
  new.target_kind:=lower(btrim(new.target_kind));
  new.target_id:=btrim(new.target_id);
  new.target_label:=nullif(btrim(new.target_label),'');
  new.relation_basis:=lower(btrim(new.relation_basis));

  if new.target_domain='atlas' and new.target_kind='external_relationship' then
    begin select * into v_relationship from atlas.external_relationships where id=new.target_id::uuid; exception when invalid_text_representation then raise exception 'External relationship target id is invalid.' using errcode='23514'; end;
    if v_relationship.id is null then raise exception 'External relationship target does not exist.' using errcode='23514'; end if;
    if v_source.custodian_organization_id is not null then
      if v_relationship.organization_id is distinct from v_source.custodian_organization_id or v_relationship.organization_unit_id is distinct from v_source.custodian_organization_unit_id then raise exception 'Organization communication source may only link to relationships in its own source scope.' using errcode='23514'; end if;
    else
      if not exists(select 1 from atlas.organization_memberships om where om.organization_id=v_relationship.organization_id and om.user_id=v_principal_user_id and om.active) then raise exception 'Principal is not a member of the target relationship organization.' using errcode='42501'; end if;
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;$function$;

create or replace function atlas.guard_communication_attachment_parent_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_event atlas.communication_events%rowtype;
begin
  select * into v_event from atlas.communication_events where id=new.event_id;
  if v_event.id is null or v_event.principal_id is distinct from new.principal_id or v_event.organization_id is distinct from new.organization_id or v_event.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Communication attachment must share parent event custody.' using errcode='23514'; end if;
  return new;
end;$function$;
drop trigger if exists communication_attachments_parent_guard_v1 on atlas.communication_attachments;
create trigger communication_attachments_parent_guard_v1 before insert on atlas.communication_attachments for each row execute function atlas.guard_communication_attachment_parent_v1();
drop trigger if exists communication_attachments_append_only_v1 on atlas.communication_attachments;
create trigger communication_attachments_append_only_v1 before update or delete on atlas.communication_attachments for each row execute function atlas.reject_communication_event_mutation_v1();

create or replace function atlas.record_communication_event_participants_service_v1(p_communication_event_id uuid,p_participants jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_event atlas.communication_events%rowtype; v_participant jsonb; v_role text; v_address text; v_kind text; v_normalized text; v_count integer:=0;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if jsonb_typeof(coalesce(p_participants,'[]'::jsonb))<>'array' then raise exception 'Participants must be a JSON array.' using errcode='22023'; end if;
  for v_participant in select value from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
    v_role:=lower(coalesce(nullif(btrim(v_participant->>'role'),''),'participant'));
    if v_role not in ('sender','to','cc','bcc','participant','other') then raise exception 'Unsupported communication participant role.' using errcode='22023'; end if;
    v_address:=nullif(btrim(v_participant->>'address'),'');
    if v_address is null then raise exception 'Every communication participant requires an address.' using errcode='22023'; end if;
    v_kind:=lower(coalesce(nullif(btrim(v_participant->>'addressKind'),''),case when position('@' in v_address)>1 then 'email' when length(regexp_replace(v_address,'[^0-9]','','g'))>=7 then 'phone' else 'provider_identity' end));
    if v_kind not in ('email','phone','provider_identity','unknown') then raise exception 'Unsupported communication participant address kind.' using errcode='22023'; end if;
    v_normalized:=case when v_kind in ('email','phone') then atlas.normalize_external_party_identifier_v1(v_kind,v_address) else btrim(v_address) end;
    insert into atlas.communication_event_participants(communication_event_id,principal_id,organization_id,organization_unit_id,connected_source_id,participant_role,address_kind,address,address_normalized,is_self,metadata)
    values(v_event.id,v_event.principal_id,v_event.organization_id,v_event.organization_unit_id,v_event.connected_source_id,v_role,v_kind,v_address,v_normalized,coalesce((v_participant->>'isSelf')::boolean,false),coalesce(v_participant->'metadata','{}'::jsonb))
    on conflict (communication_event_id,participant_role,address_normalized) do nothing;
    if found then v_count:=v_count+1; end if;
  end loop;
  return jsonb_build_object('communicationEventId',v_event.id,'participantsInserted',v_count);
end;$function$;

insert into atlas.communication_event_participants(communication_event_id,principal_id,organization_id,organization_unit_id,connected_source_id,participant_role,address_kind,address,address_normalized,is_self,metadata)
select e.id,e.principal_id,e.organization_id,e.organization_unit_id,e.connected_source_id,'sender',
  case when position('@' in e.speaker_address)>1 then 'email' when length(regexp_replace(e.speaker_address,'[^0-9]','','g'))>=7 then 'phone' else 'provider_identity' end,
  e.speaker_address,
  case when position('@' in e.speaker_address)>1 then atlas.normalize_external_party_identifier_v1('email',e.speaker_address) when length(regexp_replace(e.speaker_address,'[^0-9]','','g'))>=7 then atlas.normalize_external_party_identifier_v1('phone',e.speaker_address) else btrim(e.speaker_address) end,
  e.speaker_is_self,jsonb_build_object('backfill','speaker_address')
from atlas.communication_events e
where nullif(btrim(e.speaker_address),'') is not null
on conflict (communication_event_id,participant_role,address_normalized) do nothing;

insert into atlas.communication_event_participants(communication_event_id,principal_id,organization_id,organization_unit_id,connected_source_id,participant_role,address_kind,address,address_normalized,is_self,metadata)
select e.id,e.principal_id,e.organization_id,e.organization_unit_id,e.connected_source_id,
  case when e.direction='incoming' and not e.speaker_is_self and e.speaker_address is not null and
    (case when position('@' in addr)>1 then atlas.normalize_external_party_identifier_v1('email',addr) when length(regexp_replace(addr,'[^0-9]','','g'))>=7 then atlas.normalize_external_party_identifier_v1('phone',addr) else btrim(addr) end)=
    (case when position('@' in e.speaker_address)>1 then atlas.normalize_external_party_identifier_v1('email',e.speaker_address) when length(regexp_replace(e.speaker_address,'[^0-9]','','g'))>=7 then atlas.normalize_external_party_identifier_v1('phone',e.speaker_address) else btrim(e.speaker_address) end)
    then 'sender' else 'participant' end,
  case when position('@' in addr)>1 then 'email' when length(regexp_replace(addr,'[^0-9]','','g'))>=7 then 'phone' else 'provider_identity' end,
  addr,
  case when position('@' in addr)>1 then atlas.normalize_external_party_identifier_v1('email',addr) when length(regexp_replace(addr,'[^0-9]','','g'))>=7 then atlas.normalize_external_party_identifier_v1('phone',addr) else btrim(addr) end,
  false,jsonb_build_object('backfill','sourcePayload.participantAddresses')
from atlas.communication_events e
cross join lateral regexp_split_to_table(coalesce(e.canonical_event#>>'{sourcePayload,participantAddresses}',''),'[;,]') raw(addr0)
cross join lateral (select nullif(btrim(raw.addr0),'') addr) a
where addr is not null
on conflict (communication_event_id,participant_role,address_normalized) do nothing;

comment on table atlas.communication_events is 'Immutable source-observed communication event. Custody is exactly one Principal/person-owned Connected Source or one Organization-owned Connected Source; raw communication remains evidence and does not mutate business truth.';
comment on column atlas.communication_event_participants.address_kind is 'Provider-neutral identity coordinate kind used by downstream relationship reconciliation; participant evidence remains source evidence.';

commit;
