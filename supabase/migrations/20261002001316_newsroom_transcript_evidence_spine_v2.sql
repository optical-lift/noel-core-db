create table if not exists transcript_core.processing_usage_events (
  id uuid primary key default gen_random_uuid(),
  processing_job_id uuid not null references transcript_core.processing_jobs(id) on delete cascade,
  stage text not null,
  provider text not null,
  provider_model text,
  provider_request_id text,
  audio_seconds numeric not null check (audio_seconds >= 0),
  request_count integer not null default 1 check (request_count >= 0),
  estimated_paid_equivalent_usd numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists processing_usage_events_job_idx
  on transcript_core.processing_usage_events(processing_job_id, created_at);

alter table transcript_core.processing_usage_events enable row level security;
revoke all on transcript_core.processing_usage_events from anon, authenticated;

create or replace function public.transcript_core_record_processing_usage(
  p_job_id uuid,
  p_stage text,
  p_provider text,
  p_provider_model text,
  p_provider_request_id text,
  p_audio_seconds numeric,
  p_request_count integer default 1,
  p_estimated_paid_equivalent_usd numeric default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from transcript_core.processing_jobs where id = p_job_id) then
    raise exception 'PROCESSING_JOB_NOT_FOUND';
  end if;
  if nullif(trim(p_stage), '') is null then raise exception 'USAGE_STAGE_REQUIRED'; end if;
  if nullif(trim(p_provider), '') is null then raise exception 'USAGE_PROVIDER_REQUIRED'; end if;
  if coalesce(p_audio_seconds, -1) < 0 then raise exception 'USAGE_AUDIO_SECONDS_INVALID'; end if;
  if coalesce(p_request_count, -1) < 0 then raise exception 'USAGE_REQUEST_COUNT_INVALID'; end if;

  insert into transcript_core.processing_usage_events(
    processing_job_id, stage, provider, provider_model, provider_request_id,
    audio_seconds, request_count, estimated_paid_equivalent_usd, metadata
  ) values (
    p_job_id, trim(p_stage), trim(p_provider), nullif(trim(p_provider_model), ''),
    nullif(trim(p_provider_request_id), ''), p_audio_seconds, p_request_count,
    p_estimated_paid_equivalent_usd, coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.transcript_core_record_processing_usage(uuid,text,text,text,text,numeric,integer,numeric,jsonb) from public, anon, authenticated;
grant execute on function public.transcript_core_record_processing_usage(uuid,text,text,text,text,numeric,integer,numeric,jsonb) to service_role;

create or replace function newsroom.materialize_utterances_internal(p_transcript_revision_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_recording_id uuid;
  v_workspace_id uuid;
  v_analysis_id uuid;
  v_utterance_id uuid;
  v_sequence integer := 0;
  v_text text := '';
  v_start_ms bigint;
  v_end_ms bigint;
  v_speaker text := null;
  v_segment_ids uuid[] := array[]::uuid[];
  v_segment_id uuid;
  v_ordinal integer;
  v_row record;
  v_boundary boolean;
begin
  select r.id, r.workspace_id
    into v_recording_id, v_workspace_id
  from transcript_core.transcript_revisions tr
  join transcript_core.transcripts t on t.id = tr.transcript_id
  join transcript_core.recordings r on r.id = t.recording_id
  where tr.id = p_transcript_revision_id;

  if v_recording_id is null then raise exception 'TRANSCRIPT_REVISION_NOT_FOUND'; end if;

  select id into v_analysis_id
  from transcript_core.speaker_analysis_runs
  where transcript_revision_id = p_transcript_revision_id
    and provider = 'newsroom-utterance-v1'
  order by created_at desc
  limit 1;

  if v_analysis_id is not null then return v_analysis_id; end if;

  insert into transcript_core.speaker_analysis_runs(
    workspace_id, recording_id, transcript_revision_id, provider, provider_model
  ) values (
    v_workspace_id, v_recording_id, p_transcript_revision_id,
    'newsroom-utterance-v1', 'deterministic-grouping-v1'
  ) returning id into v_analysis_id;

  for v_row in
    select ts.id as segment_id, ts.sequence, tsv.start_ms, tsv.end_ms,
           tsv.text, nullif(trim(tsv.provider_speaker), '') as provider_speaker
    from transcript_core.transcript_segments ts
    join transcript_core.transcript_revisions tr on tr.transcript_id = ts.transcript_id
    join transcript_core.transcript_segment_versions tsv
      on tsv.transcript_segment_id = ts.id
     and tsv.transcript_revision_id = p_transcript_revision_id
    where tr.id = p_transcript_revision_id
    order by ts.sequence
  loop
    if nullif(trim(v_row.text), '') is null then continue; end if;

    v_boundary := cardinality(v_segment_ids) > 0 and (
      v_row.start_ms - v_end_ms > 1800
      or char_length(v_text) >= 480
      or (char_length(v_text) >= 260 and right(rtrim(v_text), 1) in ('.','!','?'))
      or (v_speaker is not null and v_row.provider_speaker is not null and v_speaker <> v_row.provider_speaker)
    );

    if v_boundary then
      v_sequence := v_sequence + 1;
      insert into transcript_core.utterances(
        analysis_run_id, transcript_revision_id, sequence, speaker_cluster_id,
        start_ms, end_ms, text
      ) values (
        v_analysis_id, p_transcript_revision_id, v_sequence, null,
        v_start_ms, v_end_ms, trim(v_text)
      ) returning id into v_utterance_id;

      v_ordinal := 0;
      foreach v_segment_id in array v_segment_ids loop
        v_ordinal := v_ordinal + 1;
        insert into transcript_core.utterance_segments(utterance_id, transcript_segment_id, ordinal)
        values (v_utterance_id, v_segment_id, v_ordinal);
      end loop;

      v_text := '';
      v_start_ms := null;
      v_end_ms := null;
      v_speaker := null;
      v_segment_ids := array[]::uuid[];
    end if;

    if cardinality(v_segment_ids) = 0 then
      v_start_ms := v_row.start_ms;
      v_speaker := v_row.provider_speaker;
      v_text := trim(v_row.text);
    else
      v_text := trim(v_text || ' ' || trim(v_row.text));
      if v_speaker is null then v_speaker := v_row.provider_speaker; end if;
    end if;
    v_end_ms := v_row.end_ms;
    v_segment_ids := array_append(v_segment_ids, v_row.segment_id);
  end loop;

  if cardinality(v_segment_ids) > 0 then
    v_sequence := v_sequence + 1;
    insert into transcript_core.utterances(
      analysis_run_id, transcript_revision_id, sequence, speaker_cluster_id,
      start_ms, end_ms, text
    ) values (
      v_analysis_id, p_transcript_revision_id, v_sequence, null,
      v_start_ms, v_end_ms, trim(v_text)
    ) returning id into v_utterance_id;

    v_ordinal := 0;
    foreach v_segment_id in array v_segment_ids loop
      v_ordinal := v_ordinal + 1;
      insert into transcript_core.utterance_segments(utterance_id, transcript_segment_id, ordinal)
      values (v_utterance_id, v_segment_id, v_ordinal);
    end loop;
  end if;

  return v_analysis_id;
end;
$$;

revoke all on function newsroom.materialize_utterances_internal(uuid) from public, anon, authenticated;

create or replace function public.transcript_core_ensure_utterance_analysis(p_transcript_revision_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
begin
  select r.workspace_id into v_workspace_id
  from transcript_core.transcript_revisions tr
  join transcript_core.transcripts t on t.id = tr.transcript_id
  join transcript_core.recordings r on r.id = t.recording_id
  where tr.id = p_transcript_revision_id;
  if v_workspace_id is null then raise exception 'TRANSCRIPT_REVISION_NOT_FOUND'; end if;
  return newsroom.materialize_utterances_internal(p_transcript_revision_id);
end;
$$;

revoke all on function public.transcript_core_ensure_utterance_analysis(uuid) from public, anon, authenticated;
grant execute on function public.transcript_core_ensure_utterance_analysis(uuid) to service_role;

create or replace function public.newsroom_ensure_transcript_utterances(p_transcript_revision_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
begin
  select r.workspace_id into v_workspace_id
  from transcript_core.transcript_revisions tr
  join transcript_core.transcripts t on t.id = tr.transcript_id
  join transcript_core.recordings r on r.id = t.recording_id
  where tr.id = p_transcript_revision_id;
  if v_workspace_id is null then raise exception 'TRANSCRIPT_REVISION_NOT_FOUND'; end if;
  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;
  return newsroom.materialize_utterances_internal(p_transcript_revision_id);
end;
$$;

grant execute on function public.newsroom_ensure_transcript_utterances(uuid) to authenticated;
revoke all on function public.newsroom_ensure_transcript_utterances(uuid) from anon;

create or replace function public.newsroom_get_transcript_evidence(p_recording_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
  v_revision_id uuid;
  v_analysis_id uuid;
  v_result jsonb;
begin
  select r.workspace_id, t.current_revision_id
    into v_workspace_id, v_revision_id
  from transcript_core.recordings r
  join transcript_core.transcripts t on t.recording_id = r.id
  where r.id = p_recording_id;

  if v_workspace_id is null then raise exception 'RECORDING_NOT_FOUND'; end if;
  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  if v_revision_id is null then
    return jsonb_build_object('revisionId', null, 'analysisRunId', null, 'utterances', '[]'::jsonb, 'speakerClusters', '[]'::jsonb);
  end if;

  perform newsroom.materialize_utterances_internal(v_revision_id);

  select sar.id into v_analysis_id
  from transcript_core.speaker_analysis_runs sar
  where sar.transcript_revision_id = v_revision_id
  order by
    exists (select 1 from transcript_core.speaker_clusters sc where sc.analysis_run_id = sar.id) desc,
    case when sar.provider = 'newsroom-utterance-v1' then 1 else 0 end,
    sar.created_at desc
  limit 1;

  select jsonb_build_object(
    'revisionId', v_revision_id,
    'analysisRunId', v_analysis_id,
    'analysisProvider', sar.provider,
    'analysisProviderModel', sar.provider_model,
    'utterances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id,
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
        'speaker', case when sc.id is null then null else jsonb_build_object(
          'clusterId', sc.id,
          'providerSpeakerKey', sc.provider_speaker_key,
          'displayName', sa.display_name,
          'assignmentBasis', sa.basis
        ) end
      ) order by u.sequence)
      from transcript_core.utterances u
      left join transcript_core.speaker_clusters sc on sc.id = u.speaker_cluster_id
      left join lateral (
        select display_name, basis
        from transcript_core.speaker_assignments x
        where x.speaker_cluster_id = sc.id and x.superseded_at is null
        order by x.assigned_at desc
        limit 1
      ) sa on true
      where u.analysis_run_id = v_analysis_id
    ), '[]'::jsonb),
    'speakerClusters', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sc.id,
        'providerSpeakerKey', sc.provider_speaker_key,
        'displayName', sa.display_name,
        'assignmentBasis', sa.basis,
        'rangeCount', (select count(*) from transcript_core.speaker_cluster_ranges scr where scr.speaker_cluster_id = sc.id)
      ) order by sc.provider_speaker_key)
      from transcript_core.speaker_clusters sc
      left join lateral (
        select display_name, basis
        from transcript_core.speaker_assignments x
        where x.speaker_cluster_id = sc.id and x.superseded_at is null
        order by x.assigned_at desc
        limit 1
      ) sa on true
      where sc.analysis_run_id = v_analysis_id
    ), '[]'::jsonb)
  ) into v_result
  from transcript_core.speaker_analysis_runs sar
  where sar.id = v_analysis_id;

  return coalesce(v_result, jsonb_build_object('revisionId', v_revision_id, 'analysisRunId', null, 'utterances', '[]'::jsonb, 'speakerClusters', '[]'::jsonb));
