begin;

create or replace function atlas.normalize_communication_endpoint_address_v1(p_kind text,p_address text)
returns text language plpgsql immutable set search_path=pg_catalog,atlas as $function$
declare v_kind text:=lower(btrim(coalesce(p_kind,''))); v_address text:=btrim(coalesce(p_address,''));
begin
  if v_address='' then return ''; end if;
  if v_kind='email' then return atlas.normalize_external_party_identifier_v1('email',v_address); end if;
  if v_kind='phone' then return atlas.normalize_external_party_identifier_v1('phone',v_address); end if;
  return lower(v_address);
end;$function$;

create table atlas.communication_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  endpoint_kind text not null check (endpoint_kind in ('email','phone','sms','voice','web_form','social','atlas_native','other')),
  address text not null check (btrim(address)<>''),
  address_normalized text not null check (btrim(address_normalized)<>''),
  display_name text,
  endpoint_state text not null default 'active' check (endpoint_state in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict
);
create unique index communication_endpoints_org_root_identity_uq on atlas.communication_endpoints(organization_id,endpoint_kind,address_normalized) where organization_unit_id is null;
create unique index communication_endpoints_org_unit_identity_uq on atlas.communication_endpoints(organization_id,organization_unit_id,endpoint_kind,address_normalized) where organization_unit_id is not null;
create index communication_endpoints_org_state_idx on atlas.communication_endpoints(organization_id,organization_unit_id,endpoint_state,endpoint_kind);
comment on table atlas.communication_endpoints is 'Institution-owned communication identities such as hello@example.com. Endpoint identity is durable above any provider/transport account and does not belong to a human merely because that human can read or send through it.';

create or replace function atlas.guard_communication_endpoint_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  new.endpoint_kind:=lower(btrim(new.endpoint_kind));
  new.address:=btrim(new.address);
  new.address_normalized:=atlas.normalize_communication_endpoint_address_v1(new.endpoint_kind,new.address);
  new.display_name:=nullif(btrim(new.display_name),'');
  new.updated_at:=now();
  return new;
end;$function$;
create trigger communication_endpoint_guard_v1 before insert or update on atlas.communication_endpoints for each row execute function atlas.guard_communication_endpoint_v1();

create table atlas.communication_endpoint_source_bindings (
  id uuid primary key default gen_random_uuid(),
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  binding_role text not null default 'send_receive' check (binding_role in ('receive','send','send_receive')),
  binding_state text not null default 'active' check (binding_state in ('active','inactive')),
  transport_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(transport_metadata)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at is null or binding_state='inactive')
);
create unique index communication_endpoint_source_binding_active_uq on atlas.communication_endpoint_source_bindings(communication_endpoint_id,connected_source_id) where binding_state='active';
create index communication_endpoint_source_binding_source_idx on atlas.communication_endpoint_source_bindings(connected_source_id,binding_state,communication_endpoint_id);
comment on table atlas.communication_endpoint_source_bindings is 'Current/history binding between a durable institutional Communication Endpoint and a provider Connected Source. Moving an address to a new provider changes this binding, not the endpoint identity or conversation history.';

create or replace function atlas.guard_communication_endpoint_source_binding_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_source atlas.connected_sources%rowtype;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;
  if v_endpoint.id is null or v_source.id is null then raise exception 'Communication endpoint and connected source are required.' using errcode='23514'; end if;
  if v_source.custodian_organization_id is null then raise exception 'Institutional endpoint transport must be organization-owned.' using errcode='23514'; end if;
  if v_source.custodian_organization_id is distinct from v_endpoint.organization_id or v_source.custodian_organization_unit_id is distinct from v_endpoint.organization_unit_id then raise exception 'Communication endpoint and transport source must share organization/unit custody.' using errcode='23514'; end if;
  new.updated_at:=now();
  return new;
end;$function$;
create trigger communication_endpoint_source_binding_guard_v1 before insert or update on atlas.communication_endpoint_source_bindings for each row execute function atlas.guard_communication_endpoint_source_binding_v1();

