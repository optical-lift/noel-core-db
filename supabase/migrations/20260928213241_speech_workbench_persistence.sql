-- Transcript Core Speech Workbench persistence.
-- Keeps authored declaration and observed inference in separate canonical tables
-- while supporting one application-level speech workbench.

alter table transcript_core.script_revisions
  alter column source_asset_id drop not null,
  add column if not exists origin_kind text not null default 'import',
  add column if not exists ordinal integer not null default 1,
  add column if not exists snapshot_schema_version integer,
  add column if not exists native_snapshot jsonb,
  add column if not exists created_by uuid references auth.users(id);

alter table transcript_core.script_revisions
  drop constraint if exists script_revisions_origin_kind_check,
  add constraint script_revisions_origin_kind_check
    check (origin_kind in ('import','native')),
  drop constraint if exists script_revisions_ordinal_check,
  add constraint script_revisions_ordinal_check
    check (ordinal > 0),
  drop constraint if exists script_revisions_origin_payload_check,
  add constraint script_revisions_origin_payload_check
    check (
      (origin_kind = 'import' and source_asset_id is not null)
      or
      (origin_kind = 'native' and native_snapshot is not null and snapshot_schema_version is not null)
    );

create unique index if not exists script_revisions_document_ordinal_uidx
  on transcript_core.script_revisions(script_document_id, ordinal);

