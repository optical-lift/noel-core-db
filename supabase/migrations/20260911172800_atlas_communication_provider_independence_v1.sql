begin;

-- ---------------------------------------------------------------------------
-- 1. Durable Communication Endpoints may belong to a Principal OR Organization
-- ---------------------------------------------------------------------------

alter table atlas.communication_endpoints
  add column principal_id uuid references atlas.principals(id) on delete cascade;

alter table atlas.communication_endpoints
  alter column organization_id drop not null;

alter table atlas.communication_endpoints
  add constraint communication_endpoints_custody_root_check
  check ((((principal_id is not null))::integer + ((organization_id is not null))::integer) = 1),
  add constraint communication_endpoints_principal_has_no_unit_check
  check (principal_id is null or organization_unit_id is null);

create unique index communication_endpoints_principal_identity_uq
  on atlas.communication_endpoints(principal_id,endpoint_kind,address_normalized)
  where principal_id is not null;

create index communication_endpoints_principal_state_idx
  on atlas.communication_endpoints(principal_id,endpoint_state,endpoint_kind)
  where principal_id is not null;

comment on table atlas.communication_endpoints is
'Durable addressable communication identities owned by exactly one Principal or one Organization custody root. Endpoint identity remains above provider/transport accounts; changing carriers must not replace the endpoint or its Atlas history.';

create or replace function atlas.guard_communication_endpoint_source_binding_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_principal_user_id uuid;
begin
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;

  if v_endpoint.id is null or v_source.id is null then
    raise exception 'Communication endpoint and connected source are required.' using errcode='23514';
  end if;

  if v_endpoint.principal_id is not null then
    select p.user_id into v_principal_user_id
    from atlas.principals p
    where p.id=v_endpoint.principal_id and p.status='active';

    if v_principal_user_id is null then
      raise exception 'Principal communication endpoint requires an active Principal.' using errcode='23514';
    end if;

    if v_source.custodian_user_id is distinct from v_principal_user_id
       or v_source.custodian_organization_id is not null
       or v_source.custodian_organization_unit_id is not null then
      raise exception 'Principal communication endpoint and connected source must share Principal custody.' using errcode='23514';
    end if;
  else
    if v_source.custodian_organization_id is null then
      raise exception 'Institutional endpoint transport must be organization-owned.' using errcode='23514';
    end if;

    if v_source.custodian_organization_id is distinct from v_endpoint.organization_id
       or v_source.custodian_organization_unit_id is distinct from v_endpoint.organization_unit_id then
      raise exception 'Communication endpoint and connected source must share organization/unit custody.' using errcode='23514';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

