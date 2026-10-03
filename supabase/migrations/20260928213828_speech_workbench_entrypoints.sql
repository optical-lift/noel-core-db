create or replace function public.transcript_core_create_script_document(
  p_workspace_id uuid,
  p_title text,
  p_initial_snapshot jsonb default null,
  p_snapshot_schema_version integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  document_id uuid;
  draft_id uuid;
begin
  if not public.transcript_core_can_workspace_edit(p_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;
  if nullif(trim(p_title), '') is null then raise exception 'SCRIPT_TITLE_REQUIRED'; end if;
  if p_snapshot_schema_version <> 1 then raise exception 'SCRIPT_SNAPSHOT_SCHEMA_UNSUPPORTED:%', p_snapshot_schema_version; end if;
  if p_initial_snapshot is not null and jsonb_typeof(p_initial_snapshot) <> 'object' then
    raise exception 'SCRIPT_SNAPSHOT_MUST_BE_OBJECT';
  end if;

  insert into transcript_core.script_documents(workspace_id, title)
  values (p_workspace_id, trim(p_title))
  returning id into document_id;

  if p_initial_snapshot is not null then
    insert into transcript_core.script_drafts(
      script_document_id, snapshot_schema_version, snapshot, updated_by
    ) values (
      document_id, p_snapshot_schema_version, p_initial_snapshot, auth.uid()
    ) returning id into draft_id;
  end if;

  return jsonb_build_object('scriptDocumentId', document_id, 'scriptDraftId', draft_id);
end;
$$;

create or replace function public.transcript_core_list_script_documents(p_workspace_id uuid)
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
    'id', sd.id,
    'title', sd.title,
    'createdAt', sd.created_at,
    'draft', case when d.id is null then null else jsonb_build_object(
      'id', d.id,
      'baseRevisionId', d.base_revision_id,
      'snapshotSchemaVersion', d.snapshot_schema_version,
      'updatedAt', d.updated_at
    ) end,
    'latestRevision', (
      select jsonb_build_object(
        'id', sr.id,
        'ordinal', sr.ordinal,
        'originKind', sr.origin_kind,
        'createdAt', sr.created_at
      )
      from transcript_core.script_revisions sr
      where sr.script_document_id = sd.id
      order by sr.ordinal desc
      limit 1
    )
  ) order by sd.created_at desc), '[]'::jsonb)
  into result
  from transcript_core.script_documents sd
  left join transcript_core.script_drafts d on d.script_document_id = sd.id
  where sd.workspace_id = p_workspace_id;

  return result;
end;
$$;

create or replace function public.transcript_core_list_recordings(p_workspace_id uuid)
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
    'id', r.id,
    'title', r.title,
    'sourceAssetId', r.source_asset_id,
    'createdAt', r.created_at,
    'transcriptId', t.id,
    'currentRevisionId', t.current_revision_id,
    'speakerAnalysisRunId', (
      select sar.id
      from transcript_core.speaker_analysis_runs sar
      where sar.recording_id = r.id
      order by sar.created_at desc
      limit 1
    )
  ) order by r.created_at desc), '[]'::jsonb)
  into result
  from transcript_core.recordings r
  left join transcript_core.transcripts t on t.recording_id = r.id
  where r.workspace_id = p_workspace_id;

  return result;
end;
$$;

create or replace function public.transcript_core_propose_speaker_identity(
  p_speaker_cluster_id uuid,
  p_target_kind text,
  p_target_ref text,
  p_display_name text,
  p_confidence numeric,
  p_evidence jsonb
)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  candidate_id uuid;
  evidence_item jsonb;
  evidence_sequence integer := 0;