create table if not exists transcript_core.script_drafts (
  id uuid primary key default extensions.gen_random_uuid(),
  script_document_id uuid not null unique references transcript_core.script_documents(id) on delete cascade,
  base_revision_id uuid references transcript_core.script_revisions(id),
  snapshot_schema_version integer not null default 1 check (snapshot_schema_version > 0),
  snapshot jsonb not null,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists transcript_core.speaker_analysis_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete cascade,
  transcript_revision_id uuid not null references transcript_core.transcript_revisions(id) on delete cascade,
  source_job_id uuid references transcript_core.processing_jobs(id),
  provider text not null,
  provider_model text,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.speaker_clusters (
  id uuid primary key default extensions.gen_random_uuid(),
  analysis_run_id uuid not null references transcript_core.speaker_analysis_runs(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete cascade,
  provider_speaker_key text not null,
  created_at timestamptz not null default now(),
  unique (analysis_run_id, provider_speaker_key)
);

create table if not exists transcript_core.speaker_cluster_ranges (
  id uuid primary key default extensions.gen_random_uuid(),
  speaker_cluster_id uuid not null references transcript_core.speaker_clusters(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  start_ms bigint not null check (start_ms >= 0),
  end_ms bigint not null check (end_ms >= start_ms),
  unique (speaker_cluster_id, sequence)
);

create table if not exists transcript_core.speaker_cluster_range_segments (
  speaker_cluster_range_id uuid not null references transcript_core.speaker_cluster_ranges(id) on delete cascade,
  transcript_segment_id uuid not null references transcript_core.transcript_segments(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  primary key (speaker_cluster_range_id, transcript_segment_id),
  unique (speaker_cluster_range_id, ordinal)
);

create table if not exists transcript_core.speaker_identity_candidates (
  id uuid primary key default extensions.gen_random_uuid(),
  speaker_cluster_id uuid not null references transcript_core.speaker_clusters(id) on delete cascade,
  target_kind text not null check (target_kind in ('person','label')),
  target_ref text not null,
  display_name text not null,
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_by_kind text not null check (created_by_kind in ('machine','human')),
  created_by_user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.speaker_identity_evidence (
  id uuid primary key default extensions.gen_random_uuid(),
  candidate_id uuid not null references transcript_core.speaker_identity_candidates(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  evidence_kind text not null check (evidence_kind in ('transcript_context','source_metadata','human_note','external_reference')),
  statement text not null,
  source_reference text,
  unique (candidate_id, sequence)
);

create table if not exists transcript_core.speaker_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  speaker_cluster_id uuid not null references transcript_core.speaker_clusters(id) on delete cascade,
  target_kind text not null check (target_kind in ('person','label')),
  target_ref text not null,
  display_name text not null,
  basis text not null check (basis in ('human_confirmed','trusted_source_metadata')),
  assigned_by_user_id uuid references auth.users(id),
  assigned_at timestamptz not null default now(),
  superseded_at timestamptz
);

create unique index if not exists speaker_assignments_one_active_uidx
  on transcript_core.speaker_assignments(speaker_cluster_id)
  where superseded_at is null;

create table if not exists transcript_core.utterances (
  id uuid primary key default extensions.gen_random_uuid(),
  analysis_run_id uuid not null references transcript_core.speaker_analysis_runs(id) on delete cascade,
  transcript_revision_id uuid not null references transcript_core.transcript_revisions(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  speaker_cluster_id uuid references transcript_core.speaker_clusters(id) on delete set null,
  start_ms bigint not null check (start_ms >= 0),
  end_ms bigint not null check (end_ms >= start_ms),
  text text not null,
  created_at timestamptz not null default now(),
  unique (analysis_run_id, sequence)
);

create table if not exists transcript_core.utterance_segments (
  utterance_id uuid not null references transcript_core.utterances(id) on delete cascade,
  transcript_segment_id uuid not null references transcript_core.transcript_segments(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  primary key (utterance_id, transcript_segment_id),
  unique (utterance_id, ordinal)
);

create index if not exists speaker_analysis_recording_idx
  on transcript_core.speaker_analysis_runs(recording_id, created_at desc);
create index if not exists speaker_clusters_recording_idx
  on transcript_core.speaker_clusters(recording_id, created_at);
create index if not exists utterances_revision_idx
  on transcript_core.utterances(transcript_revision_id, sequence);
create index if not exists speaker_candidates_cluster_idx
  on transcript_core.speaker_identity_candidates(speaker_cluster_id, created_at);

alter table transcript_core.script_drafts enable row level security;
alter table transcript_core.speaker_analysis_runs enable row level security;
alter table transcript_core.speaker_clusters enable row level security;
alter table transcript_core.speaker_cluster_ranges enable row level security;
alter table transcript_core.speaker_cluster_range_segments enable row level security;
alter table transcript_core.speaker_identity_candidates enable row level security;
alter table transcript_core.speaker_identity_evidence enable row level security;
alter table transcript_core.speaker_assignments enable row level security;
alter table transcript_core.utterances enable row level security;
alter table transcript_core.utterance_segments enable row level security;

create or replace function public.transcript_core_save_script_draft(
  p_script_document_id uuid,
  p_snapshot jsonb,
  p_snapshot_schema_version integer default 1,
  p_base_revision_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  target_draft_id uuid;
begin
  select workspace_id into target_workspace_id
  from transcript_core.script_documents
  where id = p_script_document_id;
  if target_workspace_id is null then raise exception 'SCRIPT_DOCUMENT_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if jsonb_typeof(p_snapshot) <> 'object' then raise exception 'SCRIPT_SNAPSHOT_MUST_BE_OBJECT'; end if;
  if p_snapshot_schema_version <> 1 then raise exception 'SCRIPT_SNAPSHOT_SCHEMA_UNSUPPORTED:%', p_snapshot_schema_version; end if;
  if p_base_revision_id is not null and not exists (
    select 1 from transcript_core.script_revisions
    where id = p_base_revision_id and script_document_id = p_script_document_id
  ) then
    raise exception 'BASE_REVISION_NOT_IN_DOCUMENT';
  end if;

  insert into transcript_core.script_drafts(
    script_document_id, base_revision_id, snapshot_schema_version, snapshot, updated_by
  ) values (
    p_script_document_id, p_base_revision_id, p_snapshot_schema_version, p_snapshot, auth.uid()
  )
  on conflict (script_document_id) do update
  set base_revision_id = excluded.base_revision_id,
      snapshot_schema_version = excluded.snapshot_schema_version,
      snapshot = excluded.snapshot,
      updated_by = auth.uid(),
      updated_at = now()
  returning id into target_draft_id;

  return target_draft_id;
end;
$$;

create or replace function public.transcript_core_get_script_draft(p_script_document_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  draft_row transcript_core.script_drafts%rowtype;
begin
  select workspace_id into target_workspace_id
  from transcript_core.script_documents
  where id = p_script_document_id;
  if target_workspace_id is null then raise exception 'SCRIPT_DOCUMENT_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;
  select * into draft_row
  from transcript_core.script_drafts
  where script_document_id = p_script_document_id;
  if not found then return null; end if;
  return to_jsonb(draft_row);
end;
$$;

create or replace function public.transcript_core_create_native_script_revision(
  p_script_document_id uuid,
  p_snapshot jsonb,
  p_content_hash text,
  p_snapshot_schema_version integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  next_ordinal integer;
  revision_id uuid;
begin
  select workspace_id into target_workspace_id
  from transcript_core.script_documents
  where id = p_script_document_id
  for update;
  if target_workspace_id is null then raise exception 'SCRIPT_DOCUMENT_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if jsonb_typeof(p_snapshot) <> 'object' then raise exception 'SCRIPT_SNAPSHOT_MUST_BE_OBJECT'; end if;
  if p_snapshot_schema_version <> 1 then raise exception 'SCRIPT_SNAPSHOT_SCHEMA_UNSUPPORTED:%', p_snapshot_schema_version; end if;
  if nullif(trim(p_content_hash), '') is null then raise exception 'SCRIPT_CONTENT_HASH_REQUIRED'; end if;

  select coalesce(max(ordinal), 0) + 1 into next_ordinal
  from transcript_core.script_revisions
  where script_document_id = p_script_document_id;

  insert into transcript_core.script_revisions(
    script_document_id, source_asset_id, content_hash, origin_kind, ordinal,
    snapshot_schema_version, native_snapshot, created_by
  ) values (
    p_script_document_id, null, p_content_hash, 'native', next_ordinal,
    p_snapshot_schema_version, p_snapshot, auth.uid()
  ) returning id into revision_id;

  update transcript_core.script_drafts
  set base_revision_id = revision_id, updated_at = now(), updated_by = auth.uid()
  where script_document_id = p_script_document_id;

  return revision_id;
end;
$$;

create or replace function public.transcript_core_get_script_revision(p_revision_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  revision_row transcript_core.script_revisions%rowtype;
begin
  select sd.workspace_id into target_workspace_id
  from transcript_core.script_revisions sr
  join transcript_core.script_documents sd on sd.id = sr.script_document_id
  where sr.id = p_revision_id;
  if target_workspace_id is null then raise exception 'SCRIPT_REVISION_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;
  select * into revision_row from transcript_core.script_revisions where id = p_revision_id;
  return to_jsonb(revision_row);
end;
$$;

create or replace function public.transcript_core_store_speech_analysis(
  p_recording_id uuid,
  p_transcript_revision_id uuid,
  p_provider text,
  p_provider_model text,
  p_clusters jsonb,
  p_utterances jsonb,
  p_source_job_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  target_transcript_id uuid;
  revision_transcript_id uuid;
  analysis_id uuid;
  cluster jsonb;
  range_item jsonb;
  utterance_item jsonb;
  segment_id_text text;
  cluster_id uuid;
  range_id uuid;
  utterance_id uuid;
  range_sequence integer;
  segment_ordinal integer;
begin
  if jsonb_typeof(p_clusters) <> 'array' then raise exception 'SPEAKER_CLUSTERS_MUST_BE_ARRAY'; end if;
  if jsonb_typeof(p_utterances) <> 'array' then raise exception 'UTTERANCES_MUST_BE_ARRAY'; end if;
  if nullif(trim(p_provider), '') is null then raise exception 'SPEAKER_PROVIDER_REQUIRED'; end if;

  select r.workspace_id, t.id into target_workspace_id, target_transcript_id
  from transcript_core.recordings r
  join transcript_core.transcripts t on t.recording_id = r.id
  where r.id = p_recording_id;
  if target_workspace_id is null then raise exception 'RECORDING_TRANSCRIPT_NOT_FOUND'; end if;

  select transcript_id into revision_transcript_id
  from transcript_core.transcript_revisions
  where id = p_transcript_revision_id;
  if revision_transcript_id is null or revision_transcript_id <> target_transcript_id then
    raise exception 'TRANSCRIPT_REVISION_RECORDING_MISMATCH';
  end if;

  if p_source_job_id is not null and not exists (
    select 1 from transcript_core.processing_jobs
    where id = p_source_job_id and workspace_id = target_workspace_id
  ) then
    raise exception 'SOURCE_JOB_WORKSPACE_MISMATCH';
  end if;

  insert into transcript_core.speaker_analysis_runs(
    workspace_id, recording_id, transcript_revision_id, source_job_id, provider, provider_model
  ) values (
    target_workspace_id, p_recording_id, p_transcript_revision_id, p_source_job_id, p_provider, p_provider_model
  ) returning id into analysis_id;

  for cluster in select * from jsonb_array_elements(p_clusters)
  loop
    if nullif(cluster->>'speakerKey', '') is null then raise exception 'SPEAKER_CLUSTER_KEY_REQUIRED'; end if;
    insert into transcript_core.speaker_clusters(analysis_run_id, recording_id, provider_speaker_key)
    values (analysis_id, p_recording_id, cluster->>'speakerKey')
    returning id into cluster_id;

    range_sequence := 0;
    for range_item in select * from jsonb_array_elements(coalesce(cluster->'ranges', '[]'::jsonb))
    loop
      range_sequence := range_sequence + 1;
      insert into transcript_core.speaker_cluster_ranges(
        speaker_cluster_id, sequence, start_ms, end_ms
      ) values (
        cluster_id, range_sequence,
        (range_item->>'startMs')::bigint,
        (range_item->>'endMs')::bigint
      ) returning id into range_id;

      segment_ordinal := 0;
      for segment_id_text in select jsonb_array_elements_text(coalesce(range_item->'transcriptSegmentIds', '[]'::jsonb))
      loop
        if not exists (
          select 1
          from transcript_core.transcript_segments ts
          join transcript_core.transcript_revisions tr on tr.transcript_id = ts.transcript_id
          where ts.id = segment_id_text::uuid and tr.id = p_transcript_revision_id
        ) then
          raise exception 'CLUSTER_RANGE_SEGMENT_REVISION_MISMATCH:%', segment_id_text;
        end if;
        segment_ordinal := segment_ordinal + 1;
        insert into transcript_core.speaker_cluster_range_segments(
          speaker_cluster_range_id, transcript_segment_id, ordinal
        ) values (range_id, segment_id_text::uuid, segment_ordinal);
      end loop;
    end loop;
  end loop;

  for utterance_item in select * from jsonb_array_elements(p_utterances)
  loop
    cluster_id := null;
    if nullif(utterance_item->>'speakerKey', '') is not null then
      select id into cluster_id
      from transcript_core.speaker_clusters
      where analysis_run_id = analysis_id
        and provider_speaker_key = utterance_item->>'speakerKey';
      if cluster_id is null then raise exception 'UTTERANCE_SPEAKER_KEY_NOT_FOUND:%', utterance_item->>'speakerKey'; end if;
    end if;

    insert into transcript_core.utterances(
      analysis_run_id, transcript_revision_id, sequence, speaker_cluster_id, start_ms, end_ms, text
    ) values (
      analysis_id,
      p_transcript_revision_id,
      (utterance_item->>'sequence')::integer,
      cluster_id,
      (utterance_item->>'startMs')::bigint,
      (utterance_item->>'endMs')::bigint,
      utterance_item->>'text'
    ) returning id into utterance_id;

    segment_ordinal := 0;
    for segment_id_text in select jsonb_array_elements_text(coalesce(utterance_item->'transcriptSegmentIds', '[]'::jsonb))
    loop
      if not exists (
        select 1
        from transcript_core.transcript_segments ts
        join transcript_core.transcript_revisions tr on tr.transcript_id = ts.transcript_id
        where ts.id = segment_id_text::uuid and tr.id = p_transcript_revision_id
      ) then
        raise exception 'UTTERANCE_SEGMENT_REVISION_MISMATCH:%', segment_id_text;
      end if;
      segment_ordinal := segment_ordinal + 1;
      insert into transcript_core.utterance_segments(utterance_id, transcript_segment_id, ordinal)
      values (utterance_id, segment_id_text::uuid, segment_ordinal);
    end loop;
  end loop;

  return analysis_id;
end;
$$;

create or replace function public.transcript_core_confirm_speaker_assignment(
  p_speaker_cluster_id uuid,
  p_target_kind text,
  p_target_ref text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  new_assignment_id uuid;
begin
  select sar.workspace_id into target_workspace_id
  from transcript_core.speaker_clusters sc
  join transcript_core.speaker_analysis_runs sar on sar.id = sc.analysis_run_id
  where sc.id = p_speaker_cluster_id;
  if target_workspace_id is null then raise exception 'SPEAKER_CLUSTER_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if p_target_kind not in ('person','label') then raise exception 'SPEAKER_TARGET_KIND_INVALID'; end if;
  if nullif(trim(p_target_ref), '') is null then raise exception 'SPEAKER_TARGET_REF_REQUIRED'; end if;
  if nullif(trim(p_display_name), '') is null then raise exception 'SPEAKER_DISPLAY_NAME_REQUIRED'; end if;

  update transcript_core.speaker_assignments
  set superseded_at = now()
  where speaker_cluster_id = p_speaker_cluster_id and superseded_at is null;

  insert into transcript_core.speaker_assignments(
    speaker_cluster_id, target_kind, target_ref, display_name, basis, assigned_by_user_id
  ) values (
    p_speaker_cluster_id, p_target_kind, p_target_ref, p_display_name, 'human_confirmed', auth.uid()
  ) returning id into new_assignment_id;

  return new_assignment_id;
end;
$$;

create or replace function public.transcript_core_list_speaker_clusters(p_recording_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  result jsonb;
begin
  select workspace_id into target_workspace_id
  from transcript_core.recordings
  where id = p_recording_id;
  if target_workspace_id is null then raise exception 'RECORDING_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(row_data order by created_at, provider_speaker_key), '[]'::jsonb)
  into result
  from (
    select
      sc.created_at,
      sc.provider_speaker_key,
      jsonb_build_object(
        'id', sc.id,
        'analysisRunId', sc.analysis_run_id,
        'provider', sar.provider,
        'providerModel', sar.provider_model,
        'providerSpeakerKey', sc.provider_speaker_key,
        'ranges', coalesce((
          select jsonb_agg(jsonb_build_object(
            'startMs', scr.start_ms,
            'endMs', scr.end_ms,
            'transcriptSegmentIds', coalesce((
              select jsonb_agg(scrs.transcript_segment_id order by scrs.ordinal)
              from transcript_core.speaker_cluster_range_segments scrs
              where scrs.speaker_cluster_range_id = scr.id
            ), '[]'::jsonb)
          ) order by scr.sequence)
          from transcript_core.speaker_cluster_ranges scr
          where scr.speaker_cluster_id = sc.id
        ), '[]'::jsonb),
        'assignment', (
          select jsonb_build_object(
            'id', sa.id,
            'targetKind', sa.target_kind,
            'targetRef', sa.target_ref,
            'displayName', sa.display_name,
            'basis', sa.basis,
            'assignedAt', sa.assigned_at
          )
          from transcript_core.speaker_assignments sa
          where sa.speaker_cluster_id = sc.id and sa.superseded_at is null
        )
      ) as row_data
    from transcript_core.speaker_clusters sc
    join transcript_core.speaker_analysis_runs sar on sar.id = sc.analysis_run_id
    where sc.recording_id = p_recording_id
  ) q;
  return result;
end;
$$;

create or replace function public.transcript_core_list_utterances(p_transcript_revision_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  result jsonb;
begin
  select r.workspace_id into target_workspace_id
  from transcript_core.transcript_revisions tr
  join transcript_core.transcripts t on t.id = tr.transcript_id
  join transcript_core.recordings r on r.id = t.recording_id
  where tr.id = p_transcript_revision_id;
  if target_workspace_id is null then raise exception 'TRANSCRIPT_REVISION_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', u.id,
    'analysisRunId', u.analysis_run_id,
    'sequence', u.sequence,
    'speakerClusterId', u.speaker_cluster_id,
    'startMs', u.start_ms,
    'endMs', u.end_ms,
    'text', u.text,
    'transcriptSegmentIds', coalesce((
      select jsonb_agg(us.transcript_segment_id order by us.ordinal)
      from transcript_core.utterance_segments us
      where us.utterance_id = u.id
    ), '[]'::jsonb),
    'assignment', (
      select jsonb_build_object(
        'id', sa.id,
        'targetKind', sa.target_kind,
        'targetRef', sa.target_ref,
        'displayName', sa.display_name,
        'basis', sa.basis,
        'assignedAt', sa.assigned_at
      )
      from transcript_core.speaker_assignments sa
      where sa.speaker_cluster_id = u.speaker_cluster_id and sa.superseded_at is null
    )
  ) order by u.analysis_run_id, u.sequence), '[]'::jsonb)
  into result
  from transcript_core.utterances u
  where u.transcript_revision_id = p_transcript_revision_id;

  return result;
end;
$$;

create or replace function public.transcript_core_complete_performance_parse_job_v2(
  p_job_id uuid,
  p_parser_adapter text,
  p_parser_version text,
  p_roles jsonb,
  p_cues jsonb,
  p_events jsonb,
  p_native_snapshot jsonb
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target transcript_core.processing_jobs%rowtype;
  target_revision_id uuid;
  target_script_id uuid;
  role_name text;
  cue jsonb;
  evt jsonb;
  i integer := 0;
begin
  select * into target
  from transcript_core.processing_jobs
  where id = p_job_id
  for update;
  if not found or target.job_type <> 'parse_performance_script' then raise exception 'INVALID_PARSE_JOB'; end if;

  select id into target_script_id
  from transcript_core.performance_scripts
  where source_job_id = p_job_id;
  if target_script_id is not null then return target_script_id; end if;

  select id into target_revision_id
  from transcript_core.script_revisions
  where source_asset_id = target.source_asset_id;
  if target_revision_id is null then raise exception 'SCRIPT_REVISION_FOR_JOB_NOT_FOUND'; end if;
  if jsonb_typeof(p_native_snapshot) <> 'object' then raise exception 'SCRIPT_SNAPSHOT_MUST_BE_OBJECT'; end if;

  insert into transcript_core.performance_scripts(script_revision_id, source_job_id, parser_adapter, parser_version)
  values (target_revision_id, p_job_id, p_parser_adapter, p_parser_version)
  returning id into target_script_id;

  update transcript_core.script_revisions
  set parser_adapter = p_parser_adapter,
      parser_version = p_parser_version,
      snapshot_schema_version = 1,
      native_snapshot = p_native_snapshot
  where id = target_revision_id;

  for role_name in select jsonb_array_elements_text(p_roles)
  loop
    insert into transcript_core.cast_roles(performance_script_id, role_key, display_name)
    values (target_script_id, lower(role_name), role_name);
  end loop;

  for cue in select * from jsonb_array_elements(p_cues)
  loop
    insert into transcript_core.performance_cues(
      performance_script_id, sequence, speakers, dialogue, instructions_before,
      synchronization_mode, source_paragraph, source_style
    ) values (
      target_script_id,
      (cue->>'sequence')::integer,
      array(select jsonb_array_elements_text(cue->'speakers')),
      cue->>'dialogue',
      coalesce(array(select jsonb_array_elements_text(cue->'instructionsBefore')), '{}'),
      cue->>'synchronizationMode',
      (cue->>'sourceParagraph')::integer,
      cue->>'sourceStyle'
    );
  end loop;

  for evt in select * from jsonb_array_elements(p_events)
  loop
    i := i + 1;
    insert into transcript_core.performance_parse_events(
      performance_script_id, sequence, event_kind, payload, source_paragraph, source_style
    ) values (
      target_script_id,
      i,
      evt->>'kind',
      evt - 'kind' - 'sourceParagraph' - 'sourceStyle',
      (evt->>'sourceParagraph')::integer,
      evt->>'sourceStyle'
    );
  end loop;

  update transcript_core.processing_jobs
  set status = 'ready',
      provider = 'native-odt',
      provider_model = p_parser_adapter || ':' || p_parser_version,
      heartbeat_at = null,
      claimed_at = null,
      finished_at = now()
  where id = p_job_id;

  return target_script_id;
end;
$$;

revoke all on function public.transcript_core_save_script_draft(uuid,jsonb,integer,uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_get_script_draft(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_create_native_script_revision(uuid,jsonb,text,integer) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_get_script_revision(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_store_speech_analysis(uuid,uuid,text,text,jsonb,jsonb,uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_confirm_speaker_assignment(uuid,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_speaker_clusters(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_utterances(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_complete_performance_parse_job_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb) from public, anon, authenticated, service_role;

grant execute on function public.transcript_core_save_script_draft(uuid,jsonb,integer,uuid) to authenticated;
grant execute on function public.transcript_core_get_script_draft(uuid) to authenticated;
grant execute on function public.transcript_core_create_native_script_revision(uuid,jsonb,text,integer) to authenticated;
grant execute on function public.transcript_core_get_script_revision(uuid) to authenticated;
grant execute on function public.transcript_core_confirm_speaker_assignment(uuid,text,text,text) to authenticated;
grant execute on function public.transcript_core_list_speaker_clusters(uuid) to authenticated;
grant execute on function public.transcript_core_list_utterances(uuid) to authenticated;

grant execute on function public.transcript_core_store_speech_analysis(uuid,uuid,text,text,jsonb,jsonb,uuid) to service_role;
grant execute on function public.transcript_core_complete_performance_parse_job_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb) to service_role;