create or replace function atlas.upsert_principal_communication_endpoint_self_api_v1(
  p_endpoint_kind text,
  p_address text,
  p_display_name text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_kind text:=lower(btrim(coalesce(p_endpoint_kind,'')));
  v_address text:=btrim(coalesce(p_address,''));
  v_norm text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals
  where user_id=auth.uid() and status='active'
  order by created_at,id
  limit 1;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if v_kind not in ('email','phone','sms','voice','web_form','social','atlas_native','other') or v_address='' then
    raise exception 'Valid endpoint kind and address are required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Endpoint metadata must be an object.' using errcode='22023';
  end if;

  v_norm:=atlas.normalize_communication_endpoint_address_v1(v_kind,v_address);

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.principal_id=v_principal.id
    and ep.endpoint_kind=v_kind
    and ep.address_normalized=v_norm
  for update;

  if v_endpoint.id is null then
    insert into atlas.communication_endpoints(
      principal_id,organization_id,organization_unit_id,
      endpoint_kind,address,address_normalized,display_name,metadata
    )
    values(
      v_principal.id,null,null,
      v_kind,v_address,v_norm,nullif(btrim(p_display_name),''),coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_endpoint;
  else
    update atlas.communication_endpoints
    set display_name=coalesce(nullif(btrim(p_display_name),''),display_name),
        metadata=metadata||coalesce(p_metadata,'{}'::jsonb),
        endpoint_state='active',
        updated_at=now()
    where id=v_endpoint.id
    returning * into v_endpoint;
  end if;

  return jsonb_build_object(
    'contractVersion','principal_communication_endpoint_v1',
    'communicationEndpointId',v_endpoint.id,
    'principalId',v_endpoint.principal_id,
    'endpointKind',v_endpoint.endpoint_kind,
    'address',v_endpoint.address,
    'addressNormalized',v_endpoint.address_normalized,
    'endpointState',v_endpoint.endpoint_state
  );
end;
$function$;

revoke all on function atlas.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb) from public;
grant execute on function atlas.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Common provider-independent durable Conversation root
-- ---------------------------------------------------------------------------

create table atlas.communication_conversations (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid references atlas.principals(id) on delete cascade,
  organization_id uuid references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  stable_key text not null check (btrim(stable_key)<>''),
  subject text,
  conversation_state text not null default 'open' check (conversation_state in ('open','closed','merged')),
  opened_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  merged_into_conversation_id uuid references atlas.communication_conversations(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  check ((((principal_id is not null))::integer + ((organization_id is not null))::integer) = 1),
  check (principal_id is null or organization_unit_id is null),
  check (merged_into_conversation_id is null or conversation_state='merged')
);

create unique index communication_conversations_principal_stable_uq
  on atlas.communication_conversations(principal_id,stable_key)
  where principal_id is not null;

create unique index communication_conversations_org_stable_uq
  on atlas.communication_conversations(organization_id,stable_key)
  where organization_id is not null;

create index communication_conversations_principal_activity_idx
  on atlas.communication_conversations(principal_id,conversation_state,last_activity_at desc)
  where principal_id is not null;

create index communication_conversations_org_activity_idx
  on atlas.communication_conversations(organization_id,organization_unit_id,conversation_state,last_activity_at desc)
  where organization_id is not null;

comment on table atlas.communication_conversations is
'Provider-independent durable conversation root. Source/provider threads remain evidence beneath this root. A conversation belongs to exactly one Principal or Organization custody root.';

create table atlas.communication_conversation_source_threads (
  id uuid primary key default gen_random_uuid(),
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  communication_thread_id uuid not null unique references atlas.communication_threads(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  continuity_basis text not null check (btrim(continuity_basis)<>''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);

create index communication_conversation_source_threads_conversation_idx
  on atlas.communication_conversation_source_threads(communication_conversation_id,created_at,id);

comment on table atlas.communication_conversation_source_threads is
'Explicit bridge from provider/source-local Communication Threads into one durable Atlas Communication Conversation. No automatic cross-source merge is implied by source-thread similarity.';

create or replace function atlas.guard_communication_conversation_source_thread_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_thread atlas.communication_threads%rowtype;
begin
  select * into v_conversation from atlas.communication_conversations where id=new.communication_conversation_id;
  select * into v_thread from atlas.communication_threads where id=new.communication_thread_id;

  if v_conversation.id is null or v_thread.id is null then
    raise exception 'Communication conversation and source thread are required.' using errcode='23514';
  end if;

  if new.connected_source_id is distinct from v_thread.connected_source_id then
    raise exception 'Conversation source-thread connected source must match the source thread.' using errcode='23514';
  end if;

  if v_conversation.principal_id is not null then
    if v_thread.principal_id is distinct from v_conversation.principal_id or v_thread.organization_id is not null then
      raise exception 'Principal conversation source thread must share Principal custody.' using errcode='23514';
    end if;
  else
    if v_thread.organization_id is distinct from v_conversation.organization_id
       or v_thread.organization_unit_id is distinct from v_conversation.organization_unit_id
       or v_thread.principal_id is not null then
      raise exception 'Organization conversation source thread must share Organization/unit custody.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger communication_conversation_source_thread_guard_v1
before insert or update on atlas.communication_conversation_source_threads
for each row execute function atlas.guard_communication_conversation_source_thread_v1();

create table atlas.communication_conversation_endpoints (
  id uuid primary key default gen_random_uuid(),
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  endpoint_role text not null default 'participant' check (endpoint_role in ('primary','participant','historical')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (communication_conversation_id,communication_endpoint_id)
);

create index communication_conversation_endpoints_endpoint_idx
  on atlas.communication_conversation_endpoints(communication_endpoint_id,communication_conversation_id);

create or replace function atlas.guard_communication_conversation_endpoint_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_conversation from atlas.communication_conversations where id=new.communication_conversation_id;
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;

  if v_conversation.id is null or v_endpoint.id is null then
    raise exception 'Communication conversation and endpoint are required.' using errcode='23514';
  end if;

  if v_conversation.principal_id is not null then
    if v_endpoint.principal_id is distinct from v_conversation.principal_id or v_endpoint.organization_id is not null then
      raise exception 'Principal conversation endpoint must share Principal custody.' using errcode='23514';
    end if;
  else
    if v_endpoint.organization_id is distinct from v_conversation.organization_id
       or v_endpoint.organization_unit_id is distinct from v_conversation.organization_unit_id
       or v_endpoint.principal_id is not null then
      raise exception 'Organization conversation endpoint must share Organization/unit custody.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger communication_conversation_endpoint_guard_v1
before insert or update on atlas.communication_conversation_endpoints
for each row execute function atlas.guard_communication_conversation_endpoint_v1();

create table atlas.institutional_conversation_roots (
  institutional_conversation_id uuid primary key references atlas.institutional_conversations(id) on delete cascade,
  communication_conversation_id uuid not null unique references atlas.communication_conversations(id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table atlas.institutional_conversation_roots is
'Compatibility bridge preserving existing Institutional Conversation authority while giving each institutional conversation one provider-independent Communication Conversation root.';

insert into atlas.communication_conversations(
  principal_id,organization_id,organization_unit_id,stable_key,subject,conversation_state,
  opened_at,last_activity_at,metadata,created_at,updated_at
)
select
  null,ic.organization_id,ic.organization_unit_id,'institutional:'||ic.id::text,ic.subject,ic.conversation_state,
  ic.opened_at,ic.last_activity_at,
  jsonb_build_object('institutionalConversationId',ic.id,'compatibilityBridge','institutional_conversation_roots_v1'),
  ic.created_at,ic.updated_at
from atlas.institutional_conversations ic
on conflict (organization_id,stable_key) where organization_id is not null do nothing;

insert into atlas.institutional_conversation_roots(institutional_conversation_id,communication_conversation_id)
select ic.id,cc.id
from atlas.institutional_conversations ic
join atlas.communication_conversations cc
  on cc.organization_id=ic.organization_id
 and cc.stable_key='institutional:'||ic.id::text
on conflict (institutional_conversation_id) do nothing;

insert into atlas.communication_conversation_endpoints(
  communication_conversation_id,communication_endpoint_id,endpoint_role,metadata,created_at
)
select
  root.communication_conversation_id,ice.communication_endpoint_id,
  case when ice.endpoint_role='primary' then 'primary' else 'participant' end,
  jsonb_build_object('institutionalConversationEndpointBridge',true),
  ice.created_at
from atlas.institutional_conversation_endpoints ice
join atlas.institutional_conversation_roots root
  on root.institutional_conversation_id=ice.institutional_conversation_id
on conflict (communication_conversation_id,communication_endpoint_id) do nothing;

insert into atlas.communication_conversation_source_threads(
  communication_conversation_id,communication_thread_id,connected_source_id,continuity_basis,metadata,created_at
)
select
  root.communication_conversation_id,st.communication_thread_id,st.connected_source_id,
  'institutional_compatibility:'||st.continuity_basis,
  coalesce(st.metadata,'{}'::jsonb)||jsonb_build_object('institutionalConversationSourceThreadBridge',true),
  st.created_at
from atlas.institutional_conversation_source_threads st
join atlas.institutional_conversation_roots root
  on root.institutional_conversation_id=st.institutional_conversation_id
on conflict (communication_thread_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Provider-neutral synchronization state beneath Connected Sources
-- ---------------------------------------------------------------------------

create table atlas.communication_source_sync_states (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  sync_role text not null check (sync_role in ('capture','send_reconciliation','other')),
  state_key text not null check (btrim(state_key)<>''),
  state_kind text not null check (btrim(state_kind)<>''),
  sync_state text not null default 'active' check (sync_state in ('active','paused','reauthorization_required','error','retired')),
  state_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(state_payload)='object'),
  checkpoint_at timestamptz,
  expires_at timestamptz,
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connected_source_id,sync_role,state_key)
);

create index communication_source_sync_states_health_idx
  on atlas.communication_source_sync_states(connected_source_id,sync_state,expires_at,checkpoint_at desc);

comment on table atlas.communication_source_sync_states is
'Provider-neutral synchronization/subscription/cursor state beneath a Connected Source. IMAP UID checkpoints, Gmail history/watch state, Microsoft delta/subscription state, and future carrier cursors remain source-native evidence rather than Atlas semantic authority.';

-- ---------------------------------------------------------------------------
-- 4. Actionability evidence seam; no responsibility cutover in this release
-- ---------------------------------------------------------------------------

create table atlas.communication_actionability_assessments (
  id uuid primary key default gen_random_uuid(),
  communication_event_id uuid not null references atlas.communication_events(id) on delete cascade,
  classification text not null check (classification in ('unknown','actionable','informational','automated','junk')),
  assessment_authority text not null default 'proposed' check (assessment_authority in ('proposed','accepted','superseded')),
  assessed_by_user_id uuid references auth.users(id) on delete set null,
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  created_at timestamptz not null default now()
);

create index communication_actionability_event_idx
  on atlas.communication_actionability_assessments(communication_event_id,created_at desc,id desc);

create unique index communication_actionability_one_current_accepted_uq
  on atlas.communication_actionability_assessments(communication_event_id)
  where assessment_authority='accepted';

comment on table atlas.communication_actionability_assessments is
'Append-only evidence about whether an incoming communication requires human response. Receipt alone does not create responsibility. This table is not yet wired into the live Institutional Response Case opener.';

create or replace function atlas.guard_communication_actionability_append_only_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Communication actionability assessments are append-only.' using errcode='55000';
end;
$function$;

create trigger communication_actionability_append_only_v1
before update or delete on atlas.communication_actionability_assessments
for each row execute function atlas.guard_communication_actionability_append_only_v1();

create or replace function atlas.communication_event_actionability_v1(p_communication_event_id uuid)
returns text
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select coalesce((
    select a.classification
    from atlas.communication_actionability_assessments a
    where a.communication_event_id=p_communication_event_id
      and a.assessment_authority='accepted'
    order by a.created_at desc,a.id desc
    limit 1
  ),'unknown'::text);
$function$;

revoke all on table atlas.communication_conversations from public,anon,authenticated;
revoke all on table atlas.communication_conversation_source_threads from public,anon,authenticated;
revoke all on table atlas.communication_conversation_endpoints from public,anon,authenticated;
revoke all on table atlas.institutional_conversation_roots from public,anon,authenticated;
revoke all on table atlas.communication_source_sync_states from public,anon,authenticated;
revoke all on table atlas.communication_actionability_assessments from public,anon,authenticated;
revoke all on function atlas.communication_event_actionability_v1(uuid) from public,anon,authenticated;

alter table atlas.communication_conversations enable row level security;
alter table atlas.communication_conversation_source_threads enable row level security;
alter table atlas.communication_conversation_endpoints enable row level security;
alter table atlas.institutional_conversation_roots enable row level security;
alter table atlas.communication_source_sync_states enable row level security;
alter table atlas.communication_actionability_assessments enable row level security;

comment on function atlas.communication_event_actionability_v1(uuid) is
'Internal effective actionability read. Unknown is the fail-closed default. This function does not create or imply response responsibility.';

commit;
