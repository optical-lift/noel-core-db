create or replace function public.transcript_core_create_manuscript_document(
  p_workspace_id uuid,
  p_title text
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  document_id uuid;
begin
  if not public.transcript_core_can_workspace_edit(p_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'MANUSCRIPT_TITLE_REQUIRED';
  end if;

  insert into transcript_core.manuscript_documents(workspace_id, title)
  values (p_workspace_id, trim(p_title))
  returning id into document_id;

  return document_id;
end;
$$;

create or replace function public.transcript_core_create_manuscript_revision(
  p_manuscript_document_id uuid,
  p_content_hash text,
  p_source_format text,
  p_units jsonb,
  p_source_asset_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  next_ordinal integer;
  revision_id uuid;
  unit_item jsonb;
  unit_sequence integer;
  unit_kind text;
  unit_text text;
begin
  select workspace_id into target_workspace_id
  from transcript_core.manuscript_documents
  where id = p_manuscript_document_id;

  if target_workspace_id is null then
    raise exception 'MANUSCRIPT_DOCUMENT_NOT_FOUND';
  end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if nullif(trim(p_content_hash), '') is null then
    raise exception 'MANUSCRIPT_CONTENT_HASH_REQUIRED';
  end if;
  if jsonb_typeof(p_units) <> 'array' or jsonb_array_length(p_units) = 0 then
    raise exception 'MANUSCRIPT_UNITS_REQUIRED';
  end if;

  if p_source_asset_id is not null and not exists (
    select 1 from transcript_core.assets a
    where a.id = p_source_asset_id and a.workspace_id = target_workspace_id
  ) then
    raise exception 'MANUSCRIPT_SOURCE_ASSET_INVALID';
  end if;

  select coalesce(max(ordinal), 0) + 1 into next_ordinal
  from transcript_core.manuscript_revisions
  where manuscript_document_id = p_manuscript_document_id;

  insert into transcript_core.manuscript_revisions(
    manuscript_document_id,
    ordinal,
    source_asset_id,
    content_hash,
    source_format,
    created_by
  ) values (
    p_manuscript_document_id,
    next_ordinal,
    p_source_asset_id,
    trim(p_content_hash),
    nullif(trim(p_source_format), ''),
    auth.uid()
  ) returning id into revision_id;

  for unit_item in select value from jsonb_array_elements(p_units)
  loop
    if jsonb_typeof(unit_item) <> 'object' then
      raise exception 'MANUSCRIPT_UNIT_MUST_BE_OBJECT';
    end if;

    begin
      unit_sequence := (unit_item->>'sequence')::integer;
    exception when others then
      raise exception 'MANUSCRIPT_UNIT_SEQUENCE_INVALID';
    end;

    unit_kind := unit_item->>'kind';
    unit_text := unit_item->>'text';

    if unit_sequence is null or unit_sequence <= 0 then
      raise exception 'MANUSCRIPT_UNIT_SEQUENCE_INVALID';
    end if;
    if unit_kind not in ('paragraph','paragraph_group','sentence','custom') then
      raise exception 'MANUSCRIPT_UNIT_KIND_INVALID:%', coalesce(unit_kind, 'null');
    end if;
    if nullif(trim(unit_text), '') is null then
      raise exception 'MANUSCRIPT_UNIT_TEXT_REQUIRED:%', unit_sequence;
    end if;
    if unit_item ? 'sourceAnchor'
       and unit_item->'sourceAnchor' is not null
       and jsonb_typeof(unit_item->'sourceAnchor') <> 'object' then
      raise exception 'MANUSCRIPT_SOURCE_ANCHOR_MUST_BE_OBJECT:%', unit_sequence;
    end if;

    insert into transcript_core.narration_units(
      manuscript_revision_id,
      sequence,
      unit_kind,
      chapter_key,
      chapter_title,
      pov_key,
      pov_display_name,
      text,
      source_anchor
    ) values (
      revision_id,
      unit_sequence,
      unit_kind,
      nullif(unit_item->>'chapterKey', ''),
      nullif(unit_item->>'chapterTitle', ''),
      nullif(unit_item->>'povKey', ''),
      nullif(unit_item->>'povDisplayName', ''),
      unit_text,
      coalesce(unit_item->'sourceAnchor', '{}'::jsonb)
    );
  end loop;

  return revision_id;
end;
$$;

create or replace function public.transcript_core_list_manuscript_documents(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare result jsonb;
begin
  if not public.transcript_core_is_workspace_member(p_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', md.id,
    'title', md.title,
    'createdAt', md.created_at,
    'latestRevision', (
      select jsonb_build_object(
        'id', mr.id,
        'ordinal', mr.ordinal,
        'contentHash', mr.content_hash,
        'sourceFormat', mr.source_format,
        'createdAt', mr.created_at,
        'narrationUnitCount', (
          select count(*) from transcript_core.narration_units nu where nu.manuscript_revision_id = mr.id
        )
      )
      from transcript_core.manuscript_revisions mr
      where mr.manuscript_document_id = md.id
      order by mr.ordinal desc
      limit 1
    )
  ) order by md.created_at desc), '[]'::jsonb)
  into result
  from transcript_core.manuscript_documents md
  where md.workspace_id = p_workspace_id;

  return result;
end;
$$;

create or replace function public.transcript_core_get_manuscript_revision(p_manuscript_revision_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  result jsonb;
begin
  select md.workspace_id into target_workspace_id
  from transcript_core.manuscript_revisions mr
  join transcript_core.manuscript_documents md on md.id = mr.manuscript_document_id
  where mr.id = p_manuscript_revision_id;

  if target_workspace_id is null then
    raise exception 'MANUSCRIPT_REVISION_NOT_FOUND';
  end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select jsonb_build_object(
    'id', mr.id,
    'manuscriptDocumentId', mr.manuscript_document_id,
    'title', md.title,
    'ordinal', mr.ordinal,
    'contentHash', mr.content_hash,
    'sourceFormat', mr.source_format,
    'sourceAssetId', mr.source_asset_id,
    'createdAt', mr.created_at,
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', nu.id,
        'manuscriptRevisionId', nu.manuscript_revision_id,
        'sequence', nu.sequence,
        'kind', nu.unit_kind,
        'chapterKey', nu.chapter_key,
        'chapterTitle', nu.chapter_title,
        'povKey', nu.pov_key,
        'povDisplayName', nu.pov_display_name,
        'text', nu.text,
        'sourceAnchor', nu.source_anchor
      ) order by nu.sequence)
      from transcript_core.narration_units nu
      where nu.manuscript_revision_id = mr.id
    ), '[]'::jsonb)
  ) into result
  from transcript_core.manuscript_revisions mr
  join transcript_core.manuscript_documents md on md.id = mr.manuscript_document_id
  where mr.id = p_manuscript_revision_id;

  return result;
