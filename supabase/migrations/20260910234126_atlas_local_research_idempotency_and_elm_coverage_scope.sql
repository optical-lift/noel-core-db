create or replace function local_intel.record_research_attempt_v1(p_payload jsonb)
returns uuid
language plpgsql security definer
set search_path to 'pg_catalog','local_intel'
as $$
declare
  v_key text := nullif(btrim(p_payload->>'attempt_key'),'');
  v_entity uuid; v_context uuid; v_payload_context uuid;
  v_question uuid; v_use_case uuid;
  v_outcome text := nullif(btrim(p_payload->>'outcome'),'');
  v_effect text := nullif(btrim(p_payload->>'evidence_effect'),'');
  v_summary text := nullif(btrim(p_payload->>'finding_summary'),'');
  v_scope text := nullif(btrim(p_payload->>'source_scope'),'');
  v_attempted timestamptz := coalesce(nullif(p_payload->>'attempted_at','')::timestamptz,now());
  v_revisit timestamptz; v_kind text; v_question_text text;
  v_existing local_intel.research_attempts%rowtype; v_id uuid;
begin
  if v_key is null then raise exception 'attempt_key is required'; end if;
  begin v_entity := (p_payload->>'entity_id')::uuid; exception when others then raise exception 'entity_id must be UUID'; end;
  select e.local_context_id into v_context from local_intel.entities e where e.id=v_entity;
  if v_context is null then raise exception 'unknown entity %',v_entity; end if;
  if nullif(p_payload->>'local_context_id','') is not null then
    begin v_payload_context := (p_payload->>'local_context_id')::uuid; exception when others then raise exception 'local_context_id must be UUID'; end;
    if v_payload_context<>v_context then raise exception 'local_context_id does not match entity Local context'; end if;
  end if;

  if nullif(p_payload->>'research_question_id','') is not null then
    begin v_question := (p_payload->>'research_question_id')::uuid; exception when others then raise exception 'research_question_id must be UUID'; end;
  elsif nullif(p_payload->>'research_question_key','') is not null then
    select id into v_question from local_intel.research_questions where stable_key=(p_payload->>'research_question_key') and status='active' order by version desc limit 1;
  end if;
  if v_question is null then raise exception 'active research question is required'; end if;
  if nullif(p_payload->>'use_case_id','') is not null then
    begin v_use_case := (p_payload->>'use_case_id')::uuid; exception when others then raise exception 'use_case_id must be UUID'; end;
  end if;
  if v_outcome not in ('evidence_found','no_qualifying_public_evidence','ambiguous','source_unavailable','blocked','not_applicable') then raise exception 'invalid outcome'; end if;
  if v_effect not in ('advance','defer','deprioritize','no_change') then raise exception 'invalid evidence_effect'; end if;
  if v_summary is null or v_scope is null then raise exception 'finding_summary and source_scope are required'; end if;
  select research_kind,question_text into v_kind,v_question_text from local_intel.research_questions where id=v_question and status='active';
  if not found then raise exception 'research question is not active'; end if;
  if v_use_case is not null and not exists(select 1 from local_intel.offering_use_cases where id=v_use_case) then raise exception 'unknown use_case %',v_use_case; end if;
  if nullif(p_payload->>'revisit_after','') is not null then v_revisit := (p_payload->>'revisit_after')::timestamptz; end if;

  -- Match modern context-stamped attempts, plus the immutable legacy row for the same entity.
  select * into v_existing
  from local_intel.research_attempts
  where attempt_key=v_key
    and (local_context_id=v_context or (local_context_id is null and entity_id=v_entity))
  order by case when local_context_id is not null then 0 else 1 end,created_at desc
  limit 1;
  if found then
    if v_existing.entity_id is distinct from v_entity or v_existing.research_question_id is distinct from v_question or v_existing.use_case_id is distinct from v_use_case or v_existing.outcome is distinct from v_outcome or v_existing.evidence_effect is distinct from v_effect or v_existing.finding_summary is distinct from v_summary then
      raise exception 'attempt_key % already belongs to different immutable research attempt in this Local',v_key;
    end if;
    return v_existing.id;
  end if;

  insert into local_intel.research_attempts(local_context_id,attempt_key,entity_id,use_case_id,research_kind,research_question,research_question_id,attempted_at,outcome,evidence_effect,finding_summary,source_scope,sources_checked,queries_checked,revisit_after,metadata)
  values(v_context,v_key,v_entity,v_use_case,v_kind,v_question_text,v_question,v_attempted,v_outcome,v_effect,v_summary,v_scope,coalesce(p_payload->'sources_checked','[]'::jsonb),coalesce(p_payload->'queries_checked','[]'::jsonb),v_revisit,coalesce(p_payload->'metadata','{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;

-- This function is intentionally Elm-specific; its coverage must therefore resolve through Elm Local-owned state, not a global geography flag.
create or replace function local_intel.occurrence_in_elm_local_coverage_v1(p_city text,p_state text)
returns boolean
language sql stable security definer
set search_path to 'pg_catalog','local_intel'
as $$
  select exists(
    select 1
    from local_intel.geographic_areas ga
    where ga.area_type='locality'
      and pg_catalog.lower(pg_catalog.btrim(coalesce(ga.name,'')))=pg_catalog.lower(pg_catalog.btrim(coalesce(p_city,'')))
      and pg_catalog.upper(pg_catalog.btrim(coalesce(ga.state,'')))=pg_catalog.upper(pg_catalog.btrim(coalesce(p_state,'')))
      and ga.verification_state='source_verified'
      and (
        exists(
          select 1 from local_intel.market_origins mo
          join local_intel.local_contexts lc on lc.id=mo.local_context_id
          where lc.stable_key='elm_local' and mo.status='active' and mo.reference_area_id=ga.id
        )
        or exists(
          select 1 from local_intel.regional_ingestion_targets rit
          join local_intel.local_contexts lc on lc.id=rit.local_context_id
          where lc.stable_key='elm_local' and rit.geographic_area_id=ga.id
            and rit.target_scope='full_locality_reality_census' and rit.status in ('active','in_process')
        )
      )
  );
$$;
