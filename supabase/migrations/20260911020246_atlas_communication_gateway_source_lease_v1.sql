begin;

create table atlas.communication_gateway_source_leases (
  connected_source_id uuid primary key references atlas.connected_sources(id) on delete cascade,
  gateway_instance_key text not null check (btrim(gateway_instance_key)<>''),
  lease_token uuid not null default gen_random_uuid(),
  lease_expires_at timestamptz not null,
  acquired_at timestamptz not null default now(),
  renewed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  updated_at timestamptz not null default now()
);
comment on table atlas.communication_gateway_source_leases is 'Ephemeral execution lease ensuring at most one live gateway instance actively owns a Connected Source at a time. This is runtime coordination only; it grants no mailbox, communication, or business authority.';

create table atlas.communication_gateway_source_lease_events (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  gateway_instance_key text not null,
  lease_token uuid,
  event_kind text not null check (event_kind in ('acquired','renewed','released','expired_takeover','renewal_rejected','release_rejected')),
  lease_expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index communication_gateway_source_lease_events_idx on atlas.communication_gateway_source_lease_events(connected_source_id,occurred_at desc,id);
comment on table atlas.communication_gateway_source_lease_events is 'Append-only accounting of gateway source lease transitions. Lease state is mutable runtime coordination; this event table preserves execution-custody history.';

create trigger communication_gateway_source_lease_events_append_only_v1 before update or delete on atlas.communication_gateway_source_lease_events for each row execute function atlas.prevent_institutional_response_history_mutation_v1();

create or replace function atlas.acquire_communication_gateway_source_lease_service_v1(p_connected_source_id uuid,p_gateway_instance_key text,p_lease_seconds integer default 90,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_existing atlas.communication_gateway_source_leases%rowtype; v_token uuid; v_expires timestamptz; v_kind text;
begin
  if btrim(coalesce(p_gateway_instance_key,''))='' or p_lease_seconds<30 or p_lease_seconds>300 then raise exception 'Valid gateway instance and lease duration are required.' using errcode='22023'; end if;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and custodian_organization_id is not null and authorization_state in ('pending','connected','error','reauthorization_required');
  if v_source.id is null then raise exception 'Institutional connected source is unavailable for gateway execution.' using errcode='42501'; end if;
  select * into v_existing from atlas.communication_gateway_source_leases where connected_source_id=v_source.id for update;
  if v_existing.connected_source_id is not null and v_existing.lease_expires_at>now() and v_existing.gateway_instance_key is distinct from btrim(p_gateway_instance_key) then
    return jsonb_build_object('contractVersion','communication_gateway_source_lease_v1','acquired',false,'connectedSourceId',v_source.id,'currentGatewayInstanceKey',v_existing.gateway_instance_key,'leaseExpiresAt',v_existing.lease_expires_at);
  end if;
  v_kind:=case when v_existing.connected_source_id is not null and v_existing.lease_expires_at<=now() and v_existing.gateway_instance_key is distinct from btrim(p_gateway_instance_key) then 'expired_takeover' else 'acquired' end;
  v_token:=gen_random_uuid(); v_expires:=now()+make_interval(secs=>p_lease_seconds);
  insert into atlas.communication_gateway_source_leases(connected_source_id,gateway_instance_key,lease_token,lease_expires_at,acquired_at,renewed_at,metadata,updated_at)
  values(v_source.id,btrim(p_gateway_instance_key),v_token,v_expires,now(),now(),coalesce(p_metadata,'{}'::jsonb),now())
  on conflict (connected_source_id) do update set gateway_instance_key=excluded.gateway_instance_key,lease_token=excluded.lease_token,lease_expires_at=excluded.lease_expires_at,acquired_at=case when atlas.communication_gateway_source_leases.gateway_instance_key=excluded.gateway_instance_key then atlas.communication_gateway_source_leases.acquired_at else now() end,renewed_at=now(),metadata=atlas.communication_gateway_source_leases.metadata||excluded.metadata,updated_at=now();
  insert into atlas.communication_gateway_source_lease_events(connected_source_id,gateway_instance_key,lease_token,event_kind,lease_expires_at,metadata)
  values(v_source.id,btrim(p_gateway_instance_key),v_token,v_kind,v_expires,coalesce(p_metadata,'{}'::jsonb));
  return jsonb_build_object('contractVersion','communication_gateway_source_lease_v1','acquired',true,'connectedSourceId',v_source.id,'gatewayInstanceKey',btrim(p_gateway_instance_key),'leaseToken',v_token,'leaseExpiresAt',v_expires,'eventKind',v_kind);
end;$function$;

create or replace function atlas.renew_communication_gateway_source_lease_service_v1(p_connected_source_id uuid,p_gateway_instance_key text,p_lease_token uuid,p_lease_seconds integer default 90,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_existing atlas.communication_gateway_source_leases%rowtype; v_expires timestamptz;
begin
  if p_lease_token is null or btrim(coalesce(p_gateway_instance_key,''))='' or p_lease_seconds<30 or p_lease_seconds>300 then raise exception 'Valid gateway lease renewal inputs are required.' using errcode='22023'; end if;
  select * into v_existing from atlas.communication_gateway_source_leases where connected_source_id=p_connected_source_id for update;
  if v_existing.connected_source_id is null or v_existing.gateway_instance_key is distinct from btrim(p_gateway_instance_key) or v_existing.lease_token is distinct from p_lease_token or v_existing.lease_expires_at<=now() then
    insert into atlas.communication_gateway_source_lease_events(connected_source_id,gateway_instance_key,lease_token,event_kind,lease_expires_at,metadata)
    values(p_connected_source_id,btrim(p_gateway_instance_key),p_lease_token,'renewal_rejected',case when v_existing.connected_source_id is null then null else v_existing.lease_expires_at end,coalesce(p_metadata,'{}'::jsonb));
    return jsonb_build_object('contractVersion','communication_gateway_source_lease_renewal_v1','renewed',false,'connectedSourceId',p_connected_source_id,'gatewayInstanceKey',btrim(p_gateway_instance_key),'reason','lease_missing_changed_or_expired');
  end if;
  v_expires:=now()+make_interval(secs=>p_lease_seconds);
  update atlas.communication_gateway_source_leases set lease_expires_at=v_expires,renewed_at=now(),metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where connected_source_id=p_connected_source_id;
  insert into atlas.communication_gateway_source_lease_events(connected_source_id,gateway_instance_key,lease_token,event_kind,lease_expires_at,metadata)
  values(p_connected_source_id,btrim(p_gateway_instance_key),p_lease_token,'renewed',v_expires,coalesce(p_metadata,'{}'::jsonb));
  return jsonb_build_object('contractVersion','communication_gateway_source_lease_renewal_v1','renewed',true,'connectedSourceId',p_connected_source_id,'gatewayInstanceKey',btrim(p_gateway_instance_key),'leaseToken',p_lease_token,'leaseExpiresAt',v_expires);
end;$function$;

create or replace function atlas.release_communication_gateway_source_lease_service_v1(p_connected_source_id uuid,p_gateway_instance_key text,p_lease_token uuid,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_existing atlas.communication_gateway_source_leases%rowtype;
begin
  select * into v_existing from atlas.communication_gateway_source_leases where connected_source_id=p_connected_source_id for update;
  if v_existing.connected_source_id is null or v_existing.gateway_instance_key is distinct from btrim(coalesce(p_gateway_instance_key,'')) or v_existing.lease_token is distinct from p_lease_token then
    insert into atlas.communication_gateway_source_lease_events(connected_source_id,gateway_instance_key,lease_token,event_kind,lease_expires_at,metadata)
    values(p_connected_source_id,btrim(coalesce(p_gateway_instance_key,'')),p_lease_token,'release_rejected',case when v_existing.connected_source_id is null then null else v_existing.lease_expires_at end,coalesce(p_metadata,'{}'::jsonb));
    return jsonb_build_object('contractVersion','communication_gateway_source_lease_release_v1','released',false,'connectedSourceId',p_connected_source_id);
  end if;
  delete from atlas.communication_gateway_source_leases where connected_source_id=p_connected_source_id;
  insert into atlas.communication_gateway_source_lease_events(connected_source_id,gateway_instance_key,lease_token,event_kind,lease_expires_at,metadata)
  values(p_connected_source_id,btrim(p_gateway_instance_key),p_lease_token,'released',v_existing.lease_expires_at,coalesce(p_metadata,'{}'::jsonb));
  return jsonb_build_object('contractVersion','communication_gateway_source_lease_release_v1','released',true,'connectedSourceId',p_connected_source_id);
end;$function$;

alter table atlas.communication_gateway_source_leases enable row level security;
alter table atlas.communication_gateway_source_lease_events enable row level security;
revoke all on atlas.communication_gateway_source_leases,atlas.communication_gateway_source_lease_events from public,anon,authenticated;
grant all on atlas.communication_gateway_source_leases,atlas.communication_gateway_source_lease_events to service_role;
revoke all on function atlas.acquire_communication_gateway_source_lease_service_v1(uuid,text,integer,jsonb),atlas.renew_communication_gateway_source_lease_service_v1(uuid,text,uuid,integer,jsonb),atlas.release_communication_gateway_source_lease_service_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function atlas.acquire_communication_gateway_source_lease_service_v1(uuid,text,integer,jsonb),atlas.renew_communication_gateway_source_lease_service_v1(uuid,text,uuid,integer,jsonb),atlas.release_communication_gateway_source_lease_service_v1(uuid,text,uuid,jsonb) to service_role;

commit;