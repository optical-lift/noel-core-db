create schema if not exists newsroom;

create table if not exists newsroom.transcript_editor_states (
  transcript_id uuid primary key references transcript_core.transcripts(id) on delete cascade,
  workspace_id uuid not null,
  base_revision_id uuid,
  text_overrides jsonb not null default '{}'::jsonb,
  speaker_overrides jsonb not null default '{}'::jsonb,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  constraint transcript_editor_text_overrides_object check (jsonb_typeof(text_overrides) = 'object'),
  constraint transcript_editor_speaker_overrides_object check (jsonb_typeof(speaker_overrides) = 'object')
);

alter table newsroom.transcript_editor_states enable row level security;
revoke all on newsroom.transcript_editor_states from anon, authenticated;

create or replace function public.newsroom_get_transcript_editor_state(p_transcript_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
  v_current_revision_id uuid;
  v_state newsroom.transcript_editor_states%rowtype;
begin
  select r.workspace_id, t.current_revision_id
    into v_workspace_id, v_current_revision_id
  from transcript_core.transcripts t
  join transcript_core.recordings r on r.id = t.recording_id
  where t.id = p_transcript_id;

  if v_workspace_id is null then
    raise exception 'Transcript not found.';
  end if;

  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then
    raise exception 'Workspace membership required.';
  end if;

  select * into v_state
  from newsroom.transcript_editor_states
  where transcript_id = p_transcript_id;

  return jsonb_build_object(
    'transcriptId', p_transcript_id,
    'baseRevisionId', coalesce(v_state.base_revision_id, v_current_revision_id),
    'textOverrides', coalesce(v_state.text_overrides, '{}'::jsonb),
    'speakerOverrides', coalesce(v_state.speaker_overrides, '{}'::jsonb),
    'updatedAt', v_state.updated_at
  );
end;
$$;

create or replace function public.newsroom_save_transcript_editor_state(
  p_transcript_id uuid,
  p_base_revision_id uuid,
  p_text_overrides jsonb,
  p_speaker_overrides jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core, newsroom
as $$
declare
  v_workspace_id uuid;
  v_current_revision_id uuid;
  v_state newsroom.transcript_editor_states%rowtype;
begin
  if jsonb_typeof(coalesce(p_text_overrides, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_speaker_overrides, '{}'::jsonb)) <> 'object' then
    raise exception 'Editor overrides must be JSON objects.';
  end if;

  select r.workspace_id, t.current_revision_id
    into v_workspace_id, v_current_revision_id
  from transcript_core.transcripts t
  join transcript_core.recordings r on r.id = t.recording_id
  where t.id = p_transcript_id;

  if v_workspace_id is null then
    raise exception 'Transcript not found.';
  end if;

  if public.transcript_core_can_workspace_edit(v_workspace_id) is not true then
    raise exception 'Workspace edit access required.';
  end if;

  if p_base_revision_id is distinct from v_current_revision_id then
    raise exception 'Transcript revision changed; reload before saving edits.';
  end if;

  insert into newsroom.transcript_editor_states (
    transcript_id,
    workspace_id,
    base_revision_id,
    text_overrides,
    speaker_overrides,
    updated_by,
    updated_at
  ) values (
    p_transcript_id,
    v_workspace_id,
    p_base_revision_id,
    coalesce(p_text_overrides, '{}'::jsonb),
    coalesce(p_speaker_overrides, '{}'::jsonb),
    auth.uid(),
    now()
  )
  on conflict (transcript_id) do update set
    workspace_id = excluded.workspace_id,
    base_revision_id = excluded.base_revision_id,
    text_overrides = excluded.text_overrides,
    speaker_overrides = excluded.speaker_overrides,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into v_state;

  return jsonb_build_object(
    'transcriptId', v_state.transcript_id,
    'baseRevisionId', v_state.base_revision_id,
    'updatedAt', v_state.updated_at
  );
end;
$$;

revoke all on function public.newsroom_get_transcript_editor_state(uuid) from public, anon;
revoke all on function public.newsroom_save_transcript_editor_state(uuid,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.newsroom_get_transcript_editor_state(uuid) to authenticated;
grant execute on function public.newsroom_save_transcript_editor_state(uuid,uuid,jsonb,jsonb) to authenticated;