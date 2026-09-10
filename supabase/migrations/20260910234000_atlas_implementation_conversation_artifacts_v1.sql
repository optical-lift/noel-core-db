-- Atlas implementation conversation + source artifact capture v1
-- Human-facing goal: a setup sponsor can talk to the implementation team in a
-- shared thread and preserve the original source material before interpretation.
-- Authority goal: conversation/artifacts are evidence inputs, never canonical
-- organization truth by themselves.

begin;

alter table atlas.implementation_threads
  add column if not exists shared_with_participants boolean not null default false;

comment on column atlas.implementation_threads.shared_with_participants is
  'True only when the thread shell may be exposed to active implementation-case participants. Practitioner findings/notes remain separate workbench records.';

create table if not exists atlas.implementation_artifacts (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  submitted_by_user_id uuid not null references auth.users(id),
  submitted_by_participant_id uuid null references atlas.implementation_case_participants(id),
  artifact_kind text not null,
  source_kind text not null default 'atlas_capture',
  storage_bucket text null,
  storage_path text null,
  original_filename text null,
  mime_type text null,
  byte_size bigint null,
  duration_ms bigint null,
  captured_at timestamptz null,
  processing_state text not null default 'upload_pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz null,
  constraint implementation_artifacts_kind_check check (
    artifact_kind in ('audio_recording','document','spreadsheet','photo','image','other')
  ),
  constraint implementation_artifacts_source_kind_check check (
    source_kind in ('atlas_capture','upload','connector','import')
  ),
  constraint implementation_artifacts_processing_state_check check (
    processing_state in ('upload_pending','received','transcribing','transcribed','processing_failed','removed')
  ),
  constraint implementation_artifacts_metadata_object_check check (jsonb_typeof(metadata)='object'),
  constraint implementation_artifacts_byte_size_check check (byte_size is null or byte_size between 0 and 104857600),
  constraint implementation_artifacts_duration_check check (duration_ms is null or duration_ms >= 0),
  constraint implementation_artifacts_storage_pair_check check (
    (storage_bucket is null and storage_path is null)
    or (storage_bucket is not null and storage_path is not null)
  )
);

create index if not exists implementation_artifacts_case_thread_created_idx
  on atlas.implementation_artifacts(implementation_case_id,implementation_thread_id,created_at,id)
  where removed_at is null;
create index if not exists implementation_artifacts_submitter_idx
  on atlas.implementation_artifacts(submitted_by_user_id,created_at desc);
create unique index if not exists implementation_artifacts_storage_object_uq
  on atlas.implementation_artifacts(storage_bucket,storage_path)
  where storage_bucket is not null and storage_path is not null and removed_at is null;

comment on table atlas.implementation_artifacts is
  'Durable raw source artifacts supplied during implementation. These records preserve source/provenance and do not establish canonical Ledger facts.';

create table if not exists atlas.implementation_artifact_transcripts (
  id uuid primary key default gen_random_uuid(),
  implementation_artifact_id uuid not null references atlas.implementation_artifacts(id) on delete cascade,
  version integer not null default 1,
  status text not null default 'pending',
  transcript_text text null,
  language_code text null,
  provider_key text null,
  model_key text null,
  segments jsonb not null default '[]'::jsonb,
  error_detail text null,
  generated_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_artifact_transcripts_version_check check (version > 0),
  constraint implementation_artifact_transcripts_status_check check (
    status in ('pending','processing','ready','failed','superseded')
  ),
  constraint implementation_artifact_transcripts_segments_array_check check (jsonb_typeof(segments)='array'),
  constraint implementation_artifact_transcripts_metadata_object_check check (jsonb_typeof(metadata)='object'),
  constraint implementation_artifact_transcripts_artifact_version_uq unique (implementation_artifact_id,version)
);

create index if not exists implementation_artifact_transcripts_current_idx
  on atlas.implementation_artifact_transcripts(implementation_artifact_id,version desc);

comment on table atlas.implementation_artifact_transcripts is
  'Derived transcriptions of implementation artifacts. The raw artifact remains the source; transcript rows are replaceable/versioned derivatives.';

