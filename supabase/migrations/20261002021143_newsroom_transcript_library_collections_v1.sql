create table if not exists newsroom.transcript_collections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  name text not null,
  description text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint transcript_collections_name_not_blank check (length(btrim(name)) > 0)
);

create unique index if not exists transcript_collections_workspace_name_uq
  on newsroom.transcript_collections (workspace_id, lower(btrim(name)))
  where archived_at is null;

create table if not exists newsroom.transcript_collection_recordings (
  collection_id uuid not null references newsroom.transcript_collections(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete cascade,
  added_by uuid references auth.users(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (collection_id, recording_id)
);

create table if not exists newsroom.transcript_tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  name text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint transcript_tags_name_not_blank check (length(btrim(name)) > 0)
);

create unique index if not exists transcript_tags_workspace_name_uq
  on newsroom.transcript_tags (workspace_id, lower(btrim(name)));

create table if not exists newsroom.transcript_recording_tags (
  tag_id uuid not null references newsroom.transcript_tags(id) on delete cascade,
  recording_id uuid not null references transcript_core.recordings(id) on delete cascade,
  added_by uuid references auth.users(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (tag_id, recording_id)
);

alter table newsroom.transcript_collections enable row level security;
alter table newsroom.transcript_collection_recordings enable row level security;
alter table newsroom.transcript_tags enable row level security;
alter table newsroom.transcript_recording_tags enable row level security;

revoke all on newsroom.transcript_collections from anon, authenticated;
revoke all on newsroom.transcript_collection_recordings from anon, authenticated;
revoke all on newsroom.transcript_tags from anon, authenticated;
revoke all on newsroom.transcript_recording_tags from anon, authenticated;

create or replace function public.newsroom_list_transcript_library(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'transcript_core', 'newsroom'
as $$
declare
  v_result jsonb;
begin
  if public.transcript_core_is_workspace_member(p_workspace_id) is not true then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select jsonb_build_object(
    'recordings', coalesce((
      select jsonb_agg(item order by created_at desc)
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
              select max(v.end_ms)
              from transcript_core.transcript_segments s
              join transcript_core.transcript_segment_versions v
                on v.transcript_segment_id = s.id
               and v.transcript_revision_id = t.current_revision_id
              where s.transcript_id = t.id
            ), 0),
            'utteranceCount', coalesce((
              select count(*)
              from transcript_core.utterances u
              where u.transcript_revision_id = t.current_revision_id
            ), 0),
            'collections', coalesce((
              select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
              from newsroom.transcript_collection_recordings cr
              join newsroom.transcript_collections c on c.id = cr.collection_id
              where cr.recording_id = r.id and c.archived_at is null
            ), '[]'::jsonb),
            'tags', coalesce((
              select jsonb_agg(jsonb_build_object('id', tg.id, 'name', tg.name) order by tg.name)
              from newsroom.transcript_recording_tags rt
              join newsroom.transcript_tags tg on tg.id = rt.tag_id
              where rt.recording_id = r.id
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
        where r.workspace_id = p_workspace_id
      ) q
    ), '[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'description', c.description,
        'recordingCount', (select count(*) from newsroom.transcript_collection_recordings cr where cr.collection_id = c.id),
        'createdAt', c.created_at,
        'updatedAt', c.updated_at
      ) order by c.updated_at desc, c.name)
      from newsroom.transcript_collections c
      where c.workspace_id = p_workspace_id and c.archived_at is null
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', tg.id,
        'name', tg.name,
        'recordingCount', (select count(*) from newsroom.transcript_recording_tags rt where rt.tag_id = tg.id)
      ) order by tg.name)
      from newsroom.transcript_tags tg
      where tg.workspace_id = p_workspace_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.newsroom_create_transcript_collection(
  p_workspace_id uuid,
  p_name text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'transcript_core', 'newsroom'
as $$
declare
  v_row newsroom.transcript_collections%rowtype;
begin
  if public.transcript_core_can_workspace_edit(p_workspace_id) is not true then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'COLLECTION_NAME_REQUIRED';
  end if;

  insert into newsroom.transcript_collections (workspace_id, name, description, created_by)
  values (p_workspace_id, btrim(p_name), nullif(btrim(coalesce(p_description, '')), ''), auth.uid())
  returning * into v_row;

  return jsonb_build_object('id', v_row.id, 'name', v_row.name, 'description', v_row.description, 'recordingCount', 0);
end;
$$;

create or replace function public.newsroom_create_transcript_tag(
  p_workspace_id uuid,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'transcript_core', 'newsroom'
as $$
declare
  v_row newsroom.transcript_tags%rowtype;
begin
  if public.transcript_core_can_workspace_edit(p_workspace_id) is not true then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'TAG_NAME_REQUIRED';
  end if;

  insert into newsroom.transcript_tags (workspace_id, name, created_by)
  values (p_workspace_id, btrim(p_name), auth.uid())
  returning * into v_row;

  return jsonb_build_object('id', v_row.id, 'name', v_row.name, 'recordingCount', 0);
end;
$$;

create or replace function public.newsroom_set_recording_collection(
  p_recording_id uuid,
  p_collection_id uuid,
  p_include boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'transcript_core', 'newsroom'
as $$
declare
  v_recording_workspace uuid;
  v_collection_workspace uuid;
begin
  select workspace_id into v_recording_workspace from transcript_core.recordings where id = p_recording_id;
  select workspace_id into v_collection_workspace from newsroom.transcript_collections where id = p_collection_id and archived_at is null;

  if v_recording_workspace is null or v_collection_workspace is null or v_recording_workspace <> v_collection_workspace then
    raise exception 'COLLECTION_RECORDING_MISMATCH';
  end if;
  if public.transcript_core_can_workspace_edit(v_recording_workspace) is not true then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;

  if p_include then
    insert into newsroom.transcript_collection_recordings (collection_id, recording_id, added_by)
    values (p_collection_id, p_recording_id, auth.uid())
    on conflict do nothing;
  else
    delete from newsroom.transcript_collection_recordings
    where collection_id = p_collection_id and recording_id = p_recording_id;
  end if;

  update newsroom.transcript_collections set updated_at = now() where id = p_collection_id;
  return jsonb_build_object('recordingId', p_recording_id, 'collectionId', p_collection_id, 'included', p_include);
end;
$$;

create or replace function public.newsroom_set_recording_tag(
  p_recording_id uuid,
  p_tag_id uuid,
  p_include boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'transcript_core', 'newsroom'
as $$
declare
  v_recording_workspace uuid;
  v_tag_workspace uuid;
begin
  select workspace_id into v_recording_workspace from transcript_core.recordings where id = p_recording_id;
  select workspace_id into v_tag_workspace from newsroom.transcript_tags where id = p_tag_id;

  if v_recording_workspace is null or v_tag_workspace is null or v_recording_workspace <> v_tag_workspace then
    raise exception 'TAG_RECORDING_MISMATCH';
  end if;
  if public.transcript_core_can_workspace_edit(v_recording_workspace) is not true then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;

  if p_include then
    insert into newsroom.transcript_recording_tags (tag_id, recording_id, added_by)
    values (p_tag_id, p_recording_id, auth.uid())
    on conflict do nothing;
  else
    delete from newsroom.transcript_recording_tags
    where tag_id = p_tag_id and recording_id = p_recording_id;
  end if;

  return jsonb_build_object('recordingId', p_recording_id, 'tagId', p_tag_id, 'included', p_include);
end;
$$;

revoke all on function public.newsroom_list_transcript_library(uuid) from public, anon;
revoke all on function public.newsroom_create_transcript_collection(uuid, text, text) from public, anon;
revoke all on function public.newsroom_create_transcript_tag(uuid, text) from public, anon;
revoke all on function public.newsroom_set_recording_collection(uuid, uuid, boolean) from public, anon;
revoke all on function public.newsroom_set_recording_tag(uuid, uuid, boolean) from public, anon;

grant execute on function public.newsroom_list_transcript_library(uuid) to authenticated;
grant execute on function public.newsroom_create_transcript_collection(uuid, text, text) to authenticated;
grant execute on function public.newsroom_create_transcript_tag(uuid, text) to authenticated;
grant execute on function public.newsroom_set_recording_collection(uuid, uuid, boolean) to authenticated;
grant execute on function public.newsroom_set_recording_tag(uuid, uuid, boolean) to authenticated;