end;
$$;

create or replace function public.transcript_core_create_production(
  p_workspace_id uuid,
  p_title text,
  p_production_kind text,
  p_source_kind text,
  p_source_revision_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  production_id uuid;
  source_workspace_id uuid;
begin
  if not public.transcript_core_can_workspace_edit(p_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if nullif(trim(p_title), '') is null then
    raise exception 'PRODUCTION_TITLE_REQUIRED';
  end if;
  if p_production_kind not in ('audiobook','readers_theatre','voiceover','audio_drama','narrated_curriculum','training','other') then
    raise exception 'PRODUCTION_KIND_INVALID:%', coalesce(p_production_kind, 'null');
  end if;
  if p_source_kind not in ('script_revision','manuscript_revision') then
    raise exception 'PRODUCTION_SOURCE_KIND_INVALID:%', coalesce(p_source_kind, 'null');
  end if;
  if p_production_kind = 'audiobook' and p_source_kind <> 'manuscript_revision' then
    raise exception 'AUDIOBOOK_REQUIRES_MANUSCRIPT_SOURCE';
  end if;
  if p_production_kind = 'readers_theatre' and p_source_kind <> 'script_revision' then
    raise exception 'READERS_THEATRE_REQUIRES_SCRIPT_SOURCE';
  end if;

  if p_source_kind = 'manuscript_revision' then
    select md.workspace_id into source_workspace_id
    from transcript_core.manuscript_revisions mr
    join transcript_core.manuscript_documents md on md.id = mr.manuscript_document_id
    where mr.id = p_source_revision_id;
  else
    select sd.workspace_id into source_workspace_id
    from transcript_core.script_revisions sr
    join transcript_core.script_documents sd on sd.id = sr.script_document_id
    where sr.id = p_source_revision_id;
  end if;

  if source_workspace_id is null then
    raise exception 'PRODUCTION_SOURCE_NOT_FOUND';
  end if;
  if source_workspace_id <> p_workspace_id then
    raise exception 'PRODUCTION_SOURCE_WORKSPACE_MISMATCH';
  end if;

  insert into transcript_core.productions(workspace_id, title, production_kind)
  values (p_workspace_id, trim(p_title), p_production_kind)
  returning id into production_id;

  if p_source_kind = 'manuscript_revision' then
    insert into transcript_core.production_sources(production_id, manuscript_revision_id)
    values (production_id, p_source_revision_id);
  else
    insert into transcript_core.production_sources(production_id, script_revision_id)
    values (production_id, p_source_revision_id);
  end if;

  return production_id;
end;
$$;

create or replace function public.transcript_core_list_productions(p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare result jsonb;
begin
  if not public.transcript_core_is_workspace_member(p_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'title', p.title,
    'kind', p.production_kind,
    'status', p.status,
    'createdAt', p.created_at,
    'source', case
      when ps.manuscript_revision_id is not null then jsonb_build_object(
        'kind', 'manuscript_revision',
        'revisionId', ps.manuscript_revision_id,
        'title', md.title,
        'revisionOrdinal', mr.ordinal
      )
      else jsonb_build_object(
        'kind', 'script_revision',
        'revisionId', ps.script_revision_id,
        'title', sd.title,
        'revisionOrdinal', sr.ordinal
      )
    end,
    'selectedTakeCount', (select count(*) from transcript_core.take_selections ts where ts.production_id = p.id),
    'openIssueCount', (
      select count(*)
      from transcript_core.proofing_issues pi
      join transcript_core.proofing_passes pp on pp.id = pi.proofing_pass_id
      where pp.production_id = p.id and pi.status in ('open','pickup_required')
    ),
    'pendingPickupCount', (
      select count(*) from transcript_core.pickup_requests pr
      where pr.production_id = p.id and pr.status in ('requested','recorded')
    )
  ) order by p.created_at desc), '[]'::jsonb)
  into result
  from transcript_core.productions p
  join transcript_core.production_sources ps on ps.production_id = p.id
  left join transcript_core.manuscript_revisions mr on mr.id = ps.manuscript_revision_id
  left join transcript_core.manuscript_documents md on md.id = mr.manuscript_document_id
  left join transcript_core.script_revisions sr on sr.id = ps.script_revision_id
  left join transcript_core.script_documents sd on sd.id = sr.script_document_id
  where p.workspace_id = p_workspace_id;

  return result;
end;
$$;

create or replace function public.transcript_core_get_production(p_production_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  target_workspace_id uuid;
  result jsonb;
begin
  select workspace_id into target_workspace_id
  from transcript_core.productions
  where id = p_production_id;

  if target_workspace_id is null then
    raise exception 'PRODUCTION_NOT_FOUND';
  end if;
  if not public.transcript_core_is_workspace_member(target_workspace_id) then
    raise exception 'WORKSPACE_READ_FORBIDDEN';
  end if;

  select jsonb_build_object(
    'id', p.id,
    'workspaceId', p.workspace_id,
    'title', p.title,
    'kind', p.production_kind,
    'status', p.status,
    'createdAt', p.created_at,
    'source', case
      when ps.manuscript_revision_id is not null then jsonb_build_object(
        'kind', 'manuscript_revision',
        'revisionId', ps.manuscript_revision_id,
        'title', md.title,
        'revisionOrdinal', mr.ordinal
      )
      else jsonb_build_object(
        'kind', 'script_revision',
        'revisionId', ps.script_revision_id,
        'title', sd.title,
        'revisionOrdinal', sr.ordinal
      )
    end,
    'recordingSessionCount', (select count(*) from transcript_core.recording_sessions rs where rs.production_id = p.id),
    'takeCount', (select count(*) from transcript_core.performance_takes pt where pt.production_id = p.id),
    'selectedTakeCount', (select count(*) from transcript_core.take_selections ts where ts.production_id = p.id),
    'openIssueCount', (
      select count(*) from transcript_core.proofing_issues pi
      join transcript_core.proofing_passes pp on pp.id = pi.proofing_pass_id
      where pp.production_id = p.id and pi.status in ('open','pickup_required')
    ),
    'pendingPickupCount', (
      select count(*) from transcript_core.pickup_requests pr
      where pr.production_id = p.id and pr.status in ('requested','recorded')
    ),
    'latestMaster', (
      select jsonb_build_object(
        'id', pm.id,
        'ordinal', pm.ordinal,
        'audioAssetId', pm.audio_asset_id,
        'createdAt', pm.created_at
      )
      from transcript_core.production_masters pm
      where pm.production_id = p.id
      order by pm.ordinal desc
      limit 1
    )
  ) into result
  from transcript_core.productions p
  join transcript_core.production_sources ps on ps.production_id = p.id
  left join transcript_core.manuscript_revisions mr on mr.id = ps.manuscript_revision_id
  left join transcript_core.manuscript_documents md on md.id = mr.manuscript_document_id
  left join transcript_core.script_revisions sr on sr.id = ps.script_revision_id
  left join transcript_core.script_documents sd on sd.id = sr.script_document_id
  where p.id = p_production_id;

  return result;
end;
$$;

revoke all on function public.transcript_core_create_manuscript_document(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_create_manuscript_revision(uuid,text,text,jsonb,uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_manuscript_documents(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_get_manuscript_revision(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_create_production(uuid,text,text,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_productions(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_get_production(uuid) from public, anon, authenticated, service_role;

grant execute on function public.transcript_core_create_manuscript_document(uuid,text) to authenticated;
grant execute on function public.transcript_core_create_manuscript_revision(uuid,text,text,jsonb,uuid) to authenticated;
grant execute on function public.transcript_core_list_manuscript_documents(uuid) to authenticated;
grant execute on function public.transcript_core_get_manuscript_revision(uuid) to authenticated;
grant execute on function public.transcript_core_create_production(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.transcript_core_list_productions(uuid) to authenticated;
grant execute on function public.transcript_core_get_production(uuid) to authenticated;