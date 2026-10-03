-- Optical Lift Newsroom: internal chunk lineage for long-recording transcription.
-- The original recording remains the authoritative observed_original asset.
-- These rows only describe derived, provider-sized audio chunks used to create one transcript revision.

create table if not exists transcript_core.transcription_chunks (
  id uuid primary key,
  processing_job_id uuid not null references transcript_core.processing_jobs(id) on delete cascade,
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  derivative_asset_id uuid not null unique references transcript_core.assets(id) on delete restrict,
  sequence integer not null check (sequence > 0),
  start_ms bigint not null check (start_ms >= 0),
  end_ms bigint not null check (end_ms > start_ms),
  status text not null default 'queued' check (status in ('queued','processing','ready','failed_retryable','failed_terminal')),
  attempt integer not null default 0 check (attempt >= 0),
  provider text,
  provider_model text,
  provider_request_id text,
  segments jsonb,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  unique (processing_job_id, sequence)
);

create index if not exists transcription_chunks_job_status_idx
  on transcript_core.transcription_chunks(processing_job_id, status, sequence);

alter table transcript_core.transcription_chunks enable row level security;
revoke all on transcript_core.transcription_chunks from public, anon, authenticated;

create policy transcript_core_derivative_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'transcript-core-observed-derivatives'
  and public.transcript_core_can_workspace_edit(public.transcript_core_path_workspace(name))
);

