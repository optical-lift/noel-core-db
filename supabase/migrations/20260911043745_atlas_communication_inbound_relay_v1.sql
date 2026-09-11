begin;

create table atlas.communication_inbound_relays (
  id uuid primary key default gen_random_uuid(),
  relay_key text not null unique check (btrim(relay_key) <> ''),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  secret_sha256 text not null check (secret_sha256 ~ '^[0-9a-f]{64}$'),
  relay_state text not null default 'active' check (relay_state in ('active','disabled','rotated')),
  transport_kind text not null default 'https_raw_email' check (btrim(transport_kind) <> ''),
  last_authenticated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index communication_inbound_relays_source_idx
  on atlas.communication_inbound_relays(connected_source_id,relay_state,created_at desc);

comment on table atlas.communication_inbound_relays is
'Credential-verifier registry for push-style institutional communication relays. Stores only a SHA-256 verifier, never the relay secret itself. Relay authorization is transport authority only and does not establish communication content as governing truth.';

create or replace function atlas.guard_communication_inbound_relay_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_source from atlas.connected_sources where id=new.connected_source_id;
  select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
  if v_source.id is null or v_endpoint.id is null then
    raise exception 'Inbound relay requires a connected source and communication endpoint.' using errcode='23514';
  end if;
  if v_source.custodian_organization_id is distinct from v_endpoint.organization_id
     or v_source.custodian_organization_unit_id is distinct from v_endpoint.organization_unit_id then
    raise exception 'Inbound relay source and endpoint must share organization/unit custody.' using errcode='23514';
  end if;
  if not exists (
    select 1
    from atlas.communication_endpoint_source_bindings binding
    where binding.communication_endpoint_id=new.communication_endpoint_id
      and binding.connected_source_id=new.connected_source_id
      and binding.binding_state='active'
      and binding.binding_role in ('receive','send_receive')
  ) then
    raise exception 'Inbound relay source must be actively bound as a receive transport for endpoint.' using errcode='23514';
  end if;
  new.relay_key:=btrim(new.relay_key);
  new.secret_sha256:=lower(btrim(new.secret_sha256));
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger communication_inbound_relay_guard_v1
before insert or update on atlas.communication_inbound_relays
for each row execute function atlas.guard_communication_inbound_relay_v1();

create or replace function atlas.authenticate_communication_inbound_relay_service_v1(
  p_relay_key text,
  p_secret_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relay atlas.communication_inbound_relays%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_hash text:=lower(btrim(coalesce(p_secret_sha256,'')));
begin
  if btrim(coalesce(p_relay_key,''))='' or v_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authorized',false);
  end if;
  select * into v_relay
  from atlas.communication_inbound_relays
  where relay_key=btrim(p_relay_key) and relay_state='active'
  for update;
  if v_relay.id is null or v_relay.secret_sha256 is distinct from v_hash then
    return jsonb_build_object('authorized',false);
  end if;
  select * into v_source from atlas.connected_sources where id=v_relay.connected_source_id;
  select * into v_endpoint from atlas.communication_endpoints where id=v_relay.communication_endpoint_id;
  if v_source.id is null or v_endpoint.id is null
     or v_source.authorization_state<>'connected'
     or not (coalesce(v_source.capabilities,'{}'::jsonb) @> '{"communicationCapture":true}'::jsonb)
     or v_endpoint.endpoint_state<>'active' then
    return jsonb_build_object('authorized',false);
  end if;
  update atlas.communication_inbound_relays
  set last_authenticated_at=now(),updated_at=now()
  where id=v_relay.id;
  return jsonb_build_object(
    'authorized',true,
    'contractVersion','communication_inbound_relay_auth_v1',
    'relayId',v_relay.id,
    'relayKey',v_relay.relay_key,
    'transportKind',v_relay.transport_kind,
    'connectedSourceId',v_source.id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'organizationId',v_source.custodian_organization_id,
    'organizationUnitId',v_source.custodian_organization_unit_id,
    'communicationEndpointId',v_endpoint.id,
    'endpointAddress',v_endpoint.address,
    'endpointKind',v_endpoint.endpoint_kind
  );
end;
$function$;

create or replace function atlas.ingest_inbound_email_relay_event_service_v1(
  p_connected_source_id uuid,
  p_event jsonb,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_receipt jsonb;
  v_event_id uuid;
  v_event_ref text;
  v_conversation jsonb;
  v_response jsonb;
begin
  if jsonb_typeof(p_event)<>'object' then
    raise exception 'Inbound relay event must be one canonical communication event.' using errcode='22023';
  end if;
  if p_event->>'direction' is distinct from 'incoming' then
    raise exception 'Inbound email relay only admits incoming communication.' using errcode='22023';
  end if;
  v_event_ref:=nullif(btrim(p_event#>>'{source,eventRef}'),'');
  if v_event_ref is null then
    raise exception 'Inbound relay event source.eventRef is required.' using errcode='22023';
  end if;
  v_receipt:=atlas.ingest_organization_communication_events_service_v1(
    p_connected_source_id,
    jsonb_build_array(p_event),
    coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object('ingestTransport','institutional_inbound_relay_v1')
  );
  select id into v_event_id
  from atlas.communication_events
  where connected_source_id=p_connected_source_id and source_event_ref=v_event_ref;
  if v_event_id is null then
    raise exception 'Inbound relay ingest did not establish communication event custody.' using errcode='55000';
  end if;
  v_conversation:=atlas.ensure_institutional_conversation_for_communication_event_servi(v_event_id);
  v_response:=atlas.ensure_institutional_response_case_for_event_service_v1(v_event_id);
  return jsonb_build_object(
    'contractVersion','communication_inbound_relay_ingest_v1',
    'communicationEventId',v_event_id,
    'ingestReceipt',v_receipt,
    'conversationAdmission',v_conversation,
    'responseAdmission',v_response
  );
end;
$function$;

alter table atlas.communication_inbound_relays enable row level security;
revoke all on atlas.communication_inbound_relays from public,anon,authenticated;
grant all on atlas.communication_inbound_relays to service_role;

revoke all on function atlas.guard_communication_inbound_relay_v1() from public,anon,authenticated;
revoke all on function atlas.authenticate_communication_inbound_relay_service_v1(text,text) from public,anon,authenticated;
revoke all on function atlas.ingest_inbound_email_relay_event_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.authenticate_communication_inbound_relay_service_v1(text,text) to service_role;
grant execute on function atlas.ingest_inbound_email_relay_event_service_v1(uuid,jsonb,jsonb) to service_role;

commit;