create table if not exists atlas.implementation_conversation_entries (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  author_user_id uuid null references auth.users(id),
  author_participant_id uuid null references atlas.implementation_case_participants(id),
  entry_kind text not null,
  body text null,
  artifact_id uuid null references atlas.implementation_artifacts(id),
  reply_to_entry_id uuid null references atlas.implementation_conversation_entries(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint implementation_conversation_entries_kind_check check (
    entry_kind in ('text','artifact','system')
  ),
  constraint implementation_conversation_entries_metadata_object_check check (jsonb_typeof(metadata)='object'),
  constraint implementation_conversation_entries_shape_check check (
    (entry_kind='text' and author_user_id is not null and nullif(btrim(coalesce(body,'')),'') is not null and artifact_id is null)
    or (entry_kind='artifact' and author_user_id is not null and artifact_id is not null and body is null)
    or (entry_kind='system' and artifact_id is null)
  )
);

create index if not exists implementation_conversation_entries_thread_created_idx
  on atlas.implementation_conversation_entries(implementation_thread_id,created_at,id);
create index if not exists implementation_conversation_entries_case_created_idx
  on atlas.implementation_conversation_entries(implementation_case_id,created_at,id);
create unique index if not exists implementation_conversation_entries_artifact_uq
  on atlas.implementation_conversation_entries(artifact_id)
  where artifact_id is not null;

comment on table atlas.implementation_conversation_entries is
  'Shared human-facing implementation conversation stream. Entries preserve what was said/sent; practitioner findings and canonical Ledger facts live elsewhere.';

alter table atlas.implementation_artifacts enable row level security;
alter table atlas.implementation_artifact_transcripts enable row level security;
alter table atlas.implementation_conversation_entries enable row level security;

revoke all on atlas.implementation_artifacts from public, anon, authenticated;
revoke all on atlas.implementation_artifact_transcripts from public, anon, authenticated;
revoke all on atlas.implementation_conversation_entries from public, anon, authenticated;

create or replace function atlas.implementation_case_conversation_authorized_self_v1(
  p_implementation_case_id uuid
) returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from atlas.implementation_cases c
      where c.id=p_implementation_case_id
        and c.state not in ('closed','cancelled')
    )
    and (
      exists (
        select 1
        from atlas.implementation_case_participants cp
        where cp.implementation_case_id=p_implementation_case_id
          and cp.human_user_id=auth.uid()
          and cp.active
          and cp.ended_at is null
      )
      or atlas.implementation_practitioner_authorized_self_v1()
    );
$function$;

