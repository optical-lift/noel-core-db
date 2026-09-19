-- Atlas Capture + Intelligence Kernel v1
--
-- First post-fence persistence/runtime contract for:
--   raw capture -> durable interpretation job -> reasoning run -> model inference
--   -> human adjudication.
--
-- This migration deliberately stops BEFORE domain promotion. It does not create
-- a generic fact mutation path, identity merge, transaction mutation, task, or
-- Owner Obligation. Those consequences must enter their owning operation
-- contracts in later migrations.

BEGIN;

-- ---------------------------------------------------------------------------
-- Core capture evidence
-- ---------------------------------------------------------------------------

create table if not exists atlas.capture_observations (
  id uuid primary key default gen_random_uuid(),
  scope_kind text not null check (scope_kind in ('person','organization')),
  scope_id uuid not null,
  created_by_user_id uuid not null references auth.users(id) on delete restrict,
  source_kind text not null default 'human_capture',
  source_actor_user_id uuid null references auth.users(id) on delete restrict,
  effective_actor_user_id uuid null references auth.users(id) on delete restrict,
  capture_surface text not null default 'CAPT-01',
  content_kind text not null check (content_kind in ('text','voice_transcript','file_reference')),
  raw_text text null,
  raw_object_ref text null,
  raw_metadata jsonb not null default '{}'::jsonb,
  content_hash text not null,
  content_hash_algorithm text not null default 'sha256',
  client_request_id text null,
  captured_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  retention_class text not null default 'standard',
  check (btrim(source_kind) <> ''),
  check (btrim(capture_surface) <> ''),
  check (jsonb_typeof(raw_metadata) = 'object'),
  check (btrim(content_hash) <> ''),
  check (btrim(content_hash_algorithm) <> ''),
  check (client_request_id is null or btrim(client_request_id) <> ''),
  check (
    (content_kind in ('text','voice_transcript') and raw_text is not null and btrim(raw_text) <> '')
    or (content_kind='file_reference' and raw_object_ref is not null and btrim(raw_object_ref) <> '')
  ),
  check (raw_text is null or char_length(raw_text) <= 100000)
);

create unique index if not exists capture_observations_client_request_uidx
  on atlas.capture_observations (scope_kind, scope_id, created_by_user_id, client_request_id)
  where client_request_id is not null;

create index if not exists capture_observations_creator_idx
  on atlas.capture_observations (created_by_user_id, created_at desc);

create index if not exists capture_observations_scope_idx
  on atlas.capture_observations (scope_kind, scope_id, created_at desc);

comment on table atlas.capture_observations is
  'Append-only raw capture evidence. Atlas first preserves what was received; semantic interpretation remains downstream.';

-- ---------------------------------------------------------------------------
-- Durable DB-backed interpretation outbox / queue
-- ---------------------------------------------------------------------------

create table if not exists atlas.capture_interpretation_jobs (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references atlas.capture_observations(id) on delete restrict,
  job_type text not null default 'interpret_capture_v1',
  schema_version text not null default 'capture_interpretation_v1',
  status text not null default 'queued'
    check (status in ('queued','running','succeeded','failed','cancelled')),
  requested_by_user_id uuid null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  started_at timestamptz null,
  finished_at timestamptz null,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts >= 1),
  next_attempt_at timestamptz null,
  last_error_class text null,
  last_error_safe_message text null,
  latest_reasoning_run_id uuid null,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(job_type) <> ''),
  check (btrim(schema_version) <> ''),
  check (btrim(idempotency_key) <> ''),
  unique (observation_id, job_type, schema_version),
  unique (idempotency_key)
);

create index if not exists capture_interpretation_jobs_queue_idx
  on atlas.capture_interpretation_jobs (status, next_attempt_at, requested_at);

comment on table atlas.capture_interpretation_jobs is
  'Durable interpretation outbox/queue. Capture persistence does not depend on model success.';

-- ---------------------------------------------------------------------------
-- Reasoning provenance + structured model proposals
-- ---------------------------------------------------------------------------

