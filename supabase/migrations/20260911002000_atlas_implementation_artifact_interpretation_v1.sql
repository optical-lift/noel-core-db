-- Atlas implementation artifact transcription + governed interpretation v1
-- Raw source artifacts remain the authority for what a participant supplied.
-- Machine transcription and extraction are versioned derivatives. Human review
-- may promote candidates into private implementation findings/requests only;
-- nothing here establishes canonical Ledger truth.

begin;

-- V1 uses OpenAI file transcription, whose current file boundary is 25 MB.
-- Keep the accepted voice-note size aligned with the processor rather than
-- accepting source files that the default transcription path cannot organize.
update storage.buckets
set file_size_limit=26214400
where id='atlas-implementation-artifacts';

create table if not exists atlas.implementation_artifact_interpretations (
  id uuid primary key default gen_random_uuid(),
  implementation_artifact_id uuid not null references atlas.implementation_artifacts(id) on delete cascade,
  transcript_id uuid not null references atlas.implementation_artifact_transcripts(id) on delete cascade,
  version integer not null default 1,
  status text not null default 'pending',
  summary text null,
  provider_key text null,
  model_key text null,
  error_detail text null,
  generated_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_artifact_interpretations_version_check check (version > 0),
  constraint implementation_artifact_interpretations_status_check check (
    status in ('pending','processing','ready','failed','superseded')
  ),
  constraint implementation_artifact_interpretations_metadata_object_check check (jsonb_typeof(metadata)='object'),
  constraint implementation_artifact_interpretations_artifact_version_uq unique (implementation_artifact_id,version)
);

create index if not exists implementation_artifact_interpretations_current_idx
  on atlas.implementation_artifact_interpretations(implementation_artifact_id,version desc);
create index if not exists implementation_artifact_interpretations_transcript_idx
  on atlas.implementation_artifact_interpretations(transcript_id,version desc);

comment on table atlas.implementation_artifact_interpretations is
  'Versioned machine interpretations of an implementation transcript. Interpretation is derivative and has no canonical Ledger authority.';

create table if not exists atlas.implementation_artifact_candidates (
  id uuid primary key default gen_random_uuid(),
  interpretation_id uuid not null references atlas.implementation_artifact_interpretations(id) on delete cascade,
  candidate_kind text not null,
  work_area text not null,
  statement text not null,
  evidence_excerpt text not null,
  evidence_start_char integer not null,
  evidence_end_char integer not null,
  confidence numeric(5,4) not null,
  status text not null default 'proposed',
  promoted_record_kind text null,
  promoted_record_id uuid null,
  reviewed_by_user_id uuid null references auth.users(id),
  reviewed_at timestamptz null,
  review_note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_artifact_candidates_kind_check check (candidate_kind in ('finding','question')),
  constraint implementation_artifact_candidates_work_area_check check (
    work_area in ('people','work','time','money','things_places','systems_evidence','access_authority','handoffs_completion','structure_mismatch','other_unresolved')
  ),
  constraint implementation_artifact_candidates_statement_check check (char_length(btrim(statement)) between 1 and 4000),
  constraint implementation_artifact_candidates_excerpt_check check (char_length(evidence_excerpt) between 1 and 1200),
  constraint implementation_artifact_candidates_char_range_check check (
    evidence_start_char >= 0 and evidence_end_char > evidence_start_char
  ),
  constraint implementation_artifact_candidates_confidence_check check (confidence between 0 and 1),
  constraint implementation_artifact_candidates_status_check check (status in ('proposed','accepted','rejected','superseded')),
  constraint implementation_artifact_candidates_promotion_kind_check check (
    promoted_record_kind is null or promoted_record_kind in ('implementation_finding','implementation_request')
  ),
  constraint implementation_artifact_candidates_review_shape_check check (
    (status='proposed' and reviewed_by_user_id is null and reviewed_at is null and promoted_record_kind is null and promoted_record_id is null)
    or (status='accepted' and reviewed_by_user_id is not null and reviewed_at is not null and promoted_record_kind is not null and promoted_record_id is not null)
    or (status='rejected' and reviewed_by_user_id is not null and reviewed_at is not null and promoted_record_kind is null and promoted_record_id is null)
    or status='superseded'
  )
);

