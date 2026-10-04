-- Atlas canonical-party bulk ingestion control plane v1.
-- Reuses local_intel.ingestion_sources as the configured source registry.

create table if not exists local_intel.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  ingestion_source_id uuid not null
    references local_intel.ingestion_sources(id) on delete restrict,
  run_key text not null,
  run_state text not null default 'running',
  parser_key text not null,
  parser_version text not null,
  acquisition_method text,
  cursor_start text,
  cursor_end text,
  window_start timestamptz,
  window_end timestamptz,
  records_seen integer not null default 0,
  records_extracted integer not null default 0,
  records_rejected integer not null default 0,
  records_resolved integer not null default 0,
  records_admitted integer not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ingestion_source_id,run_key),
  constraint ingestion_runs_run_key_v1
    check (btrim(run_key) <> ''),
  constraint ingestion_runs_state_v1
    check (run_state in ('running','succeeded','partial','failed','cancelled')),
  constraint ingestion_runs_parser_key_v1
    check (parser_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ingestion_runs_parser_version_v1
    check (btrim(parser_version) <> ''),
  constraint ingestion_runs_counts_v1
    check (
      records_seen >= 0
      and records_extracted >= 0
      and records_rejected >= 0
      and records_resolved >= 0
      and records_admitted >= 0
    ),
  constraint ingestion_runs_window_v1
    check (window_end is null or window_start is null or window_end >= window_start),
  constraint ingestion_runs_finish_shape_v1
    check (
      (run_state='running' and finished_at is null)
      or
      (run_state<>'running' and finished_at is not null)
    ),
  constraint ingestion_runs_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists ingestion_runs_source_started_idx_v1
  on local_intel.ingestion_runs(ingestion_source_id,started_at desc);

comment on table local_intel.ingestion_runs is
  'One bounded execution against a configured ingestion source. Preserves parser/version, cursor/window, counts, and completion state without making source records canonical truth.';

create table if not exists local_intel.ingestion_raw_object_manifests (
  id uuid primary key default gen_random_uuid(),
  ingestion_run_id uuid not null
    references local_intel.ingestion_runs(id) on delete cascade,
  source_object_key text,
  storage_uri text not null,
  hash_algorithm text not null default 'sha256',
  content_hash text not null,
  mime_type text,
  byte_size bigint,
  retrieved_at timestamptz not null default now(),
  object_state text not null default 'available',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (ingestion_run_id,storage_uri),
  constraint ingestion_raw_objects_storage_uri_v1
    check (btrim(storage_uri) <> ''),
  constraint ingestion_raw_objects_hash_algorithm_v1
    check (hash_algorithm ~ '^[a-z0-9][a-z0-9_-]*$'),
  constraint ingestion_raw_objects_hash_v1
    check (length(content_hash) >= 32),
  constraint ingestion_raw_objects_byte_size_v1
    check (byte_size is null or byte_size >= 0),
  constraint ingestion_raw_objects_state_v1
    check (object_state in ('available','missing','invalid')),
  constraint ingestion_raw_objects_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists ingestion_raw_objects_hash_idx_v1
  on local_intel.ingestion_raw_object_manifests(hash_algorithm,content_hash);

comment on table local_intel.ingestion_raw_object_manifests is
  'Manifest only for immutable raw ingestion artifacts. Bytes remain in object storage; Postgres keeps URI, hash, MIME/size, retrieval time, and provenance metadata.';

create table if not exists local_intel.ingestion_observations (
  id uuid primary key default gen_random_uuid(),
  ingestion_run_id uuid not null
    references local_intel.ingestion_runs(id) on delete cascade,
  raw_object_manifest_id uuid
    references local_intel.ingestion_raw_object_manifests(id) on delete set null,
  source_record_key text not null,
  observation_kind text not null,
  proposed_entity_type text,
  proposed_display_name text,
  source_locator text,
  payload_hash text,
  observation_payload jsonb not null default '{}'::jsonb,
  extracted_claims jsonb not null default '[]'::jsonb,
  observed_at timestamptz not null default now(),
  observation_state text not null default 'extracted',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (ingestion_run_id,source_record_key,observation_kind),
  constraint ingestion_observations_record_key_v1
    check (btrim(source_record_key) <> ''),
  constraint ingestion_observations_kind_v1
    check (observation_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ingestion_observations_entity_type_v1
    check (
      proposed_entity_type is null
      or proposed_entity_type in (
        'person','business','organization','nonprofit','government','place'
      )
    ),
  constraint ingestion_observations_payload_hash_v1
    check (payload_hash is null or length(payload_hash) >= 32),
  constraint ingestion_observations_payload_v1
    check (jsonb_typeof(observation_payload)='object'),
  constraint ingestion_observations_claims_v1
    check (jsonb_typeof(extracted_claims)='array'),
  constraint ingestion_observations_state_v1
    check (observation_state in ('extracted','resolved','admitted','rejected')),
  constraint ingestion_observations_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists ingestion_observations_run_state_idx_v1
  on local_intel.ingestion_observations(
    ingestion_run_id,observation_state,source_record_key
  );

comment on table local_intel.ingestion_observations is
  'Generic parser output. An observation is source testimony, not canonical truth. extracted_claims are candidate claims awaiting resolution and governed admission.';

create table if not exists local_intel.ingestion_observation_resolutions (
  id uuid primary key default gen_random_uuid(),
  ingestion_observation_id uuid not null
    references local_intel.ingestion_observations(id) on delete cascade,
  resolution_state text not null,
  canonical_entity_id uuid
    references local_intel.entities(id) on delete restrict,
  is_current boolean not null default true,
  resolver_key text not null,
  resolver_version text not null,
  confidence numeric(5,4),
  decision_basis jsonb not null default '{}'::jsonb,
  decided_by text,
  decided_at timestamptz not null default now(),
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_observation_resolutions_state_v1
    check (resolution_state in (
      'resolved_existing','new_entity_candidate','ambiguous','rejected'
    )),
  constraint ingestion_observation_resolutions_entity_shape_v1
    check (
      (resolution_state='resolved_existing' and canonical_entity_id is not null)
      or
      (resolution_state<>'resolved_existing' and canonical_entity_id is null)
    ),
  constraint ingestion_observation_resolutions_current_shape_v1
    check (
      (is_current and superseded_at is null)
      or
      (not is_current and superseded_at is not null)
    ),
  constraint ingestion_observation_resolutions_resolver_key_v1
    check (resolver_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ingestion_observation_resolutions_version_v1
    check (btrim(resolver_version) <> ''),
  constraint ingestion_observation_resolutions_confidence_v1
    check (confidence is null or confidence between 0 and 1),
  constraint ingestion_observation_resolutions_basis_v1
    check (jsonb_typeof(decision_basis)='object'),
  constraint ingestion_observation_resolutions_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists ingestion_observation_resolutions_current_uq_v1
  on local_intel.ingestion_observation_resolutions(ingestion_observation_id)
  where is_current;

create index if not exists ingestion_observation_resolutions_entity_idx_v1
  on local_intel.ingestion_observation_resolutions(canonical_entity_id)
  where is_current and canonical_entity_id is not null;

comment on table local_intel.ingestion_observation_resolutions is
  'Resolution/adjudication history for parser observations. Resolution selects identity state but does not itself admit evidence into canonical Shared Intelligence.';

alter table local_intel.ingestion_runs enable row level security;
alter table local_intel.ingestion_raw_object_manifests enable row level security;
alter table local_intel.ingestion_observations enable row level security;
alter table local_intel.ingestion_observation_resolutions enable row level security;

revoke all on table local_intel.ingestion_runs from public,anon,authenticated;
revoke all on table local_intel.ingestion_raw_object_manifests from public,anon,authenticated;
revoke all on table local_intel.ingestion_observations from public,anon,authenticated;
revoke all on table local_intel.ingestion_observation_resolutions from public,anon,authenticated;

grant select,insert,update,delete on table local_intel.ingestion_runs to service_role;
grant select,insert,update,delete on table local_intel.ingestion_raw_object_manifests to service_role;
grant select,insert,update,delete on table local_intel.ingestion_observations to service_role;
grant select,insert,update,delete on table local_intel.ingestion_observation_resolutions to service_role;

create or replace function local_intel.set_bulk_ingestion_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists ingestion_runs_updated_at_v1
  on local_intel.ingestion_runs;
create trigger ingestion_runs_updated_at_v1
before update on local_intel.ingestion_runs
for each row execute function local_intel.set_bulk_ingestion_updated_at_v1();

create or replace function local_intel.start_ingestion_run_service_v1(
  p_ingestion_source_id uuid,
  p_run_key text,
  p_parser_key text,
  p_parser_version text,
  p_acquisition_method text default null,
  p_cursor_start text default null,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_run local_intel.ingestion_runs%rowtype;
  v_parser text:=lower(btrim(coalesce(p_parser_key,'')));
begin
  if not exists(
    select 1
    from local_intel.ingestion_sources s
    where s.id=p_ingestion_source_id
  ) then
    raise exception 'Configured ingestion source not found.' using errcode='P0002';
  end if;

  if btrim(coalesce(p_run_key,''))='' then
    raise exception 'Run key is required.' using errcode='22023';
  end if;

  if v_parser !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Parser key must be normalized.' using errcode='22023';
  end if;

  if btrim(coalesce(p_parser_version,''))='' then
    raise exception 'Parser version is required.' using errcode='22023';
  end if;

  if p_window_end is not null
     and p_window_start is not null
     and p_window_end<p_window_start then
    raise exception 'Ingestion window end precedes start.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Run metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into local_intel.ingestion_runs(
    ingestion_source_id,run_key,run_state,parser_key,parser_version,
    acquisition_method,cursor_start,window_start,window_end,metadata
  )
  values(
    p_ingestion_source_id,btrim(p_run_key),'running',v_parser,
    btrim(p_parser_version),nullif(btrim(p_acquisition_method),''),
    nullif(btrim(p_cursor_start),''),p_window_start,p_window_end,
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (ingestion_source_id,run_key)
  do nothing
  returning * into v_run;

  if v_run.id is null then
    select * into v_run
    from local_intel.ingestion_runs r
    where r.ingestion_source_id=p_ingestion_source_id
      and r.run_key=btrim(p_run_key);
  end if;

  return jsonb_build_object(
    'contractVersion','ingestion_run_v1',
    'ingestionRunId',v_run.id,
    'ingestionSourceId',v_run.ingestion_source_id,
    'runKey',v_run.run_key,
    'runState',v_run.run_state,
    'parserKey',v_run.parser_key,
    'parserVersion',v_run.parser_version,
    'startedAt',v_run.started_at
  );
end
$function$;

create or replace function local_intel.record_ingestion_raw_object_service_v1(
  p_ingestion_run_id uuid,
  p_storage_uri text,
  p_content_hash text,
  p_hash_algorithm text default 'sha256',
  p_source_object_key text default null,
  p_mime_type text default null,
  p_byte_size bigint default null,
  p_retrieved_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_row local_intel.ingestion_raw_object_manifests%rowtype;
  v_hash_algorithm text:=lower(btrim(coalesce(p_hash_algorithm,'')));
begin
  if not exists(
    select 1
    from local_intel.ingestion_runs r
    where r.id=p_ingestion_run_id
      and r.run_state='running'
  ) then
    raise exception 'Running ingestion run not found.' using errcode='P0002';
  end if;

  if btrim(coalesce(p_storage_uri,''))='' then
    raise exception 'Storage URI is required.' using errcode='22023';
  end if;

  if length(coalesce(p_content_hash,''))<32 then
    raise exception 'Content hash is required.' using errcode='22023';
  end if;

  if v_hash_algorithm !~ '^[a-z0-9][a-z0-9_-]*$' then
    raise exception 'Hash algorithm is invalid.' using errcode='22023';
  end if;

  if p_byte_size is not null and p_byte_size<0 then
    raise exception 'Byte size cannot be negative.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Raw object metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into local_intel.ingestion_raw_object_manifests(
    ingestion_run_id,source_object_key,storage_uri,hash_algorithm,
    content_hash,mime_type,byte_size,retrieved_at,metadata
  )
  values(
    p_ingestion_run_id,nullif(btrim(p_source_object_key),''),
    btrim(p_storage_uri),v_hash_algorithm,btrim(p_content_hash),
    nullif(btrim(p_mime_type),''),p_byte_size,coalesce(p_retrieved_at,now()),
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (ingestion_run_id,storage_uri)
  do update set
    source_object_key=coalesce(
      excluded.source_object_key,
      local_intel.ingestion_raw_object_manifests.source_object_key
    ),
    hash_algorithm=excluded.hash_algorithm,
    content_hash=excluded.content_hash,
    mime_type=coalesce(
      excluded.mime_type,
      local_intel.ingestion_raw_object_manifests.mime_type
    ),
    byte_size=coalesce(
      excluded.byte_size,
      local_intel.ingestion_raw_object_manifests.byte_size
    ),
    retrieved_at=excluded.retrieved_at,
    metadata=local_intel.ingestion_raw_object_manifests.metadata
      || excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','ingestion_raw_object_manifest_v1',
    'rawObjectManifestId',v_row.id,
    'ingestionRunId',v_row.ingestion_run_id,
    'storageUri',v_row.storage_uri,
    'hashAlgorithm',v_row.hash_algorithm,
    'contentHash',v_row.content_hash,
    'objectState',v_row.object_state
  );
end
$function$;

create or replace function local_intel.record_ingestion_observation_service_v1(
  p_ingestion_run_id uuid,
  p_source_record_key text,
  p_observation_kind text,
  p_proposed_entity_type text default null,
  p_proposed_display_name text default null,
  p_raw_object_manifest_id uuid default null,
  p_source_locator text default null,
  p_payload_hash text default null,
  p_observation_payload jsonb default '{}'::jsonb,
  p_extracted_claims jsonb default '[]'::jsonb,
  p_observed_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_observation_kind,'')));
  v_entity_type text:=case
    when p_proposed_entity_type is null then null
    else lower(btrim(p_proposed_entity_type))
  end;
  v_row local_intel.ingestion_observations%rowtype;
begin
  if not exists(
    select 1
    from local_intel.ingestion_runs r
    where r.id=p_ingestion_run_id
      and r.run_state='running'
  ) then
    raise exception 'Running ingestion run not found.' using errcode='P0002';
  end if;

  if p_raw_object_manifest_id is not null
     and not exists(
       select 1
       from local_intel.ingestion_raw_object_manifests o
       where o.id=p_raw_object_manifest_id
         and o.ingestion_run_id=p_ingestion_run_id
     ) then
    raise exception 'Raw object manifest is outside this ingestion run.'
      using errcode='42501';
  end if;

  if btrim(coalesce(p_source_record_key,''))='' then
    raise exception 'Source record key is required.' using errcode='22023';
  end if;

  if v_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Observation kind must be normalized.' using errcode='22023';
  end if;

  if v_entity_type is not null
     and v_entity_type not in (
       'person','business','organization','nonprofit','government','place'
     ) then
    raise exception 'Proposed entity type is invalid.' using errcode='22023';
  end if;

  if p_payload_hash is not null and length(p_payload_hash)<32 then
    raise exception 'Payload hash is too short.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_observation_payload,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_extracted_claims,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Observation payload/claims/metadata have invalid JSON shapes.'
      using errcode='22023';
  end if;

  select * into v_row
  from local_intel.ingestion_observations o
  where o.ingestion_run_id=p_ingestion_run_id
    and o.source_record_key=btrim(p_source_record_key)
    and o.observation_kind=v_kind;

  if v_row.id is not null then
    if v_row.proposed_entity_type is distinct from v_entity_type
       or v_row.proposed_display_name is distinct from nullif(btrim(p_proposed_display_name),'')
       or v_row.raw_object_manifest_id is distinct from p_raw_object_manifest_id
       or v_row.source_locator is distinct from nullif(btrim(p_source_locator),'')
       or v_row.payload_hash is distinct from nullif(btrim(p_payload_hash),'')
       or v_row.observation_payload is distinct from coalesce(p_observation_payload,'{}'::jsonb)
       or v_row.extracted_claims is distinct from coalesce(p_extracted_claims,'[]'::jsonb) then
      raise exception 'Observation key already exists with different parser output.'
        using errcode='23505';
    end if;
  else
    insert into local_intel.ingestion_observations(
      ingestion_run_id,raw_object_manifest_id,source_record_key,
      observation_kind,proposed_entity_type,proposed_display_name,
      source_locator,payload_hash,observation_payload,extracted_claims,
      observed_at,metadata
    )
    values(
      p_ingestion_run_id,p_raw_object_manifest_id,btrim(p_source_record_key),
      v_kind,v_entity_type,nullif(btrim(p_proposed_display_name),''),
      nullif(btrim(p_source_locator),''),nullif(btrim(p_payload_hash),''),
      coalesce(p_observation_payload,'{}'::jsonb),
      coalesce(p_extracted_claims,'[]'::jsonb),
      coalesce(p_observed_at,now()),coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'contractVersion','ingestion_observation_v1',
    'ingestionObservationId',v_row.id,
    'ingestionRunId',v_row.ingestion_run_id,
    'sourceRecordKey',v_row.source_record_key,
    'observationKind',v_row.observation_kind,
    'observationState',v_row.observation_state
  );
end
$function$;

create or replace function local_intel.record_ingestion_observation_resolution_service_v1(
  p_ingestion_observation_id uuid,
  p_resolution_state text,
  p_resolver_key text,
  p_resolver_version text,
  p_canonical_entity_id uuid default null,
  p_confidence numeric default null,
  p_decision_basis jsonb default '{}'::jsonb,
  p_decided_by text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_state text:=lower(btrim(coalesce(p_resolution_state,'')));
  v_resolver text:=lower(btrim(coalesce(p_resolver_key,'')));
  v_previous local_intel.ingestion_observation_resolutions%rowtype;
  v_row local_intel.ingestion_observation_resolutions%rowtype;
begin
  if not exists(
    select 1 from local_intel.ingestion_observations o
    where o.id=p_ingestion_observation_id
  ) then
    raise exception 'Ingestion observation not found.' using errcode='P0002';
  end if;

  if v_state not in (
    'resolved_existing','new_entity_candidate','ambiguous','rejected'
  ) then
    raise exception 'Invalid resolution state.' using errcode='22023';
  end if;

  if (v_state='resolved_existing') <> (p_canonical_entity_id is not null) then
    raise exception 'Canonical entity is required only for resolved_existing.'
      using errcode='22023';
  end if;

  if p_canonical_entity_id is not null
     and not exists(
       select 1 from local_intel.entities e where e.id=p_canonical_entity_id
     ) then
    raise exception 'Canonical entity not found.' using errcode='P0002';
  end if;

  if v_resolver !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_resolver_version,''))='' then
    raise exception 'Resolver key/version are required.' using errcode='22023';
  end if;

  if p_confidence is not null and (p_confidence<0 or p_confidence>1) then
    raise exception 'Resolution confidence must be between 0 and 1.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_decision_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Resolution basis/metadata must be JSON objects.'
      using errcode='22023';
  end if;

  select * into v_previous
  from local_intel.ingestion_observation_resolutions r
  where r.ingestion_observation_id=p_ingestion_observation_id
    and r.is_current
  limit 1;

  if v_previous.id is not null then
    update local_intel.ingestion_observation_resolutions
    set is_current=false,
        superseded_at=now()
    where id=v_previous.id;
  end if;

  insert into local_intel.ingestion_observation_resolutions(
    ingestion_observation_id,resolution_state,canonical_entity_id,
    is_current,resolver_key,resolver_version,confidence,decision_basis,
    decided_by,metadata
  )
  values(
    p_ingestion_observation_id,v_state,p_canonical_entity_id,true,
    v_resolver,btrim(p_resolver_version),p_confidence,
    coalesce(p_decision_basis,'{}'::jsonb),
    nullif(btrim(p_decided_by),''),coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_row;

  update local_intel.ingestion_observations
  set observation_state=case
    when v_state='rejected' then 'rejected'
    else 'resolved'
  end
  where id=p_ingestion_observation_id;

  return jsonb_build_object(
    'contractVersion','ingestion_observation_resolution_v1',
    'resolutionId',v_row.id,
    'ingestionObservationId',v_row.ingestion_observation_id,
    'resolutionState',v_row.resolution_state,
    'canonicalEntityId',v_row.canonical_entity_id,
    'confidence',v_row.confidence,
    'isCurrent',v_row.is_current
  );
end
$function$;

create or replace function local_intel.complete_ingestion_run_service_v1(
  p_ingestion_run_id uuid,
  p_run_state text,
  p_records_seen integer default null,
  p_cursor_end text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_state text:=lower(btrim(coalesce(p_run_state,'')));
  v_run local_intel.ingestion_runs%rowtype;
  v_extracted integer;
  v_rejected integer;
  v_resolved integer;
  v_admitted integer;
begin
  if v_state not in ('succeeded','partial','failed','cancelled') then
    raise exception 'Invalid terminal ingestion run state.' using errcode='22023';
  end if;

  if p_records_seen is not null and p_records_seen<0 then
    raise exception 'Records seen cannot be negative.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Run metadata must be a JSON object.' using errcode='22023';
  end if;

  select
    count(*)::integer,
    count(*) filter (where observation_state='rejected')::integer,
    count(*) filter (where observation_state in ('resolved','admitted'))::integer,
    count(*) filter (where observation_state='admitted')::integer
  into v_extracted,v_rejected,v_resolved,v_admitted
  from local_intel.ingestion_observations o
  where o.ingestion_run_id=p_ingestion_run_id;

  update local_intel.ingestion_runs r
  set run_state=v_state,
      records_seen=coalesce(p_records_seen,r.records_seen),
      records_extracted=coalesce(v_extracted,0),
      records_rejected=coalesce(v_rejected,0),
      records_resolved=coalesce(v_resolved,0),
      records_admitted=coalesce(v_admitted,0),
      cursor_end=coalesce(nullif(btrim(p_cursor_end),''),r.cursor_end),
      finished_at=now(),
      metadata=r.metadata || coalesce(p_metadata,'{}'::jsonb),
      updated_at=now()
  where r.id=p_ingestion_run_id
    and r.run_state='running'
  returning * into v_run;

  if v_run.id is null then
    raise exception 'Running ingestion run not found.' using errcode='P0002';
  end if;

  return jsonb_build_object(
    'contractVersion','ingestion_run_completion_v1',
    'ingestionRunId',v_run.id,
    'runState',v_run.run_state,
    'recordsSeen',v_run.records_seen,
    'recordsExtracted',v_run.records_extracted,
    'recordsRejected',v_run.records_rejected,
    'recordsResolved',v_run.records_resolved,
    'recordsAdmitted',v_run.records_admitted,
    'finishedAt',v_run.finished_at
  );
end
$function$;

revoke all on function local_intel.start_ingestion_run_service_v1(
  uuid,text,text,text,text,text,timestamptz,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.start_ingestion_run_service_v1(
  uuid,text,text,text,text,text,timestamptz,timestamptz,jsonb
) to service_role;

revoke all on function local_intel.record_ingestion_raw_object_service_v1(
  uuid,text,text,text,text,text,bigint,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.record_ingestion_raw_object_service_v1(
  uuid,text,text,text,text,text,bigint,timestamptz,jsonb
) to service_role;

revoke all on function local_intel.record_ingestion_observation_service_v1(
  uuid,text,text,text,text,uuid,text,text,jsonb,jsonb,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.record_ingestion_observation_service_v1(
  uuid,text,text,text,text,uuid,text,text,jsonb,jsonb,timestamptz,jsonb
) to service_role;

revoke all on function local_intel.record_ingestion_observation_resolution_service_v1(
  uuid,text,text,text,uuid,numeric,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.record_ingestion_observation_resolution_service_v1(
  uuid,text,text,text,uuid,numeric,jsonb,text,jsonb
) to service_role;

revoke all on function local_intel.complete_ingestion_run_service_v1(
  uuid,text,integer,text,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.complete_ingestion_run_service_v1(
  uuid,text,integer,text,jsonb
) to service_role;
