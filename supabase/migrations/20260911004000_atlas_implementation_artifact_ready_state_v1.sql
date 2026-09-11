-- Finalize implementation artifact processing lifecycle after successful interpretation.
begin;

alter table atlas.implementation_artifacts
  drop constraint if exists implementation_artifacts_processing_state_check;

alter table atlas.implementation_artifacts
  add constraint implementation_artifacts_processing_state_check
  check (processing_state in ('upload_pending','received','transcribing','transcribed','ready','processing_failed','removed'));

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
  where i.id=p_interpretation_id
  for update;
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
    if v_area not in ('people','work','time','money','things_places','systems_evidence','access_authority','handoffs_completion','structure_mismatch','other_unresolved') then raise exception 'Invalid candidate work area.' using errcode='22023'; end if;
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

  update atlas.implementation_artifacts
  set processing_state='ready',updated_at=now()
  where id=v_interpretation.implementation_artifact_id;

  return jsonb_build_object('ok',true,'interpretationId',p_interpretation_id,'candidateCount',v_count,'status','ready');
end;
$function$;

revoke all on function atlas.complete_implementation_artifact_interpretation_service_v1(uuid,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.complete_implementation_artifact_interpretation_service_v1(uuid,text,jsonb,jsonb) to service_role;

commit;
