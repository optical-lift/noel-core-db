-- Atlas connected-source provider observation custody v1.
--
-- Provider records preserved here remain source evidence. They do not become Money,
-- Registration, Work, identity, or other Atlas domain truth merely by being observed.

create table if not exists atlas.connected_source_observations (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
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
begin
  if p_connected_source_id is null or v_kind = '' or v_key = '' then
    raise exception 'Connected source and provider object identity are required.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' or jsonb_typeof(v_provenance) <> 'object' then
    raise exception 'Provider payload and provenance must be JSON objects.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from atlas.connected_sources source
    where source.id = p_connected_source_id and source.authorization_state = 'connected'
  ) then
    raise exception 'Provider observations require a connected source.' using errcode = '55000';
  end if;

  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'utf8'), 'sha256'), 'hex');

  insert into atlas.connected_source_observations (
    connected_source_id, provider_object_kind, provider_object_key,
    provider_created_at, observed_at, payload, payload_sha256, provenance
  ) values (
    p_connected_source_id, v_kind, v_key,
    p_provider_created_at, v_observed_at, v_payload, v_hash, v_provenance
  )
  on conflict (connected_source_id, provider_object_kind, provider_object_key, payload_sha256) do nothing
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

create or replace function atlas.record_connected_source_observation_batch_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_records jsonb,
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
  v_records jsonb := coalesce(p_records, '[]'::jsonb);
  v_provenance jsonb := coalesce(p_provenance, '{}'::jsonb);
  v_observed_at timestamptz := coalesce(p_observed_at, now());
  v_record jsonb;
  v_key text;
  v_payload jsonb;
  v_created_at timestamptz;
  v_hash text;
  v_inserted integer := 0;
  v_total integer := 0;
begin
  if p_connected_source_id is null or v_kind = '' or jsonb_typeof(v_records) <> 'array' then
    raise exception 'Connected source, provider object kind, and record array are required.' using errcode = '22023';
  end if;
  if jsonb_array_length(v_records) > 500 then
    raise exception 'A provider observation batch may contain at most 500 records.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_provenance) <> 'object' then
    raise exception 'Provider provenance must be a JSON object.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from atlas.connected_sources source
    where source.id = p_connected_source_id and source.authorization_state = 'connected'
  ) then
    raise exception 'Provider observations require a connected source.' using errcode = '55000';
  end if;

  for v_record in select value from jsonb_array_elements(v_records)
  loop
    v_total := v_total + 1;
    v_key := btrim(coalesce(v_record->>'key',''));
    v_payload := coalesce(v_record->'payload','{}'::jsonb);
    v_created_at := case
      when nullif(v_record->>'providerCreatedAt','') is null then null
      else (v_record->>'providerCreatedAt')::timestamptz
    end;

    if v_key = '' or jsonb_typeof(v_payload) <> 'object' then
      raise exception 'Each provider record requires a key and object payload.' using errcode = '22023';
    end if;

    v_hash := encode(extensions.digest(convert_to(v_payload::text, 'utf8'), 'sha256'), 'hex');

    insert into atlas.connected_source_observations (
      connected_source_id, provider_object_kind, provider_object_key,
      provider_created_at, observed_at, payload, payload_sha256, provenance
    ) values (
      p_connected_source_id, v_kind, v_key,
      v_created_at, v_observed_at, v_payload, v_hash, v_provenance
    )
    on conflict (connected_source_id, provider_object_kind, provider_object_key, payload_sha256) do nothing;

    if found then v_inserted := v_inserted + 1; end if;
  end loop;

  return jsonb_build_object(
    'connectedSourceId',p_connected_source_id,
    'providerObjectKind',v_kind,
    'recordCount',v_total,
    'insertedCount',v_inserted,
    'duplicateCount',v_total-v_inserted
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
  with scoped as (
    select observation.*
    from atlas.connected_source_observations observation
    where observation.connected_source_id = p_connected_source_id
  ), kind_counts as (
    select provider_object_kind, count(distinct provider_object_key) as object_count
    from scoped
    group by provider_object_kind
  )
  select jsonb_build_object(
    'connectedSourceId',p_connected_source_id,
    'observationCount',(select count(*) from scoped),
    'objectCount',(select count(distinct (provider_object_kind,provider_object_key)) from scoped),
    'latestObservedAt',(select max(observed_at) from scoped),
    'kinds',coalesce((select jsonb_object_agg(provider_object_kind,object_count) from kind_counts),'{}'::jsonb)
  );
$function$;

comment on table atlas.connected_source_observations is
'Append-only snapshots of external provider records observed through a governed connected source. Source evidence only; not canonical domain truth.';
comment on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) is
'Service-only append-only provider observation intake. Identical snapshots are idempotent by source/object/payload hash.';
comment on function atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb) is
'Service-only bounded batch provider observation intake for one source/object kind.';

revoke all on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb) from public, anon, authenticated;
revoke all on function atlas.connected_source_observation_summary_service_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb) to service_role;
grant execute on function atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb) to service_role;
grant execute on function atlas.connected_source_observation_summary_service_v1(uuid) to service_role;

insert into atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'atlas.record_connected_source_observation_service_v1(uuid,text,text,jsonb,timestamptz,timestamptz,jsonb)',
  'service_internal','verified','active',false,true,true,1,1,
  jsonb_build_object('source','atlas_connected_source_observations_v1','purpose','Preserve one append-only external provider record snapshot behind a connected source.','boundary','Service-role provider adapters only.','truthBoundary','Provider observation remains source evidence, not Atlas domain truth.'),false
),
(
  'atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)',
  'service_internal','verified','active',false,true,true,1,1,
  jsonb_build_object('source','atlas_connected_source_observations_v1','purpose','Preserve a bounded batch of provider records behind one connected source.','boundary','Service-role provider adapters only; batches are limited to 500 records.','truthBoundary','Provider observations remain source evidence, not Atlas domain truth.'),false
),
(
  'atlas.connected_source_observation_summary_service_v1(uuid)',
  'service_internal','verified','active',false,true,true,1,1,
  jsonb_build_object('source','atlas_connected_source_observations_v1','purpose','Summarize acquired provider evidence coverage.','boundary','Service-role only.','truthBoundary','Coverage statistics describe source evidence only.'),false
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