create table atlas.communication_endpoint_member_grants (
  id uuid primary key default gen_random_uuid(),
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  membership_id uuid not null references atlas.organization_memberships(id) on delete cascade,
  capability text not null check (capability in ('view','send','claim','handoff','close','admin')),
  grant_state text not null default 'active' check (grant_state in ('active','revoked')),
  granted_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (revoked_at is null or grant_state='revoked')
);
create unique index communication_endpoint_member_grant_active_uq on atlas.communication_endpoint_member_grants(communication_endpoint_id,membership_id,capability) where grant_state='active';
create index communication_endpoint_member_grant_member_idx on atlas.communication_endpoint_member_grants(membership_id,grant_state,communication_endpoint_id);
comment on table atlas.communication_endpoint_member_grants is 'Endpoint-scoped authority for organization members. Visibility, sending, claiming, handoff, close, and administration are separate capabilities; none transfers ownership of the endpoint to the member.';

create or replace function atlas.guard_communication_endpoint_member_grant_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_grantor atlas.organization_memberships%rowtype;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_member from atlas.organization_memberships where id=new.membership_id;
  if v_endpoint.id is null or v_member.id is null or v_member.organization_id is distinct from v_endpoint.organization_id then raise exception 'Endpoint grant membership must belong to the endpoint organization.' using errcode='23514'; end if;
  if new.grant_state='active' and not v_member.active then raise exception 'Endpoint capability cannot be actively granted to an inactive membership.' using errcode='23514'; end if;
  if new.granted_by_membership_id is not null then
    select * into v_grantor from atlas.organization_memberships where id=new.granted_by_membership_id;
    if v_grantor.id is null or v_grantor.organization_id is distinct from v_endpoint.organization_id then raise exception 'Granting membership must belong to the endpoint organization.' using errcode='23514'; end if;
  end if;
  new.updated_at:=now();
  return new;
end;$function$;
create trigger communication_endpoint_member_grant_guard_v1 before insert or update on atlas.communication_endpoint_member_grants for each row execute function atlas.guard_communication_endpoint_member_grant_v1();

create or replace function atlas.communication_endpoint_authorized_self_v1(p_endpoint_id uuid,p_capability text)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas,auth as $function$
  select exists(
    select 1 from atlas.communication_endpoints ep
    join atlas.organization_memberships om on om.organization_id=ep.organization_id and om.user_id=auth.uid() and om.active
    where ep.id=p_endpoint_id and ep.endpoint_state='active'
      and (om.role='owner' or exists(select 1 from atlas.communication_endpoint_member_grants g where g.communication_endpoint_id=ep.id and g.membership_id=om.id and g.capability in (lower(btrim(coalesce(p_capability,''))),'admin') and g.grant_state='active'))
  );
$function$;

create or replace function atlas.upsert_communication_endpoint_self_api_v1(p_organization_id uuid,p_organization_unit_id uuid,p_endpoint_kind text,p_address text,p_display_name text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_member atlas.organization_memberships%rowtype; v_endpoint atlas.communication_endpoints%rowtype; v_kind text:=lower(btrim(coalesce(p_endpoint_kind,''))); v_address text:=btrim(coalesce(p_address,'')); v_norm text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=p_organization_id and user_id=auth.uid() and active and role='owner' order by created_at limit 1;
  if v_member.id is null then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units u where u.organization_id=p_organization_id and u.id=p_organization_unit_id) then raise exception 'Organization unit is outside organization.' using errcode='23514'; end if;
  if v_kind not in ('email','phone','sms','voice','web_form','social','atlas_native','other') or v_address='' then raise exception 'Valid endpoint kind and address are required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Endpoint metadata must be an object.' using errcode='22023'; end if;
  v_norm:=atlas.normalize_communication_endpoint_address_v1(v_kind,v_address);
  select * into v_endpoint from atlas.communication_endpoints ep where ep.organization_id=p_organization_id and ep.organization_unit_id is not distinct from p_organization_unit_id and ep.endpoint_kind=v_kind and ep.address_normalized=v_norm for update;
  if v_endpoint.id is null then
    insert into atlas.communication_endpoints(organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,metadata)
    values(p_organization_id,p_organization_unit_id,v_kind,v_address,v_norm,nullif(btrim(p_display_name),''),coalesce(p_metadata,'{}'::jsonb)) returning * into v_endpoint;
  else
    update atlas.communication_endpoints set display_name=coalesce(nullif(btrim(p_display_name),''),display_name),metadata=metadata||coalesce(p_metadata,'{}'::jsonb),endpoint_state='active',updated_at=now() where id=v_endpoint.id returning * into v_endpoint;
  end if;
  return jsonb_build_object('contractVersion','communication_endpoint_v1','communicationEndpointId',v_endpoint.id,'organizationId',v_endpoint.organization_id,'organizationUnitId',v_endpoint.organization_unit_id,'endpointKind',v_endpoint.endpoint_kind,'address',v_endpoint.address,'addressNormalized',v_endpoint.address_normalized,'endpointState',v_endpoint.endpoint_state);