create or replace function atlas.ensure_implementation_conversation_thread_self_api_v1(
  p_implementation_case_id uuid,
  p_title text default 'General intake'
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid := auth.uid();
  v_title text := btrim(coalesce(p_title,'General intake'));
  v_id uuid;
begin
  if not atlas.implementation_case_conversation_authorized_self_v1(p_implementation_case_id) then
    raise exception 'Implementation conversation authority required.' using errcode='42501';
  end if;
  if v_title='' or char_length(v_title)>160 then
    raise exception 'Conversation title must be between 1 and 160 characters.' using errcode='22023';
  end if;

  select t.id into v_id
  from atlas.implementation_threads t
  where t.implementation_case_id=p_implementation_case_id
    and t.shared_with_participants
    and t.state='open'
    and lower(t.title)=lower(v_title)
  order by t.created_at,t.id
  limit 1;

  if v_id is null then
    insert into atlas.implementation_threads(
      implementation_case_id,work_area,title,state,author_user_id,shared_with_participants
    ) values (
      p_implementation_case_id,'other_unresolved',v_title,'open',v_uid,true
    ) returning id into v_id;
  end if;

  return jsonb_build_object(
    'ok',true,
    'implementationCaseId',p_implementation_case_id,
    'implementationThreadId',v_id,
    'title',v_title
  );
end;
$function$;

create or replace function atlas.post_implementation_conversation_text_self_api_v1(
  p_implementation_case_id uuid,
  p_implementation_thread_id uuid,
  p_body text,
  p_reply_to_entry_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid := auth.uid();
  v_body text := btrim(coalesce(p_body,''));
  v_participant_id uuid;
  v_id uuid;
begin
  if not atlas.implementation_case_conversation_authorized_self_v1(p_implementation_case_id) then
    raise exception 'Implementation conversation authority required.' using errcode='42501';
  end if;
  if char_length(v_body) < 1 or char_length(v_body) > 20000 then
    raise exception 'Conversation message must be between 1 and 20000 characters.' using errcode='22023';
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
  if p_reply_to_entry_id is not null and not exists (
    select 1 from atlas.implementation_conversation_entries e
    where e.id=p_reply_to_entry_id
      and e.implementation_case_id=p_implementation_case_id
      and e.implementation_thread_id=p_implementation_thread_id
  ) then
    raise exception 'Reply target not found in this conversation.' using errcode='23503';
  end if;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.human_user_id=v_uid and cp.active and cp.ended_at is null
  order by cp.started_at desc,cp.id
  limit 1;

  insert into atlas.implementation_conversation_entries(
    implementation_case_id,implementation_thread_id,author_user_id,author_participant_id,
    entry_kind,body,reply_to_entry_id,metadata
  ) values (
    p_implementation_case_id,p_implementation_thread_id,v_uid,v_participant_id,
    'text',v_body,p_reply_to_entry_id,jsonb_build_object('source','atlas_implementation_conversation')
  ) returning id into v_id;

  return jsonb_build_object('ok',true,'entryId',v_id,'implementationThreadId',p_implementation_thread_id);
end;
$function$;

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
  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 104857600 then
    raise exception 'Audio file must be between 1 byte and 100 MB.' using errcode='22023';
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
    coalesce(p_captured_at,now()),'upload_pending',jsonb_build_object('source','atlas_audio_capture_v1')
  );

  return jsonb_build_object(
    'ok',true,
    'artifactId',v_artifact_id,
    'implementationCaseId',p_implementation_case_id,
    'implementationThreadId',p_implementation_thread_id,
    'storageBucket','atlas-implementation-artifacts',
    'storagePath',v_path,
    'mimeType',v_mime,
    'processingState','upload_pending'
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
  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 104857600 then
    raise exception 'Audio file must be between 1 byte and 100 MB.' using errcode='22023';
  end if;

  update atlas.implementation_artifacts
  set byte_size=p_byte_size,
      duration_ms=coalesce(p_duration_ms,duration_ms),
      processing_state='received',
      updated_at=now()
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
      implementation_case_id,implementation_thread_id,author_user_id,author_participant_id,
      entry_kind,artifact_id,metadata
    ) values (
      v_artifact.implementation_case_id,v_artifact.implementation_thread_id,
      v_artifact.submitted_by_user_id,v_participant_id,'artifact',p_artifact_id,
      jsonb_build_object('source','atlas_audio_capture_v1')
    ) returning id into v_entry_id;
  end if;

  insert into atlas.implementation_artifact_transcripts(
    implementation_artifact_id,version,status,metadata
  ) values (
    p_artifact_id,1,'pending',jsonb_build_object('source','audio_artifact_commit')
  ) on conflict (implementation_artifact_id,version) do nothing;

  return jsonb_build_object(
    'ok',true,'artifactId',p_artifact_id,'entryId',v_entry_id,
    'processingState','received','transcriptionState','pending'
  );
end;
$function$;

create or replace function atlas.implementation_artifact_access_self_api_v1(
  p_artifact_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_artifact atlas.implementation_artifacts%rowtype;
begin
  select a.* into v_artifact
  from atlas.implementation_artifacts a
  where a.id=p_artifact_id and a.removed_at is null;

  if v_artifact.id is null then
    return jsonb_build_object('ok',false,'code','artifact_not_found');
  end if;
  if not atlas.implementation_case_conversation_authorized_self_v1(v_artifact.implementation_case_id) then
    return jsonb_build_object('ok',false,'code','conversation_authority_required');
  end if;

  return jsonb_build_object(
    'ok',true,
    'artifactId',v_artifact.id,
    'implementationCaseId',v_artifact.implementation_case_id,
    'implementationThreadId',v_artifact.implementation_thread_id,
    'artifactKind',v_artifact.artifact_kind,
    'storageBucket',v_artifact.storage_bucket,
    'storagePath',v_artifact.storage_path,
    'mimeType',v_artifact.mime_type,
    'byteSize',v_artifact.byte_size,
    'durationMs',v_artifact.duration_ms,
    'processingState',v_artifact.processing_state
  );
end;
$function$;

create or replace function atlas.implementation_conversation_self_api_v1(
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
  if not atlas.implementation_case_conversation_authorized_self_v1(p_implementation_case_id) then
    return jsonb_build_object('ok',false,'code','conversation_authority_required','threads','[]'::jsonb);
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_conversation_self_api_v1',
    'implementationCaseId',p_implementation_case_id,
    'threads',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'workArea',t.work_area,
        'state',t.state,
        'createdAt',t.created_at,
        'entries',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',e.id,
            'entryKind',e.entry_kind,
            'body',e.body,
            'replyToEntryId',e.reply_to_entry_id,
            'createdAt',e.created_at,
            'author',jsonb_build_object(
              'userId',e.author_user_id,
              'relationshipKind',(
                select cp.relationship_kind
                from atlas.implementation_case_participants cp
                where cp.implementation_case_id=p_implementation_case_id
                  and cp.human_user_id=e.author_user_id
                  and cp.active and cp.ended_at is null
                order by cp.started_at desc,cp.id
                limit 1
              ),
              'isMe',e.author_user_id=auth.uid(),
              'isPractitioner',exists(
                select 1 from atlas.implementation_practitioners ip
                where ip.human_user_id=e.author_user_id and ip.status='active'
              )
            ),
            'artifact',case when a.id is null then null else jsonb_build_object(
              'id',a.id,
              'artifactKind',a.artifact_kind,
              'originalFilename',a.original_filename,
              'mimeType',a.mime_type,
              'byteSize',a.byte_size,
              'durationMs',a.duration_ms,
              'capturedAt',a.captured_at,
              'processingState',a.processing_state,
              'transcript',(
                select jsonb_build_object(
                  'id',tr.id,'version',tr.version,'status',tr.status,
                  'text',tr.transcript_text,'languageCode',tr.language_code,
                  'generatedAt',tr.generated_at
                )
                from atlas.implementation_artifact_transcripts tr
                where tr.implementation_artifact_id=a.id and tr.status<>'superseded'
                order by tr.version desc
                limit 1
              )
            ) end
          ) order by e.created_at,e.id)
          from atlas.implementation_conversation_entries e
          left join atlas.implementation_artifacts a on a.id=e.artifact_id and a.removed_at is null
          where e.implementation_thread_id=t.id
        ),'[]'::jsonb)
      ) order by t.created_at,t.id)
      from atlas.implementation_threads t
      where t.implementation_case_id=p_implementation_case_id
        and t.shared_with_participants
        and t.state<>'cancelled'
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- Private bucket. Browser uploads will use exact-path signed upload URLs generated
-- by the Atlas server; playback uses short-lived signed read URLs after the same
-- conversation authorization check.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'atlas-implementation-artifacts',
  'atlas-implementation-artifacts',
  false,
  104857600,
  array['audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav','audio/x-wav','audio/x-m4a','audio/aac']::text[]
)
on conflict (id) do update
set public=false,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