create or replace function public.transcript_core_register_transcription_chunk(
  p_chunk_id uuid,
  p_job_id uuid,
  p_storage_bucket text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_byte_size bigint,
  p_sequence integer,
  p_start_ms bigint,
  p_end_ms bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_job transcript_core.processing_jobs%rowtype;
  existing_chunk transcript_core.transcription_chunks%rowtype;
  existing_asset transcript_core.assets%rowtype;
  new_asset_id uuid;
begin
  select * into target_job
  from transcript_core.processing_jobs
  where id = p_job_id
  for update;

  if not found or target_job.job_type <> 'transcribe_recording' then
    raise exception 'INVALID_TRANSCRIPTION_JOB';
  end if;
  if target_job.status in ('ready','failed_terminal') then
    raise exception 'TRANSCRIPTION_JOB_CLOSED';
  end if;
  if not public.transcript_core_can_workspace_edit(target_job.workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if p_storage_bucket <> 'transcript-core-observed-derivatives' then
    raise exception 'DERIVATIVE_BUCKET_MISMATCH';
  end if;
  if public.transcript_core_path_workspace(p_storage_path) is distinct from target_job.workspace_id then
    raise exception 'DERIVATIVE_PATH_WORKSPACE_MISMATCH';
  end if;
  if p_sequence <= 0 or p_start_ms < 0 or p_end_ms <= p_start_ms then
    raise exception 'INVALID_TRANSCRIPTION_CHUNK_RANGE';
  end if;
  if p_byte_size <= 0 or coalesce(length(trim(p_content_hash)), 0) = 0 then
    raise exception 'INVALID_TRANSCRIPTION_CHUNK_ASSET';
  end if;

  select * into existing_chunk
  from transcript_core.transcription_chunks
  where processing_job_id = p_job_id and sequence = p_sequence
  for update;

  if found then
    select * into existing_asset
    from transcript_core.assets
    where id = existing_chunk.derivative_asset_id;

    if existing_chunk.start_ms <> p_start_ms
      or existing_chunk.end_ms <> p_end_ms
      or existing_asset.storage_bucket <> p_storage_bucket
      or existing_asset.storage_path <> p_storage_path
      or existing_asset.content_hash <> p_content_hash
      or existing_asset.byte_size <> p_byte_size then
      raise exception 'TRANSCRIPTION_CHUNK_SEQUENCE_REUSED';
    end if;

    return jsonb_build_object(
      'chunk_id', existing_chunk.id,
      'asset_id', existing_chunk.derivative_asset_id,
      'sequence', existing_chunk.sequence,
      'status', existing_chunk.status
    );
  end if;

  insert into transcript_core.assets(
    workspace_id,
    provenance_class,
    storage_bucket,
    storage_path,
    content_hash,
    mime_type,
    byte_size
  ) values (
    target_job.workspace_id,
    'observed_derivative',
    p_storage_bucket,
    p_storage_path,
    p_content_hash,
    p_mime_type,
    p_byte_size
  ) returning id into new_asset_id;

  insert into transcript_core.transcription_chunks(
    id,
    processing_job_id,
    workspace_id,
    derivative_asset_id,
    sequence,
    start_ms,
    end_ms
  ) values (
    p_chunk_id,
    p_job_id,
    target_job.workspace_id,
    new_asset_id,
    p_sequence,
    p_start_ms,
    p_end_ms
  );

  return jsonb_build_object(
    'chunk_id', p_chunk_id,
    'asset_id', new_asset_id,
    'sequence', p_sequence,
    'status', 'queued'
  );
end;
$$;

revoke all on function public.transcript_core_register_transcription_chunk(uuid,uuid,text,text,text,text,bigint,integer,bigint,bigint) from public, anon;
grant execute on function public.transcript_core_register_transcription_chunk(uuid,uuid,text,text,text,text,bigint,integer,bigint,bigint) to authenticated;

create or replace function public.transcript_core_get_transcription_progress(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_job transcript_core.processing_jobs%rowtype;
  total_chunks integer;
  ready_chunks integer;
  processing_chunks integer;
  retryable_chunks integer;
  terminal_chunks integer;
begin
  select * into target_job
  from transcript_core.processing_jobs
  where id = p_job_id;

  if not found or target_job.job_type <> 'transcribe_recording' then
    raise exception 'INVALID_TRANSCRIPTION_JOB';
  end if;
  if not public.transcript_core_is_workspace_member(target_job.workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select
    count(*)::integer,
    count(*) filter (where status = 'ready')::integer,
    count(*) filter (where status = 'processing')::integer,
    count(*) filter (where status = 'failed_retryable')::integer,
    count(*) filter (where status = 'failed_terminal')::integer
  into total_chunks, ready_chunks, processing_chunks, retryable_chunks, terminal_chunks
  from transcript_core.transcription_chunks
  where processing_job_id = p_job_id;

  return jsonb_build_object(
    'jobId', target_job.id,
    'jobStatus', target_job.status,
    'totalChunks', total_chunks,
    'readyChunks', ready_chunks,
    'processingChunks', processing_chunks,
    'retryableChunks', retryable_chunks,
    'terminalChunks', terminal_chunks,
    'errorCode', target_job.error_code,
    'errorMessage', target_job.error_message
  );
end;
$$;

revoke all on function public.transcript_core_get_transcription_progress(uuid) from public, anon;
grant execute on function public.transcript_core_get_transcription_progress(uuid) to authenticated, service_role;

create or replace function public.transcript_core_claim_next_transcription_chunk(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_job transcript_core.processing_jobs%rowtype;
  target_chunk transcript_core.transcription_chunks%rowtype;
  target_asset transcript_core.assets%rowtype;
  total_chunks integer;
  ready_chunks integer;
  processing_chunks integer;
  retryable_chunks integer;
  terminal_chunks integer;
begin
  select * into target_job
  from transcript_core.processing_jobs
  where id = p_job_id
  for update;

  if not found or target_job.job_type <> 'transcribe_recording' then
    raise exception 'INVALID_TRANSCRIPTION_JOB';
  end if;

  select
    count(*)::integer,
    count(*) filter (where status = 'ready')::integer,
    count(*) filter (where status = 'processing')::integer,
    count(*) filter (where status = 'failed_retryable')::integer,
    count(*) filter (where status = 'failed_terminal')::integer
  into total_chunks, ready_chunks, processing_chunks, retryable_chunks, terminal_chunks
  from transcript_core.transcription_chunks
  where processing_job_id = p_job_id;

  if total_chunks = 0 or target_job.status in ('ready','failed_terminal') then
    return jsonb_build_object(
      'total_chunks', total_chunks,
      'ready_chunks', ready_chunks,
      'processing_chunks', processing_chunks,
      'retryable_chunks', retryable_chunks,
      'terminal_chunks', terminal_chunks,
      'chunk', null
    );
  end if;

  select * into target_chunk
  from transcript_core.transcription_chunks
  where processing_job_id = p_job_id
    and (
      status in ('queued','failed_retryable')
      or (status = 'processing' and started_at < now() - interval '4 minutes')
    )
  order by sequence
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object(
      'total_chunks', total_chunks,
      'ready_chunks', ready_chunks,
      'processing_chunks', processing_chunks,
      'retryable_chunks', retryable_chunks,
      'terminal_chunks', terminal_chunks,
      'chunk', null
    );
  end if;

  update transcript_core.transcription_chunks
  set status = 'processing',
      attempt = attempt + 1,
      started_at = now(),
      finished_at = null,
      error_code = null,
      error_message = null
  where id = target_chunk.id
  returning * into target_chunk;

  select * into target_asset
  from transcript_core.assets
  where id = target_chunk.derivative_asset_id;

  update transcript_core.processing_jobs
  set status = case when ready_chunks > 0 then 'partially_processed'::transcript_core.processing_job_status else 'processing'::transcript_core.processing_job_status end,
      started_at = coalesce(started_at, now()),
      heartbeat_at = now(),
      claimed_at = coalesce(claimed_at, now()),
      error_code = null,
      error_message = null
  where id = p_job_id;

  return jsonb_build_object(
    'total_chunks', total_chunks,
    'ready_chunks', ready_chunks,
    'processing_chunks', processing_chunks + 1,
    'retryable_chunks', greatest(retryable_chunks - case when target_chunk.attempt > 1 then 1 else 0 end, 0),
    'terminal_chunks', terminal_chunks,
    'chunk', jsonb_build_object(
      'chunk_id', target_chunk.id,
      'sequence', target_chunk.sequence,
      'start_ms', target_chunk.start_ms,
      'end_ms', target_chunk.end_ms,
      'asset_id', target_asset.id,
      'storage_bucket', target_asset.storage_bucket,
      'storage_path', target_asset.storage_path,
      'mime_type', target_asset.mime_type,
      'byte_size', target_asset.byte_size,
      'content_hash', target_asset.content_hash
    )
  );
end;
$$;

revoke all on function public.transcript_core_claim_next_transcription_chunk(uuid) from public, anon, authenticated;
grant execute on function public.transcript_core_claim_next_transcription_chunk(uuid) to service_role;

create or replace function public.transcript_core_complete_transcription_chunk(
  p_chunk_id uuid,
  p_provider text,
  p_provider_model text,
  p_provider_request_id text,
  p_segments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_chunk transcript_core.transcription_chunks%rowtype;
  total_chunks integer;
  ready_chunks integer;
  all_segments jsonb;
  target_revision_id uuid;
begin
  select * into target_chunk
  from transcript_core.transcription_chunks
  where id = p_chunk_id
  for update;

  if not found then raise exception 'TRANSCRIPTION_CHUNK_NOT_FOUND'; end if;
  if target_chunk.status = 'ready' then
    select count(*)::integer,
           count(*) filter (where status = 'ready')::integer
    into total_chunks, ready_chunks
    from transcript_core.transcription_chunks
    where processing_job_id = target_chunk.processing_job_id;

    return jsonb_build_object(
      'chunk_id', target_chunk.id,
      'total_chunks', total_chunks,
      'ready_chunks', ready_chunks,
      'revision_id', null
    );
  end if;
  if target_chunk.status <> 'processing' then
    raise exception 'TRANSCRIPTION_CHUNK_NOT_CLAIMED';
  end if;
  if jsonb_typeof(p_segments) <> 'array' or jsonb_array_length(p_segments) = 0 then
    raise exception 'TRANSCRIPTION_CHUNK_SEGMENTS_REQUIRED';
  end if;

  update transcript_core.transcription_chunks
  set status = 'ready',
      provider = p_provider,
      provider_model = p_provider_model,
      provider_request_id = nullif(p_provider_request_id, ''),
      segments = p_segments,
      finished_at = now(),
      error_code = null,
      error_message = null
  where id = target_chunk.id;

  select count(*)::integer,
         count(*) filter (where status = 'ready')::integer
  into total_chunks, ready_chunks
  from transcript_core.transcription_chunks
  where processing_job_id = target_chunk.processing_job_id;

  if ready_chunks = total_chunks and total_chunks > 0 then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'sequence', global_sequence,
        'startMs', start_ms,
        'endMs', end_ms,
        'text', segment_text,
        'providerSpeaker', provider_speaker
      ) order by global_sequence
    ), '[]'::jsonb)
    into all_segments
    from (
      select
        row_number() over (order by c.sequence, s.ordinality)::integer as global_sequence,
        (s.segment->>'startMs')::bigint as start_ms,
        (s.segment->>'endMs')::bigint as end_ms,
        s.segment->>'text' as segment_text,
        nullif(s.segment->>'providerSpeaker','') as provider_speaker
      from transcript_core.transcription_chunks c
      cross join lateral jsonb_array_elements(c.segments) with ordinality as s(segment, ordinality)
      where c.processing_job_id = target_chunk.processing_job_id
        and c.status = 'ready'
    ) normalized;

    select public.transcript_core_complete_transcription_job(
      target_chunk.processing_job_id,
      p_provider,
      p_provider_model,
      all_segments
    ) into target_revision_id;
  else
    update transcript_core.processing_jobs
    set status = 'partially_processed',
        heartbeat_at = null,
        claimed_at = null
    where id = target_chunk.processing_job_id;
  end if;

  return jsonb_build_object(
    'chunk_id', target_chunk.id,
    'total_chunks', total_chunks,
    'ready_chunks', ready_chunks,
    'revision_id', target_revision_id
  );
end;
$$;

revoke all on function public.transcript_core_complete_transcription_chunk(uuid,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.transcript_core_complete_transcription_chunk(uuid,text,text,text,jsonb) to service_role;

create or replace function public.transcript_core_fail_transcription_chunk(
  p_chunk_id uuid,
  p_retryable boolean,
  p_error_code text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path to 'transcript_core', 'public'
as $$
declare
  target_chunk transcript_core.transcription_chunks%rowtype;
begin
  select * into target_chunk
  from transcript_core.transcription_chunks
  where id = p_chunk_id
  for update;

  if not found then raise exception 'TRANSCRIPTION_CHUNK_NOT_FOUND'; end if;

  update transcript_core.transcription_chunks
  set status = case when p_retryable then 'failed_retryable' else 'failed_terminal' end,
      error_code = p_error_code,
      error_message = left(p_error_message, 4000),
      finished_at = case when p_retryable then null else now() end
  where id = p_chunk_id;

  update transcript_core.processing_jobs
  set status = 'partially_processed',
      heartbeat_at = null,
      claimed_at = null,
      error_code = case when p_retryable then 'CHUNK_RETRYABLE' else 'CHUNK_FAILED_TERMINAL' end,
      error_message = left(p_error_message, 4000)
  where id = target_chunk.processing_job_id
    and status <> 'ready';
end;
$$;

revoke all on function public.transcript_core_fail_transcription_chunk(uuid,boolean,text,text) from public, anon, authenticated;
grant execute on function public.transcript_core_fail_transcription_chunk(uuid,boolean,text,text) to service_role;