create table atlas.communication_outbound_transport_relays (
  id uuid primary key default gen_random_uuid(),
  relay_key text not null unique check (btrim(relay_key) <> ''),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete restrict,
  secret_sha256 text not null check (secret_sha256 ~ '^[0-9a-f]{64}$'),
  relay_state text not null default 'active' check (relay_state in ('active','disabled','rotated')),
  transport_kind text not null default 'smtp_worker' check (btrim(transport_kind) <> ''),
  last_authenticated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index communication_outbound_transport_relays_source_idx
  on atlas.communication_outbound_transport_relays(connected_source_id,relay_state,created_at desc);

comment on table atlas.communication_outbound_transport_relays is
'Credential-verifier registry for an external institutional outbound transport worker. It may execute only already-authorized outbound operations for its bound send source; it does not create send authority or arbitrary message content.';

create or replace function atlas.guard_communication_outbound_transport_relay_v1()
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
    raise exception 'Outbound transport relay requires a connected source and communication endpoint.' using errcode='23514';
  end if;
  if v_endpoint.endpoint_kind <> 'email' then
    raise exception 'Outbound email transport relay requires an email endpoint.' using errcode='23514';
  end if;
  if v_source.custodian_organization_id is distinct from v_endpoint.organization_id
     or v_source.custodian_organization_unit_id is distinct from v_endpoint.organization_unit_id then
    raise exception 'Outbound transport relay source and endpoint must share organization/unit custody.' using errcode='23514';
  end if;
  if not exists (
    select 1
    from atlas.communication_endpoint_source_bindings binding
    where binding.communication_endpoint_id=new.communication_endpoint_id
      and binding.connected_source_id=new.connected_source_id
      and binding.binding_state='active'
      and binding.binding_role in ('send','send_receive')
  ) then
    raise exception 'Outbound transport relay source must be actively bound as a send transport for endpoint.' using errcode='23514';
  end if;
  new.relay_key:=btrim(new.relay_key);
  new.secret_sha256:=lower(btrim(new.secret_sha256));
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger communication_outbound_transport_relay_guard_v1
before insert or update on atlas.communication_outbound_transport_relays
for each row execute function atlas.guard_communication_outbound_transport_relay_v1();

create or replace function atlas.authenticate_communication_outbound_transport_relay_service_v1(
  p_relay_key text,
  p_secret_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relay atlas.communication_outbound_transport_relays%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_hash text:=lower(btrim(coalesce(p_secret_sha256,'')));
begin
  if btrim(coalesce(p_relay_key,''))='' or v_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authorized',false);
  end if;
  select * into v_relay
  from atlas.communication_outbound_transport_relays
  where relay_key=btrim(p_relay_key) and relay_state='active'
  for update;
  if v_relay.id is null or v_relay.secret_sha256 is distinct from v_hash then
    return jsonb_build_object('authorized',false);
  end if;
  select * into v_source from atlas.connected_sources where id=v_relay.connected_source_id;
  select * into v_endpoint from atlas.communication_endpoints where id=v_relay.communication_endpoint_id;
  if v_source.id is null or v_endpoint.id is null
     or v_source.authorization_state<>'connected'
     or not (coalesce(v_source.capabilities,'{}'::jsonb) @> '{"communicationSend":true}'::jsonb)
     or v_endpoint.endpoint_state<>'active' then
    return jsonb_build_object('authorized',false);
  end if;
  update atlas.communication_outbound_transport_relays
  set last_authenticated_at=now(),updated_at=now()
  where id=v_relay.id;
  return jsonb_build_object(
    'authorized',true,
    'contractVersion','communication_outbound_transport_relay_auth_v1',
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
    'endpointDisplayName',v_endpoint.display_name,
    'smtp',coalesce(v_source.metadata->'smtp','{}'::jsonb),
    'username',coalesce(nullif(v_source.metadata->>'username',''),v_source.provider_account_key)
  );
end;
$function$;

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
    select * into v_reply from atlas.communication_events where id=v_op.reply_to_communication_event_id;
    if v_reply.id is null then raise exception 'Reply target communication event not found.' using errcode='P0002'; end if;
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

alter table atlas.communication_outbound_transport_relays enable row level security;
revoke all on atlas.communication_outbound_transport_relays from public,anon,authenticated;
grant all on atlas.communication_outbound_transport_relays to service_role;

revoke all on function atlas.guard_communication_outbound_transport_relay_v1() from public,anon,authenticated;
revoke all on function atlas.authenticate_communication_outbound_transport_relay_service_v1(text,text) from public,anon,authenticated;
revoke all on function atlas.communication_outbound_email_transport_job_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.authenticate_communication_outbound_transport_relay_service_v1(text,text) to service_role;
grant execute on function atlas.communication_outbound_email_transport_job_service_v1(uuid) to service_role;