create index if not exists implementation_artifact_candidates_interpretation_idx
  on atlas.implementation_artifact_candidates(interpretation_id,status,created_at,id);
create index if not exists implementation_artifact_candidates_review_queue_idx
  on atlas.implementation_artifact_candidates(status,created_at,id)
  where status='proposed';
create index if not exists implementation_artifact_candidates_promoted_idx
  on atlas.implementation_artifact_candidates(promoted_record_kind,promoted_record_id)
  where promoted_record_id is not null;

comment on table atlas.implementation_artifact_candidates is
  'Machine-extracted implementation candidates grounded in exact transcript excerpts. A practitioner must accept/reject each candidate before it enters implementation work.';

alter table atlas.implementation_artifact_interpretations enable row level security;
alter table atlas.implementation_artifact_candidates enable row level security;
revoke all on atlas.implementation_artifact_interpretations from public, anon, authenticated;
revoke all on atlas.implementation_artifact_candidates from public, anon, authenticated;

create or replace function atlas.implementation_practitioner_assigned_to_case_self_v1(
  p_implementation_case_id uuid
) returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select atlas.implementation_practitioner_authorized_self_v1()
    and exists (
      select 1
      from atlas.implementation_case_participants cp
      where cp.implementation_case_id=p_implementation_case_id
        and cp.relationship_kind='practitioner'
        and cp.active
        and cp.ended_at is null
        and cp.human_user_id=auth.uid()
    );
$function$;

-- Replace the audio prepare/commit membranes with the processor-compatible
-- 25 MB ceiling. Generic artifact rows retain their broader 100 MB shape for
-- future non-audio capture channels.
create or replace function atlas.prepare_implementation_audio_artifact_self_api_v1(
  p_implementation_case_id uuid,
  p_implementation_thread_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_duration_ms bigint default null,
  p_captured_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid := auth.uid();
  v_participant_id uuid;
  v_artifact_id uuid := gen_random_uuid();
  v_mime text := lower(split_part(btrim(coalesce(p_mime_type,'')),';',1));
  v_ext text;
  v_path text;
begin
  if not atlas.implementation_case_conversation_authorized_self_v1(p_implementation_case_id) then
    raise exception 'Implementation conversation authority required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from atlas.implementation_threads t
    where t.id=p_implementation_thread_id
      and t.implementation_case_id=p_implementation_case_id
      and t.shared_with_participants
      and t.state='open'
  ) then
    raise exception 'Shared implementation thread not found.' using errcode='23503';
  end if;
  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 26214400 then
    raise exception 'Audio file must be between 1 byte and 25 MB.' using errcode='22023';
  end if;
  if p_duration_ms is not null and (p_duration_ms < 0 or p_duration_ms > 21600000) then
    raise exception 'Audio duration must be no more than 6 hours.' using errcode='22023';
  end if;

  v_ext := case v_mime
    when 'audio/webm' then 'webm'
    when 'audio/ogg' then 'ogg'
    when 'audio/mp4' then 'm4a'
    when 'audio/mpeg' then 'mp3'
    when 'audio/wav' then 'wav'
    when 'audio/x-wav' then 'wav'
    when 'audio/x-m4a' then 'm4a'
    when 'audio/aac' then 'aac'
    else null
  end;
  if v_ext is null then
    raise exception 'Unsupported audio format: %',v_mime using errcode='22023';
  end if;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.human_user_id=v_uid and cp.active and cp.ended_at is null
  order by cp.started_at desc,cp.id
  limit 1;

  v_path := 'implementation/' || p_implementation_case_id::text || '/' || v_artifact_id::text || '/source.' || v_ext;

  insert into atlas.implementation_artifacts(
    id,implementation_case_id,implementation_thread_id,submitted_by_user_id,submitted_by_participant_id,
    artifact_kind,source_kind,storage_bucket,storage_path,original_filename,mime_type,byte_size,duration_ms,
    captured_at,processing_state,metadata
  ) values (
    v_artifact_id,p_implementation_case_id,p_implementation_thread_id,v_uid,v_participant_id,
    'audio_recording','atlas_capture','atlas-implementation-artifacts',v_path,
    nullif(btrim(coalesce(p_original_filename,'')),''),v_mime,p_byte_size,p_duration_ms,
    coalesce(p_captured_at,now()),'upload_pending',jsonb_build_object('source','atlas_audio_capture_v1','maxProcessableBytes',26214400)
  );

  return jsonb_build_object(
    'ok',true,'artifactId',v_artifact_id,'implementationCaseId',p_implementation_case_id,
    'implementationThreadId',p_implementation_thread_id,'storageBucket','atlas-implementation-artifacts',
    'storagePath',v_path,'mimeType',v_mime,'processingState','upload_pending'
  );
