-- Practitioner voice messages share the participant conversation but remain
-- conversation-only evidence. They are transcribed for both sides to read,
-- but are not interpreted as source material about the organization.

begin;

create or replace function atlas.begin_implementation_artifact_transcription_service_v1(
  p_artifact_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_artifact atlas.implementation_artifacts%rowtype;
  v_transcript atlas.implementation_artifact_transcripts%rowtype;
  v_version integer;
  v_starting_label text;
  v_submitter_is_practitioner boolean := false;
begin
  select a.* into v_artifact
  from atlas.implementation_artifacts a
  where a.id=p_artifact_id and a.removed_at is null
  for update;

  if v_artifact.id is null then
    raise exception 'Implementation artifact not found.' using errcode='23503';
  end if;
  if v_artifact.artifact_kind<>'audio_recording' or v_artifact.storage_bucket is null or v_artifact.storage_path is null then
    raise exception 'Processable audio artifact not found.' using errcode='23514';
  end if;
  if v_artifact.processing_state='upload_pending' then
    raise exception 'Artifact upload has not been committed.' using errcode='23514';
  end if;
  if v_artifact.byte_size is null or v_artifact.byte_size < 1 or v_artifact.byte_size > 26214400 then
    raise exception 'Audio artifact is outside the 25 MB transcription boundary.' using errcode='22023';
  end if;

  select (
    exists (
      select 1
      from atlas.implementation_case_participants cp
      where cp.id=v_artifact.submitted_by_participant_id
        and cp.relationship_kind='practitioner'
        and cp.active
        and cp.ended_at is null
    )
    or exists (
      select 1
      from atlas.implementation_practitioners ip
      where ip.human_user_id=v_artifact.submitted_by_user_id
        and ip.status='active'
    )
  ) into v_submitter_is_practitioner;

  select tr.* into v_transcript
  from atlas.implementation_artifact_transcripts tr
  where tr.implementation_artifact_id=p_artifact_id and tr.status<>'superseded'
  order by tr.version desc
  limit 1
  for update;

  select p.starting_label into v_starting_label
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
  where c.id=v_artifact.implementation_case_id;

  if v_transcript.id is not null and v_transcript.status='ready' then
    return jsonb_build_object(
      'ok',true,
      'shouldTranscribe',false,
      'reason','transcript_ready',
      'artifactId',v_artifact.id,
      'implementationCaseId',v_artifact.implementation_case_id,
      'implementationThreadId',v_artifact.implementation_thread_id,
      'transcriptId',v_transcript.id,
      'transcriptText',v_transcript.transcript_text,
      'storageBucket',v_artifact.storage_bucket,
      'storagePath',v_artifact.storage_path,
      'mimeType',v_artifact.mime_type,
      'byteSize',v_artifact.byte_size,
      'startingLabel',v_starting_label,
      'submitterIsPractitioner',v_submitter_is_practitioner
    );
  end if;

  if v_transcript.id is not null and v_transcript.status='processing'
     and v_transcript.updated_at > now()-interval '10 minutes' then
    return jsonb_build_object(
      'ok',true,
      'shouldTranscribe',false,
      'reason','already_processing',
      'artifactId',v_artifact.id,
      'transcriptId',v_transcript.id,
      'submitterIsPractitioner',v_submitter_is_practitioner
    );
  end if;

  if v_transcript.id is null or v_transcript.status='failed' then
    select coalesce(max(tr.version),0)+1 into v_version
    from atlas.implementation_artifact_transcripts tr
    where tr.implementation_artifact_id=p_artifact_id;

    insert into atlas.implementation_artifact_transcripts(
      implementation_artifact_id,version,status,metadata
    ) values (
      p_artifact_id,v_version,'processing',jsonb_build_object('source','atlas_implementation_artifact_processor')
    ) returning * into v_transcript;
  else
    update atlas.implementation_artifact_transcripts
    set status='processing',error_detail=null,updated_at=now()
    where id=v_transcript.id
    returning * into v_transcript;
  end if;

  update atlas.implementation_artifacts
  set processing_state='transcribing',updated_at=now()
  where id=p_artifact_id;

  return jsonb_build_object(
    'ok',true,
    'shouldTranscribe',true,
    'artifactId',v_artifact.id,
    'implementationCaseId',v_artifact.implementation_case_id,
    'implementationThreadId',v_artifact.implementation_thread_id,
    'transcriptId',v_transcript.id,
    'storageBucket',v_artifact.storage_bucket,
    'storagePath',v_artifact.storage_path,
    'originalFilename',v_artifact.original_filename,
    'mimeType',v_artifact.mime_type,
    'byteSize',v_artifact.byte_size,
    'durationMs',v_artifact.duration_ms,
    'startingLabel',v_starting_label,
    'submitterIsPractitioner',v_submitter_is_practitioner
  );
end;
$function$;

create or replace function atlas.complete_implementation_practitioner_voice_service_v1(
  p_artifact_id uuid,
  p_transcript_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_artifact atlas.implementation_artifacts%rowtype;
  v_submitter_is_practitioner boolean := false;
begin
  select a.* into v_artifact
  from atlas.implementation_artifacts a
  where a.id=p_artifact_id and a.removed_at is null
  for update;

  if v_artifact.id is null then
    raise exception 'Implementation artifact not found.' using errcode='23503';
  end if;

  if not exists (
    select 1
    from atlas.implementation_artifact_transcripts tr
    where tr.id=p_transcript_id
      and tr.implementation_artifact_id=p_artifact_id
      and tr.status='ready'
  ) then
    raise exception 'Ready practitioner transcript not found.' using errcode='23503';
  end if;

  select (
    exists (
      select 1
      from atlas.implementation_case_participants cp
      where cp.id=v_artifact.submitted_by_participant_id
        and cp.relationship_kind='practitioner'
        and cp.active
        and cp.ended_at is null
    )
    or exists (
      select 1
      from atlas.implementation_practitioners ip
      where ip.human_user_id=v_artifact.submitted_by_user_id
        and ip.status='active'
    )
  ) into v_submitter_is_practitioner;

  if not v_submitter_is_practitioner then
    raise exception 'Artifact was not submitted by an implementation practitioner.' using errcode='23514';
  end if;

  update atlas.implementation_artifacts
  set processing_state='ready',
      metadata=metadata || jsonb_build_object(
        'conversationOnly',true,
        'interpretationSuppressed',true,
        'interpretationSuppressedReason','practitioner_outbound_voice'
      ),
      updated_at=now()
  where id=p_artifact_id;

  return jsonb_build_object(
    'ok',true,
    'artifactId',p_artifact_id,
    'transcriptId',p_transcript_id,
    'processingState','ready',
    'interpretationSuppressed',true
  );
end;
$function$;

revoke all on function atlas.complete_implementation_practitioner_voice_service_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.complete_implementation_practitioner_voice_service_v1(uuid,uuid) to service_role;

comment on function atlas.complete_implementation_practitioner_voice_service_v1(uuid,uuid) is
  'Marks a practitioner-authored shared-conversation voice artifact ready after transcription. Practitioner outbound speech is conversation, not evidence about the organization, so machine interpretation is intentionally suppressed.';

commit;