begin
  if not exists (select 1 from transcript_core.speaker_clusters where id = p_speaker_cluster_id) then
    raise exception 'SPEAKER_CLUSTER_NOT_FOUND';
  end if;
  if p_target_kind not in ('person','label') then raise exception 'SPEAKER_TARGET_KIND_INVALID'; end if;
  if nullif(trim(p_target_ref), '') is null then raise exception 'SPEAKER_TARGET_REF_REQUIRED'; end if;
  if nullif(trim(p_display_name), '') is null then raise exception 'SPEAKER_DISPLAY_NAME_REQUIRED'; end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then raise exception 'SPEAKER_CONFIDENCE_INVALID'; end if;
  if jsonb_typeof(p_evidence) <> 'array' then raise exception 'SPEAKER_EVIDENCE_MUST_BE_ARRAY'; end if;

  insert into transcript_core.speaker_identity_candidates(
    speaker_cluster_id, target_kind, target_ref, display_name, confidence, created_by_kind
  ) values (
    p_speaker_cluster_id, p_target_kind, p_target_ref, p_display_name, p_confidence, 'machine'
  ) returning id into candidate_id;

  for evidence_item in select * from jsonb_array_elements(p_evidence)
  loop
    if evidence_item->>'kind' not in ('transcript_context','source_metadata','human_note','external_reference') then
      raise exception 'SPEAKER_EVIDENCE_KIND_INVALID:%', evidence_item->>'kind';
    end if;
    if nullif(trim(evidence_item->>'statement'), '') is null then raise exception 'SPEAKER_EVIDENCE_STATEMENT_REQUIRED'; end if;
    evidence_sequence := evidence_sequence + 1;
    insert into transcript_core.speaker_identity_evidence(
      candidate_id, sequence, evidence_kind, statement, source_reference
    ) values (
      candidate_id,
      evidence_sequence,
      evidence_item->>'kind',
      evidence_item->>'statement',
      nullif(evidence_item->>'sourceReference','')
    );
  end loop;

  return candidate_id;
end;
$$;

create or replace function public.transcript_core_confirm_speaker_candidate(p_candidate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = transcript_core, public
as $$
declare
  candidate transcript_core.speaker_identity_candidates%rowtype;
  target_workspace_id uuid;
  assignment_id uuid;
begin
  select * into candidate from transcript_core.speaker_identity_candidates where id = p_candidate_id;
  if not found then raise exception 'SPEAKER_CANDIDATE_NOT_FOUND'; end if;

  select sar.workspace_id into target_workspace_id
  from transcript_core.speaker_clusters sc
  join transcript_core.speaker_analysis_runs sar on sar.id = sc.analysis_run_id
  where sc.id = candidate.speaker_cluster_id;
  if target_workspace_id is null then raise exception 'SPEAKER_CLUSTER_NOT_FOUND'; end if;
  if not public.transcript_core_can_workspace_edit(target_workspace_id) then
    raise exception 'WORKSPACE_EDIT_FORBIDDEN';
  end if;

  update transcript_core.speaker_assignments
  set superseded_at = now()
  where speaker_cluster_id = candidate.speaker_cluster_id and superseded_at is null;

  insert into transcript_core.speaker_assignments(
    speaker_cluster_id, target_kind, target_ref, display_name, basis, assigned_by_user_id
  ) values (
    candidate.speaker_cluster_id,
    candidate.target_kind,
    candidate.target_ref,
    candidate.display_name,
    'human_confirmed',
    auth.uid()
  ) returning id into assignment_id;

  return assignment_id;
end;
$$;

revoke all on function public.transcript_core_create_script_document(uuid,text,jsonb,integer) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_script_documents(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_list_recordings(uuid) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_propose_speaker_identity(uuid,text,text,text,numeric,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.transcript_core_confirm_speaker_candidate(uuid) from public, anon, authenticated, service_role;

grant execute on function public.transcript_core_create_script_document(uuid,text,jsonb,integer) to authenticated;
grant execute on function public.transcript_core_list_script_documents(uuid) to authenticated;
grant execute on function public.transcript_core_list_recordings(uuid) to authenticated;
grant execute on function public.transcript_core_confirm_speaker_candidate(uuid) to authenticated;
grant execute on function public.transcript_core_propose_speaker_identity(uuid,text,text,text,numeric,jsonb) to service_role;