revoke all on function atlas.implementation_case_conversation_authorized_self_v1(uuid) from public, anon;
revoke all on function atlas.ensure_implementation_conversation_thread_self_api_v1(uuid,text) from public, anon;
revoke all on function atlas.post_implementation_conversation_text_self_api_v1(uuid,uuid,text,uuid) from public, anon;
revoke all on function atlas.prepare_implementation_audio_artifact_self_api_v1(uuid,uuid,text,text,bigint,bigint,timestamptz) from public, anon;
revoke all on function atlas.commit_implementation_audio_artifact_self_api_v1(uuid,bigint,bigint) from public, anon;
revoke all on function atlas.implementation_artifact_access_self_api_v1(uuid) from public, anon;
revoke all on function atlas.implementation_conversation_self_api_v1(uuid) from public, anon;

grant execute on function atlas.implementation_case_conversation_authorized_self_v1(uuid) to authenticated;
grant execute on function atlas.ensure_implementation_conversation_thread_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.post_implementation_conversation_text_self_api_v1(uuid,uuid,text,uuid) to authenticated;
grant execute on function atlas.prepare_implementation_audio_artifact_self_api_v1(uuid,uuid,text,text,bigint,bigint,timestamptz) to authenticated;
grant execute on function atlas.commit_implementation_audio_artifact_self_api_v1(uuid,bigint,bigint) to authenticated;
grant execute on function atlas.implementation_artifact_access_self_api_v1(uuid) to authenticated;
grant execute on function atlas.implementation_conversation_self_api_v1(uuid) to authenticated;

commit;
