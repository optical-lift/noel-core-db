alter type transcript_core.asset_provenance_class
  add value if not exists 'authored_performance_recording';

insert into storage.buckets (id, name, public)
values ('transcript-core-performance-recordings','transcript-core-performance-recordings',false)
on conflict (id) do update set public = false;

create table if not exists transcript_core.production_recording_imports (
  id uuid primary key,
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  recording_session_id uuid references transcript_core.recording_sessions(id) on delete set null,
  audio_asset_id uuid not null unique references transcript_core.assets(id),
  file_name text not null,
  origin text not null check (origin in ('human_recording','generated_voice')),
  performer_kind text not null check (performer_kind in ('human_person','voice_profile','label')),
  performer_ref text not null,
  performer_display_name text not null,
  duration_ms bigint check (duration_ms is null or duration_ms >= 0),
  status text not null default 'uploaded'
    check (status in ('uploaded','transcribed','matching','needs_review','matched','rejected')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.performance_recording_transcripts (
  id uuid primary key default extensions.gen_random_uuid(),
  recording_import_id uuid not null references transcript_core.production_recording_imports(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  provider text not null,
  provider_model text,
  text text not null,
  segments jsonb not null default '[]'::jsonb check (jsonb_typeof(segments) = 'array'),
  created_at timestamptz not null default now(),
  unique (recording_import_id, ordinal)
);

create table if not exists transcript_core.performance_recording_match_candidates (
  id uuid primary key default extensions.gen_random_uuid(),
  recording_import_id uuid not null references transcript_core.production_recording_imports(id) on delete cascade,
  transcript_id uuid not null references transcript_core.performance_recording_transcripts(id) on delete cascade,
  manuscript_revision_id uuid not null references transcript_core.manuscript_revisions(id) on delete cascade,
  start_narration_unit_id uuid not null references transcript_core.narration_units(id) on delete cascade,
  end_narration_unit_id uuid not null references transcript_core.narration_units(id) on delete cascade,
  start_sequence integer not null check (start_sequence > 0),
  end_sequence integer not null check (end_sequence >= start_sequence),
  score numeric not null check (score >= 0 and score <= 1),
  lexical_coverage numeric check (lexical_coverage is null or (lexical_coverage >= 0 and lexical_coverage <= 1)),
  length_fit numeric check (length_fit is null or (length_fit >= 0 and length_fit <= 1)),
  method text not null,
  method_version text not null,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  status text not null default 'proposed' check (status in ('proposed','accepted','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (recording_import_id, transcript_id, start_sequence, end_sequence, method, method_version)
);

create index if not exists production_recording_imports_production_idx
  on transcript_core.production_recording_imports(production_id, created_at desc);
create index if not exists performance_recording_transcripts_import_idx
  on transcript_core.performance_recording_transcripts(recording_import_id, ordinal desc);
create index if not exists performance_recording_match_candidates_review_idx
  on transcript_core.performance_recording_match_candidates(recording_import_id, status, score desc);

alter table transcript_core.production_recording_imports enable row level security;
alter table transcript_core.performance_recording_transcripts enable row level security;
alter table transcript_core.performance_recording_match_candidates enable row level security;

create policy transcript_core_performance_recording_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'transcript-core-performance-recordings'
  and public.transcript_core_can_workspace_edit(public.transcript_core_path_workspace(name))
);

create policy transcript_core_performance_recording_read on storage.objects
for select to authenticated
using (
  bucket_id = 'transcript-core-performance-recordings'
  and public.transcript_core_is_workspace_member(public.transcript_core_path_workspace(name))
);

create or replace function public.transcript_core_register_performance_recording_import(
  p_import_id uuid,
  p_production_id uuid,
  p_recording_session_id uuid,
  p_storage_bucket text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_byte_size bigint,
  p_file_name text,
  p_origin text,
  p_performer_kind text,
  p_performer_ref text,
  p_performer_display_name text,
  p_duration_ms bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  existing_import transcript_core.production_recording_imports%rowtype;
  asset_id uuid;
begin
  select workspace_id into target_workspace_id
  from transcript_core.productions
  where id = p_production_id;

  if target_workspace_id is null then raise exception 'PRODUCTION_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if p_storage_bucket <> 'transcript-core-performance-recordings' then
    raise exception 'PERFORMANCE_RECORDING_BUCKET_INVALID';
  end if;
  if public.transcript_core_path_workspace(p_storage_path) is distinct from target_workspace_id then
    raise exception 'PERFORMANCE_RECORDING_PATH_WORKSPACE_MISMATCH';
  end if;
  if nullif(trim(p_content_hash), '') is null then raise exception 'PERFORMANCE_RECORDING_HASH_REQUIRED'; end if;
  if nullif(trim(p_mime_type), '') is null or p_mime_type not like 'audio/%' then
    raise exception 'PERFORMANCE_RECORDING_MIME_INVALID';
  end if;
  if p_byte_size < 0 then raise exception 'PERFORMANCE_RECORDING_BYTE_SIZE_INVALID'; end if;
  if nullif(trim(p_file_name), '') is null then raise exception 'PERFORMANCE_RECORDING_FILE_NAME_REQUIRED'; end if;
  if p_origin not in ('human_recording','generated_voice') then raise exception 'PERFORMANCE_RECORDING_ORIGIN_INVALID'; end if;
  if p_performer_kind not in ('human_person','voice_profile','label') then raise exception 'PERFORMANCE_RECORDING_PERFORMER_KIND_INVALID'; end if;
  if nullif(trim(p_performer_ref), '') is null then raise exception 'PERFORMANCE_RECORDING_PERFORMER_REF_REQUIRED'; end if;
  if nullif(trim(p_performer_display_name), '') is null then raise exception 'PERFORMANCE_RECORDING_PERFORMER_NAME_REQUIRED'; end if;
  if p_duration_ms is not null and p_duration_ms < 0 then raise exception 'PERFORMANCE_RECORDING_DURATION_INVALID'; end if;

  if p_recording_session_id is not null and not exists (
    select 1 from transcript_core.recording_sessions rs
    where rs.id = p_recording_session_id and rs.production_id = p_production_id
  ) then
    raise exception 'PERFORMANCE_RECORDING_SESSION_INVALID';
  end if;

  select * into existing_import
  from transcript_core.production_recording_imports
  where id = p_import_id;

  if found then
    if existing_import.production_id <> p_production_id then
      raise exception 'PERFORMANCE_RECORDING_IMPORT_ID_CONFLICT';
    end if;
    select a.id into asset_id
    from transcript_core.assets a
    where a.id = existing_import.audio_asset_id
      and a.storage_bucket = p_storage_bucket
      and a.storage_path = p_storage_path;
    if asset_id is null then raise exception 'PERFORMANCE_RECORDING_IMPORT_ID_CONFLICT'; end if;
    return jsonb_build_object('recordingImportId', existing_import.id, 'assetId', existing_import.audio_asset_id);
  end if;

  insert into transcript_core.assets(
    workspace_id, provenance_class, storage_bucket, storage_path,
    content_hash, mime_type, byte_size
  ) values (
    target_workspace_id, 'authored_performance_recording', p_storage_bucket, p_storage_path,
    trim(p_content_hash), trim(p_mime_type), p_byte_size
  ) returning id into asset_id;

  insert into transcript_core.production_recording_imports(
    id, production_id, recording_session_id, audio_asset_id, file_name, origin,
    performer_kind, performer_ref, performer_display_name, duration_ms, created_by
  ) values (
    p_import_id, p_production_id, p_recording_session_id, asset_id, trim(p_file_name), p_origin,
    p_performer_kind, trim(p_performer_ref), trim(p_performer_display_name), p_duration_ms, auth.uid()
  );

  return jsonb_build_object('recordingImportId', p_import_id, 'assetId', asset_id);
end;
$$;

create or replace function public.transcript_core_list_performance_recording_imports(p_production_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  result jsonb;
begin
  select workspace_id into target_workspace_id from transcript_core.productions where id = p_production_id;
  if target_workspace_id is null then raise exception 'PRODUCTION_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then raise exception 'WORKSPACE_READ_FORBIDDEN'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', pri.id,
    'productionId', pri.production_id,
    'recordingSessionId', pri.recording_session_id,
    'audioAssetId', pri.audio_asset_id,
    'fileName', pri.file_name,
    'origin', pri.origin,
    'performerKind', pri.performer_kind,
    'performerRef', pri.performer_ref,
    'performerDisplayName', pri.performer_display_name,
    'durationMs', pri.duration_ms,
    'status', pri.status,
    'createdAt', pri.created_at,
    'latestTranscript', (
      select jsonb_build_object(
        'id', prt.id,
        'ordinal', prt.ordinal,
        'provider', prt.provider,
        'providerModel', prt.provider_model,
        'text', prt.text,
        'createdAt', prt.created_at
      )
      from transcript_core.performance_recording_transcripts prt
      where prt.recording_import_id = pri.id
      order by prt.ordinal desc
      limit 1
    ),
    'matchCandidates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mc.id,
        'manuscriptRevisionId', mc.manuscript_revision_id,
        'startNarrationUnitId', mc.start_narration_unit_id,
        'endNarrationUnitId', mc.end_narration_unit_id,
        'startSequence', mc.start_sequence,
        'endSequence', mc.end_sequence,
        'score', mc.score,
        'lexicalCoverage', mc.lexical_coverage,
        'lengthFit', mc.length_fit,
        'method', mc.method,
        'methodVersion', mc.method_version,
        'evidence', mc.evidence,
        'status', mc.status,
        'createdAt', mc.created_at
      ) order by mc.score desc, mc.created_at)
      from transcript_core.performance_recording_match_candidates mc
      where mc.recording_import_id = pri.id
    ), '[]'::jsonb)
  ) order by pri.created_at desc), '[]'::jsonb)
  into result
  from transcript_core.production_recording_imports pri
  where pri.production_id = p_production_id;

  return result;
