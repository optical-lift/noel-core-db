create or replace function public.transcript_core_read_queue(
  p_queue_name text, p_visibility_timeout_seconds integer default 300
)
returns table(msg_id bigint, read_ct bigint, enqueued_at timestamptz, vt timestamptz, message jsonb)
language plpgsql
security definer
set search_path = public, pgmq
as $$
begin
  if p_queue_name not in (
    'transcript_core_transcription_jobs','transcript_core_performance_parse_jobs',
    'transcript_core_voice_render_jobs','transcript_core_performance_mix_jobs','transcript_core_performance_verify_jobs'
  ) then raise exception 'QUEUE_NOT_ALLOWED'; end if;
  return query
  select r.msg_id, r.read_ct::bigint, r.enqueued_at, r.vt, r.message
  from pgmq.read(p_queue_name, p_visibility_timeout_seconds, 1) r;
end;
$$;

revoke all on function public.transcript_core_read_queue(text,integer) from public, anon, authenticated, service_role;
grant execute on function public.transcript_core_read_queue(text,integer) to service_role;