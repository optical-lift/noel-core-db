-- Transcript -> Reporting convergence v1
--
-- Reality artery:
-- Transcript Core recording -> Reporting Source/revision/passages -> Reporting Topic
-- relationship -> Newsroom Collection projection.
--
-- Transcript Core remains source custody. Reporting Core remains reporting-memory
-- authority. These Newsroom bridge tables only record publication scope and the
-- cross-domain identity bindings needed to expose the relationship lawfully.

create schema if not exists newsroom;

create table if not exists newsroom.reporting_recording_sources (
  publication_id uuid not null references newsroom.publications(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete restrict,
  source_asset_id uuid not null references transcript_core.assets(id) on delete restrict,
  reporting_source_id uuid not null references reporting.sources(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (publication_id, recording_id)
);

create index if not exists ix_newsroom_reporting_recording_sources_source_v1
  on newsroom.reporting_recording_sources (reporting_source_id);

create table if not exists newsroom.reporting_transcript_revision_sources (
  publication_id uuid not null references newsroom.publications(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete restrict,
  transcript_revision_id uuid not null references transcript_core.transcript_revisions(id) on delete restrict,
  reporting_source_id uuid not null references reporting.sources(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (publication_id, transcript_revision_id)
);

create index if not exists ix_newsroom_reporting_transcript_revision_sources_recording_v1
  on newsroom.reporting_transcript_revision_sources (publication_id, recording_id);

create index if not exists ix_newsroom_reporting_transcript_revision_sources_source_v1
  on newsroom.reporting_transcript_revision_sources (reporting_source_id);

create table if not exists newsroom.reporting_topic_scopes (
  publication_id uuid not null references newsroom.publications(id) on delete cascade,
  topic_id uuid not null references reporting.topics(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (publication_id, topic_id)
);

create index if not exists ix_newsroom_reporting_topic_scopes_topic_v1
  on newsroom.reporting_topic_scopes (topic_id);

create unique index if not exists ux_newsroom_reporting_topic_scopes_topic_v1
  on newsroom.reporting_topic_scopes (topic_id);

alter table newsroom.reporting_recording_sources enable row level security;
alter table newsroom.reporting_transcript_revision_sources enable row level security;
alter table newsroom.reporting_topic_scopes enable row level security;

revoke all on newsroom.reporting_recording_sources from public, anon, authenticated;
revoke all on newsroom.reporting_transcript_revision_sources from public, anon, authenticated;
revoke all on newsroom.reporting_topic_scopes from public, anon, authenticated;

create or replace function newsroom.sync_transcript_reporting_source_internal_v1(
  p_publication_id uuid,
  p_recording_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, newsroom, reporting, transcript_core, extensions
as $$
declare
  v_binding_ref text;
  v_recording transcript_core.recordings%rowtype;
  v_asset transcript_core.assets%rowtype;
  v_transcript transcript_core.transcripts%rowtype;
  v_revision transcript_core.transcript_revisions%rowtype;
  v_audio_family_key text;
  v_audio_version_key text;
  v_transcript_family_key text;
  v_transcript_version_key text;
  v_audio_source_id uuid;
  v_transcript_source_id uuid;
  v_previous_active_source_id uuid;
  v_text_origin text;
  v_derivation_kind text;
begin
  select b.external_ref
    into v_binding_ref
  from newsroom.publication_domain_bindings b
  join newsroom.publications p
    on p.id = b.publication_id
   and p.state = 'active'
  join newsroom.workspaces w
    on w.id = p.workspace_id
   and w.state = 'active'
  where b.publication_id = p_publication_id
    and b.domain_key = 'transcript_core'
    and b.binding_kind = 'workspace'
    and b.state = 'active'
  limit 1;

  if v_binding_ref is null then
    raise exception 'NEWSROOM_TRANSCRIPT_BINDING_REQUIRED';
  end if;

  select r.*
    into v_recording
  from transcript_core.recordings r
  where r.id = p_recording_id
    and r.workspace_id::text = v_binding_ref;

  if v_recording.id is null then
    raise exception 'NEWSROOM_RECORDING_OUTSIDE_PUBLICATION_BINDING';
  end if;

  select a.*
    into v_asset
  from transcript_core.assets a
  where a.id = v_recording.source_asset_id
    and a.workspace_id = v_recording.workspace_id;

  if v_asset.id is null then
    raise exception 'NEWSROOM_RECORDING_SOURCE_ASSET_MISSING';
  end if;

  v_audio_family_key := 'transcript-core:recording:' || v_recording.id::text || ':audio';
  v_audio_version_key := v_audio_family_key || ':original';

  select s.id
    into v_audio_source_id
  from reporting.sources s
  where s.source_version_key = v_audio_version_key;

  if v_audio_source_id is not null and exists (
    select 1
    from reporting.sources s
    where s.id = v_audio_source_id
      and (
        lower(coalesce(s.content_sha256, '')) <> lower(v_asset.content_hash)
        or coalesce(s.external_locator ->> 'sourceAssetId', '') <> v_asset.id::text
        or coalesce(s.external_locator ->> 'recordingId', '') <> v_recording.id::text
      )
  ) then
    raise exception 'NEWSROOM_RECORDING_SOURCE_IDENTITY_CONFLICT';
  end if;

  if v_audio_source_id is null then
    insert into reporting.sources (
      source_family_key,
      source_version_key,
      source_kind,
      authority_class,
      visibility_class,
      title,
      external_locator,
      content_sha256,
      content_type,
      source_status,
      metadata
    ) values (
      v_audio_family_key,
      v_audio_version_key,
      'recording',
      'unknown',
      'newsroom_private',
      v_recording.title,
      jsonb_build_object(
        'system', 'transcript_core',
        'recordingId', v_recording.id,
        'sourceAssetId', v_asset.id,
        'workspaceId', v_recording.workspace_id
      ),
      lower(v_asset.content_hash),
      v_asset.mime_type,
      'active',
      jsonb_build_object(
        'custodyOwner', 'transcript_core',
        'sourceSemantics', 'observed_original_recording',
        'recordingCreatedAt', v_recording.created_at
      )
    )
    returning id into v_audio_source_id;
  else
    update reporting.sources
    set title = v_recording.title,
        content_sha256 = lower(v_asset.content_hash),
        content_type = v_asset.mime_type,
        external_locator = jsonb_build_object(
          'system', 'transcript_core',
          'recordingId', v_recording.id,
          'sourceAssetId', v_asset.id,
          'workspaceId', v_recording.workspace_id
        ),
        metadata = metadata || jsonb_build_object(
          'custodyOwner', 'transcript_core',
          'sourceSemantics', 'observed_original_recording',
          'recordingCreatedAt', v_recording.created_at
        ),
        source_status = 'active',
        updated_at = now()
    where id = v_audio_source_id;
  end if;

  if exists (
    select 1
    from newsroom.reporting_recording_sources rrs
    where rrs.publication_id = p_publication_id
      and rrs.recording_id = v_recording.id
      and (rrs.source_asset_id <> v_asset.id or rrs.reporting_source_id <> v_audio_source_id)
  ) then
    raise exception 'NEWSROOM_RECORDING_BRIDGE_IDENTITY_CONFLICT';
  end if;

  insert into newsroom.reporting_recording_sources (
    publication_id,
    recording_id,
    source_asset_id,
    reporting_source_id
  ) values (
    p_publication_id,
    v_recording.id,
    v_asset.id,
    v_audio_source_id
  )
  on conflict (publication_id, recording_id) do update
  set updated_at = now();

  select t.*
    into v_transcript
  from transcript_core.transcripts t
  where t.recording_id = v_recording.id;

  if v_transcript.id is null or v_transcript.current_revision_id is null then
    return jsonb_build_object(
      'recordingId', v_recording.id,
      'audioSourceId', v_audio_source_id,
      'transcriptSourceId', null,
      'transcriptRevisionId', null
    );
  end if;

  select tr.*
    into v_revision
  from transcript_core.transcript_revisions tr
  where tr.id = v_transcript.current_revision_id
    and tr.transcript_id = v_transcript.id;

  if v_revision.id is null then
    raise exception 'NEWSROOM_CURRENT_TRANSCRIPT_REVISION_MISSING';
  end if;

  v_transcript_family_key := 'transcript-core:recording:' || v_recording.id::text || ':transcript';
  v_transcript_version_key := 'transcript-core:transcript-revision:' || v_revision.id::text;
  v_text_origin := case when v_revision.revision_kind::text = 'human' then 'human_transcript' else 'machine_transcript' end;
  v_derivation_kind := v_text_origin;

  select s.id
    into v_previous_active_source_id
  from reporting.sources s
  where s.source_family_key = v_transcript_family_key
    and s.source_status = 'active'
    and s.source_version_key <> v_transcript_version_key
  limit 1;

  if v_previous_active_source_id is not null then
    update reporting.sources
    set source_status = 'superseded',
        updated_at = now()
    where id = v_previous_active_source_id;
  end if;

  select s.id
    into v_transcript_source_id
  from reporting.sources s
  where s.source_version_key = v_transcript_version_key;

  if v_transcript_source_id is not null and exists (
    select 1
    from reporting.sources s
    where s.id = v_transcript_source_id
      and (
        s.parent_source_id is distinct from v_audio_source_id
        or coalesce(s.external_locator ->> 'transcriptRevisionId', '') <> v_revision.id::text
        or coalesce(s.external_locator ->> 'recordingId', '') <> v_recording.id::text
      )
  ) then
    raise exception 'NEWSROOM_TRANSCRIPT_SOURCE_IDENTITY_CONFLICT';
  end if;

  if v_transcript_source_id is null then
    insert into reporting.sources (
      source_family_key,
      source_version_key,
      source_kind,
      authority_class,
      visibility_class,
      title,
      external_locator,
      content_type,
      parent_source_id,
      derivation_kind,
      supersedes_source_id,
      source_status,
      metadata
    ) values (
      v_transcript_family_key,
      v_transcript_version_key,
      'transcript',
      'unknown',
      'newsroom_private',
      v_recording.title || ' — transcript revision ' || v_revision.ordinal::text,
      jsonb_build_object(
        'system', 'transcript_core',
        'recordingId', v_recording.id,
        'transcriptId', v_transcript.id,
        'transcriptRevisionId', v_revision.id,
        'workspaceId', v_recording.workspace_id
      ),
      'text/plain',
      v_audio_source_id,
      v_derivation_kind,
      v_previous_active_source_id,
      'active',
      jsonb_build_object(
        'custodyOwner', 'transcript_core',
        'revisionKind', v_revision.revision_kind::text,
        'revisionOrdinal', v_revision.ordinal,
        'provider', v_revision.provider,
        'providerModel', v_revision.provider_model,
        'audioVerificationImplied', false
      )
    )
    returning id into v_transcript_source_id;
  else
    update reporting.sources
    set title = v_recording.title || ' — transcript revision ' || v_revision.ordinal::text,
        parent_source_id = v_audio_source_id,
        derivation_kind = v_derivation_kind,
        supersedes_source_id = coalesce(reporting.sources.supersedes_source_id, v_previous_active_source_id),
        source_status = 'active',
        external_locator = jsonb_build_object(
          'system', 'transcript_core',
          'recordingId', v_recording.id,
          'transcriptId', v_transcript.id,
          'transcriptRevisionId', v_revision.id,
          'workspaceId', v_recording.workspace_id
        ),
        metadata = metadata || jsonb_build_object(
          'custodyOwner', 'transcript_core',
          'revisionKind', v_revision.revision_kind::text,
          'revisionOrdinal', v_revision.ordinal,
          'provider', v_revision.provider,
          'providerModel', v_revision.provider_model,
          'audioVerificationImplied', false
        ),
        updated_at = now()
    where id = v_transcript_source_id;
  end if;

  if exists (
    select 1
    from newsroom.reporting_transcript_revision_sources rtrs
    where rtrs.publication_id = p_publication_id
      and rtrs.transcript_revision_id = v_revision.id
      and (rtrs.recording_id <> v_recording.id or rtrs.reporting_source_id <> v_transcript_source_id)
  ) then
    raise exception 'NEWSROOM_TRANSCRIPT_BRIDGE_IDENTITY_CONFLICT';
  end if;

  insert into newsroom.reporting_transcript_revision_sources (
    publication_id,
    recording_id,
    transcript_revision_id,
    reporting_source_id
  ) values (
    p_publication_id,
    v_recording.id,
    v_revision.id,
    v_transcript_source_id
  )
  on conflict (publication_id, transcript_revision_id) do nothing;

  insert into reporting.source_passages (
    source_id,
    stable_key,
    passage_kind,
    ordinal,
    speaker_label_raw,
    text,
    text_origin,
    is_verbatim,
    machine_derived,
    text_sha256,
    locator,
    metadata
  )
  select
    v_transcript_source_id,
    'transcript-core:transcript-revision:' || v_revision.id::text || ':segment:' || s.id::text,
    'transcript_segment',
    s.sequence,
    sv.provider_speaker,
    sv.text,
    v_text_origin,
    false,
    (v_revision.revision_kind::text = 'machine'),
    encode(extensions.digest(sv.text, 'sha256'), 'hex'),
    jsonb_build_object(
      'system', 'transcript_core',
      'recordingId', v_recording.id,
      'transcriptId', v_transcript.id,
      'transcriptRevisionId', v_revision.id,
      'transcriptSegmentId', s.id,
      'startMs', sv.start_ms,
      'endMs', sv.end_ms
    ),
    jsonb_build_object(
      'providerSpeaker', sv.provider_speaker,
      'audioVerificationImplied', false
    )
  from transcript_core.transcript_segments s
  join transcript_core.transcript_segment_versions sv
    on sv.transcript_segment_id = s.id
   and sv.transcript_revision_id = v_revision.id
  where s.transcript_id = v_transcript.id
  on conflict (stable_key) do nothing;

  return jsonb_build_object(
    'recordingId', v_recording.id,
    'audioSourceId', v_audio_source_id,
    'transcriptSourceId', v_transcript_source_id,
    'transcriptRevisionId', v_revision.id
  );
end;
$$;

revoke all on function newsroom.sync_transcript_reporting_source_internal_v1(uuid, uuid) from public, anon, authenticated;

create or replace function public.newsroom_sync_transcript_reporting_source_v1(
  p_publication_id uuid,
  p_recording_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, newsroom, transcript_core
as $$
declare
  v_user_id uuid := auth.uid();
  v_workspace_ref text;
  v_workspace_id uuid;
begin
  if v_user_id is null then
    raise exception 'NEWSROOM_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from newsroom.publications p
    join newsroom.workspaces w
      on w.id = p.workspace_id
     and w.state = 'active'
    join newsroom.workspace_memberships wm
      on wm.workspace_id = p.workspace_id
     and wm.user_id = v_user_id
     and wm.membership_state = 'active'
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = wm.id
    where p.id = p_publication_id
      and p.state = 'active'
  ) then
    raise exception 'NEWSROOM_PUBLICATION_ACCESS_FORBIDDEN';
  end if;

  select b.external_ref
    into v_workspace_ref
  from newsroom.publication_domain_bindings b
  where b.publication_id = p_publication_id
    and b.domain_key = 'transcript_core'
    and b.binding_kind = 'workspace'
    and b.state = 'active'
  limit 1;

  if v_workspace_ref is null then
    raise exception 'NEWSROOM_TRANSCRIPT_ACCESS_FORBIDDEN';
  end if;

  begin
    v_workspace_id := v_workspace_ref::uuid;
  exception when invalid_text_representation then
    raise exception 'NEWSROOM_TRANSCRIPT_BINDING_INVALID';
  end;

  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'NEWSROOM_TRANSCRIPT_ACCESS_FORBIDDEN';
  end if;

  return newsroom.sync_transcript_reporting_source_internal_v1(p_publication_id, p_recording_id);
end;
$$;

revoke all on function public.newsroom_sync_transcript_reporting_source_v1(uuid, uuid) from public, anon;
grant execute on function public.newsroom_sync_transcript_reporting_source_v1(uuid, uuid) to authenticated;

create or replace function public.newsroom_create_reporting_topic_v1(
  p_publication_id uuid,
  p_title text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, newsroom, reporting
as $$
declare
  v_user_id uuid := auth.uid();
  v_topic_id uuid := gen_random_uuid();
  v_title text := btrim(coalesce(p_title, ''));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
begin
  if v_user_id is null then
    raise exception 'NEWSROOM_AUTH_REQUIRED';
  end if;

  if v_title = '' then
    raise exception 'NEWSROOM_TOPIC_TITLE_REQUIRED';
  end if;

  if not exists (
    select 1
    from newsroom.publications p
    join newsroom.workspaces w
      on w.id = p.workspace_id
     and w.state = 'active'
    join newsroom.workspace_memberships wm
      on wm.workspace_id = p.workspace_id
     and wm.user_id = v_user_id
     and wm.membership_state = 'active'
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = wm.id
    where p.id = p_publication_id
      and p.state = 'active'
  ) then
    raise exception 'NEWSROOM_PUBLICATION_ACCESS_FORBIDDEN';
  end if;

  if exists (
    select 1
    from newsroom.reporting_topic_scopes rts
    join reporting.topics t on t.id = rts.topic_id
    where rts.publication_id = p_publication_id
      and t.workflow_state <> 'archived'
      and lower(btrim(t.title)) = lower(v_title)
  ) then
    raise exception 'NEWSROOM_TOPIC_TITLE_EXISTS';
  end if;

  insert into reporting.topics (
    id,
    stable_key,
    title,
    description,
    workflow_state,
    metadata
  ) values (
    v_topic_id,
    'newsroom:publication:' || p_publication_id::text || ':topic:' || v_topic_id::text,
    v_title,
    v_description,
    'continuing',
    jsonb_build_object(
      'newsroomPublicationId', p_publication_id,
      'productProjection', 'collection'
    )
  );

  insert into newsroom.reporting_topic_scopes (publication_id, topic_id, created_by)
  values (p_publication_id, v_topic_id, v_user_id);

  return jsonb_build_object(
    'id', v_topic_id,
    'title', v_title,
    'description', v_description,
    'workflowState', 'continuing',
    'recordingCount', 0
  );
end;
$$;

revoke all on function public.newsroom_create_reporting_topic_v1(uuid, text, text) from public, anon;
grant execute on function public.newsroom_create_reporting_topic_v1(uuid, text, text) to authenticated;

create or replace function public.newsroom_set_recording_topic_v1(
  p_publication_id uuid,
  p_recording_id uuid,
  p_topic_id uuid,
  p_include boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, newsroom, reporting, transcript_core
as $$
declare
  v_user_id uuid := auth.uid();
  v_workspace_ref text;
  v_workspace_id uuid;
  v_sync jsonb;
  v_source_id uuid;
begin
  if v_user_id is null then
    raise exception 'NEWSROOM_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from newsroom.publications p
    join newsroom.workspaces w
      on w.id = p.workspace_id
     and w.state = 'active'
    join newsroom.workspace_memberships wm
      on wm.workspace_id = p.workspace_id
     and wm.user_id = v_user_id
     and wm.membership_state = 'active'
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = wm.id
    where p.id = p_publication_id
      and p.state = 'active'
  ) then
    raise exception 'NEWSROOM_PUBLICATION_ACCESS_FORBIDDEN';
  end if;

  if not exists (
    select 1
    from newsroom.reporting_topic_scopes ts
    join reporting.topics t on t.id = ts.topic_id
    where ts.publication_id = p_publication_id
      and ts.topic_id = p_topic_id
      and t.workflow_state <> 'archived'
  ) then
    raise exception 'NEWSROOM_TOPIC_OUTSIDE_PUBLICATION_SCOPE';
  end if;

  select b.external_ref
    into v_workspace_ref
  from newsroom.publication_domain_bindings b
  where b.publication_id = p_publication_id
    and b.domain_key = 'transcript_core'
    and b.binding_kind = 'workspace'
    and b.state = 'active'
  limit 1;

  if v_workspace_ref is null then
    raise exception 'NEWSROOM_TRANSCRIPT_ACCESS_FORBIDDEN';
  end if;

  begin
    v_workspace_id := v_workspace_ref::uuid;
  exception when invalid_text_representation then
    raise exception 'NEWSROOM_TRANSCRIPT_BINDING_INVALID';
  end;

  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'NEWSROOM_TRANSCRIPT_ACCESS_FORBIDDEN';
  end if;

  v_sync := newsroom.sync_transcript_reporting_source_internal_v1(p_publication_id, p_recording_id);
  v_source_id := nullif(v_sync ->> 'audioSourceId', '')::uuid;

  if v_source_id is null then
    raise exception 'NEWSROOM_REPORTING_SOURCE_NOT_READY';
  end if;

  if coalesce(p_include, false) then
    insert into reporting.topic_sources (topic_id, source_id, relation_role)
    values (p_topic_id, v_source_id, 'collection_member')
    on conflict do nothing;
  else
    delete from reporting.topic_sources
    where topic_id = p_topic_id
      and source_id = v_source_id
      and relation_role = 'collection_member';
  end if;

  update reporting.topics
  set updated_at = now()
  where id = p_topic_id;

  return jsonb_build_object(
    'recordingId', p_recording_id,
    'topicId', p_topic_id,
    'included', coalesce(p_include, false)
  );
end;
$$;

revoke all on function public.newsroom_set_recording_topic_v1(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.newsroom_set_recording_topic_v1(uuid, uuid, uuid, boolean) to authenticated;

create or replace function public.newsroom_transcript_library_v2(
  p_publication_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, newsroom, reporting, transcript_core
as $$
declare
  v_user_id uuid := auth.uid();
  v_workspace_ref text;
  v_workspace_id uuid;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'NEWSROOM_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from newsroom.publications p
    join newsroom.workspaces w
      on w.id = p.workspace_id
     and w.state = 'active'
    join newsroom.workspace_memberships wm
      on wm.workspace_id = p.workspace_id
     and wm.user_id = v_user_id
     and wm.membership_state = 'active'
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = wm.id
    where p.id = p_publication_id
      and p.state = 'active'
  ) then
    raise exception 'NEWSROOM_PUBLICATION_ACCESS_FORBIDDEN';
  end if;

  select b.external_ref
    into v_workspace_ref
  from newsroom.publication_domain_bindings b
  where b.publication_id = p_publication_id
    and b.domain_key = 'transcript_core'
    and b.binding_kind = 'workspace'
    and b.state = 'active'
  limit 1;

  if v_workspace_ref is null then
    raise exception 'NEWSROOM_TRANSCRIPT_BINDING_REQUIRED';
  end if;

  begin
    v_workspace_id := v_workspace_ref::uuid;
  exception when invalid_text_representation then
    raise exception 'NEWSROOM_TRANSCRIPT_BINDING_INVALID';
  end;

  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'NEWSROOM_TRANSCRIPT_ACCESS_FORBIDDEN';
  end if;

  select jsonb_build_object(
    'recordings', coalesce((
      select jsonb_agg(q.item order by q.created_at desc)
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
            'processingJobId', pj.id,
            'processingStatus', pj.status,
            'processingAttempt', pj.attempt,
            'processingErrorCode', pj.error_code,
            'processingErrorMessage', pj.error_message,
            'provider', pj.provider,
            'providerModel', pj.provider_model,
            'durationMs', coalesce((
              select max(sv.end_ms)
              from transcript_core.transcript_segments s
              join transcript_core.transcript_segment_versions sv
                on sv.transcript_segment_id = s.id
               and sv.transcript_revision_id = t.current_revision_id
              where s.transcript_id = t.id
            ), 0),
            'utteranceCount', coalesce((
              select count(*)
              from transcript_core.utterances u
              where u.transcript_revision_id = t.current_revision_id
            ), 0),
            'reportingSourceReady', (rrs.reporting_source_id is not null),
            'collections', coalesce((
              select jsonb_agg(
                jsonb_build_object('id', rt.id, 'title', rt.title)
                order by rt.updated_at desc, rt.title
              )
              from newsroom.reporting_topic_scopes rts
              join reporting.topics rt
                on rt.id = rts.topic_id
               and rt.workflow_state <> 'archived'
              join reporting.topic_sources ts
                on ts.topic_id = rt.id
               and ts.relation_role = 'collection_member'
              where rts.publication_id = p_publication_id
                and ts.source_id = rrs.reporting_source_id
            ), '[]'::jsonb)
          ) as item
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
        left join newsroom.reporting_recording_sources rrs
          on rrs.publication_id = p_publication_id
         and rrs.recording_id = r.id
        where r.workspace_id = v_workspace_id
      ) q
    ), '[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'title', t.title,
          'description', t.description,
          'workflowState', t.workflow_state,
          'recordingCount', (
            select count(distinct rrs.recording_id)
            from reporting.topic_sources ts
            join newsroom.reporting_recording_sources rrs
              on rrs.publication_id = p_publication_id
             and rrs.reporting_source_id = ts.source_id
            where ts.topic_id = t.id
              and ts.relation_role = 'collection_member'
          ),
          'createdAt', t.created_at,
          'updatedAt', t.updated_at
        )
        order by t.updated_at desc, t.title
      )
      from newsroom.reporting_topic_scopes rts
      join reporting.topics t on t.id = rts.topic_id
      where rts.publication_id = p_publication_id
        and t.workflow_state <> 'archived'
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.newsroom_transcript_library_v2(uuid) from public, anon;
grant execute on function public.newsroom_transcript_library_v2(uuid) to authenticated;

do $$
declare
  v_row record;
begin
  for v_row in
    select b.publication_id, r.id as recording_id
    from newsroom.publication_domain_bindings b
    join transcript_core.recordings r on r.workspace_id::text = b.external_ref
    where b.domain_key = 'transcript_core'
      and b.binding_kind = 'workspace'
      and b.state = 'active'
  loop
    perform newsroom.sync_transcript_reporting_source_internal_v1(v_row.publication_id, v_row.recording_id);
  end loop;
end;
$$;

comment on function public.newsroom_transcript_library_v2(uuid) is
  'Publication-scoped Transcript library projection. Collections are Reporting Core Topics linked to the registered original recording source.';

comment on function public.newsroom_set_recording_topic_v1(uuid, uuid, uuid, boolean) is
  'Adds/removes a publication-scoped Reporting Topic relationship for a Transcript Core recording. collection_member is organizational and does not assert every passage concerns the Topic.';