begin;

insert into atlas.identity_subject_external_identifiers(
  organization_id, subject_id, provider_key, identifier_type, identifier_value,
  identifier_normalized, is_current, priority, metadata, created_at, updated_at
)
select
  f.organization_id, m.identity_subject_id, null, 'email', a.alias,
  lower(btrim(a.alias)), true, greatest(1, least(9, a.priority::int + 3))::smallint,
  jsonb_build_object('source','legacy_buyer_identity_alias_backfill','buyerIdentityAliasId',a.id,'buyerRelationshipId',a.buyer_relationship_id,'farmId',a.farm_id) || coalesce(a.metadata,'{}'::jsonb),
  a.created_at, coalesce(a.updated_at,a.created_at)
from atlas.buyer_identity_aliases a
join atlas.buyer_relationship_reconstruction b on b.id=a.buyer_relationship_id and b.farm_id=a.farm_id
join atlas.farms f on f.id=a.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=a.buyer_relationship_id
where a.alias_type='email' and a.is_current and btrim(a.alias)<>''
on conflict do nothing;

create table atlas.flower_availability_outreach_rounds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  availability_snapshot_id uuid references atlas.flower_route_availability_snapshots(id) on delete restrict,
  round_key text not null,
  channel text not null default 'email',
  sender_label text,
  sender_address text,
  subject text not null,
  body_text text not null,
  body_sha256 text not null,
  sent_at timestamptz not null,
  source_kind text not null default 'manual_report',
  source_ref text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint flower_availability_outreach_rounds_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  constraint flower_availability_outreach_rounds_key_nonblank check (btrim(round_key)<>''),
  constraint flower_availability_outreach_rounds_channel_nonblank check (btrim(channel)<>''),
  constraint flower_availability_outreach_rounds_subject_nonblank check (btrim(subject)<>''),
  constraint flower_availability_outreach_rounds_hash_shape check (body_sha256 ~ '^[0-9a-f]{64}$'),
  constraint flower_availability_outreach_rounds_source_kind_check check (source_kind in ('manual_report','provider_observation','imported_record'))
);
create unique index flower_availability_outreach_rounds_farm_key_uq on atlas.flower_availability_outreach_rounds(farm_id,round_key);
create index flower_availability_outreach_rounds_farm_time_idx on atlas.flower_availability_outreach_rounds(farm_id,sent_at desc,id);

create table atlas.flower_availability_outreach_recipients (
  id uuid primary key default gen_random_uuid(),
  outreach_round_id uuid not null references atlas.flower_availability_outreach_rounds(id) on delete restrict,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  interaction_id uuid not null references atlas.external_relationship_interactions(id) on delete restrict,
  recipient_address text not null,
  recipient_address_normalized text not null,
  recipient_role text not null default 'to' check (recipient_role in ('to','cc','bcc')),
  source_label text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint flower_availability_outreach_recipient_address_nonblank check (btrim(recipient_address)<>''),
  constraint flower_availability_outreach_recipient_normalized_nonblank check (btrim(recipient_address_normalized)<>''),
  unique(outreach_round_id,recipient_address_normalized)
);
create index flower_availability_outreach_recipients_relationship_idx on atlas.flower_availability_outreach_recipients(external_relationship_id,outreach_round_id);
create unique index flower_availability_outreach_recipients_interaction_uq on atlas.flower_availability_outreach_recipients(interaction_id);

comment on table atlas.flower_availability_outreach_rounds is 'Flower-specific availability outreach record. One row preserves the exact availability email offered in one round; it is not Demand, Sale, reservation, or fulfillment truth.';
comment on table atlas.flower_availability_outreach_recipients is 'Per-recipient participation in one flower availability outreach round, linked to the organization-owned External Relationship and its append-only interaction history.';