end;
$$;

grant execute on function public.newsroom_get_transcript_evidence(uuid) to authenticated;
revoke all on function public.newsroom_get_transcript_evidence(uuid) from anon;

create or replace function public.newsroom_checkpoint_transcript_revision(p_transcript_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
  v_current_revision_id uuid;
  v_editor newsroom.transcript_editor_states%rowtype;
  v_new_revision_id uuid := gen_random_uuid();
  v_new_ordinal integer;
  v_override_count integer;
begin
  select r.workspace_id, t.current_revision_id
    into v_workspace_id, v_current_revision_id
  from transcript_core.transcripts t
  join transcript_core.recordings r on r.id = t.recording_id
  where t.id = p_transcript_id;

  if v_workspace_id is null then raise exception 'TRANSCRIPT_NOT_FOUND'; end if;
  if public.transcript_core_can_workspace_edit(v_workspace_id) is not true then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if v_current_revision_id is null then raise exception 'TRANSCRIPT_REVISION_NOT_FOUND'; end if;

  select * into v_editor
  from newsroom.transcript_editor_states
  where transcript_id = p_transcript_id;

  if v_editor.transcript_id is null then
    return jsonb_build_object('revisionId', v_current_revision_id, 'created', false, 'reason', 'no_draft');
  end if;
  if v_editor.base_revision_id is distinct from v_current_revision_id then
    raise exception 'TRANSCRIPT_REVISION_CHANGED';
  end if;

  select count(*) into v_override_count
  from jsonb_each_text(coalesce(v_editor.text_overrides, '{}'::jsonb));
  if v_override_count = 0 then
    return jsonb_build_object('revisionId', v_current_revision_id, 'created', false, 'reason', 'no_text_changes');
  end if;

  select coalesce(max(ordinal), 0) + 1 into v_new_ordinal
  from transcript_core.transcript_revisions
  where transcript_id = p_transcript_id;

  insert into transcript_core.transcript_revisions(
    id, transcript_id, ordinal, revision_kind, source_job_id, provider, provider_model, created_by
  ) values (
    v_new_revision_id, p_transcript_id, v_new_ordinal, 'human'::transcript_core.transcript_revision_kind,
    null, null, null, auth.uid()
  );

  insert into transcript_core.transcript_segment_versions(
    transcript_revision_id, transcript_segment_id, start_ms, end_ms, text, provider_speaker
  )
  select
    v_new_revision_id,
    tsv.transcript_segment_id,
    tsv.start_ms,
    tsv.end_ms,
    coalesce(v_editor.text_overrides ->> tsv.transcript_segment_id::text, tsv.text),
    tsv.provider_speaker
  from transcript_core.transcript_segment_versions tsv
  where tsv.transcript_revision_id = v_current_revision_id;

  update transcript_core.transcripts
  set current_revision_id = v_new_revision_id
  where id = p_transcript_id;

  update newsroom.transcript_editor_states
  set base_revision_id = v_new_revision_id,
      text_overrides = '{}'::jsonb,
      updated_by = auth.uid(),
      updated_at = now()
  where transcript_id = p_transcript_id;

  perform newsroom.materialize_utterances_internal(v_new_revision_id);

  return jsonb_build_object(
    'revisionId', v_new_revision_id,
    'ordinal', v_new_ordinal,
    'revisionKind', 'human',
    'created', true,
    'textChangeCount', v_override_count
  );
end;
$$;

grant execute on function public.newsroom_checkpoint_transcript_revision(uuid) to authenticated;
revoke all on function public.newsroom_checkpoint_transcript_revision(uuid) from anon;

create or replace function public.newsroom_get_transcript_revision_history(p_transcript_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core
as $$
declare
  v_workspace_id uuid;
  v_result jsonb;
begin
  select r.workspace_id into v_workspace_id
  from transcript_core.transcripts t
  join transcript_core.recordings r on r.id = t.recording_id
  where t.id = p_transcript_id;
  if v_workspace_id is null then raise exception 'TRANSCRIPT_NOT_FOUND'; end if;
  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then raise exception 'WORKSPACE_READ_FORBIDDEN'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tr.id,
    'ordinal', tr.ordinal,
    'revisionKind', tr.revision_kind,
    'provider', tr.provider,
    'providerModel', tr.provider_model,
    'createdBy', tr.created_by,
    'createdAt', tr.created_at,
    'isCurrent', tr.id = t.current_revision_id
  ) order by tr.ordinal), '[]'::jsonb)
  into v_result
  from transcript_core.transcripts t
  join transcript_core.transcript_revisions tr on tr.transcript_id = t.id
  where t.id = p_transcript_id;
  return v_result;
