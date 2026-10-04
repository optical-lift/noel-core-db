-- Serialize publication-to-Reporting source synchronization per recording.
-- The sync membrane is idempotent, but two simultaneous client loads could both
-- observe a missing Reporting Source and race to insert the same source_version_key.

create or replace function public.newsroom_sync_transcript_reporting_source_v1(
  p_publication_id uuid,
  p_recording_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'newsroom', 'transcript_core'
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

  -- The browser can legitimately issue overlapping loads during auth hydration.
  -- Serialize the same recording's projection so the second transaction observes
  -- the Reporting Source established by the first instead of raising 23505.
  perform pg_advisory_xact_lock(hashtextextended(p_recording_id::text, 0));

  return newsroom.sync_transcript_reporting_source_internal_v1(p_publication_id, p_recording_id);
end;
$$;

revoke all on function public.newsroom_sync_transcript_reporting_source_v1(uuid,uuid) from public, anon;
grant execute on function public.newsroom_sync_transcript_reporting_source_v1(uuid,uuid) to authenticated;