create or replace function atlas.guard_flower_availability_outreach_scope_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_round atlas.flower_availability_outreach_rounds%rowtype; v_farm atlas.farms%rowtype; v_relationship atlas.external_relationships%rowtype;
begin
  if tg_table_name='flower_availability_outreach_rounds' then
    select * into v_farm from atlas.farms where id=new.farm_id;
    if v_farm.id is null or v_farm.organization_id is distinct from new.organization_id or v_farm.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Availability outreach round must use the farm organization/unit.' using errcode='23514'; end if;
    if new.availability_snapshot_id is not null and not exists(select 1 from atlas.flower_route_availability_snapshots s where s.id=new.availability_snapshot_id and s.farm_id=new.farm_id) then raise exception 'Availability snapshot must belong to the same farm.' using errcode='23514'; end if;
    new.round_key:=btrim(new.round_key); new.channel:=lower(btrim(new.channel)); new.sender_label:=nullif(btrim(new.sender_label),''); new.sender_address:=nullif(lower(btrim(new.sender_address)),''); new.subject:=btrim(new.subject); new.source_kind:=lower(btrim(new.source_kind)); new.source_ref:=nullif(btrim(new.source_ref),''); return new;
  end if;
  select * into v_round from atlas.flower_availability_outreach_rounds where id=new.outreach_round_id;
  if v_round.id is null then raise exception 'Availability outreach recipient requires an existing round.' using errcode='23514'; end if;
  select * into v_relationship from atlas.external_relationships where id=new.external_relationship_id;
  if v_relationship.id is null or v_relationship.organization_id is distinct from v_round.organization_id or v_relationship.organization_unit_id is distinct from v_round.organization_unit_id or v_relationship.subject_id is distinct from new.identity_subject_id then raise exception 'Availability outreach recipient relationship is outside the round scope.' using errcode='23514'; end if;
  if not exists(select 1 from atlas.external_relationship_interactions i where i.id=new.interaction_id and i.organization_id=v_round.organization_id and i.external_relationship_id=new.external_relationship_id) then raise exception 'Availability outreach recipient interaction must belong to the same relationship.' using errcode='23514'; end if;
  new.recipient_address:=btrim(new.recipient_address); new.recipient_address_normalized:=lower(btrim(new.recipient_address_normalized)); new.recipient_role:=lower(btrim(new.recipient_role)); new.source_label:=nullif(btrim(new.source_label),''); return new;
end;$function$;
create trigger flower_availability_outreach_round_scope_guard_v1 before insert or update on atlas.flower_availability_outreach_rounds for each row execute function atlas.guard_flower_availability_outreach_scope_v1();
create trigger flower_availability_outreach_recipient_scope_guard_v1 before insert or update on atlas.flower_availability_outreach_recipients for each row execute function atlas.guard_flower_availability_outreach_scope_v1();

create or replace function atlas.prevent_flower_availability_outreach_mutation_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$ begin raise exception 'Availability outreach history is append-only; record a later round or evidence event instead.' using errcode='55000'; end;$function$;
create trigger flower_availability_outreach_round_append_only_v1 before update or delete on atlas.flower_availability_outreach_rounds for each row execute function atlas.prevent_flower_availability_outreach_mutation_v1();
create trigger flower_availability_outreach_recipient_append_only_v1 before update or delete on atlas.flower_availability_outreach_recipients for each row execute function atlas.prevent_flower_availability_outreach_mutation_v1();

