create or replace function public.transcript_core_list_resume_candidates_v1(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  v_result jsonb;
begin
  if not public.transcript_core_can_workspace_edit(p_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(q.item order by q.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select r.created_at,
      jsonb_build_object(
        'recordingId', r.id,
        'title', r.title,
        'jobId', pj.id,
        'jobStatus', pj.status,
        'sourceByteSize', a.byte_size,
        'storageBucket', a.storage_bucket,
        'storagePath', a.storage_path,
        'mimeType', a.mime_type,
        'existingSequences', coalesce((select jsonb_agg(c.sequence order by c.sequence) from transcript_core.transcription_chunks c where c.processing_job_id = pj.id), '[]'::jsonb),
        'existingChunkCount', (select count(*)::integer from transcript_core.transcription_chunks c where c.processing_job_id = pj.id),
        'errorCode', pj.error_code,
        'errorMessage', pj.error_message,
        'createdAt', r.created_at
      ) as item
    from transcript_core.recordings r
    join transcript_core.assets a on a.id = r.source_asset_id
    join lateral (
      select job.* from transcript_core.processing_jobs job
      where job.source_asset_id = r.source_asset_id and job.job_type = 'transcribe_recording'
      order by job.created_at desc limit 1
    ) pj on true
    where r.workspace_id = p_workspace_id
      and a.provenance_class = 'observed_original'
      and a.storage_bucket = 'transcript-core-observed-originals'
      and a.byte_size > 24 * 1024 * 1024
      and pj.status::text in ('queued', 'failed_retryable')
      and not exists (select 1 from transcript_core.transcripts t where t.recording_id = r.id and t.current_revision_id is not null)
      and not exists (select 1 from transcript_core.transcription_chunks c where c.processing_job_id = pj.id and c.status = 'processing')
  ) q;

  return v_result;
end;
$$;

revoke all on function public.transcript_core_list_resume_candidates_v1(uuid) from public, anon;
grant execute on function public.transcript_core_list_resume_candidates_v1(uuid) to authenticated;