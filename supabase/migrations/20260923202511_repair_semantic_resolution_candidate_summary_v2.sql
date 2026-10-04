-- Repair v2 resolver candidate summaries to preserve the existing
-- ledger_source_party_resolution_candidates.match_summary JSON-array contract.

create or replace function atlas.evaluate_ledger_source_party_resolution_service_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_as_of_date date default current_date,
  p_policy_key text default 'default_v1',
  p_resolver_version text default 'identity_resolution_engine_v2'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_policy atlas.identity_resolution_policies%rowtype;
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_existing atlas.ledger_source_party_resolutions%rowtype;
  v_top numeric(5,4);
  v_second numeric(5,4);
  v_top_auto_eligible boolean;
  v_state text;
  v_candidates jsonb;
begin
  if p_as_of_date is null then
    raise exception 'Resolution as-of date is required.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  select * into v_existing
  from atlas.ledger_source_party_resolutions x
  where x.ledger_id=p_ledger_id
    and x.source_party_record_id=p_source_party_record_id
    and x.is_current
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','ledger_source_party_resolution_evaluation_v2',
      'decisionState','already_resolved',
      'sourcePartyRecordId',p_source_party_record_id,
      'canonicalEntityId',v_existing.canonical_entity_id,
      'resolutionId',v_existing.id
    );
  end if;

  select * into v_policy
  from atlas.identity_resolution_policies p
  where p.policy_key=p_policy_key
    and p.policy_state='active';

  if v_policy.policy_key is null then
    raise exception 'Identity resolution policy is missing or inactive.'
      using errcode='P0002';
  end if;

  update atlas.ledger_source_party_resolution_cases c
  set case_state='superseded',
      updated_at=now()
  where c.ledger_id=p_ledger_id
    and c.source_party_record_id=p_source_party_record_id
    and c.case_state in ('auto_resolvable','needs_review','new_candidate');

  create temporary table if not exists pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id uuid,
    identity_signal_id uuid,
    identifier_kind text,
    signal_mode text,
    semantic_key text,
    evidence_family_key text,
    weight numeric(5,4),
    allows_auto_resolution boolean
  ) on commit drop;
  truncate pg_temp.atlas_resolution_matches_v2;

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    e.entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.shared_evidence_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.shared_evidence_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_evidence_claims e
    on e.claim_kind=s.identifier_kind
   and e.normalized_value=s.normalized_value
   and e.lifecycle_state='current'
   and e.disclosure_posture<>'suppressed'
   and 'identity_resolution'=any(e.permitted_uses)
   and (e.valid_from is null or e.valid_from<=p_as_of_date)
   and (e.valid_until is null or e.valid_until>=p_as_of_date)
  join local_intel.entities ent
    on ent.id=e.entity_id
   and ent.entity_type=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='shared_evidence_lookup'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date)
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions sup
      where sup.entity_id=e.entity_id
        and sup.suppression_state='active'
        and (sup.effective_until is null or sup.effective_until>now())
        and sup.suppression_scope='all_use'
        and (sup.evidence_claim_id is null or sup.evidence_claim_id=e.id)
    );

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    b.canonical_entity_id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.private_blind_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.private_blind_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_private_identifier_bindings b
    on b.identifier_kind=s.identifier_kind
   and b.token_version=s.token_version
   and b.blind_token=s.blind_token
   and b.binding_state='current'
   and b.valid_from<=p_as_of_date
   and (b.valid_until is null or b.valid_until>=p_as_of_date)
  join local_intel.entities ent
    on ent.id=b.canonical_entity_id
   and ent.entity_type=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='private_blind_match'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date);

  insert into atlas.ledger_source_party_resolution_cases(
    ledger_id,source_party_record_id,policy_key,resolver_version,
    case_state,decision_basis
  )
  values(
    p_ledger_id,p_source_party_record_id,v_policy.policy_key,
    coalesce(nullif(btrim(p_resolver_version),''),'identity_resolution_engine_v2'),
    'new_candidate',
    jsonb_build_object(
      'asOfDate',p_as_of_date,
      'autoResolveThreshold',v_policy.auto_resolve_threshold,
      'reviewThreshold',v_policy.review_threshold,
      'ambiguityMargin',v_policy.ambiguity_margin,
      'scoring','strongest_signal_per_evidence_family_then_probabilistic_union'
    )
  )
  returning * into v_case;

  with family_matches as (
    select
      canonical_entity_id,
      evidence_family_key,
      max(weight) as family_weight,
      bool_or(allows_auto_resolution) as family_auto_eligible,
      jsonb_agg(
        distinct jsonb_build_object(
          'identifierKind',identifier_kind,
          'signalMode',signal_mode,
          'semanticKey',semantic_key
        )
      ) as family_signals
    from pg_temp.atlas_resolution_matches_v2
    group by canonical_entity_id,evidence_family_key
  ),
  scored as (
    select
      canonical_entity_id,
      case
        when bool_or(family_weight>=0.9999) then 1.0000::numeric
        else round(
          (1-exp(sum(ln(greatest(1-family_weight,0.000001)))))::numeric,
          4
        )
      end as score,
      bool_or(family_auto_eligible) as auto_eligible,
      jsonb_agg(
        jsonb_build_object(
          'evidenceFamilyKey',evidence_family_key,
          'familyWeight',family_weight,
          'signals',family_signals
        )
        order by family_weight desc,evidence_family_key
      ) as summary
    from family_matches
    group by canonical_entity_id
  ),
  ranked as (
    select
      canonical_entity_id,
      least(score,1.0000)::numeric(5,4) as score,
      auto_eligible,
      summary,
      row_number() over(order by score desc,canonical_entity_id) as rank_no
    from scored
  )
  insert into atlas.ledger_source_party_resolution_candidates(
    ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,score,match_summary
  )
  select
    p_ledger_id,v_case.id,canonical_entity_id,rank_no,score,
    jsonb_build_array(jsonb_build_object(
      'autoEligible',auto_eligible,
      'families',summary
    ))
  from ranked;

  select
    c.score,
    coalesce((c.match_summary#>>'{0,autoEligible}')::boolean,false)
  into v_top,v_top_auto_eligible
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=1;

  select c.score into v_second
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=2;

  if v_top is null then
    v_state:='new_candidate';
  elsif v_top>=v_policy.auto_resolve_threshold
        and coalesce(v_top_auto_eligible,false)
        and (v_second is null or v_top-v_second>=v_policy.ambiguity_margin) then
    v_state:='auto_resolvable';
  elsif v_top>=v_policy.review_threshold then
    v_state:='needs_review';
  else
    v_state:='new_candidate';
  end if;

  update atlas.ledger_source_party_resolution_cases
  set case_state=v_state,
      top_score=v_top,
      second_score=v_second,
      updated_at=now()
  where id=v_case.id
  returning * into v_case;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'canonicalEntityId',c.canonical_entity_id,
      'candidateRank',c.candidate_rank,
      'score',c.score,
      'matchSummary',c.match_summary,
      'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
        'entityId',e.id,
        'name',e.name,
        'entityType',e.entity_type,
        'city',e.city,
        'state',e.state
      ))
    )
    order by c.candidate_rank
  ),'[]'::jsonb)
  into v_candidates
  from atlas.ledger_source_party_resolution_candidates c
  join local_intel.entities e on e.id=c.canonical_entity_id
  where c.resolution_case_id=v_case.id;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_evaluation_v2',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',p_source_party_record_id,
    'asOfDate',p_as_of_date,
    'decisionState',v_case.case_state,
    'topScore',v_case.top_score,
    'secondScore',v_case.second_score,
    'candidates',v_candidates
  );
end
$function$;

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
        jsonb_build_array(jsonb_build_object(
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
        )),
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