end;
$$;

grant execute on function public.newsroom_get_transcript_revision_history(uuid) to authenticated;
revoke all on function public.newsroom_get_transcript_revision_history(uuid) from anon;

create or replace function public.newsroom_get_transcript_usage(p_recording_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core
as $$
declare
  v_workspace_id uuid;
  v_source_asset_id uuid;
  v_result jsonb;
begin
  select workspace_id, source_asset_id into v_workspace_id, v_source_asset_id
  from transcript_core.recordings where id = p_recording_id;
  if v_workspace_id is null then raise exception 'RECORDING_NOT_FOUND'; end if;
  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then raise exception 'WORKSPACE_READ_FORBIDDEN'; end if;

  select jsonb_build_object(
    'audioSeconds', coalesce(sum(u.audio_seconds), 0),
    'requestCount', coalesce(sum(u.request_count), 0),
    'estimatedPaidEquivalentUsd', coalesce(sum(u.estimated_paid_equivalent_usd), 0),
    'providers', coalesce(jsonb_agg(distinct jsonb_build_object('provider', u.provider, 'model', u.provider_model)) filter (where u.id is not null), '[]'::jsonb),
    'latestAt', max(u.created_at)
  ) into v_result
  from transcript_core.processing_jobs j
  left join transcript_core.processing_usage_events u on u.processing_job_id = j.id
  where j.workspace_id = v_workspace_id
    and j.source_asset_id = v_source_asset_id
    and j.job_type = 'transcribe_recording';

  return coalesce(v_result, jsonb_build_object('audioSeconds',0,'requestCount',0,'estimatedPaidEquivalentUsd',0,'providers','[]'::jsonb,'latestAt',null));
end;
$$;

grant execute on function public.newsroom_get_transcript_usage(uuid) to authenticated;
revoke all on function public.newsroom_get_transcript_usage(uuid) from anon;

-- Backfill durable provisional utterances for current transcript revisions already present.
do $$
declare v_revision_id uuid;
begin
  for v_revision_id in
    select current_revision_id from transcript_core.transcripts where current_revision_id is not null
  loop
    perform newsroom.materialize_utterances_internal(v_revision_id);
  end loop;
end;
$$;