begin;

create or replace function atlas.provision_communication_outbound_transport_relay_service_v1(
  p_connected_source_id uuid,
  p_communication_endpoint_id uuid,
  p_transport_kind text,
  p_relay_key text,
  p_secret_sha256 text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_transport_kind,'')));
  v_key text:=btrim(coalesce(p_relay_key,''));
  v_digest text:=lower(btrim(coalesce(p_secret_sha256,'')));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_count integer;
  v_existing atlas.communication_outbound_transport_relays%rowtype;
  v_relay atlas.communication_outbound_transport_relays%rowtype;
  v_rotated boolean:=false;
  v_secret_changed boolean:=false;
begin
  if p_connected_source_id is null or p_communication_endpoint_id is null then
    raise exception 'Connected source and communication endpoint are required.' using errcode='22023';
  end if;
  if v_kind='' or v_key='' or v_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'Transport kind, relay key, and a lowercase SHA-256 relay secret digest are required.' using errcode='22023';
  end if;
  if jsonb_typeof(v_metadata)<>'object' then
    raise exception 'Relay metadata must be a JSON object.' using errcode='22023';
  end if;
  if lower(v_metadata::text) ~ '"(relay_secret|secret|password|access_token|refresh_token|api_key|client_secret)"[[:space:]]*:' then
    raise exception 'Reusable credentials are not allowed in relay metadata.' using errcode='22023';
  end if;

  select count(*) into v_count
  from atlas.communication_outbound_transport_relays r
  where r.connected_source_id=p_connected_source_id
    and r.communication_endpoint_id=p_communication_endpoint_id
    and lower(btrim(r.transport_kind))=v_kind
    and r.relay_state in ('active','disabled');
  if v_count>1 then
    raise exception 'Outbound relay custody is ambiguous for this source, endpoint, and transport kind.' using errcode='55000';
  end if;

  if v_count=1 then
    select * into v_existing
    from atlas.communication_outbound_transport_relays r
    where r.connected_source_id=p_connected_source_id
      and r.communication_endpoint_id=p_communication_endpoint_id
      and lower(btrim(r.transport_kind))=v_kind
      and r.relay_state in ('active','disabled')
    for update;
  end if;

  if v_existing.id is not null and v_existing.relay_key is distinct from v_key then
    update atlas.communication_outbound_transport_relays
    set relay_state='rotated',
        metadata=metadata||jsonb_build_object(
          'rotatedAt',now(),
          'rotationReason','relay_key_replaced'
        ),
        updated_at=now()
    where id=v_existing.id;
    v_rotated:=true;
    v_existing.id:=null;
  end if;

  if v_existing.id is null then
    insert into atlas.communication_outbound_transport_relays(
      relay_key,connected_source_id,communication_endpoint_id,secret_sha256,relay_state,transport_kind,metadata
    ) values (
      v_key,p_connected_source_id,p_communication_endpoint_id,v_digest,'active',v_kind,
      v_metadata||jsonb_build_object('provisionedAt',now(),'credentialStorage','sha256_digest_only')
    ) returning * into v_relay;
  else
    v_secret_changed:=v_existing.secret_sha256 is distinct from v_digest;
    update atlas.communication_outbound_transport_relays
    set secret_sha256=v_digest,
        relay_state='active',
        last_authenticated_at=case when v_secret_changed then null else last_authenticated_at end,
        metadata=metadata||v_metadata||jsonb_build_object(
          'credentialStorage','sha256_digest_only',
          'lastProvisionedAt',now()
        )||case when v_secret_changed then jsonb_build_object('secretRotatedAt',now()) else '{}'::jsonb end,
        updated_at=now()
    where id=v_existing.id
    returning * into v_relay;
  end if;

  return jsonb_build_object(
    'contractVersion','communication_outbound_transport_relay_provisioning_v1',
    'relayId',v_relay.id,
    'relayKey',v_relay.relay_key,
    'connectedSourceId',v_relay.connected_source_id,
    'communicationEndpointId',v_relay.communication_endpoint_id,
    'transportKind',v_relay.transport_kind,
    'relayState',v_relay.relay_state,
    'previousRelayRotated',v_rotated,
    'secretDigestChanged',v_secret_changed,
    'plaintextSecretStored',false
  );
end;
$function$;
revoke all on function atlas.provision_communication_outbound_transport_relay_service_v1(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.provision_communication_outbound_transport_relay_service_v1(uuid,uuid,text,text,text,jsonb) to service_role;

create or replace function atlas.disable_communication_outbound_transport_relay_service_v1(
  p_relay_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relay atlas.communication_outbound_transport_relays%rowtype;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  select * into v_relay
  from atlas.communication_outbound_transport_relays
  where id=p_relay_id
  for update;
  if v_relay.id is null then
    raise exception 'Outbound transport relay not found.' using errcode='P0002';
  end if;

  update atlas.communication_outbound_transport_relays
  set relay_state='disabled',
      metadata=metadata||jsonb_build_object('disabledAt',now(),'disableReason',v_reason),
      updated_at=now()
  where id=v_relay.id
  returning * into v_relay;

  return jsonb_build_object(
    'contractVersion','communication_outbound_transport_relay_disable_v1',
    'relayId',v_relay.id,
    'relayKey',v_relay.relay_key,
    'connectedSourceId',v_relay.connected_source_id,
    'communicationEndpointId',v_relay.communication_endpoint_id,
    'transportKind',v_relay.transport_kind,
    'relayState',v_relay.relay_state
  );
end;
$function$;
revoke all on function atlas.disable_communication_outbound_transport_relay_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function atlas.disable_communication_outbound_transport_relay_service_v1(uuid,text) to service_role;

create or replace function public.provision_communication_outbound_transport_relay_service_v1(
  p_connected_source_id uuid,
  p_communication_endpoint_id uuid,
  p_transport_kind text,
  p_relay_key text,
  p_secret_sha256 text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.provision_communication_outbound_transport_relay_service_v1(
    p_connected_source_id,p_communication_endpoint_id,p_transport_kind,p_relay_key,p_secret_sha256,p_metadata
  );
$function$;
revoke all on function public.provision_communication_outbound_transport_relay_service_v1(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.provision_communication_outbound_transport_relay_service_v1(uuid,uuid,text,text,text,jsonb) to service_role;

create or replace function public.disable_communication_outbound_transport_relay_service_v1(p_relay_id uuid,p_reason text default null)
returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.disable_communication_outbound_transport_relay_service_v1(p_relay_id,p_reason);
$function$;
revoke all on function public.disable_communication_outbound_transport_relay_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.disable_communication_outbound_transport_relay_service_v1(uuid,text) to service_role;

comment on function atlas.provision_communication_outbound_transport_relay_service_v1(uuid,uuid,text,text,text,jsonb) is
  'Service-only infrastructure provisioning for an already governed endpoint/source send binding. Stores only a SHA-256 relay-secret digest; the plaintext relay secret must remain in infrastructure secret custody.';
comment on function atlas.disable_communication_outbound_transport_relay_service_v1(uuid,text) is
  'Service-only relay disable operation. Does not delete transport history or connected-source custody.';

commit;
