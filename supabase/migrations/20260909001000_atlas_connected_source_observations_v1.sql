-- Atlas connected-source provider observation custody v1.
--
-- This is source evidence only. A Stripe Checkout Session, customer, payment intent,
-- or any future provider record does not become Money, Registration, Work, identity,
-- or other Atlas domain truth merely because it was observed here.

create table if not exists atlas.connected_source_observations (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null
    references atlas.connected_sources(id) on delete cascade,
  provider_object_kind text not null,
  provider_object_key text not null,
  provider_created_at timestamptz,
  observed_at timestamptz not null default now(),
  payload jsonb not null,
  payload_sha256 text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint connected_source_observations_kind_check check (btrim(provider_object_kind) <> ''),
  constraint connected_source_observations_key_check check (btrim(provider_object_key) <> ''),
  constraint connected_source_observations_payload_object_check check (jsonb_typeof(payload) = 'object'),
  constraint connected_source_observations_provenance_object_check check (jsonb_typeof(provenance) = 'object'),
  unique (connected_source_id, provider_object_kind, provider_object_key, payload_sha256)
);

create index if not exists connected_source_observations_source_time_idx
  on atlas.connected_source_observations (connected_source_id, observed_at desc, id);

create index if not exists connected_source_observations_object_idx
  on atlas.connected_source_observations (connected_source_id, provider_object_kind, provider_object_key, observed_at desc);

alter table atlas.connected_source_observations enable row level security;
revoke all on table atlas.connected_source_observations from public, anon, authenticated;
grant select, insert on table atlas.connected_source_observations to service_role;

create or replace function atlas.record_connected_source_observation_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_payload jsonb,
  p_provider_created_at timestamptz default null,
  p_observed_at timestamptz default now(),
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, extensions
as $function$
declare
  v_kind text := btrim(coalesce(p_provider_object_kind, ''));
  v_key text := btrim(coalesce(p_provider_object_key, ''));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_provenance jsonb := coalesce(p_provenance, '{}'::jsonb);
  v_observed_at timestamptz := coalesce(p_observed_at, now());
  v_hash text;
  v_observation_id uuid;
  v_inserted boolean := false;
  v_source atlas.connected_sources%rowtype;
begin
  if p_connected_source_id is null or v_kind = '' or v_key = '' then
    raise exception 'Connected source and provider object identity are required.' using errcode = '22023';
  end if;

  if jsonb_typeof(v_payload) <> 'object' or jsonb_typeof(v_provenance) <> 'object' then
    raise exception 'Provider payload and provenance must be JSON objects.' using errcode = '22023';
  end if;

  select source.* into v_source
  from atlas.connected_sources source
  where source.id = p_connected_source_id;

  if v_source.id is null then
    raise exception 'Connected source is unavailable.' using errcode = '22023';
  end if;

  if v_source.authorization_state <> 'connected' then
    raise exception 'Provider observations require a connected source.' using errcode = '55000';
  end if;

  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'utf8'), 'sha256'), 'hex');

  insert into atlas.connected_source_observations (
    connected_source_id,
    provider_object_kind,
    provider_object_key,
    provider_created_at,
    observed_at,
    payload,
    payload_sha256,
    provenance
  ) values (
    p_connected_source_id,
    v_kind,
    v_key,
    p_provider_created_at,
    v_observed_at,
    v_payload,
    v_hash,
    v_provenance
  )
  on conflict (connected_source_id, provider_object_kind, provider_object_key, payload_sha256)
    do nothing
  returning id into v_observation_id;

  if v_observation_id is null then
    select observation.id into v_observation_id
    from atlas.connected_source_observations observation
    where observation.connected_source_id = p_connected_source_id
      and observation.provider_object_kind = v_kind
      and observation.provider_object_key = v_key
      and observation.payload_sha256 = v_hash
    limit 1;
  else
    v_inserted := true;
  end if;

  return jsonb_build_object(
    'observationId',v_observation_id,
    'connectedSourceId',p_connected_source_id,
    'providerObjectKind',v_kind,
    'providerObjectKey',v_key,
    'payloadSha256',v_hash,
    'inserted',v_inserted
  );
end;
$function$;

create or replace function atlas.connected_source_observation_summary_service_v1(
  p_connected_source_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select jsonb_build_object(
    'connectedSourceId',p_connected_source_id,
    'observationCount',count(*),
    'objectCount',count(distinct (observation.provider_object_kind, observation.provider_object_key)),
    'latestObservedAt',max(observation.observed_at),
    'kinds',coalesce(
      jsonb_object_agg(kind_row.provider_object_kind, kind_row.object_count)
        filter (where kind_row.provider_object_kind is not null),
      '{}'::jsonb
    )
  )
  from atlas.connected_source_observations observation
  left join lateral (
    select observation.provider_object_kind, count(distinct observation.provider_object_key) as object_count
  ) kind_row on true
  where observation.connected_source_id = p_connected_source_id;
$function$;

comment on table atlas.connected_source_observations is
'Append-only snapshots of external provider records observed through a governed connected source. Source evidence only; not canonical domain truth.';

comment on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) is
'Service-only append-only provider observation intake. Identical snapshots are idempotent by source/object/payload hash.';

revoke all on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) from public, anon, authenticated;
revoke all on function atlas.connected_source_observation_summary_service_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) to service_role;
grant execute on function atlas.connected_source_observation_summary_service_v1(uuid) to service_role;

insert into atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb)',
  'service_internal','verified','active',false,true,true,1,1,
  jsonb_build_object(
    'source','atlas_connected_source_observations_v1',
    'purpose','Preserve append-only external provider record snapshots behind a connected source.',
    'boundary','Service-role provider adapters only. Browser callers cannot write raw provider observations.',
    'truthBoundary','A provider observation remains source evidence and cannot itself establish Money, Registration, Work, identity, or other Atlas domain truth.'
  ),false
),
(
  'atlas.connected_source_observation_summary_service_v1(uuid)',
  'service_internal','verified','active',false,true,true,1,1,
  jsonb_build_object(
    'source','atlas_connected_source_observations_v1',
    'purpose','Summarize provider observation coverage for server-side implementation/read adapters.',
    'boundary','Service-role only; raw payload access remains contained.',
    'truthBoundary','Coverage statistics describe acquired provider evidence only.'
  ),false
)
on conflict (signature) do update
set classification=excluded.classification,
    confidence=excluded.confidence,
    review_status=excluded.review_status,
    authenticated_execute_expected=excluded.authenticated_execute_expected,
    security_definer_expected=excluded.security_definer_expected,
    service_execute_expected=excluded.service_execute_expected,
    caller_count=excluded.caller_count,
    policy_reference_count=excluded.policy_reference_count,
    evidence=excluded.evidence,
    anonymous_execute_expected=excluded.anonymous_execute_expected,
    reviewed_at=now();
