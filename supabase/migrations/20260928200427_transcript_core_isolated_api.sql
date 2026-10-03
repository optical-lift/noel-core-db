create or replace function public.transcript_core_path_workspace(object_name text)
returns uuid
language plpgsql
immutable
as $$
declare result uuid;
begin
  begin
    result := split_part(object_name, '/', 1)::uuid;
  exception when others then
    return null;
  end;
  return result;
end;
$$;

create or replace function public.transcript_core_is_workspace_member(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = transcript_core, public
as $$
  select exists (
    select 1
    from transcript_core.workspace_memberships m
    where m.workspace_id = target_workspace
      and m.user_id = auth.uid()
  );
$$;

create or replace function public.transcript_core_can_workspace_edit(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = transcript_core, public
as $$
  select exists (
    select 1
    from transcript_core.workspace_memberships m
    where m.workspace_id = target_workspace
      and m.user_id = auth.uid()
      and m.role in ('owner','editor')
  );
$$;

create or replace function public.transcript_core_create_workspace(p_name text)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  insert into transcript_core.workspaces(name, created_by)
  values (p_name, auth.uid()) returning id into new_id;
  insert into transcript_core.workspace_memberships(workspace_id, user_id, role)
  values (new_id, auth.uid(), 'owner');
  return new_id;
end;
$$;

create or replace function public.transcript_core_processing_queue_name(target_job_type text)
returns text
language sql
immutable
as $$
  select case target_job_type
    when 'transcribe_recording' then 'transcript_core_transcription_jobs'
    when 'parse_performance_script' then 'transcript_core_performance_parse_jobs'
    when 'render_voice_take' then 'transcript_core_voice_render_jobs'
    when 'mix_performance' then 'transcript_core_performance_mix_jobs'
    when 'verify_performance' then 'transcript_core_performance_verify_jobs'
    else null
  end;
$$;

create or replace function public.transcript_core_enqueue_processing_job(target_job_id uuid)
returns bigint
language plpgsql
security definer
set search_path = transcript_core, public, pgmq
as $$
declare
  target_job transcript_core.processing_jobs%rowtype;
  target_queue text;
  message_id bigint;
begin
  select * into target_job
  from transcript_core.processing_jobs
  where id = target_job_id
  for update;
  if not found then raise exception 'PROCESSING_JOB_NOT_FOUND'; end if;
  if target_job.queue_message_id is not null then return target_job.queue_message_id; end if;
  target_queue := public.transcript_core_processing_queue_name(target_job.job_type);
  if target_queue is null then raise exception 'UNSUPPORTED_JOB_TYPE:%', target_job.job_type; end if;
  select q into message_id from pgmq.send(target_queue, jsonb_build_object('job_id', target_job.id)) as q;
  update transcript_core.processing_jobs
  set queue_name = target_queue, queue_message_id = message_id
  where id = target_job.id;
  return message_id;
end;
$$;

create or replace function public.transcript_core_register_source_ingest(
  p_ingest_id uuid,
  p_workspace_id uuid,
  p_source_kind text,
  p_title text,
  p_storage_bucket text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_byte_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public, pgmq
as $$
declare
  existing transcript_core.source_ingests%rowtype;
  new_asset_id uuid;
  new_recording_id uuid;
  new_script_document_id uuid;
  new_script_revision_id uuid;
  new_job_id uuid;
  expected_bucket text;
  expected_provenance transcript_core.asset_provenance_class;
  initial_job_type text;
begin
  if not public.transcript_core_can_workspace_edit(p_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if p_source_kind = 'recording' then
    expected_bucket := 'transcript-core-observed-originals';
    expected_provenance := 'observed_original';
    initial_job_type := 'transcribe_recording';
  elsif p_source_kind = 'script' then
    expected_bucket := 'transcript-core-script-sources';
    expected_provenance := 'script_source';
    initial_job_type := 'parse_performance_script';
  else
    raise exception 'UNSUPPORTED_SOURCE_KIND:%', p_source_kind;
  end if;
  if p_storage_bucket <> expected_bucket then
    raise exception 'SOURCE_BUCKET_MISMATCH:%', p_storage_bucket;
  end if;
  if public.transcript_core_path_workspace(p_storage_path) is distinct from p_workspace_id then
    raise exception 'SOURCE_PATH_WORKSPACE_MISMATCH';
  end if;
  insert into transcript_core.source_ingests(id, workspace_id, source_kind)
  values (p_ingest_id, p_workspace_id, p_source_kind)
  on conflict (id) do nothing;
  select * into existing from transcript_core.source_ingests where id = p_ingest_id for update;
  if existing.workspace_id <> p_workspace_id or existing.source_kind <> p_source_kind then
    raise exception 'INGEST_ID_REUSED_WITH_DIFFERENT_SOURCE';
  end if;
  if existing.completed_at is not null then
    return jsonb_build_object(
      'ingest_id', existing.id, 'asset_id', existing.asset_id,
      'recording_id', existing.recording_id,
      'script_document_id', existing.script_document_id,
      'script_revision_id', existing.script_revision_id,
      'processing_job_id', existing.processing_job_id
    );
  end if;
  insert into transcript_core.assets(
    workspace_id, provenance_class, storage_bucket, storage_path, content_hash, mime_type, byte_size
  ) values (
    p_workspace_id, expected_provenance, p_storage_bucket, p_storage_path, p_content_hash, p_mime_type, p_byte_size
  ) returning id into new_asset_id;
  if p_source_kind = 'recording' then
    insert into transcript_core.recordings(workspace_id, source_asset_id, title)
    values (p_workspace_id, new_asset_id, p_title) returning id into new_recording_id;
  else
    insert into transcript_core.script_documents(workspace_id, title)
    values (p_workspace_id, p_title) returning id into new_script_document_id;
    insert into transcript_core.script_revisions(script_document_id, source_asset_id, content_hash)
    values (new_script_document_id, new_asset_id, p_content_hash) returning id into new_script_revision_id;
  end if;
  insert into transcript_core.processing_jobs(workspace_id, job_type, source_asset_id)
  values (p_workspace_id, initial_job_type, new_asset_id) returning id into new_job_id;
  perform public.transcript_core_enqueue_processing_job(new_job_id);
  update transcript_core.source_ingests
  set asset_id = new_asset_id,
      recording_id = new_recording_id,
      script_document_id = new_script_document_id,
      script_revision_id = new_script_revision_id,
      processing_job_id = new_job_id,
      completed_at = now()
  where id = p_ingest_id;
  return jsonb_build_object(
    'ingest_id', p_ingest_id, 'asset_id', new_asset_id,
    'recording_id', new_recording_id,
    'script_document_id', new_script_document_id,
    'script_revision_id', new_script_revision_id,
    'processing_job_id', new_job_id
  );
end;
$$;

create or replace function public.transcript_core_claim_processing_job(p_job_id uuid)
returns boolean
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare target transcript_core.processing_jobs%rowtype;
begin
  select * into target from transcript_core.processing_jobs where id = p_job_id for update;
  if not found then return false; end if;
  if target.status in ('ready','failed_terminal') then return false; end if;
  if target.status = 'processing' and target.heartbeat_at > now() - interval '5 minutes' then return false; end if;
  update transcript_core.processing_jobs
  set status = 'processing', attempt = attempt + 1, claimed_at = now(), heartbeat_at = now(),
      started_at = coalesce(started_at, now()), error_code = null, error_message = null
  where id = p_job_id;
  return true;
end;
$$;

create or replace function public.transcript_core_heartbeat_processing_job(p_job_id uuid)
returns void
language sql
security definer
set search_path = transcript_core, public
as $$
  update transcript_core.processing_jobs set heartbeat_at = now()
  where id = p_job_id and status = 'processing';
$$;

create or replace function public.transcript_core_fail_processing_job(
  p_job_id uuid, p_retryable boolean, p_error_code text, p_error_message text
)
returns void
language sql
security definer
set search_path = transcript_core, public
as $$
  update transcript_core.processing_jobs
  set status = case when p_retryable then 'failed_retryable'::transcript_core.processing_job_status else 'failed_terminal'::transcript_core.processing_job_status end,
      error_code = p_error_code, error_message = p_error_message,
      heartbeat_at = null, claimed_at = null,
      finished_at = case when p_retryable then null else now() end
  where id = p_job_id and status = 'processing';
$$;

create or replace function public.transcript_core_load_job_with_asset(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare j transcript_core.processing_jobs%rowtype; a transcript_core.assets%rowtype;
begin
  select * into j from transcript_core.processing_jobs where id = p_job_id;
  if not found then raise exception 'JOB_NOT_FOUND'; end if;
  if j.source_asset_id is null then raise exception 'JOB_HAS_NO_SOURCE_ASSET'; end if;
  select * into a from transcript_core.assets where id = j.source_asset_id;
  if not found then raise exception 'ASSET_NOT_FOUND'; end if;
  return jsonb_build_object(
    'job_id', j.id, 'job_type', j.job_type, 'status', j.status, 'attempt', j.attempt,
    'asset_id', a.id, 'storage_bucket', a.storage_bucket, 'storage_path', a.storage_path, 'mime_type', a.mime_type
  );
end;
$$;

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
  return query select r.msg_id, r.read_ct, r.enqueued_at, r.vt, r.message
  from pgmq.read(p_queue_name, p_visibility_timeout_seconds, 1) r;
end;
$$;

create or replace function public.transcript_core_delete_queue_message(p_queue_name text, p_message_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public, pgmq
as $$
begin
  if p_queue_name not in (
    'transcript_core_transcription_jobs','transcript_core_performance_parse_jobs',
    'transcript_core_voice_render_jobs','transcript_core_performance_mix_jobs','transcript_core_performance_verify_jobs'
  ) then raise exception 'QUEUE_NOT_ALLOWED'; end if;
  return pgmq.delete(p_queue_name, p_message_id);
end;
$$;

create or replace function public.transcript_core_complete_transcription_job(
  p_job_id uuid, p_provider text, p_provider_model text, p_segments jsonb
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target transcript_core.processing_jobs%rowtype;
  target_recording_id uuid; target_transcript_id uuid; target_revision_id uuid;
  segment jsonb; new_segment_id uuid;
begin
  select * into target from transcript_core.processing_jobs where id = p_job_id for update;
  if not found or target.job_type <> 'transcribe_recording' then raise exception 'INVALID_TRANSCRIPTION_JOB'; end if;
  select id into target_revision_id from transcript_core.transcript_revisions where source_job_id = p_job_id;
  if target_revision_id is not null then return target_revision_id; end if;
  select id into target_recording_id from transcript_core.recordings where source_asset_id = target.source_asset_id;
  if target_recording_id is null then raise exception 'RECORDING_FOR_JOB_NOT_FOUND'; end if;
  select id into target_transcript_id from transcript_core.transcripts where recording_id = target_recording_id;
  if target_transcript_id is null then
    insert into transcript_core.transcripts(recording_id) values (target_recording_id) returning id into target_transcript_id;
  elsif exists (select 1 from transcript_core.transcript_revisions where transcript_id = target_transcript_id) then
    raise exception 'TRANSCRIPT_RETRANSCRIPTION_POLICY_UNDEFINED';
  end if;
  insert into transcript_core.transcript_revisions(transcript_id, ordinal, revision_kind, source_job_id, provider, provider_model)
  values (target_transcript_id, 1, 'machine', p_job_id, p_provider, p_provider_model)
  returning id into target_revision_id;
  for segment in select * from jsonb_array_elements(p_segments)
  loop
    insert into transcript_core.transcript_segments(transcript_id, sequence, anchor_start_ms, anchor_end_ms)
    values (target_transcript_id, (segment->>'sequence')::integer, (segment->>'startMs')::bigint, (segment->>'endMs')::bigint)
    returning id into new_segment_id;
    insert into transcript_core.transcript_segment_versions(
      transcript_revision_id, transcript_segment_id, start_ms, end_ms, text, provider_speaker
    ) values (
      target_revision_id, new_segment_id,
      (segment->>'startMs')::bigint, (segment->>'endMs')::bigint,
      segment->>'text', nullif(segment->>'providerSpeaker','')
    );
  end loop;
  update transcript_core.transcripts set current_revision_id = target_revision_id where id = target_transcript_id;
  update transcript_core.processing_jobs
  set status = 'ready', provider = p_provider, provider_model = p_provider_model,
      heartbeat_at = null, claimed_at = null, finished_at = now()
  where id = p_job_id;
  return target_revision_id;
end;
$$;

create or replace function public.transcript_core_complete_performance_parse_job(
  p_job_id uuid, p_parser_adapter text, p_parser_version text,
  p_roles jsonb, p_cues jsonb, p_events jsonb
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target transcript_core.processing_jobs%rowtype;
  target_revision_id uuid; target_script_id uuid; role_name text; cue jsonb; evt jsonb; i integer := 0;
begin
  select * into target from transcript_core.processing_jobs where id = p_job_id for update;
  if not found or target.job_type <> 'parse_performance_script' then raise exception 'INVALID_PARSE_JOB'; end if;
  select id into target_script_id from transcript_core.performance_scripts where source_job_id = p_job_id;
  if target_script_id is not null then return target_script_id; end if;
  select id into target_revision_id from transcript_core.script_revisions where source_asset_id = target.source_asset_id;
  if target_revision_id is null then raise exception 'SCRIPT_REVISION_FOR_JOB_NOT_FOUND'; end if;
  insert into transcript_core.performance_scripts(script_revision_id, source_job_id, parser_adapter, parser_version)
  values (target_revision_id, p_job_id, p_parser_adapter, p_parser_version)
  returning id into target_script_id;
  update transcript_core.script_revisions
  set parser_adapter = p_parser_adapter, parser_version = p_parser_version
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
      target_script_id, (cue->>'sequence')::integer,
      array(select jsonb_array_elements_text(cue->'speakers')),
      cue->>'dialogue', coalesce(array(select jsonb_array_elements_text(cue->'instructionsBefore')), '{}'),
      cue->>'synchronizationMode', (cue->>'sourceParagraph')::integer, cue->>'sourceStyle'
    );
  end loop;
  for evt in select * from jsonb_array_elements(p_events)
  loop
    i := i + 1;
    insert into transcript_core.performance_parse_events(
      performance_script_id, sequence, event_kind, payload, source_paragraph, source_style
    ) values (
      target_script_id, i, evt->>'kind', evt - 'kind' - 'sourceParagraph' - 'sourceStyle',
      (evt->>'sourceParagraph')::integer, evt->>'sourceStyle'
    );
  end loop;
  update transcript_core.processing_jobs
  set status = 'ready', provider = 'native-odt', provider_model = p_parser_adapter || ':' || p_parser_version,
      heartbeat_at = null, claimed_at = null, finished_at = now()
  where id = p_job_id;
  return target_script_id;
end;
$$;

revoke all on function public.transcript_core_path_workspace(text) from public;
revoke all on function public.transcript_core_is_workspace_member(uuid) from public;
revoke all on function public.transcript_core_can_workspace_edit(uuid) from public;
revoke all on function public.transcript_core_create_workspace(text) from public;
revoke all on function public.transcript_core_processing_queue_name(text) from public;
revoke all on function public.transcript_core_enqueue_processing_job(uuid) from public;
revoke all on function public.transcript_core_register_source_ingest(uuid,uuid,text,text,text,text,text,text,bigint) from public;
revoke all on function public.transcript_core_claim_processing_job(uuid) from public;
revoke all on function public.transcript_core_heartbeat_processing_job(uuid) from public;
revoke all on function public.transcript_core_fail_processing_job(uuid,boolean,text,text) from public;
revoke all on function public.transcript_core_load_job_with_asset(uuid) from public;
revoke all on function public.transcript_core_read_queue(text,integer) from public;
revoke all on function public.transcript_core_delete_queue_message(text,bigint) from public;
revoke all on function public.transcript_core_complete_transcription_job(uuid,text,text,jsonb) from public;
revoke all on function public.transcript_core_complete_performance_parse_job(uuid,text,text,jsonb,jsonb,jsonb) from public;

grant execute on function public.transcript_core_path_workspace(text) to authenticated, service_role;
grant execute on function public.transcript_core_is_workspace_member(uuid) to authenticated, service_role;
grant execute on function public.transcript_core_can_workspace_edit(uuid) to authenticated, service_role;
grant execute on function public.transcript_core_create_workspace(text) to authenticated;
grant execute on function public.transcript_core_register_source_ingest(uuid,uuid,text,text,text,text,text,text,bigint) to authenticated, service_role;
grant execute on function public.transcript_core_claim_processing_job(uuid) to service_role;
grant execute on function public.transcript_core_heartbeat_processing_job(uuid) to service_role;
grant execute on function public.transcript_core_fail_processing_job(uuid,boolean,text,text) to service_role;
grant execute on function public.transcript_core_load_job_with_asset(uuid) to service_role;
grant execute on function public.transcript_core_read_queue(text,integer) to service_role;
grant execute on function public.transcript_core_delete_queue_message(text,bigint) to service_role;
grant execute on function public.transcript_core_complete_transcription_job(uuid,text,text,jsonb) to service_role;
grant execute on function public.transcript_core_complete_performance_parse_job(uuid,text,text,jsonb,jsonb,jsonb) to service_role;

create policy transcript_core_source_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('transcript-core-observed-originals','transcript-core-script-sources')
  and public.transcript_core_can_workspace_edit(public.transcript_core_path_workspace(name))
);

create policy transcript_core_asset_read on storage.objects
for select to authenticated
using (
  bucket_id in (
    'transcript-core-observed-originals','transcript-core-observed-derivatives','transcript-core-script-sources',
    'transcript-core-generated-takes','transcript-core-generated-renders'
  )
  and public.transcript_core_is_workspace_member(public.transcript_core_path_workspace(name))
);