create table if not exists atlas.reasoning_runs (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references atlas.capture_observations(id) on delete restrict,
  job_id uuid not null references atlas.capture_interpretation_jobs(id) on delete restrict,
  purpose text not null default 'capture_interpretation_v1',
  model_provider text not null,
  model_id text not null,
  model_version_or_snapshot text null,
  router_policy_version text not null,
  prompt_contract_version text not null,
  output_schema_version text not null,
  tool_registry_version text not null,
  context_manifest jsonb not null default '[]'::jsonb,
  structured_result jsonb null,
  status text not null default 'running'
    check (status in ('running','succeeded','failed','cancelled')),
  started_at timestamptz not null default now(),
  finished_at timestamptz null,
  usage_metadata jsonb not null default '{}'::jsonb,
  safe_error jsonb null,
  parent_reasoning_run_id uuid null references atlas.reasoning_runs(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (btrim(purpose) <> ''),
  check (btrim(model_provider) <> ''),
  check (btrim(model_id) <> ''),
  check (btrim(router_policy_version) <> ''),
  check (btrim(prompt_contract_version) <> ''),
  check (btrim(output_schema_version) <> ''),
  check (btrim(tool_registry_version) <> ''),
  check (jsonb_typeof(context_manifest) = 'array'),
  check (structured_result is null or jsonb_typeof(structured_result) = 'object'),
  check (jsonb_typeof(usage_metadata) = 'object'),
  check (safe_error is null or jsonb_typeof(safe_error) = 'object')
);

alter table atlas.capture_interpretation_jobs
  drop constraint if exists capture_interpretation_jobs_latest_reasoning_run_fk;
alter table atlas.capture_interpretation_jobs
  add constraint capture_interpretation_jobs_latest_reasoning_run_fk
  foreign key (latest_reasoning_run_id) references atlas.reasoning_runs(id) on delete restrict;

create index if not exists reasoning_runs_observation_idx
  on atlas.reasoning_runs (observation_id, started_at desc);
create index if not exists reasoning_runs_job_idx
  on atlas.reasoning_runs (job_id, started_at desc);

comment on table atlas.reasoning_runs is
  'Bounded reasoning provenance: provider/model/contracts/context refs/result/usage without requiring private chain-of-thought.';

create table if not exists atlas.model_inferences (
  id uuid primary key default gen_random_uuid(),
  reasoning_run_id uuid not null references atlas.reasoning_runs(id) on delete restrict,
  observation_id uuid not null references atlas.capture_observations(id) on delete restrict,
  candidate_key text not null,
  candidate_type text not null,
  candidate_payload jsonb not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  confidence jsonb null,
  review_policy text not null default 'human_required'
    check (review_policy in ('human_required','human_optional','no_promotion','domain_policy')),
  inference_status text not null default 'proposed'
    check (inference_status in ('proposed','superseded')),
  schema_version text not null default 'capture_interpretation_v1',
  created_at timestamptz not null default now(),
  check (btrim(candidate_key) <> ''),
  check (btrim(candidate_type) <> ''),
  check (jsonb_typeof(candidate_payload) = 'object'),
  check (jsonb_typeof(evidence_refs) = 'array'),
  check (confidence is null or jsonb_typeof(confidence) = 'object'),
  check (btrim(schema_version) <> ''),
  unique (reasoning_run_id, candidate_key)
);

create index if not exists model_inferences_observation_idx
  on atlas.model_inferences (observation_id, created_at);

comment on table atlas.model_inferences is
  'Structured model proposals. These rows are inference, not established fact or mutation authority.';

-- ---------------------------------------------------------------------------
-- Human correction/adjudication ledger
-- ---------------------------------------------------------------------------

create table if not exists atlas.human_adjudications (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references atlas.capture_observations(id) on delete restrict,
  reasoning_run_id uuid null references atlas.reasoning_runs(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  surface text not null default 'CAPT-03',
  review_outcome text not null default 'reviewed'
    check (review_outcome in ('reviewed','keep_note','leave_unresolved')),
  authority_context jsonb not null default '{}'::jsonb,
  optional_human_note text null,
  supersedes_adjudication_id uuid null references atlas.human_adjudications(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (btrim(surface) <> ''),
  check (jsonb_typeof(authority_context) = 'object')
);

create index if not exists human_adjudications_observation_idx
  on atlas.human_adjudications (observation_id, created_at desc);

comment on table atlas.human_adjudications is
  'Append-only human review/correction event over model proposals. It does not itself bypass owning-domain warrant or authority.';

create table if not exists atlas.human_adjudication_items (
  id uuid primary key default gen_random_uuid(),
  adjudication_id uuid not null references atlas.human_adjudications(id) on delete restrict,
  model_inference_id uuid null references atlas.model_inferences(id) on delete restrict,
  candidate_key text not null,
  decision text not null
    check (decision in ('accepted','rejected','corrected','unresolved','not_material')),
  presented_payload jsonb not null,
  corrected_payload jsonb null,
  explanation text null,
  created_at timestamptz not null default now(),
  check (btrim(candidate_key) <> ''),
  check (jsonb_typeof(presented_payload) = 'object'),
  check (corrected_payload is null or jsonb_typeof(corrected_payload) = 'object'),
  check ((decision='corrected' and corrected_payload is not null) or decision<>'corrected')
);

create index if not exists human_adjudication_items_adjudication_idx
  on atlas.human_adjudication_items (adjudication_id, created_at);

comment on table atlas.human_adjudication_items is
  'Exact candidate-level human decision. Presented model payload survives correction rather than being overwritten.';

-- ---------------------------------------------------------------------------
-- Append-only and lineage guards
-- ---------------------------------------------------------------------------

create or replace function atlas.block_capture_evidence_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Atlas capture evidence, model proposals, and human adjudications are append-only.' using errcode='55000';
end;
$function$;

drop trigger if exists capture_observations_append_only on atlas.capture_observations;
create trigger capture_observations_append_only
before update or delete on atlas.capture_observations
for each row execute function atlas.block_capture_evidence_mutation_v1();

drop trigger if exists model_inferences_append_only on atlas.model_inferences;
create trigger model_inferences_append_only
before update or delete on atlas.model_inferences
for each row execute function atlas.block_capture_evidence_mutation_v1();

drop trigger if exists human_adjudications_append_only on atlas.human_adjudications;
create trigger human_adjudications_append_only
before update or delete on atlas.human_adjudications
for each row execute function atlas.block_capture_evidence_mutation_v1();

drop trigger if exists human_adjudication_items_append_only on atlas.human_adjudication_items;
create trigger human_adjudication_items_append_only
before update or delete on atlas.human_adjudication_items
for each row execute function atlas.block_capture_evidence_mutation_v1();

create or replace function atlas.capture_lineage_guard_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
declare
  v_run_observation uuid;
  v_job_observation uuid;
  v_adjudication_observation uuid;
  v_adjudication_run uuid;
  v_inference_observation uuid;
  v_inference_run uuid;
begin
  if tg_table_name='reasoning_runs' then
    select observation_id into v_job_observation
    from atlas.capture_interpretation_jobs
    where id=new.job_id;
    if v_job_observation is null or v_job_observation<>new.observation_id then
      raise exception 'Reasoning run job/observation lineage mismatch.' using errcode='23514';
    end if;
  elsif tg_table_name='model_inferences' then
    select observation_id into v_run_observation
    from atlas.reasoning_runs
    where id=new.reasoning_run_id;
    if v_run_observation is null or v_run_observation<>new.observation_id then
      raise exception 'Model inference run/observation lineage mismatch.' using errcode='23514';
    end if;
  elsif tg_table_name='human_adjudications' then
    if new.reasoning_run_id is not null then
      select observation_id into v_run_observation
      from atlas.reasoning_runs
      where id=new.reasoning_run_id;
      if v_run_observation is null or v_run_observation<>new.observation_id then
        raise exception 'Human adjudication run/observation lineage mismatch.' using errcode='23514';
      end if;
    end if;
  elsif tg_table_name='human_adjudication_items' then
    select a.observation_id, a.reasoning_run_id
      into v_adjudication_observation, v_adjudication_run
    from atlas.human_adjudications a
    where a.id=new.adjudication_id;

    if v_adjudication_observation is null then
      raise exception 'Human adjudication item references missing adjudication.' using errcode='23514';
    end if;

    if new.model_inference_id is not null then
      select mi.observation_id, mi.reasoning_run_id
        into v_inference_observation, v_inference_run
      from atlas.model_inferences mi
      where mi.id=new.model_inference_id;

      if v_inference_observation is null
         or v_inference_observation<>v_adjudication_observation
         or (v_adjudication_run is not null and v_inference_run<>v_adjudication_run) then
        raise exception 'Human adjudication item/inference lineage mismatch.' using errcode='23514';
      end if;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists reasoning_runs_lineage_guard on atlas.reasoning_runs;
create trigger reasoning_runs_lineage_guard
before insert or update on atlas.reasoning_runs
for each row execute function atlas.capture_lineage_guard_v1();

drop trigger if exists model_inferences_lineage_guard on atlas.model_inferences;
create trigger model_inferences_lineage_guard
before insert on atlas.model_inferences
for each row execute function atlas.capture_lineage_guard_v1();

drop trigger if exists human_adjudications_lineage_guard on atlas.human_adjudications;
create trigger human_adjudications_lineage_guard
before insert on atlas.human_adjudications
for each row execute function atlas.capture_lineage_guard_v1();

drop trigger if exists human_adjudication_items_lineage_guard on atlas.human_adjudication_items;
create trigger human_adjudication_items_lineage_guard
before insert on atlas.human_adjudication_items
for each row execute function atlas.capture_lineage_guard_v1();

-- ---------------------------------------------------------------------------
-- Custody / scope helper
-- Current Atlas convention: scope_kind='person' uses authenticated user UUID as
-- custody scope key; this remains distinct from semantic Person identity.
-- ---------------------------------------------------------------------------

create or replace function atlas.can_use_capture_scope_v1(
  p_scope_kind text,
  p_scope_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
begin
  if auth.uid() is null or p_scope_id is null then
    return false;
  end if;

  if p_scope_kind='person' then
    return p_scope_id=auth.uid();
  end if;

  if p_scope_kind='organization' then
    return atlas.is_organization_member(p_scope_id);
  end if;

  return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Authenticated capture API
-- Observation + queue row are inserted in one transaction. The user receives
-- the observation ID before any model call is required.
-- ---------------------------------------------------------------------------

create or replace function atlas.capture_text_observation_api_v1(
  p_scope_kind text,
  p_scope_id uuid,
  p_raw_text text,
  p_client_request_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth, extensions
as $function$
declare
  v_user_id uuid := auth.uid();
  v_existing atlas.capture_observations%rowtype;
  v_observation atlas.capture_observations%rowtype;
  v_job atlas.capture_interpretation_jobs%rowtype;
  v_hash text;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  if not atlas.can_use_capture_scope_v1(p_scope_kind, p_scope_id) then
    raise exception 'Capture scope is not available to this user.' using errcode='42501';
  end if;

  if p_raw_text is null or btrim(p_raw_text)='' then
    raise exception 'Capture text is required.' using errcode='22023';
  end if;

  if char_length(p_raw_text)>100000 then
    raise exception 'Capture text exceeds the V1 limit.' using errcode='22023';
  end if;

  if p_client_request_id is null or btrim(p_client_request_id)='' then
    raise exception 'client_request_id is required for idempotent capture.' using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Capture metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.capture_observations o
  where o.scope_kind=p_scope_kind
    and o.scope_id=p_scope_id
    and o.created_by_user_id=v_user_id
    and o.client_request_id=p_client_request_id;

  if found then
    if v_existing.raw_text is distinct from p_raw_text then
      raise exception 'client_request_id was already used for a different capture payload.' using errcode='23505';
    end if;

    select * into v_job
    from atlas.capture_interpretation_jobs j
    where j.observation_id=v_existing.id
      and j.job_type='interpret_capture_v1'
      and j.schema_version='capture_interpretation_v1';

    return jsonb_build_object(
      'observation_id', v_existing.id,
      'job_id', v_job.id,
      'capture_status', 'saved',
      'interpretation_status', coalesce(v_job.status,'not_queued'),
      'idempotent_replay', true
    );
  end if;

  v_hash := encode(digest(convert_to(p_raw_text,'UTF8'),'sha256'),'hex');

  insert into atlas.capture_observations (
    scope_kind,
    scope_id,
    created_by_user_id,
    source_kind,
    source_actor_user_id,
    capture_surface,
    content_kind,
    raw_text,
    raw_metadata,
    content_hash,
    content_hash_algorithm,
    client_request_id,
    captured_at,
    retention_class
  ) values (
    p_scope_kind,
    p_scope_id,
    v_user_id,
    'human_capture',
    v_user_id,
    'CAPT-01',
    'text',
    p_raw_text,
    p_metadata,
    v_hash,
    'sha256',
    p_client_request_id,
    now(),
    'standard'
  ) returning * into v_observation;

  insert into atlas.capture_interpretation_jobs (
    observation_id,
    job_type,
    schema_version,
    requested_by_user_id,
    idempotency_key
  ) values (
    v_observation.id,
    'interpret_capture_v1',
    'capture_interpretation_v1',
    v_user_id,
    'capture:' || v_observation.id::text || ':interpret_capture_v1:capture_interpretation_v1'
  ) returning * into v_job;

  return jsonb_build_object(
    'observation_id', v_observation.id,
    'job_id', v_job.id,
    'capture_status', 'saved',
    'interpretation_status', v_job.status,
    'idempotent_replay', false
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Creator-only review bundle API
-- ---------------------------------------------------------------------------

create or replace function atlas.capture_review_bundle_api_v1(
  p_observation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_observation atlas.capture_observations%rowtype;
  v_job atlas.capture_interpretation_jobs%rowtype;
  v_run atlas.reasoning_runs%rowtype;
  v_candidates jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_observation
  from atlas.capture_observations o
  where o.id=p_observation_id
    and o.created_by_user_id=v_user_id
    and atlas.can_use_capture_scope_v1(o.scope_kind,o.scope_id);

  if not found then
    raise exception 'Capture observation is not available.' using errcode='42501';
  end if;

  select * into v_job
  from atlas.capture_interpretation_jobs j
  where j.observation_id=v_observation.id
  order by j.requested_at desc
  limit 1;

  select * into v_run
  from atlas.reasoning_runs r
  where r.observation_id=v_observation.id
    and r.status='succeeded'
  order by r.finished_at desc nulls last, r.started_at desc
  limit 1;

  if v_run.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', mi.id,
      'candidate_key', mi.candidate_key,
      'candidate_type', mi.candidate_type,
      'candidate_payload', mi.candidate_payload,
      'evidence_refs', mi.evidence_refs,
      'confidence', mi.confidence,
      'review_policy', mi.review_policy,
      'schema_version', mi.schema_version
    ) order by mi.created_at, mi.candidate_key), '[]'::jsonb)
    into v_candidates
    from atlas.model_inferences mi
    where mi.reasoning_run_id=v_run.id
      and mi.inference_status='proposed';
  end if;

  return jsonb_build_object(
    'observation', jsonb_build_object(
      'id', v_observation.id,
      'scope_kind', v_observation.scope_kind,
      'scope_id', v_observation.scope_id,
      'content_kind', v_observation.content_kind,
      'raw_text', v_observation.raw_text,
      'captured_at', v_observation.captured_at
    ),
    'interpretation_job', case when v_job.id is null then null else jsonb_build_object(
      'id', v_job.id,
      'status', v_job.status,
      'attempt_count', v_job.attempt_count,
      'last_error_safe_message', v_job.last_error_safe_message
    ) end,
    'reasoning_run', case when v_run.id is null then null else jsonb_build_object(
      'id', v_run.id,
      'status', v_run.status,
      'model_provider', v_run.model_provider,
      'model_id', v_run.model_id,
      'prompt_contract_version', v_run.prompt_contract_version,
      'output_schema_version', v_run.output_schema_version,
      'tool_registry_version', v_run.tool_registry_version,
      'started_at', v_run.started_at,
      'finished_at', v_run.finished_at
    ) end,
    'candidates', v_candidates
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Human adjudication API. This persists review only. Domain promotion is
-- intentionally absent from this migration.
-- ---------------------------------------------------------------------------

create or replace function atlas.capture_adjudicate_api_v1(
  p_observation_id uuid,
  p_reasoning_run_id uuid,
  p_review_outcome text,
  p_items jsonb default '[]'::jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_observation atlas.capture_observations%rowtype;
  v_run atlas.reasoning_runs%rowtype;
  v_adjudication_id uuid;
  v_item jsonb;
  v_inference atlas.model_inferences%rowtype;
  v_decision text;
  v_corrected jsonb;
  v_explanation text;
  v_inference_id uuid;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  if p_review_outcome not in ('reviewed','keep_note','leave_unresolved') then
    raise exception 'Unsupported review outcome.' using errcode='22023';
  end if;

  if p_items is null or jsonb_typeof(p_items)<>'array' then
    raise exception 'Adjudication items must be a JSON array.' using errcode='22023';
  end if;

  select * into v_observation
  from atlas.capture_observations o
  where o.id=p_observation_id
    and o.created_by_user_id=v_user_id
    and atlas.can_use_capture_scope_v1(o.scope_kind,o.scope_id);

  if not found then
    raise exception 'Capture observation is not available.' using errcode='42501';
  end if;

  if p_reasoning_run_id is not null then
    select * into v_run
    from atlas.reasoning_runs r
    where r.id=p_reasoning_run_id
      and r.observation_id=p_observation_id
      and r.status='succeeded';
    if not found then
      raise exception 'Reasoning run is not an active reviewable run for this observation.' using errcode='22023';
    end if;
  end if;

  insert into atlas.human_adjudications (
    observation_id,
    reasoning_run_id,
    actor_user_id,
    surface,
    review_outcome,
    authority_context,
    optional_human_note
  ) values (
    p_observation_id,
    p_reasoning_run_id,
    v_user_id,
    'CAPT-03',
    p_review_outcome,
    jsonb_build_object('authenticated_user_id',v_user_id),
    p_note
  ) returning id into v_adjudication_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'Each adjudication item must be a JSON object.' using errcode='22023';
    end if;

    if nullif(v_item->>'model_inference_id','') is null then
      raise exception 'model_inference_id is required for V1 candidate review.' using errcode='22023';
    end if;

    v_inference_id := (v_item->>'model_inference_id')::uuid;
    v_decision := v_item->>'decision';
    v_corrected := v_item->'corrected_payload';
    v_explanation := nullif(v_item->>'explanation','');

    if v_decision not in ('accepted','rejected','corrected','unresolved','not_material') then
      raise exception 'Unsupported candidate decision.' using errcode='22023';
    end if;

    select * into v_inference
    from atlas.model_inferences mi
    where mi.id=v_inference_id
      and mi.observation_id=p_observation_id
      and (p_reasoning_run_id is null or mi.reasoning_run_id=p_reasoning_run_id)
      and mi.inference_status='proposed';

    if not found then
      raise exception 'Adjudication candidate does not belong to the reviewed observation/run.' using errcode='22023';
    end if;

    if v_decision='corrected' and (v_corrected is null or jsonb_typeof(v_corrected)<>'object') then
      raise exception 'Corrected candidate requires corrected_payload object.' using errcode='22023';
    end if;

    insert into atlas.human_adjudication_items (
      adjudication_id,
      model_inference_id,
      candidate_key,
      decision,
      presented_payload,
      corrected_payload,
      explanation
    ) values (
      v_adjudication_id,
      v_inference.id,
      v_inference.candidate_key,
      v_decision,
      v_inference.candidate_payload,
      case when v_decision='corrected' then v_corrected else null end,
      v_explanation
    );

    v_count := v_count + 1;
  end loop;

  if p_review_outcome='reviewed' and v_count=0 and p_reasoning_run_id is not null then
    raise exception 'Reviewed outcome requires at least one candidate decision.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'adjudication_id', v_adjudication_id,
    'observation_id', p_observation_id,
    'reasoning_run_id', p_reasoning_run_id,
    'review_outcome', p_review_outcome,
    'item_count', v_count,
    'promotion_status', 'not_yet_applied'
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Service-role worker APIs
-- ---------------------------------------------------------------------------

create or replace function atlas.capture_claim_interpretation_job_api_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_job atlas.capture_interpretation_jobs%rowtype;
begin
  with candidate as (
    select j.id
    from atlas.capture_interpretation_jobs j
    where j.status='queued'
      and (j.next_attempt_at is null or j.next_attempt_at<=now())
      and j.attempt_count<j.max_attempts
    order by j.requested_at, j.id
    for update skip locked
    limit 1
  )
  update atlas.capture_interpretation_jobs j
     set status='running',
         started_at=now(),
         finished_at=null,
         attempt_count=j.attempt_count+1,
         next_attempt_at=null,
         updated_at=now()
  from candidate c
  where j.id=c.id
  returning j.* into v_job;

  if v_job.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'job_id', v_job.id,
    'observation_id', v_job.observation_id,
    'job_type', v_job.job_type,
    'schema_version', v_job.schema_version,
    'attempt_count', v_job.attempt_count,
    'max_attempts', v_job.max_attempts
  );
end;
$function$;

create or replace function atlas.capture_begin_reasoning_run_api_v1(
  p_job_id uuid,
  p_model_provider text,
  p_model_id text,
  p_model_version_or_snapshot text,
  p_router_policy_version text,
  p_prompt_contract_version text,
  p_output_schema_version text,
  p_tool_registry_version text,
  p_context_manifest jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_job atlas.capture_interpretation_jobs%rowtype;
  v_run atlas.reasoning_runs%rowtype;
begin
  if p_context_manifest is null or jsonb_typeof(p_context_manifest)<>'array' then
    raise exception 'context_manifest must be a JSON array.' using errcode='22023';
  end if;

  select * into v_job
  from atlas.capture_interpretation_jobs j
  where j.id=p_job_id
  for update;

  if not found or v_job.status<>'running' then
    raise exception 'Interpretation job is not currently claimed/running.' using errcode='55000';
  end if;

  insert into atlas.reasoning_runs (
    observation_id,
    job_id,
    purpose,
    model_provider,
    model_id,
    model_version_or_snapshot,
    router_policy_version,
    prompt_contract_version,
    output_schema_version,
    tool_registry_version,
    context_manifest,
    status
  ) values (
    v_job.observation_id,
    v_job.id,
    'capture_interpretation_v1',
    p_model_provider,
    p_model_id,
    p_model_version_or_snapshot,
    p_router_policy_version,
    p_prompt_contract_version,
    p_output_schema_version,
    p_tool_registry_version,
    p_context_manifest,
    'running'
  ) returning * into v_run;

  update atlas.capture_interpretation_jobs
     set latest_reasoning_run_id=v_run.id,
         updated_at=now()
   where id=v_job.id;

  return jsonb_build_object(
    'reasoning_run_id', v_run.id,
    'observation_id', v_run.observation_id,
    'job_id', v_run.job_id
  );
end;
$function$;

create or replace function atlas.capture_complete_reasoning_run_api_v1(
  p_reasoning_run_id uuid,
  p_structured_result jsonb,
  p_candidates jsonb,
  p_usage_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_run atlas.reasoning_runs%rowtype;
  v_candidate jsonb;
  v_count integer := 0;
  v_confidence jsonb;
begin
  if p_structured_result is null or jsonb_typeof(p_structured_result)<>'object' then
    raise exception 'structured_result must be a JSON object.' using errcode='22023';
  end if;
  if p_candidates is null or jsonb_typeof(p_candidates)<>'array' then
    raise exception 'candidates must be a JSON array.' using errcode='22023';
  end if;
  if p_usage_metadata is null or jsonb_typeof(p_usage_metadata)<>'object' then
    raise exception 'usage_metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_run
  from atlas.reasoning_runs r
  where r.id=p_reasoning_run_id
  for update;

  if not found or v_run.status<>'running' then
    raise exception 'Reasoning run is not running.' using errcode='55000';
  end if;

  for v_candidate in select value from jsonb_array_elements(p_candidates)
  loop
    if jsonb_typeof(v_candidate)<>'object' then
      raise exception 'Each candidate must be a JSON object.' using errcode='22023';
    end if;
    if nullif(v_candidate->>'candidate_key','') is null
       or nullif(v_candidate->>'candidate_type','') is null then
      raise exception 'Candidate key/type are required.' using errcode='22023';
    end if;
    if v_candidate->'candidate_payload' is null
       or jsonb_typeof(v_candidate->'candidate_payload')<>'object' then
      raise exception 'candidate_payload must be a JSON object.' using errcode='22023';
    end if;
    if coalesce(jsonb_typeof(v_candidate->'evidence_refs'),'array')<>'array' then
      raise exception 'evidence_refs must be a JSON array.' using errcode='22023';
    end if;

    v_confidence := v_candidate->'confidence';
    if v_confidence is not null and jsonb_typeof(v_confidence)<>'object' then
      raise exception 'confidence must be a JSON object when supplied.' using errcode='22023';
    end if;

    insert into atlas.model_inferences (
      reasoning_run_id,
      observation_id,
      candidate_key,
      candidate_type,
      candidate_payload,
      evidence_refs,
      confidence,
      review_policy,
      schema_version
    ) values (
      v_run.id,
      v_run.observation_id,
      v_candidate->>'candidate_key',
      v_candidate->>'candidate_type',
      v_candidate->'candidate_payload',
      coalesce(v_candidate->'evidence_refs','[]'::jsonb),
      v_confidence,
      coalesce(nullif(v_candidate->>'review_policy',''),'human_required'),
      v_run.output_schema_version
    );

    v_count := v_count+1;
  end loop;

  update atlas.reasoning_runs
     set status='succeeded',
         structured_result=p_structured_result,
         usage_metadata=p_usage_metadata,
         finished_at=now()
   where id=v_run.id;

  update atlas.capture_interpretation_jobs
     set status='succeeded',
         finished_at=now(),
         last_error_class=null,
         last_error_safe_message=null,
         updated_at=now()
   where id=v_run.job_id;

  return jsonb_build_object(
    'reasoning_run_id', v_run.id,
    'candidate_count', v_count,
    'status', 'succeeded'
  );
end;
$function$;

create or replace function atlas.capture_fail_reasoning_run_api_v1(
  p_reasoning_run_id uuid,
  p_error_class text,
  p_safe_message text,
  p_retryable boolean default true,
  p_retry_after_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_run atlas.reasoning_runs%rowtype;
  v_job atlas.capture_interpretation_jobs%rowtype;
  v_retry boolean;
begin
  select * into v_run
  from atlas.reasoning_runs r
  where r.id=p_reasoning_run_id
  for update;

  if not found or v_run.status<>'running' then
    raise exception 'Reasoning run is not running.' using errcode='55000';
  end if;

  select * into v_job
  from atlas.capture_interpretation_jobs j
  where j.id=v_run.job_id
  for update;

  v_retry := coalesce(p_retryable,false) and v_job.attempt_count<v_job.max_attempts;

  update atlas.reasoning_runs
     set status='failed',
         safe_error=jsonb_build_object(
           'error_class',coalesce(nullif(p_error_class,''),'unknown'),
           'safe_message',coalesce(p_safe_message,'Interpretation failed.')
         ),
         finished_at=now()
   where id=v_run.id;

  update atlas.capture_interpretation_jobs
     set status=case when v_retry then 'queued' else 'failed' end,
         finished_at=case when v_retry then null else now() end,
         next_attempt_at=case
           when v_retry then now()+make_interval(secs=>greatest(coalesce(p_retry_after_seconds,60),1))
           else null
         end,
         last_error_class=coalesce(nullif(p_error_class,''),'unknown'),
         last_error_safe_message=coalesce(p_safe_message,'Interpretation failed.'),
         updated_at=now()
   where id=v_job.id;

  return jsonb_build_object(
    'reasoning_run_id', v_run.id,
    'job_id', v_job.id,
    'retry_scheduled', v_retry,
    'job_status', case when v_retry then 'queued' else 'failed' end
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- Authenticated product access is RPC-only in V1. Raw capture/inference tables
-- are not directly readable/writable by authenticated clients.
-- ---------------------------------------------------------------------------

alter table atlas.capture_observations enable row level security;
alter table atlas.capture_interpretation_jobs enable row level security;
alter table atlas.reasoning_runs enable row level security;
alter table atlas.model_inferences enable row level security;
alter table atlas.human_adjudications enable row level security;
alter table atlas.human_adjudication_items enable row level security;

revoke all on table atlas.capture_observations from public, anon, authenticated;
revoke all on table atlas.capture_interpretation_jobs from public, anon, authenticated;
revoke all on table atlas.reasoning_runs from public, anon, authenticated;
revoke all on table atlas.model_inferences from public, anon, authenticated;
revoke all on table atlas.human_adjudications from public, anon, authenticated;
revoke all on table atlas.human_adjudication_items from public, anon, authenticated;

grant all on table atlas.capture_observations to service_role;
grant all on table atlas.capture_interpretation_jobs to service_role;
grant all on table atlas.reasoning_runs to service_role;
grant all on table atlas.model_inferences to service_role;
grant all on table atlas.human_adjudications to service_role;
grant all on table atlas.human_adjudication_items to service_role;

revoke all on function atlas.can_use_capture_scope_v1(text,uuid) from public, anon, authenticated;
revoke all on function atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb) from public, anon;
revoke all on function atlas.capture_review_bundle_api_v1(uuid) from public, anon;
revoke all on function atlas.capture_adjudicate_api_v1(uuid,uuid,text,jsonb,text) from public, anon;
revoke all on function atlas.capture_claim_interpretation_job_api_v1() from public, anon, authenticated;
revoke all on function atlas.capture_begin_reasoning_run_api_v1(uuid,text,text,text,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function atlas.capture_complete_reasoning_run_api_v1(uuid,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.capture_fail_reasoning_run_api_v1(uuid,text,text,boolean,integer) from public, anon, authenticated;
revoke all on function atlas.block_capture_evidence_mutation_v1() from public, anon, authenticated;
revoke all on function atlas.capture_lineage_guard_v1() from public, anon, authenticated;

grant execute on function atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb) to authenticated;
grant execute on function atlas.capture_review_bundle_api_v1(uuid) to authenticated;
grant execute on function atlas.capture_adjudicate_api_v1(uuid,uuid,text,jsonb,text) to authenticated;

grant execute on function atlas.can_use_capture_scope_v1(text,uuid) to service_role;
grant execute on function atlas.capture_claim_interpretation_job_api_v1() to service_role;
grant execute on function atlas.capture_begin_reasoning_run_api_v1(uuid,text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function atlas.capture_complete_reasoning_run_api_v1(uuid,jsonb,jsonb,jsonb) to service_role;
grant execute on function atlas.capture_fail_reasoning_run_api_v1(uuid,text,text,boolean,integer) to service_role;
grant execute on function atlas.block_capture_evidence_mutation_v1() to service_role;
grant execute on function atlas.capture_lineage_guard_v1() to service_role;

comment on function atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb) is
  'Guarded idempotent V1 text capture. Persists raw observation and durable interpretation job atomically; performs no model call or domain mutation.';
comment on function atlas.capture_review_bundle_api_v1(uuid) is
  'Creator-only V1 review read: raw capture + interpretation status + latest successful reasoning candidates.';
comment on function atlas.capture_adjudicate_api_v1(uuid,uuid,text,jsonb,text) is
  'Creator-only V1 human adjudication ledger. This migration deliberately performs no downstream domain promotion.';
comment on function atlas.capture_claim_interpretation_job_api_v1() is
  'Service-role SKIP LOCKED claim of one queued capture interpretation job.';
comment on function atlas.capture_begin_reasoning_run_api_v1(uuid,text,text,text,text,text,text,text,jsonb) is
  'Service-role creation of one versioned capture reasoning run.';
comment on function atlas.capture_complete_reasoning_run_api_v1(uuid,jsonb,jsonb,jsonb) is
  'Service-role persistence of validated structured model result and candidate proposals.';
comment on function atlas.capture_fail_reasoning_run_api_v1(uuid,text,text,boolean,integer) is
  'Service-role failure/retry transition for a capture reasoning run; raw capture remains durable.';

COMMIT;