end;
$function$;

create or replace function atlas.commit_implementation_audio_artifact_self_api_v1(
  p_artifact_id uuid,
  p_byte_size bigint,
  p_duration_ms bigint default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid := auth.uid();
  v_artifact atlas.implementation_artifacts%rowtype;
  v_entry_id uuid;
  v_participant_id uuid;
begin
  select a.* into v_artifact
  from atlas.implementation_artifacts a
  where a.id=p_artifact_id and a.removed_at is null
  for update;

  if v_artifact.id is null then
    raise exception 'Implementation artifact not found.' using errcode='23503';
  end if;
  if not atlas.implementation_case_conversation_authorized_self_v1(v_artifact.implementation_case_id) then
    raise exception 'Implementation conversation authority required.' using errcode='42501';
  end if;
  if v_artifact.submitted_by_user_id<>v_uid and not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Only the submitter or an implementation practitioner may commit this artifact.' using errcode='42501';
  end if;
  if v_artifact.processing_state not in ('upload_pending','received') then
    raise exception 'Artifact is not awaiting upload confirmation.' using errcode='23514';
  end if;
  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 26214400 then
    raise exception 'Audio file must be between 1 byte and 25 MB.' using errcode='22023';
  end if;

  update atlas.implementation_artifacts
  set byte_size=p_byte_size,duration_ms=coalesce(p_duration_ms,duration_ms),processing_state='received',updated_at=now()
  where id=p_artifact_id;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_artifact.implementation_case_id
    and cp.human_user_id=v_artifact.submitted_by_user_id
    and cp.active and cp.ended_at is null
  order by cp.started_at desc,cp.id
  limit 1;

  select e.id into v_entry_id
  from atlas.implementation_conversation_entries e
  where e.artifact_id=p_artifact_id;

  if v_entry_id is null then
    insert into atlas.implementation_conversation_entries(
      implementation_case_id,implementation_thread_id,author_user_id,author_participant_id,entry_kind,artifact_id,metadata
    ) values (
      v_artifact.implementation_case_id,v_artifact.implementation_thread_id,v_artifact.submitted_by_user_id,
      v_participant_id,'artifact',p_artifact_id,jsonb_build_object('source','atlas_audio_capture_v1')
    ) returning id into v_entry_id;
  end if;

  insert into atlas.implementation_artifact_transcripts(implementation_artifact_id,version,status,metadata)
  values (p_artifact_id,1,'pending',jsonb_build_object('source','audio_artifact_commit'))
  on conflict (implementation_artifact_id,version) do nothing;

  return jsonb_build_object(
    'ok',true,'artifactId',p_artifact_id,'entryId',v_entry_id,
    'processingState','received','transcriptionState','pending'
  );
end;
$function$;

-- Service-role processing membranes. These are intentionally unavailable to
-- browser-authenticated users; the Edge Function is the external worker.
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
      'ok',true,'shouldTranscribe',false,'reason','transcript_ready',
      'artifactId',v_artifact.id,'implementationCaseId',v_artifact.implementation_case_id,
      'implementationThreadId',v_artifact.implementation_thread_id,'transcriptId',v_transcript.id,
      'transcriptText',v_transcript.transcript_text,'storageBucket',v_artifact.storage_bucket,
      'storagePath',v_artifact.storage_path,'mimeType',v_artifact.mime_type,'byteSize',v_artifact.byte_size,
      'startingLabel',v_starting_label
    );
  end if;

  if v_transcript.id is not null and v_transcript.status='processing'
     and v_transcript.updated_at > now()-interval '10 minutes' then
    return jsonb_build_object(
      'ok',true,'shouldTranscribe',false,'reason','already_processing',
      'artifactId',v_artifact.id,'transcriptId',v_transcript.id
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
    'ok',true,'shouldTranscribe',true,'artifactId',v_artifact.id,
    'implementationCaseId',v_artifact.implementation_case_id,'implementationThreadId',v_artifact.implementation_thread_id,
    'transcriptId',v_transcript.id,'storageBucket',v_artifact.storage_bucket,'storagePath',v_artifact.storage_path,
    'originalFilename',v_artifact.original_filename,'mimeType',v_artifact.mime_type,'byteSize',v_artifact.byte_size,
    'durationMs',v_artifact.duration_ms,'startingLabel',v_starting_label
  );