create or replace function atlas.record_flower_availability_outreach_service_v1(p_farm_id uuid,p_round_key text,p_sent_at timestamptz,p_subject text,p_body text,p_recipients jsonb,p_availability_snapshot_id uuid default null,p_sender_label text default null,p_sender_address text default null,p_source_kind text default 'manual_report',p_source_ref text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare v_farm atlas.farms%rowtype; v_round_id uuid; v_existing_hash text; v_body_hash text; v_recipient jsonb; v_email text; v_display_name text; v_source_label text; v_role text; v_relationship_id uuid; v_subject_id uuid; v_buyer_relationship_id uuid; v_local_intel_entity_id uuid; v_candidates uuid[]; v_interaction_id uuid; v_recipient_count integer:=0; v_stable_key text;
begin
  select * into v_farm from atlas.farms where id=p_farm_id; if v_farm.id is null or v_farm.organization_id is null then raise exception 'Farm with organization scope is required.' using errcode='P0002'; end if;
  if btrim(coalesce(p_round_key,''))='' or btrim(coalesce(p_subject,''))='' then raise exception 'Round key and subject are required.' using errcode='22023'; end if; if p_body is null then raise exception 'Exact email body is required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_recipients,'[]'::jsonb))<>'array' then raise exception 'Recipients must be a JSON array.' using errcode='22023'; end if; if jsonb_array_length(coalesce(p_recipients,'[]'::jsonb))=0 then raise exception 'At least one recipient is required.' using errcode='22023'; end if; if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;
  if p_availability_snapshot_id is not null and not exists(select 1 from atlas.flower_route_availability_snapshots s where s.id=p_availability_snapshot_id and s.farm_id=p_farm_id) then raise exception 'Availability snapshot is outside this farm.' using errcode='23514'; end if;
  v_body_hash:=encode(extensions.digest(convert_to(p_body,'UTF8'),'sha256'),'hex');
  select id,body_sha256 into v_round_id,v_existing_hash from atlas.flower_availability_outreach_rounds where farm_id=p_farm_id and round_key=btrim(p_round_key);
  if v_round_id is not null then if v_existing_hash is distinct from v_body_hash then raise exception 'Round key already exists with different email content.' using errcode='23505'; end if; return jsonb_build_object('outreachRoundId',v_round_id,'created',false,'recipientCount',(select count(*) from atlas.flower_availability_outreach_recipients r where r.outreach_round_id=v_round_id)); end if;
  insert into atlas.flower_availability_outreach_rounds(organization_id,organization_unit_id,farm_id,availability_snapshot_id,round_key,channel,sender_label,sender_address,subject,body_text,body_sha256,sent_at,source_kind,source_ref,metadata) values(v_farm.organization_id,v_farm.organization_unit_id,v_farm.id,p_availability_snapshot_id,btrim(p_round_key),'email',nullif(btrim(p_sender_label),''),nullif(lower(btrim(p_sender_address)),''),btrim(p_subject),p_body,v_body_hash,p_sent_at,lower(btrim(coalesce(nullif(p_source_kind,''),'manual_report'))),nullif(btrim(p_source_ref),''),coalesce(p_metadata,'{}'::jsonb)) returning id into v_round_id;
  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_email:=lower(btrim(coalesce(v_recipient->>'email',''))); if v_email='' then raise exception 'Every availability outreach recipient requires an email address.' using errcode='22023'; end if; v_display_name:=nullif(btrim(v_recipient->>'displayName'),''); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),''); v_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'to')); if v_role not in ('to','cc','bcc') then raise exception 'recipientRole must be to, cc, or bcc.' using errcode='22023'; end if;
    v_relationship_id:=null; v_subject_id:=null; v_buyer_relationship_id:=null; v_local_intel_entity_id:=null; v_candidates:=null;
    begin v_relationship_id:=nullif(btrim(v_recipient->>'externalRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid externalRelationshipId for recipient %.',v_email using errcode='22023'; end;
    if v_relationship_id is null then begin v_buyer_relationship_id:=nullif(btrim(v_recipient->>'buyerRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid buyerRelationshipId for recipient %.',v_email using errcode='22023'; end; if v_buyer_relationship_id is not null then select m.external_relationship_id,m.identity_subject_id into v_relationship_id,v_subject_id from atlas.legacy_buyer_relationship_external_mappings m join atlas.buyer_relationship_reconstruction b on b.id=m.buyer_relationship_id where m.buyer_relationship_id=v_buyer_relationship_id and b.farm_id=p_farm_id; end if; end if;
    if v_relationship_id is null then begin v_local_intel_entity_id:=nullif(btrim(v_recipient->>'localIntelEntityId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid localIntelEntityId for recipient %.',v_email using errcode='22023'; end; if v_local_intel_entity_id is not null then select m.external_relationship_id,m.identity_subject_id into v_relationship_id,v_subject_id from atlas.buyer_relationship_reconstruction b join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.id where b.farm_id=p_farm_id and b.entity_id=v_local_intel_entity_id order by b.created_at limit 1; if v_relationship_id is null then select array_agg(distinct r.id) into v_candidates from atlas.identity_subject_external_identifiers i join atlas.external_relationships r on r.subject_id=i.subject_id where i.organization_id=v_farm.organization_id and i.provider_key='local_intel' and i.identifier_type='entity_id' and i.identifier_normalized=v_local_intel_entity_id::text and i.is_current and r.organization_unit_id is not distinct from v_farm.organization_unit_id and r.relationship_state in ('prospective','active','unknown'); if coalesce(array_length(v_candidates,1),0)=1 then v_relationship_id:=v_candidates[1]; elsif coalesce(array_length(v_candidates,1),0)>1 then raise exception 'Local Intel entity is ambiguously linked to multiple relationships.' using errcode='23505'; end if; end if; end if; end if;
    if v_relationship_id is null then select array_agg(distinct r.id) into v_candidates from atlas.identity_subject_external_identifiers i join atlas.external_relationships r on r.subject_id=i.subject_id where i.organization_id=v_farm.organization_id and i.identifier_type='email' and i.identifier_normalized=v_email and i.is_current and r.organization_unit_id is not distinct from v_farm.organization_unit_id and r.relationship_state in ('prospective','active','unknown'); if coalesce(array_length(v_candidates,1),0)=1 then v_relationship_id:=v_candidates[1]; elsif coalesce(array_length(v_candidates,1),0)>1 then raise exception 'Email % is ambiguously linked to multiple relationships.',v_email using errcode='23505'; end if; end if;
    if v_relationship_id is not null then select subject_id into v_subject_id from atlas.external_relationships where id=v_relationship_id and organization_id=v_farm.organization_id and organization_unit_id is not distinct from v_farm.organization_unit_id and relationship_state in ('prospective','active','unknown'); if v_subject_id is null then raise exception 'Recipient relationship is outside the farm organization/unit.' using errcode='23514'; end if; else insert into atlas.identity_subjects(organization_id,state,creation_basis) values(v_farm.organization_id,'active',jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id,'roundKey',btrim(p_round_key),'email',v_email,'localIntelEntityId',v_local_intel_entity_id,'sourceLabel',v_source_label)) returning id into v_subject_id; insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis) values(v_subject_id,v_farm.organization_id,'organization',v_display_name,'[]'::jsonb,jsonb_build_array(jsonb_build_object('type','email','value',v_email)),v_display_name is null,case when v_display_name is null then null else 0.8 end,jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id,'roundKey',btrim(p_round_key))); v_stable_key:='flower-prospect-email:'||substr(encode(extensions.digest(convert_to(v_email,'UTF8'),'sha256'),'hex'),1,32); insert into atlas.external_relationships(organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata) values(v_farm.organization_id,v_farm.organization_unit_id,v_subject_id,v_stable_key,'prospective',jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id,'roundKey',btrim(p_round_key),'sourceLabel',v_source_label)) returning id into v_relationship_id; insert into atlas.external_relationship_roles(external_relationship_id,role_key,role_state,basis) values(v_relationship_id,'customer','active',jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id)); end if;
    insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata) values(v_farm.organization_id,v_subject_id,null,'email',v_email,v_email,true,7,jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id,'roundKey',btrim(p_round_key),'sourceLabel',v_source_label)) on conflict do nothing;
    if v_display_name is not null then insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata) values(v_farm.organization_id,v_subject_id,null,'display_name',v_display_name,lower(v_display_name),true,4,jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id)) on conflict do nothing; update atlas.identity_subject_projections set display_name=coalesce(display_name,v_display_name),projection_basis=projection_basis||jsonb_build_object('availabilityOutreachRoundId',v_round_id) where subject_id=v_subject_id; end if;
    if v_local_intel_entity_id is not null then insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata) values(v_farm.organization_id,v_subject_id,'local_intel','entity_id',v_local_intel_entity_id::text,v_local_intel_entity_id::text,true,9,jsonb_build_object('source','flower_availability_outreach','farmId',v_farm.id,'roundKey',btrim(p_round_key))) on conflict do nothing; end if;
    insert into atlas.external_relationship_interactions(organization_id,organization_unit_id,external_relationship_id,occurred_at,interaction_kind,channel,outcome,contact_label,follow_up,note,metadata) values(v_farm.organization_id,v_farm.organization_unit_id,v_relationship_id,p_sent_at,'availability_offer_sent','email','sent',coalesce(v_display_name,v_email),null,btrim(p_subject),jsonb_build_object('direction','outgoing','flowerAvailabilityOutreachRoundId',v_round_id,'availabilitySnapshotId',p_availability_snapshot_id,'recipientAddress',v_email,'bodySha256',v_body_hash,'sourceLabel',v_source_label)||coalesce(v_recipient->'metadata','{}'::jsonb)) returning id into v_interaction_id;
    insert into atlas.flower_availability_outreach_recipients(outreach_round_id,external_relationship_id,identity_subject_id,interaction_id,recipient_address,recipient_address_normalized,recipient_role,source_label,metadata) values(v_round_id,v_relationship_id,v_subject_id,v_interaction_id,v_email,v_email,v_role,v_source_label,coalesce(v_recipient->'metadata','{}'::jsonb)||jsonb_build_object('buyerRelationshipId',v_buyer_relationship_id,'localIntelEntityId',v_local_intel_entity_id));
    v_recipient_count:=v_recipient_count+1;
  end loop;
  return jsonb_build_object('outreachRoundId',v_round_id,'created',true,'recipientCount',v_recipient_count,'bodySha256',v_body_hash);
end;$function$;

alter table atlas.flower_availability_outreach_rounds enable row level security;
alter table atlas.flower_availability_outreach_recipients enable row level security;
revoke all on atlas.flower_availability_outreach_rounds from public,anon,authenticated;
revoke all on atlas.flower_availability_outreach_recipients from public,anon,authenticated;
grant select,insert on atlas.flower_availability_outreach_rounds to service_role;
grant select,insert on atlas.flower_availability_outreach_recipients to service_role;
revoke all on function atlas.guard_flower_availability_outreach_scope_v1() from public,anon,authenticated;
revoke all on function atlas.prevent_flower_availability_outreach_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) to service_role;

commit;
