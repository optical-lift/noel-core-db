-- Optical Lift Newsroom: authenticated Transcript Core read surfaces and worker packet.
-- Reuses the existing transcript_core schema. No duplicate transcript tables are created.

create or replace function public.transcript_core_list_recordings(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare result jsonb;
begin
  if not public.transcript_core_is_workspace_member(p_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
  into result
  from (
    select
      r.created_at,
      jsonb_build_object(
        'id', r.id,
        'title', r.title,
        'sourceAssetId', r.source_asset_id,
        'createdAt', r.created_at,
        'transcriptId', t.id,
        'currentRevisionId', t.current_revision_id,
        'speakerAnalysisRunId', (
          select sar.id
          from transcript_core.speaker_analysis_runs sar
          where sar.recording_id = r.id
          order by sar.created_at desc
          limit 1
        ),
        'processingJobId', pj.id,
        'processingStatus', pj.status,
        'processingAttempt', pj.attempt,
        'processingErrorCode', pj.error_code,
        'processingErrorMessage', pj.error_message,
        'provider', pj.provider,
        'providerModel', pj.provider_model
      ) as row_data
    from transcript_core.recordings r
    left join transcript_core.transcripts t on t.recording_id = r.id
    left join lateral (
      select job.*
      from transcript_core.processing_jobs job
      where job.source_asset_id = r.source_asset_id
        and job.job_type = 'transcribe_recording'
      order by job.created_at desc
      limit 1
    ) pj on true
    where r.workspace_id = p_workspace_id
  ) q;

  return result;
end;
$$;

revoke all on function public.transcript_core_list_recordings(uuid) from public, anon;
grant execute on function public.transcript_core_list_recordings(uuid) to authenticated;

create or replace function public.transcript_core_get_recording_detail(p_recording_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_recording transcript_core.recordings%rowtype;
  target_asset transcript_core.assets%rowtype;
  target_transcript transcript_core.transcripts%rowtype;
  target_revision transcript_core.transcript_revisions%rowtype;
  target_job transcript_core.processing_jobs%rowtype;
  segment_rows jsonb := '[]'::jsonb;
begin
  select * into target_recording
  from transcript_core.recordings
  where id = p_recording_id;

  if not found then raise exception 'RECORDING_NOT_FOUND'; end if;
  if not public.transcript_core_is_workspace_member(target_recording.workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select * into target_asset
  from transcript_core.assets
  where id = target_recording.source_asset_id;

  select * into target_job
  from transcript_core.processing_jobs
  where source_asset_id = target_recording.source_asset_id
    and job_type = 'transcribe_recording'
  order by created_at desc
  limit 1;

  select * into target_transcript
  from transcript_core.transcripts
  where recording_id = target_recording.id;

  if target_transcript.id is not null and target_transcript.current_revision_id is not null then
    select * into target_revision
    from transcript_core.transcript_revisions
    where id = target_transcript.current_revision_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id,
      'sequence', s.sequence,
      'startMs', v.start_ms,
      'endMs', v.end_ms,
      'text', v.text,
      'providerSpeaker', v.provider_speaker
    ) order by s.sequence), '[]'::jsonb)
    into segment_rows
    from transcript_core.transcript_segments s
    join transcript_core.transcript_segment_versions v
      on v.transcript_segment_id = s.id
     and v.transcript_revision_id = target_revision.id
    where s.transcript_id = target_transcript.id;
  end if;

  return jsonb_build_object(
    'id', target_recording.id,
    'workspaceId', target_recording.workspace_id,
    'title', target_recording.title,
    'createdAt', target_recording.created_at,
    'sourceAsset', jsonb_build_object(
      'id', target_asset.id,
      'storageBucket', target_asset.storage_bucket,
      'storagePath', target_asset.storage_path,
      'contentHash', target_asset.content_hash,
      'mimeType', target_asset.mime_type,
      'byteSize', target_asset.byte_size
    ),
    'processingJob', case when target_job.id is null then null else jsonb_build_object(
      'id', target_job.id,
      'status', target_job.status,
      'attempt', target_job.attempt,
      'provider', target_job.provider,
      'providerModel', target_job.provider_model,
      'errorCode', target_job.error_code,
      'errorMessage', target_job.error_message
    ) end,
    'transcript', case when target_transcript.id is null then null else jsonb_build_object(
      'id', target_transcript.id,
      'currentRevisionId', target_transcript.current_revision_id,
      'revisionKind', target_revision.revision_kind,
      'revisionOrdinal', target_revision.ordinal,
      'provider', target_revision.provider,
      'providerModel', target_revision.provider_model,
      'segments', segment_rows
    ) end
  );
end;
$$;

revoke all on function public.transcript_core_get_recording_detail(uuid) from public, anon;
grant execute on function public.transcript_core_get_recording_detail(uuid) to authenticated;

create or replace function public.transcript_core_load_job_with_asset(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  j transcript_core.processing_jobs%rowtype;
  a transcript_core.assets%rowtype;
begin
  select * into j from transcript_core.processing_jobs where id = p_job_id;
  if not found then raise exception 'JOB_NOT_FOUND'; end if;
  if j.source_asset_id is null then raise exception 'JOB_HAS_NO_SOURCE_ASSET'; end if;

  select * into a from transcript_core.assets where id = j.source_asset_id;
  if not found then raise exception 'ASSET_NOT_FOUND'; end if;

  return jsonb_build_object(
    'job_id', j.id,
    'workspace_id', j.workspace_id,
    'job_type', j.job_type,
    'status', j.status,
    'attempt', j.attempt,
    'queue_name', j.queue_name,
    'queue_message_id', j.queue_message_id,
    'asset_id', a.id,
    'storage_bucket', a.storage_bucket,
    'storage_path', a.storage_path,
    'mime_type', a.mime_type,
    'byte_size', a.byte_size,
    'content_hash', a.content_hash
  );
end;
$$;

revoke all on function public.transcript_core_load_job_with_asset(uuid) from public, anon, authenticated;
grant execute on function public.transcript_core_load_job_with_asset(uuid) to service_role;