end;$function$;

create or replace function atlas.bind_communication_endpoint_source_self_api_v1(p_communication_endpoint_id uuid,p_connected_source_id uuid,p_binding_role text default 'send_receive',p_transport_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_member atlas.organization_memberships%rowtype; v_binding atlas.communication_endpoint_source_bindings%rowtype; v_role text:=lower(btrim(coalesce(p_binding_role,'')));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id;
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active and role='owner' order by created_at limit 1;
  if v_member.id is null then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if v_role not in ('receive','send','send_receive') then raise exception 'Unsupported endpoint/source binding role.' using errcode='22023'; end if;
  select * into v_binding from atlas.communication_endpoint_source_bindings where communication_endpoint_id=v_endpoint.id and connected_source_id=p_connected_source_id and binding_state='active' limit 1 for update;
  if v_binding.id is null then
    insert into atlas.communication_endpoint_source_bindings(communication_endpoint_id,connected_source_id,binding_role,transport_metadata) values(v_endpoint.id,p_connected_source_id,v_role,coalesce(p_transport_metadata,'{}'::jsonb)) returning * into v_binding;
  else
    update atlas.communication_endpoint_source_bindings set binding_role=v_role,transport_metadata=transport_metadata||coalesce(p_transport_metadata,'{}'::jsonb),updated_at=now() where id=v_binding.id returning * into v_binding;
  end if;
  return jsonb_build_object('contractVersion','communication_endpoint_source_binding_v1','bindingId',v_binding.id,'communicationEndpointId',v_endpoint.id,'connectedSourceId',p_connected_source_id,'bindingRole',v_binding.binding_role,'bindingState',v_binding.binding_state);
end;$function$;

create or replace function atlas.set_communication_endpoint_member_capability_self_api_v1(p_communication_endpoint_id uuid,p_membership_id uuid,p_capability text,p_enabled boolean,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_endpoint atlas.communication_endpoints%rowtype; v_actor atlas.organization_memberships%rowtype; v_existing atlas.communication_endpoint_member_grants%rowtype; v_cap text:=lower(btrim(coalesce(p_capability,'')));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id;
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_actor from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active and role='owner' order by created_at limit 1;
  if v_actor.id is null then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if v_cap not in ('view','send','claim','handoff','close','admin') then raise exception 'Unsupported communication endpoint capability.' using errcode='22023'; end if;
  select * into v_existing from atlas.communication_endpoint_member_grants where communication_endpoint_id=v_endpoint.id and membership_id=p_membership_id and capability=v_cap and grant_state='active' limit 1 for update;
  if p_enabled then
    if v_existing.id is null then insert into atlas.communication_endpoint_member_grants(communication_endpoint_id,membership_id,capability,granted_by_membership_id,metadata) values(v_endpoint.id,p_membership_id,v_cap,v_actor.id,jsonb_build_object('reason',nullif(btrim(coalesce(p_reason,'')),''))) returning * into v_existing; end if;
  else
    if v_existing.id is not null then update atlas.communication_endpoint_member_grants set grant_state='revoked',revoked_at=now(),metadata=metadata||jsonb_build_object('revocationReason',nullif(btrim(coalesce(p_reason,'')),''),'revokedByMembershipId',v_actor.id),updated_at=now() where id=v_existing.id returning * into v_existing; end if;
  end if;
  return jsonb_build_object('contractVersion','communication_endpoint_member_capability_v1','communicationEndpointId',v_endpoint.id,'membershipId',p_membership_id,'capability',v_cap,'enabled',p_enabled,'grantId',v_existing.id);
end;$function$;

create table atlas.institutional_conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  stable_key text not null check (btrim(stable_key)<>''),
  subject text,
  conversation_state text not null default 'open' check (conversation_state in ('open','closed','merged')),
  opened_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  merged_into_conversation_id uuid references atlas.institutional_conversations(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,stable_key),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  check (merged_into_conversation_id is null or conversation_state='merged')
);
create index institutional_conversations_activity_idx on atlas.institutional_conversations(organization_id,organization_unit_id,conversation_state,last_activity_at desc,id);
comment on table atlas.institutional_conversations is 'Durable institution-level conversation continuity above provider/source threads. Source messages remain immutable Communication Events; a conversation may survive provider changes and later span multiple transport rails.';

create table atlas.institutional_conversation_endpoints (
  id uuid primary key default gen_random_uuid(),
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  endpoint_role text not null default 'primary' check (endpoint_role in ('primary','participant')),
  created_at timestamptz not null default now(),
  unique(institutional_conversation_id,communication_endpoint_id)
);

create table atlas.institutional_conversation_source_threads (
  id uuid primary key default gen_random_uuid(),
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  communication_thread_id uuid not null references atlas.communication_threads(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  continuity_basis text not null default 'source_thread' check (btrim(continuity_basis)<>''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(communication_thread_id)
);

create table atlas.institutional_conversation_messages (
  id uuid primary key default gen_random_uuid(),
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  communication_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  continuity_basis text not null check (btrim(continuity_basis)<>''),
  occurred_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(communication_event_id)
);
create index institutional_conversation_messages_conversation_idx on atlas.institutional_conversation_messages(institutional_conversation_id,occurred_at,id);

create table atlas.institutional_conversation_relationships (
  id uuid primary key default gen_random_uuid(),
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  relationship_role text not null default 'external_party' check (relationship_role in ('external_party','primary_external_party','participant')),
  created_at timestamptz not null default now(),
  unique(institutional_conversation_id,external_relationship_id)
);

create table atlas.institutional_communication_admission_reviews (
  id uuid primary key default gen_random_uuid(),
  communication_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  review_state text not null check (review_state in ('no_endpoint','ambiguous_endpoint','scope_conflict')),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(communication_event_id,evidence_sha256),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict
);
comment on table atlas.institutional_communication_admission_reviews is 'Explicit unresolved institutional-admission evidence when a company-owned Communication Event cannot be safely attached to exactly one institutional endpoint/conversation.';

create or replace function atlas.prevent_institutional_communication_evidence_mutation_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $function$
begin raise exception 'Institutional communication linkage/evidence is append-only.' using errcode='55000'; end;$function$;
create trigger institutional_conversation_source_threads_append_only_v1 before update or delete on atlas.institutional_conversation_source_threads for each row execute function atlas.prevent_institutional_communication_evidence_mutation_v1();
create trigger institutional_conversation_messages_append_only_v1 before update or delete on atlas.institutional_conversation_messages for each row execute function atlas.prevent_institutional_communication_evidence_mutation_v1();
create trigger institutional_conversation_relationships_append_only_v1 before update or delete on atlas.institutional_conversation_relationships for each row execute function atlas.prevent_institutional_communication_evidence_mutation_v1();
create trigger institutional_communication_admission_reviews_append_only_v1 before update or delete on atlas.institutional_communication_admission_reviews for each row execute function atlas.prevent_institutional_communication_evidence_mutation_v1();

create or replace function atlas.guard_institutional_conversation_endpoint_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  if v_conv.id is null or v_endpoint.id is null or v_conv.organization_id is distinct from v_endpoint.organization_id or v_conv.organization_unit_id is distinct from v_endpoint.organization_unit_id then raise exception 'Conversation and endpoint must share organization/unit scope.' using errcode='23514'; end if;
  return new;
end;$function$;
create trigger institutional_conversation_endpoint_guard_v1 before insert or update on atlas.institutional_conversation_endpoints for each row execute function atlas.guard_institutional_conversation_endpoint_v1();

create or replace function atlas.guard_institutional_conversation_source_thread_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_thread atlas.communication_threads%rowtype;
begin
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_thread from atlas.communication_threads where id=new.communication_thread_id;
  if v_conv.id is null or v_thread.id is null or v_thread.organization_id is distinct from v_conv.organization_id or v_thread.organization_unit_id is distinct from v_conv.organization_unit_id or v_thread.connected_source_id is distinct from new.connected_source_id then raise exception 'Conversation source thread must share organization/unit/source custody.' using errcode='23514'; end if;
  return new;
end;$function$;
create trigger institutional_conversation_source_thread_guard_v1 before insert on atlas.institutional_conversation_source_threads for each row execute function atlas.guard_institutional_conversation_source_thread_v1();

create or replace function atlas.guard_institutional_conversation_message_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_event atlas.communication_events%rowtype; v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_event from atlas.communication_events where id=new.communication_event_id;
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  if v_conv.id is null or v_event.id is null or v_endpoint.id is null then raise exception 'Conversation message requires conversation, event, and endpoint.' using errcode='23514'; end if;
  if v_event.organization_id is distinct from v_conv.organization_id or v_event.organization_unit_id is distinct from v_conv.organization_unit_id or v_endpoint.organization_id is distinct from v_conv.organization_id or v_endpoint.organization_unit_id is distinct from v_conv.organization_unit_id then raise exception 'Conversation message must share institutional scope.' using errcode='23514'; end if;
  new.occurred_at:=coalesce(new.occurred_at,v_event.occurred_at);
  return new;
end;$function$;
create trigger institutional_conversation_message_guard_v1 before insert on atlas.institutional_conversation_messages for each row execute function atlas.guard_institutional_conversation_message_v1();

create or replace function atlas.guard_institutional_conversation_relationship_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_rel atlas.external_relationships%rowtype;
begin
  select * into v_conv from atlas.institutional_conversations where id=new.institutional_conversation_id;
  select * into v_rel from atlas.external_relationships where id=new.external_relationship_id;
  if v_conv.id is null or v_rel.id is null or v_rel.organization_id is distinct from v_conv.organization_id or v_rel.organization_unit_id is distinct from v_conv.organization_unit_id then raise exception 'Conversation relationship must share organization/unit scope.' using errcode='23514'; end if;
  return new;
end;$function$;
create trigger institutional_conversation_relationship_guard_v1 before insert on atlas.institutional_conversation_relationships for each row execute function atlas.guard_institutional_conversation_relationship_v1();

create or replace function atlas.ensure_institutional_conversation_for_communication_event_service_v1(p_communication_event_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare
  v_event atlas.communication_events%rowtype; v_endpoint_id uuid; v_candidate_count int; v_conv_id uuid; v_stable_key text; v_subject text; v_review jsonb; v_review_hash text; v_rel uuid; v_created boolean:=false;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  if v_event.organization_id is null then return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state','not_institutional','communicationEventId',v_event.id); end if;

  select count(*),min(ep.id) into v_candidate_count,v_endpoint_id
  from atlas.communication_endpoint_source_bindings b join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
  where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active'
    and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown')
    and exists(select 1 from atlas.communication_event_participants p where p.communication_event_id=v_event.id and p.is_self and p.address_normalized=ep.address_normalized and ((ep.endpoint_kind='email' and p.address_kind='email') or (ep.endpoint_kind in ('phone','sms','voice') and p.address_kind='phone') or ep.endpoint_kind not in ('email','phone','sms','voice')));

  if v_candidate_count=0 then
    select count(*),min(ep.id) into v_candidate_count,v_endpoint_id
    from atlas.communication_endpoint_source_bindings b join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
    where b.connected_source_id=v_event.connected_source_id and b.binding_state='active' and ep.endpoint_state='active'
      and (b.binding_role='send_receive' or (v_event.direction='incoming' and b.binding_role='receive') or (v_event.direction='outgoing' and b.binding_role='send') or v_event.direction='unknown');
  end if;

  if v_candidate_count<>1 then
    v_review:=jsonb_build_object('state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,'communicationEventId',v_event.id,'connectedSourceId',v_event.connected_source_id,'candidateCount',v_candidate_count);
    v_review_hash:=encode(extensions.digest(convert_to(v_review::text,'UTF8'),'sha256'),'hex');
    insert into atlas.institutional_communication_admission_reviews(communication_event_id,connected_source_id,organization_id,organization_unit_id,review_state,evidence,evidence_sha256)
    values(v_event.id,v_event.connected_source_id,v_event.organization_id,v_event.organization_unit_id,case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,v_review,v_review_hash) on conflict do nothing;
    return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,'communicationEventId',v_event.id,'candidateCount',v_candidate_count);
  end if;

  if v_event.thread_id is not null then select institutional_conversation_id into v_conv_id from atlas.institutional_conversation_source_threads where communication_thread_id=v_event.thread_id; end if;
  if v_conv_id is null then
    v_stable_key:=case when v_event.thread_id is not null then 'source-thread:'||v_event.connected_source_id::text||':'||v_event.thread_id::text else 'source-event:'||v_event.id::text end;
    v_subject:=coalesce(nullif(btrim(v_event.canonical_event->>'subject'),''),nullif(btrim(v_event.canonical_event#>>'{sourcePayload,subject}'),''),'Conversation');
    insert into atlas.institutional_conversations(organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata)
    values(v_event.organization_id,v_event.organization_unit_id,v_stable_key,v_subject,coalesce(v_event.occurred_at,v_event.captured_at),coalesce(v_event.occurred_at,v_event.captured_at),jsonb_build_object('createdFromCommunicationEventId',v_event.id))
    on conflict (organization_id,stable_key) do update set last_activity_at=greatest(atlas.institutional_conversations.last_activity_at,excluded.last_activity_at),updated_at=now()
    returning id into v_conv_id;
    v_created:=true;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint_id,'primary') on conflict do nothing;
    if v_event.thread_id is not null then insert into atlas.institutional_conversation_source_threads(institutional_conversation_id,communication_thread_id,connected_source_id,continuity_basis,metadata) values(v_conv_id,v_event.thread_id,v_event.connected_source_id,'source_thread',jsonb_build_object('firstCommunicationEventId',v_event.id)) on conflict (communication_thread_id) do nothing; end if;
  else
    update atlas.institutional_conversations set last_activity_at=greatest(last_activity_at,coalesce(v_event.occurred_at,v_event.captured_at)),updated_at=now() where id=v_conv_id;
    insert into atlas.institutional_conversation_endpoints(institutional_conversation_id,communication_endpoint_id,endpoint_role) values(v_conv_id,v_endpoint_id,'participant') on conflict do nothing;
  end if;

  insert into atlas.institutional_conversation_messages(institutional_conversation_id,communication_event_id,communication_endpoint_id,continuity_basis,occurred_at,metadata)
  values(v_conv_id,v_event.id,v_endpoint_id,case when v_event.thread_id is null then 'source_event' else 'source_thread' end,v_event.occurred_at,jsonb_build_object('connectedSourceId',v_event.connected_source_id,'sourceEventRef',v_event.source_event_ref)) on conflict (communication_event_id) do nothing;

  for v_rel in select distinct r.external_relationship_id from atlas.communication_participant_relationship_resolutions r where r.communication_event_id=v_event.id and r.external_relationship_id is not null loop
    insert into atlas.institutional_conversation_relationships(institutional_conversation_id,external_relationship_id,relationship_role) values(v_conv_id,v_rel,'external_party') on conflict do nothing;
  end loop;

  return jsonb_build_object('contractVersion','institutional_conversation_admission_v1','state','admitted','communicationEventId',v_event.id,'institutionalConversationId',v_conv_id,'communicationEndpointId',v_endpoint_id,'conversationCreated',v_created);
end;$function$;

create or replace function atlas.ingest_organization_communication_events_service_v2(p_connected_source_id uuid,p_events jsonb,p_manifest jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_receipt jsonb; v_batch_id uuid; v_event_id uuid; v_admission jsonb; v_admitted int:=0; v_unresolved int:=0;
begin
  v_receipt:=atlas.ingest_organization_communication_events_service_v1(p_connected_source_id,p_events,p_manifest);
  v_batch_id:=(v_receipt->>'batchId')::uuid;
  for v_event_id in select id from atlas.communication_events where ingest_batch_id=v_batch_id order by created_at,id loop
    v_admission:=atlas.ensure_institutional_conversation_for_communication_event_service_v1(v_event_id);
    if v_admission->>'state'='admitted' then v_admitted:=v_admitted+1; else v_unresolved:=v_unresolved+1; end if;
  end loop;
  return v_receipt||jsonb_build_object('institutionalConversationsAdmitted',v_admitted,'institutionalAdmissionUnresolved',v_unresolved,'contractVersion','organization_communication_ingest_receipt_v2');
end;$function$;

alter table atlas.communication_endpoints enable row level security;
alter table atlas.communication_endpoint_source_bindings enable row level security;
alter table atlas.communication_endpoint_member_grants enable row level security;
alter table atlas.institutional_conversations enable row level security;
alter table atlas.institutional_conversation_endpoints enable row level security;
alter table atlas.institutional_conversation_source_threads enable row level security;
alter table atlas.institutional_conversation_messages enable row level security;
alter table atlas.institutional_conversation_relationships enable row level security;
alter table atlas.institutional_communication_admission_reviews enable row level security;

revoke all on atlas.communication_endpoints,atlas.communication_endpoint_source_bindings,atlas.communication_endpoint_member_grants,atlas.institutional_conversations,atlas.institutional_conversation_endpoints,atlas.institutional_conversation_source_threads,atlas.institutional_conversation_messages,atlas.institutional_conversation_relationships,atlas.institutional_communication_admission_reviews from public,anon,authenticated;
grant all on atlas.communication_endpoints,atlas.communication_endpoint_source_bindings,atlas.communication_endpoint_member_grants,atlas.institutional_conversations,atlas.institutional_conversation_endpoints,atlas.institutional_conversation_source_threads,atlas.institutional_conversation_messages,atlas.institutional_conversation_relationships,atlas.institutional_communication_admission_reviews to service_role;

revoke all on function atlas.normalize_communication_endpoint_address_v1(text,text),atlas.guard_communication_endpoint_v1(),atlas.guard_communication_endpoint_source_binding_v1(),atlas.guard_communication_endpoint_member_grant_v1(),atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid),atlas.ingest_organization_communication_events_service_v2(uuid,jsonb,jsonb),atlas.prevent_institutional_communication_evidence_mutation_v1(),atlas.guard_institutional_conversation_endpoint_v1(),atlas.guard_institutional_conversation_source_thread_v1(),atlas.guard_institutional_conversation_message_v1(),atlas.guard_institutional_conversation_relationship_v1() from public,anon,authenticated;
grant execute on function atlas.normalize_communication_endpoint_address_v1(text,text),atlas.guard_communication_endpoint_v1(),atlas.guard_communication_endpoint_source_binding_v1(),atlas.guard_communication_endpoint_member_grant_v1(),atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid),atlas.ingest_organization_communication_events_service_v2(uuid,jsonb,jsonb),atlas.prevent_institutional_communication_evidence_mutation_v1(),atlas.guard_institutional_conversation_endpoint_v1(),atlas.guard_institutional_conversation_source_thread_v1(),atlas.guard_institutional_conversation_message_v1(),atlas.guard_institutional_conversation_relationship_v1() to service_role;
revoke all on function atlas.communication_endpoint_authorized_self_v1(uuid,text),atlas.upsert_communication_endpoint_self_api_v1(uuid,uuid,text,text,text,jsonb),atlas.bind_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb),atlas.set_communication_endpoint_member_capability_self_api_v1(uuid,uuid,text,boolean,text) from public,anon;
grant execute on function atlas.communication_endpoint_authorized_self_v1(uuid,text),atlas.upsert_communication_endpoint_self_api_v1(uuid,uuid,text,text,text,jsonb),atlas.bind_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb),atlas.set_communication_endpoint_member_capability_self_api_v1(uuid,uuid,text,boolean,text) to authenticated,service_role;

commit;