end;
$function$;

create or replace function atlas.complete_implementation_artifact_transcript_service_v1(
  p_artifact_id uuid,
  p_transcript_id uuid,
  p_transcript_text text,
  p_language_code text default null,
  p_provider_key text default 'openai',
  p_model_key text default 'gpt-transcribe',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_text text := btrim(coalesce(p_transcript_text,''));
begin
  if char_length(v_text)<1 then raise exception 'Transcript text required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;
  if not exists (
    select 1 from atlas.implementation_artifact_transcripts tr
    where tr.id=p_transcript_id and tr.implementation_artifact_id=p_artifact_id and tr.status='processing'
  ) then raise exception 'Processing transcript not found.' using errcode='23503'; end if;

  update atlas.implementation_artifact_transcripts
  set status='ready',transcript_text=v_text,language_code=nullif(btrim(coalesce(p_language_code,'')),''),
      provider_key=nullif(btrim(coalesce(p_provider_key,'')),''),model_key=nullif(btrim(coalesce(p_model_key,'')),''),
      generated_at=now(),error_detail=null,metadata=metadata||p_metadata,updated_at=now()
  where id=p_transcript_id;

  update atlas.implementation_artifacts
  set processing_state='transcribed',updated_at=now()
  where id=p_artifact_id;

  return jsonb_build_object('ok',true,'artifactId',p_artifact_id,'transcriptId',p_transcript_id,'status','ready');
end;
$function$;

create or replace function atlas.begin_implementation_artifact_interpretation_service_v1(
  p_artifact_id uuid,
  p_transcript_id uuid,
  p_provider_key text default 'openai',
  p_model_key text default 'gpt-5.6-terra'
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_transcript atlas.implementation_artifact_transcripts%rowtype;
  v_interpretation atlas.implementation_artifact_interpretations%rowtype;
  v_version integer;
begin
  select tr.* into v_transcript
  from atlas.implementation_artifact_transcripts tr
  where tr.id=p_transcript_id and tr.implementation_artifact_id=p_artifact_id and tr.status='ready';
  if v_transcript.id is null then raise exception 'Ready transcript not found.' using errcode='23503'; end if;

  select i.* into v_interpretation
  from atlas.implementation_artifact_interpretations i
  where i.implementation_artifact_id=p_artifact_id and i.transcript_id=p_transcript_id and i.status<>'superseded'
  order by i.version desc limit 1 for update;

  if v_interpretation.id is not null and v_interpretation.status='ready' then
    return jsonb_build_object('ok',true,'shouldInterpret',false,'reason','interpretation_ready','interpretationId',v_interpretation.id);
  end if;
  if v_interpretation.id is not null and v_interpretation.status='processing'
     and v_interpretation.updated_at > now()-interval '10 minutes' then
    return jsonb_build_object('ok',true,'shouldInterpret',false,'reason','already_processing','interpretationId',v_interpretation.id);
  end if;

  if v_interpretation.id is null or v_interpretation.status='failed' then
    select coalesce(max(i.version),0)+1 into v_version
    from atlas.implementation_artifact_interpretations i
    where i.implementation_artifact_id=p_artifact_id;
    insert into atlas.implementation_artifact_interpretations(
      implementation_artifact_id,transcript_id,version,status,provider_key,model_key,metadata
    ) values (
      p_artifact_id,p_transcript_id,v_version,'processing',nullif(btrim(coalesce(p_provider_key,'')),''),
      nullif(btrim(coalesce(p_model_key,'')),''),jsonb_build_object('source','atlas_implementation_artifact_processor')
    ) returning * into v_interpretation;
  else
    update atlas.implementation_artifact_interpretations
    set status='processing',error_detail=null,provider_key=nullif(btrim(coalesce(p_provider_key,'')),''),
        model_key=nullif(btrim(coalesce(p_model_key,'')),''),updated_at=now()
    where id=v_interpretation.id returning * into v_interpretation;
  end if;

  return jsonb_build_object(
    'ok',true,'shouldInterpret',true,'interpretationId',v_interpretation.id,
    'artifactId',p_artifact_id,'transcriptId',p_transcript_id,'transcriptText',v_transcript.transcript_text
  );
end;
$function$;

create or replace function atlas.complete_implementation_artifact_interpretation_service_v1(
  p_interpretation_id uuid,
  p_summary text,
  p_candidates jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_interpretation atlas.implementation_artifact_interpretations%rowtype;
  v_transcript_text text;
  v_item jsonb;
  v_kind text;
  v_area text;
  v_statement text;
  v_excerpt text;
  v_start integer;
  v_confidence numeric;
  v_count integer := 0;
begin
  if p_candidates is null or jsonb_typeof(p_candidates)<>'array' then raise exception 'Candidates must be a JSON array.' using errcode='22023'; end if;
  if jsonb_array_length(p_candidates)>50 then raise exception 'Candidate count exceeds processing limit.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;

  select i.* into v_interpretation
  from atlas.implementation_artifact_interpretations i
  where i.id=p_interpretation_id for update;
  if v_interpretation.id is null or v_interpretation.status<>'processing' then
    raise exception 'Processing interpretation not found.' using errcode='23503';
  end if;
  select tr.transcript_text into v_transcript_text
  from atlas.implementation_artifact_transcripts tr
  where tr.id=v_interpretation.transcript_id and tr.status='ready';
  if nullif(v_transcript_text,'') is null then raise exception 'Ready transcript text not found.' using errcode='23503'; end if;

  delete from atlas.implementation_artifact_candidates where interpretation_id=p_interpretation_id;

  for v_item in select value from jsonb_array_elements(p_candidates) loop
    v_kind := v_item->>'candidateKind';
    v_area := v_item->>'workArea';
    v_statement := btrim(coalesce(v_item->>'statement',''));
    v_excerpt := coalesce(v_item->>'evidenceExcerpt','');
    begin v_confidence := (v_item->>'confidence')::numeric; exception when others then v_confidence := null; end;

    if v_kind not in ('finding','question') then raise exception 'Invalid candidate kind.' using errcode='22023'; end if;
    if v_area not in ('people','work','time','money','things_places','systems_evidence','access_authority','handoffs_completion','structure_mismatch','other_unresolved') then
      raise exception 'Invalid candidate work area.' using errcode='22023';
    end if;
    if char_length(v_statement)<1 or char_length(v_statement)>4000 then raise exception 'Invalid candidate statement.' using errcode='22023'; end if;
    if char_length(v_excerpt)<1 or char_length(v_excerpt)>1200 then raise exception 'Invalid evidence excerpt.' using errcode='22023'; end if;
    if v_confidence is null or v_confidence<0 or v_confidence>1 then raise exception 'Invalid candidate confidence.' using errcode='22023'; end if;

    v_start := strpos(v_transcript_text,v_excerpt);
    if v_start=0 then raise exception 'Candidate evidence excerpt is not present in transcript.' using errcode='22023'; end if;

    insert into atlas.implementation_artifact_candidates(
      interpretation_id,candidate_kind,work_area,statement,evidence_excerpt,evidence_start_char,evidence_end_char,confidence,status
    ) values (
      p_interpretation_id,v_kind,v_area,v_statement,v_excerpt,v_start-1,(v_start-1)+char_length(v_excerpt),v_confidence,'proposed'
    );
    v_count := v_count+1;
  end loop;

  update atlas.implementation_artifact_interpretations
  set status='ready',summary=nullif(btrim(coalesce(p_summary,'')),''),generated_at=now(),error_detail=null,
      metadata=metadata||p_metadata,updated_at=now()
  where id=p_interpretation_id;

  return jsonb_build_object('ok',true,'interpretationId',p_interpretation_id,'candidateCount',v_count,'status','ready');
end;
$function$;

create or replace function atlas.mark_implementation_artifact_processing_failed_service_v1(
  p_artifact_id uuid,
  p_stage text,
  p_error_detail text,
  p_retryable boolean default true,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_error text := left(coalesce(p_error_detail,'Processing failed.'),4000);
begin
  if p_stage not in ('transcription','interpretation','configuration','download') then raise exception 'Invalid processing stage.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;

  update atlas.implementation_artifacts
  set processing_state='processing_failed',
      metadata=metadata||jsonb_build_object('lastProcessingFailure',jsonb_build_object('stage',p_stage,'retryable',coalesce(p_retryable,true),'at',now()))||p_metadata,
      updated_at=now()
  where id=p_artifact_id and removed_at is null;

  if p_stage in ('transcription','configuration','download') then
    update atlas.implementation_artifact_transcripts
    set status='failed',error_detail=v_error,updated_at=now()
    where id=(
      select tr.id from atlas.implementation_artifact_transcripts tr
      where tr.implementation_artifact_id=p_artifact_id and tr.status in ('pending','processing')
      order by tr.version desc limit 1
    );
  else
    update atlas.implementation_artifact_interpretations
    set status='failed',error_detail=v_error,updated_at=now()
    where id=(
      select i.id from atlas.implementation_artifact_interpretations i
      where i.implementation_artifact_id=p_artifact_id and i.status='processing'
      order by i.version desc limit 1
    );
  end if;

  return jsonb_build_object('ok',true,'artifactId',p_artifact_id,'stage',p_stage,'retryable',coalesce(p_retryable,true));
end;
$function$;

create or replace function atlas.implementation_artifact_review_self_api_v1(
  p_implementation_case_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required','artifacts','[]'::jsonb);
  end if;
  if not exists(select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id) then
    return jsonb_build_object('ok',false,'code','case_not_found','artifacts','[]'::jsonb);
  end if;

  select jsonb_build_object(
    'ok',true,'contractVersion','implementation_artifact_review_self_api_v1',
    'implementationCaseId',p_implementation_case_id,
    'assignedToMe',atlas.implementation_practitioner_assigned_to_case_self_v1(p_implementation_case_id),
    'artifacts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,'threadId',a.implementation_thread_id,'artifactKind',a.artifact_kind,
        'originalFilename',a.original_filename,'mimeType',a.mime_type,'byteSize',a.byte_size,
        'durationMs',a.duration_ms,'capturedAt',a.captured_at,'processingState',a.processing_state,
        'submittedByUserId',a.submitted_by_user_id,'createdAt',a.created_at,
        'transcript',(
          select jsonb_build_object(
            'id',tr.id,'version',tr.version,'status',tr.status,'text',tr.transcript_text,
            'languageCode',tr.language_code,'providerKey',tr.provider_key,'modelKey',tr.model_key,
            'errorDetail',tr.error_detail,'generatedAt',tr.generated_at
          ) from atlas.implementation_artifact_transcripts tr
          where tr.implementation_artifact_id=a.id and tr.status<>'superseded'
          order by tr.version desc limit 1
        ),
        'interpretation',(
          select jsonb_build_object(
            'id',i.id,'version',i.version,'status',i.status,'summary',i.summary,
            'providerKey',i.provider_key,'modelKey',i.model_key,'errorDetail',i.error_detail,'generatedAt',i.generated_at,
            'candidates',coalesce((
              select jsonb_agg(jsonb_build_object(
                'id',cnd.id,'candidateKind',cnd.candidate_kind,'workArea',cnd.work_area,
                'statement',cnd.statement,'evidenceExcerpt',cnd.evidence_excerpt,
                'evidenceStartChar',cnd.evidence_start_char,'evidenceEndChar',cnd.evidence_end_char,
                'confidence',cnd.confidence,'status',cnd.status,'promotedRecordKind',cnd.promoted_record_kind,
                'promotedRecordId',cnd.promoted_record_id,'reviewedAt',cnd.reviewed_at,'reviewNote',cnd.review_note
              ) order by cnd.created_at,cnd.id)
              from atlas.implementation_artifact_candidates cnd where cnd.interpretation_id=i.id
            ),'[]'::jsonb)
          ) from atlas.implementation_artifact_interpretations i
          where i.implementation_artifact_id=a.id and i.status<>'superseded'
          order by i.version desc limit 1
        )
      ) order by a.created_at desc,a.id)
      from atlas.implementation_artifacts a
      where a.implementation_case_id=p_implementation_case_id and a.removed_at is null
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;

create or replace function atlas.review_implementation_artifact_candidate_self_api_v1(
  p_candidate_id uuid,
  p_decision text,
  p_review_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_candidate atlas.implementation_artifact_candidates%rowtype;
  v_case_id uuid;
  v_source_thread_id uuid;
  v_target_thread_id uuid;
  v_promoted_id uuid;
  v_title text;
begin
  if p_decision not in ('accept','reject') then raise exception 'Decision must be accept or reject.' using errcode='22023'; end if;

  select cnd.* into v_candidate
  from atlas.implementation_artifact_candidates cnd
  where cnd.id=p_candidate_id
  for update;
  if v_candidate.id is null then raise exception 'Implementation candidate not found.' using errcode='23503'; end if;

  select a.implementation_case_id,a.implementation_thread_id into v_case_id,v_source_thread_id
  from atlas.implementation_artifact_interpretations i
  join atlas.implementation_artifacts a on a.id=i.implementation_artifact_id
  where i.id=v_candidate.interpretation_id;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_case_id) then
    raise exception 'Assigned implementation practitioner authority required.' using errcode='42501';
  end if;

  if v_candidate.status in ('accepted','rejected') then
    if (v_candidate.status='accepted' and p_decision='accept') or (v_candidate.status='rejected' and p_decision='reject') then
      return jsonb_build_object('ok',true,'alreadyReviewed',true,'candidateId',v_candidate.id,'status',v_candidate.status,
        'promotedRecordKind',v_candidate.promoted_record_kind,'promotedRecordId',v_candidate.promoted_record_id);
    end if;
    raise exception 'Candidate has already been reviewed.' using errcode='23514';
  end if;
  if v_candidate.status<>'proposed' then raise exception 'Candidate is not reviewable.' using errcode='23514'; end if;

  if p_decision='reject' then
    update atlas.implementation_artifact_candidates
    set status='rejected',reviewed_by_user_id=auth.uid(),reviewed_at=now(),review_note=nullif(btrim(coalesce(p_review_note,'')),''),updated_at=now()
    where id=v_candidate.id;
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'status','rejected','canonicalLedgerChanged',false);
  end if;

  v_title := 'Intake · ' || initcap(replace(v_candidate.work_area,'_',' '));
  select t.id into v_target_thread_id
  from atlas.implementation_threads t
  where t.implementation_case_id=v_case_id and t.work_area=v_candidate.work_area
    and not t.shared_with_participants and t.state='open' and t.title=v_title
  order by t.created_at,t.id limit 1;

  if v_target_thread_id is null then
    insert into atlas.implementation_threads(implementation_case_id,work_area,title,state,author_user_id,shared_with_participants)
    values(v_case_id,v_candidate.work_area,v_title,'open',auth.uid(),false)
    returning id into v_target_thread_id;
  end if;

  if v_candidate.candidate_kind='finding' then
    insert into atlas.implementation_findings(implementation_thread_id,statement,status,author_user_id)
    values(v_target_thread_id,v_candidate.statement,'proposed',auth.uid()) returning id into v_promoted_id;
    update atlas.implementation_artifact_candidates
    set status='accepted',promoted_record_kind='implementation_finding',promoted_record_id=v_promoted_id,
        reviewed_by_user_id=auth.uid(),reviewed_at=now(),review_note=nullif(btrim(coalesce(p_review_note,'')),''),updated_at=now()
    where id=v_candidate.id;
  else
    insert into atlas.implementation_requests(implementation_thread_id,request_text,status,author_user_id)
    values(v_target_thread_id,v_candidate.statement,'open',auth.uid()) returning id into v_promoted_id;
    update atlas.implementation_artifact_candidates
    set status='accepted',promoted_record_kind='implementation_request',promoted_record_id=v_promoted_id,
        reviewed_by_user_id=auth.uid(),reviewed_at=now(),review_note=nullif(btrim(coalesce(p_review_note,'')),''),updated_at=now()
    where id=v_candidate.id;
  end if;

  return jsonb_build_object(
    'ok',true,'candidateId',v_candidate.id,'status','accepted','targetThreadId',v_target_thread_id,
    'promotedRecordKind',case when v_candidate.candidate_kind='finding' then 'implementation_finding' else 'implementation_request' end,
    'promotedRecordId',v_promoted_id,'canonicalLedgerChanged',false
  );
end;
$function$;

revoke all on function atlas.implementation_practitioner_assigned_to_case_self_v1(uuid) from public, anon;
revoke all on function atlas.implementation_artifact_review_self_api_v1(uuid) from public, anon;
revoke all on function atlas.review_implementation_artifact_candidate_self_api_v1(uuid,text,text) from public, anon;
grant execute on function atlas.implementation_practitioner_assigned_to_case_self_v1(uuid) to authenticated;
grant execute on function atlas.implementation_artifact_review_self_api_v1(uuid) to authenticated;
grant execute on function atlas.review_implementation_artifact_candidate_self_api_v1(uuid,text,text) to authenticated;

revoke all on function atlas.begin_implementation_artifact_transcription_service_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.complete_implementation_artifact_transcript_service_v1(uuid,uuid,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function atlas.begin_implementation_artifact_interpretation_service_v1(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function atlas.complete_implementation_artifact_interpretation_service_v1(uuid,text,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.mark_implementation_artifact_processing_failed_service_v1(uuid,text,text,boolean,jsonb) from public, anon, authenticated;
grant execute on function atlas.begin_implementation_artifact_transcription_service_v1(uuid) to service_role;
grant execute on function atlas.complete_implementation_artifact_transcript_service_v1(uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function atlas.begin_implementation_artifact_interpretation_service_v1(uuid,uuid,text,text) to service_role;
grant execute on function atlas.complete_implementation_artifact_interpretation_service_v1(uuid,text,jsonb,jsonb) to service_role;
grant execute on function atlas.mark_implementation_artifact_processing_failed_service_v1(uuid,text,text,boolean,jsonb) to service_role;

commit;