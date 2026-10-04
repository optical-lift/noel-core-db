-- Semantic-aware resolution commit v2.
-- New flows rely on the v2 temporal/cardinality projection trigger and do not
-- write the legacy one-token→one-entity private match table.

create or replace function atlas.commit_ledger_source_party_resolution_case_service_v2(
  p_ledger_id uuid,
  p_resolution_case_id uuid,
  p_canonical_entity_id uuid,
  p_decision_method text default 'human_confirmed',
  p_established_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_candidate atlas.ledger_source_party_resolution_candidates%rowtype;
  v_method text:=lower(btrim(coalesce(p_decision_method,'')));
  v_resolution jsonb;
  v_resolution_confidence numeric(5,4);
  v_next_rank integer;
begin
  select * into v_case
  from atlas.ledger_source_party_resolution_cases c
  where c.id=p_resolution_case_id
    and c.ledger_id=p_ledger_id;

  if v_case.id is null then
    raise exception 'Resolution case is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if v_method='automatic' then
    if v_case.case_state<>'auto_resolvable' then
      raise exception 'Automatic commit requires an auto-resolvable case.'
        using errcode='22023';
    end if;

    select * into v_candidate
    from atlas.ledger_source_party_resolution_candidates c
    where c.resolution_case_id=v_case.id
      and c.canonical_entity_id=p_canonical_entity_id
      and c.candidate_rank=1;

    if v_candidate.id is null then
      raise exception 'Automatic commit requires the top candidate.'
        using errcode='22023';
    end if;

    v_resolution_confidence:=v_candidate.score;

  elsif v_method='human_confirmed' then
    if v_case.case_state not in ('auto_resolvable','needs_review','new_candidate') then
      raise exception 'Resolution case is not open for human confirmation.'
        using errcode='22023';
    end if;

    if not exists(
      select 1 from local_intel.entities e where e.id=p_canonical_entity_id
    ) then
      raise exception 'Human-confirmed canonical entity does not exist.'
        using errcode='P0002';
    end if;

    select * into v_candidate
    from atlas.ledger_source_party_resolution_candidates c
    where c.resolution_case_id=v_case.id
      and c.canonical_entity_id=p_canonical_entity_id;

    if v_candidate.id is null then
      select coalesce(max(candidate_rank),0)+1
      into v_next_rank
      from atlas.ledger_source_party_resolution_candidates
      where resolution_case_id=v_case.id;

      insert into atlas.ledger_source_party_resolution_candidates(
        ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,
        score,match_summary,candidate_state
      )
      values(
        p_ledger_id,v_case.id,p_canonical_entity_id,v_next_rank,
        0.0000,
        jsonb_build_object(
          'autoEligible',false,
          'families',jsonb_build_array(jsonb_build_object(
            'evidenceFamilyKey','human_confirmation',
            'familyWeight',0.0000,
            'signals',jsonb_build_array(jsonb_build_object(
              'signalMode','human_confirmation',
              'identifierKind','human_confirmation',
              'semanticKey','human_confirmation'
            ))
          ))
        ),
        'proposed'
      )
      returning * into v_candidate;
    end if;

    v_resolution_confidence:=1.0000;
  else
    raise exception 'Decision method must be automatic or human_confirmed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Commit metadata must be a JSON object.'
      using errcode='22023';
  end if;

  v_resolution:=atlas.resolve_ledger_source_party_record_service_v1(
    p_ledger_id,
    v_case.source_party_record_id,
    p_canonical_entity_id,
    v_method,
    v_resolution_confidence,
    v_case.resolver_version,
    v_case.decision_basis || jsonb_build_object(
      'resolutionCaseId',v_case.id,
      'candidateRank',v_candidate.candidate_rank,
      'machineCandidateScore',v_candidate.score,
      'matchSummary',v_candidate.match_summary,
      'semanticResolutionVersion','v2'
    ),
    p_established_by_principal_id,
    coalesce(p_metadata,'{}'::jsonb)
  );

  update atlas.ledger_source_party_resolution_candidates
  set candidate_state=case
    when canonical_entity_id=p_canonical_entity_id then 'selected'
    else 'rejected'
  end
  where resolution_case_id=v_case.id;

  update atlas.ledger_source_party_resolution_cases
  set case_state='resolved',
      selected_entity_id=p_canonical_entity_id,
      decided_at=now(),
      decided_by_principal_id=p_established_by_principal_id,
      metadata=metadata || coalesce(p_metadata,'{}'::jsonb),
      updated_at=now()
  where id=v_case.id;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_commit_v2',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',v_case.source_party_record_id,
    'canonicalEntityId',p_canonical_entity_id,
    'decisionMethod',v_method,
    'resolution',v_resolution
  );
end
$function$;

revoke all on function atlas.commit_ledger_source_party_resolution_case_service_v2(
  uuid,uuid,uuid,text,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.commit_ledger_source_party_resolution_case_service_v2(
  uuid,uuid,uuid,text,uuid,jsonb
) to service_role;

comment on function atlas.commit_ledger_source_party_resolution_case_service_v2(
  uuid,uuid,uuid,text,uuid,jsonb
) is
  'Semantic-aware resolution commit. Private identifier bindings are projected by v2 cardinality/temporality rules; this function does not teach the legacy one-token→one-entity table.';