end;
$$;

create or replace function public.transcript_core_store_performance_recording_transcript(
  p_recording_import_id uuid,
  p_provider text,
  p_provider_model text,
  p_text text,
  p_segments jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  next_ordinal integer;
  transcript_id uuid;
begin
  if not exists (select 1 from transcript_core.production_recording_imports where id = p_recording_import_id) then
    raise exception 'PERFORMANCE_RECORDING_IMPORT_NOT_FOUND';
  end if;
  if nullif(trim(p_provider), '') is null then raise exception 'PERFORMANCE_RECORDING_TRANSCRIPT_PROVIDER_REQUIRED'; end if;
  if nullif(trim(p_text), '') is null then raise exception 'PERFORMANCE_RECORDING_TRANSCRIPT_TEXT_REQUIRED'; end if;
  if jsonb_typeof(p_segments) <> 'array' then raise exception 'PERFORMANCE_RECORDING_TRANSCRIPT_SEGMENTS_MUST_BE_ARRAY'; end if;

  select coalesce(max(ordinal), 0) + 1 into next_ordinal
  from transcript_core.performance_recording_transcripts
  where recording_import_id = p_recording_import_id;

  insert into transcript_core.performance_recording_transcripts(
    recording_import_id, ordinal, provider, provider_model, text, segments
  ) values (
    p_recording_import_id, next_ordinal, trim(p_provider), nullif(trim(p_provider_model), ''), p_text, p_segments
  ) returning id into transcript_id;

  update transcript_core.production_recording_imports
  set status = 'transcribed'
  where id = p_recording_import_id;

  return transcript_id;
end;
$$;

create or replace function public.transcript_core_store_manuscript_match_candidates(
  p_recording_import_id uuid,
  p_transcript_id uuid,
  p_method text,
  p_method_version text,
  p_candidates jsonb
)
returns integer
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_revision_id uuid;
  candidate jsonb;
  inserted_count integer := 0;
  start_unit transcript_core.narration_units%rowtype;
  end_unit transcript_core.narration_units%rowtype;
  candidate_score numeric;
begin
  select ps.manuscript_revision_id into target_revision_id
  from transcript_core.production_recording_imports pri
  join transcript_core.production_sources ps on ps.production_id = pri.production_id
  where pri.id = p_recording_import_id;

  if target_revision_id is null then raise exception 'PERFORMANCE_RECORDING_MANUSCRIPT_SOURCE_REQUIRED'; end if;
  if not exists (
    select 1 from transcript_core.performance_recording_transcripts prt
    where prt.id = p_transcript_id and prt.recording_import_id = p_recording_import_id
  ) then raise exception 'PERFORMANCE_RECORDING_TRANSCRIPT_INVALID'; end if;
  if nullif(trim(p_method), '') is null or nullif(trim(p_method_version), '') is null then
    raise exception 'PERFORMANCE_RECORDING_MATCH_METHOD_REQUIRED';
  end if;
  if jsonb_typeof(p_candidates) <> 'array' then raise exception 'PERFORMANCE_RECORDING_MATCH_CANDIDATES_MUST_BE_ARRAY'; end if;

  update transcript_core.production_recording_imports set status = 'matching' where id = p_recording_import_id;

  for candidate in select value from jsonb_array_elements(p_candidates)
  loop
    select * into start_unit from transcript_core.narration_units
    where id = (candidate->>'startNarrationUnitId')::uuid
      and manuscript_revision_id = target_revision_id;
    if not found then raise exception 'PERFORMANCE_RECORDING_MATCH_START_UNIT_INVALID'; end if;

    select * into end_unit from transcript_core.narration_units
    where id = (candidate->>'endNarrationUnitId')::uuid
      and manuscript_revision_id = target_revision_id;
    if not found then raise exception 'PERFORMANCE_RECORDING_MATCH_END_UNIT_INVALID'; end if;
    if end_unit.sequence < start_unit.sequence then raise exception 'PERFORMANCE_RECORDING_MATCH_RANGE_INVALID'; end if;

    candidate_score := (candidate->>'score')::numeric;
    if candidate_score < 0 or candidate_score > 1 then raise exception 'PERFORMANCE_RECORDING_MATCH_SCORE_INVALID'; end if;

    insert into transcript_core.performance_recording_match_candidates(
      recording_import_id, transcript_id, manuscript_revision_id,
      start_narration_unit_id, end_narration_unit_id, start_sequence, end_sequence,
      score, lexical_coverage, length_fit, method, method_version, evidence
    ) values (
      p_recording_import_id, p_transcript_id, target_revision_id,
      start_unit.id, end_unit.id, start_unit.sequence, end_unit.sequence,
      candidate_score,
      nullif(candidate->>'lexicalCoverage','')::numeric,
      nullif(candidate->>'lengthFit','')::numeric,
      trim(p_method), trim(p_method_version),
      coalesce(candidate->'evidence', '{}'::jsonb)
    )
    on conflict (recording_import_id, transcript_id, start_sequence, end_sequence, method, method_version)
    do update set
      score = excluded.score,
      lexical_coverage = excluded.lexical_coverage,
      length_fit = excluded.length_fit,
      evidence = excluded.evidence,
      status = 'proposed',
      reviewed_by = null,
      reviewed_at = null;

    inserted_count := inserted_count + 1;
  end loop;

  update transcript_core.production_recording_imports
  set status = case when inserted_count > 0 then 'needs_review' else 'transcribed' end
  where id = p_recording_import_id;

  return inserted_count;
end;
$$;

create or replace function public.transcript_core_accept_manuscript_match_candidate(p_candidate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  candidate transcript_core.performance_recording_match_candidates%rowtype;
  target_workspace_id uuid;
begin
  select * into candidate
  from transcript_core.performance_recording_match_candidates
  where id = p_candidate_id;
  if not found then raise exception 'PERFORMANCE_RECORDING_MATCH_CANDIDATE_NOT_FOUND'; end if;

  select p.workspace_id into target_workspace_id
  from transcript_core.production_recording_imports pri
  join transcript_core.productions p on p.id = pri.production_id
  where pri.id = candidate.recording_import_id;
  if target_workspace_id is null then raise exception 'PERFORMANCE_RECORDING_IMPORT_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then raise exception 'WORKSPACE_EDIT_FORBIDDEN'; end if;

  update transcript_core.performance_recording_match_candidates
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where recording_import_id = candidate.recording_import_id
    and id <> candidate.id
    and status = 'proposed';

  update transcript_core.performance_recording_match_candidates
  set status = 'accepted', reviewed_by = auth.uid(), reviewed_at = now()
  where id = candidate.id;

  update transcript_core.production_recording_imports
  set status = 'matched'
  where id = candidate.recording_import_id;

  return candidate.id;
end;
$$;

revoke all on function public.transcript_core_register_performance_recording_import(uuid,uuid,uuid,text,text,text,text,bigint,text,text,text,text,text,bigint) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_performance_recording_imports(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_store_performance_recording_transcript(uuid,text,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_store_manuscript_match_candidates(uuid,uuid,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_accept_manuscript_match_candidate(uuid) from public, anon, authenticated, service_role;

grant execute on function public.transcript_core_register_performance_recording_import(uuid,uuid,uuid,text,text,text,text,bigint,text,text,text,text,text,bigint) to authenticated;
grant execute on function public.transcript_core_list_performance_recording_imports(uuid) to authenticated;
grant execute on function public.transcript_core_accept_manuscript_match_candidate(uuid) to authenticated;
grant execute on function public.transcript_core_store_performance_recording_transcript(uuid,text,text,text,jsonb) to service_role;
grant execute on function public.transcript_core_store_manuscript_match_candidates(uuid,uuid,text,text,jsonb) to service_role;