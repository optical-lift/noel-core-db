-- Atlas person Rhythm existing-Evidence adapter v1
--
-- Additive interoperability seam for the person-owned feedback loop. A run or
-- other occurrence may already exist as canonical person Claim/Evidence because
-- it arrived through Ask Atlas, an import, or another input surface. This adapter
-- lets that existing truth satisfy one current Rhythm opportunity without
-- recapturing it. The linked Goal requirement remains the authority for what
-- Evidence is admissible.

begin;

create or replace function atlas.apply_person_rhythm_occurrence_evidence_api_v1(
  p_opportunity_id uuid,
  p_evidence_id uuid,
  p_source_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_goal_packet jsonb;
  v_requirement jsonb;
  v_selector jsonb;
  v_selector_subject jsonb;
  v_satisfaction jsonb;
  v_satisfaction_event_id uuid;
  v_goal_evaluation jsonb;
  v_updated integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_opportunity_id is null or p_evidence_id is null then
    raise exception 'opportunityId and evidenceId are required.' using errcode='22023';
  end if;
  v_source_key := btrim(coalesce(p_source_key,''));
  if v_source_key='' then
    raise exception 'sourceKey is required.' using errcode='22023';
  end if;

  select o.* into v_opportunity
  from atlas.person_rhythm_opportunities o
  join atlas.person_goal_rhythm_bindings b on b.id=o.binding_id
  join atlas.claim_records pc on pc.id=b.plan_claim_id
  where o.id=p_opportunity_id
    and o.owner_user_id=v_user_id
    and b.owner_user_id=v_user_id
    and b.status='active'
    and pc.scope_kind='person'
    and pc.scope_id=v_user_id
    and pc.claim_type='goal_rhythm_plan'
    and pc.lifecycle_state='accepted'
    and pc.authority_kind in ('person_acceptance','person_correction')
    and (pc.valid_from is null or pc.valid_from<=now())
    and (pc.valid_until is null or pc.valid_until>now())
    and o.projection_state<>'withdrawn'
  for update of o;
  if v_opportunity.id is null then
    raise exception 'Current person Rhythm opportunity not found for this user.' using errcode='42501';
  end if;

  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.id=v_opportunity.binding_id
    and b.owner_user_id=v_user_id
    and b.status='active';
  if v_binding.id is null then
    raise exception 'Active Goal Rhythm binding not found for this opportunity.' using errcode='23514';
  end if;

  -- Revalidate the current accepted planning authority rather than trusting the
  -- projection row by itself.
  perform atlas.person_goal_rhythm_plan_envelope_v1(v_user_id,v_binding.plan_claim_id);

  select * into v_evidence
  from atlas.evidence_records e
  where e.id=p_evidence_id
    and e.scope_kind='person'
    and e.scope_id=v_user_id;
  if v_evidence.id is null then
    raise exception 'Occurrence Evidence must belong to this person.' using errcode='42501';
  end if;
  if v_evidence.observed_at is null then
    raise exception 'Occurrence Evidence requires an observedAt timestamp.' using errcode='23514';
  end if;
  if v_evidence.observed_at>now()+interval '5 minutes' then
    raise exception 'Occurrence Evidence cannot prove future execution.' using errcode='22023';
  end if;
  if v_evidence.observed_at<v_opportunity.starts_at
     or v_evidence.observed_at>v_opportunity.ends_at then
    raise exception 'Occurrence Evidence observedAt must fall inside the selected accepted Rhythm opportunity window.' using errcode='22023';
  end if;

  select * into v_claim
  from atlas.claim_records c
  where c.primary_evidence_id=v_evidence.id
    and c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.subject_domain=v_evidence.subject_domain
    and c.subject_kind=v_evidence.subject_kind
    and c.subject_id=v_evidence.subject_id
    and c.lifecycle_state not in ('superseded','rejected','expired')
    and (c.valid_from is null or c.valid_from<=v_evidence.observed_at)
    and (c.valid_until is null or c.valid_until>=v_evidence.observed_at)
  order by c.recorded_at desc,c.id desc
  limit 1;
  if v_claim.id is null then
    raise exception 'Occurrence Evidence must back a current same-person Claim.' using errcode='23514';
  end if;

  select d.engine_packet into v_goal_packet
  from atlas.person_life_definitions d
  where d.id=v_binding.goal_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='goal'
    and d.status='active';
  if v_goal_packet is null then
    raise exception 'Active linked Goal definition not found.' using errcode='23514';
  end if;

  select r.value into v_requirement
  from jsonb_array_elements(coalesce(v_goal_packet->'requirements','[]'::jsonb)) r(value)
  where coalesce(r.value->>'requirementKey',r.value->>'requirement_key')=v_binding.goal_requirement_key
  limit 1;
  if v_requirement is null
     or coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind')<>'claim_threshold' then
    raise exception 'Rhythm occurrence v1 requires the linked Goal requirement to be an evidence-backed claim_threshold.' using errcode='23514';
  end if;

  v_selector := v_requirement->'evidenceSelector';
  v_selector_subject := v_selector->'subject';
  if jsonb_typeof(v_selector)<>'object'
     or jsonb_typeof(v_selector_subject)<>'object'
     or jsonb_typeof(v_selector->'lifecycleStates')<>'array'
     or jsonb_typeof(v_selector->'authorityKinds')<>'array' then
    raise exception 'Linked Goal requirement has an invalid Evidence selector.' using errcode='23514';
  end if;

  if v_selector_subject->>'domain' is distinct from v_claim.subject_domain
     or v_selector_subject->>'kind' is distinct from v_claim.subject_kind
     or v_selector_subject->>'id' is distinct from v_claim.subject_id
     or v_selector->>'claimType' is distinct from v_claim.claim_type
     or not exists (
       select 1 from jsonb_array_elements_text(v_selector->'lifecycleStates') x(value)
       where x.value=v_claim.lifecycle_state
     )
     or not exists (
       select 1 from jsonb_array_elements_text(v_selector->'authorityKinds') x(value)
       where x.value=v_claim.authority_kind
     ) then
    raise exception 'Existing Claim/Evidence is not authorized by the linked Goal requirement Evidence selector.' using errcode='23514';
  end if;

  if v_opportunity.projection_state='satisfied' then
    if v_opportunity.satisfied_by_evidence_id is distinct from v_evidence.id
       or v_opportunity.satisfied_by_claim_id is distinct from v_claim.id then
      raise exception 'This Rhythm opportunity is already satisfied by different canonical Evidence.' using errcode='23505';
    end if;
    v_goal_evaluation := atlas.evaluate_person_goal_from_claim_evidence_api_v1(
      v_binding.goal_definition_id,
      'person_rhythm_goal_evaluation:' || v_evidence.id::text
    );
    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'opportunityId',v_opportunity.id,
      'bindingId',v_binding.id,
      'rhythmDefinitionId',v_binding.rhythm_definition_id,
      'goalDefinitionId',v_binding.goal_definition_id,
      'goalRequirementKey',v_binding.goal_requirement_key,
      'evidenceId',v_evidence.id,
      'claimId',v_claim.id,
      'rhythmEventId',v_opportunity.satisfaction_event_id,
      'goalEvaluation',v_goal_evaluation,
      'truthBoundary',jsonb_build_object(
        'reusesExistingCanonicalEvidence',true,
        'requirementSelectorAuthorizesEvidence',true,
        'sameEvidenceFeedsRhythmAndGoal',true,
        'goalDefinitionIsNotRewritten',true,
        'doesNotCreateTask',true,
        'doesNotCreateClockPlacement',true
      )
    );
  end if;

  if v_opportunity.projection_state<>'projected' then
    raise exception 'Only a current projected Rhythm opportunity can be satisfied by Evidence.' using errcode='22023';
  end if;

  v_satisfaction := atlas.record_person_life_state_api_v1(
    v_binding.rhythm_definition_id,
    jsonb_build_object(
      'sourceKey','person_rhythm_existing_evidence:' || v_source_key,
      'eventKind','rhythm_satisfaction',
      'satisfiedAt',v_evidence.observed_at,
      'asOf',v_evidence.observed_at,
      'evidence',jsonb_build_object(
        'canonicalEvidenceId',v_evidence.id,
        'canonicalClaimId',v_claim.id,
        'opportunityId',v_opportunity.id,
        'bindingId',v_binding.id,
        'goalDefinitionId',v_binding.goal_definition_id,
        'goalRequirementKey',v_binding.goal_requirement_key,
        'planClaimId',v_binding.plan_claim_id,
        'reusedExistingEvidence',true
      )
    )
  );
  v_satisfaction_event_id := (v_satisfaction->>'eventId')::uuid;

  update atlas.person_rhythm_opportunities o
  set projection_state='satisfied',
      satisfied_by_evidence_id=v_evidence.id,
      satisfied_by_claim_id=v_claim.id,
      satisfaction_event_id=v_satisfaction_event_id,
      satisfied_at=v_evidence.observed_at,
      metadata=o.metadata || jsonb_build_object(
        'satisfactionAdapter','atlas.apply_person_rhythm_occurrence_evidence_api_v1',
        'reusedExistingEvidence',true
      ),
      updated_at=now()
  where o.id=v_opportunity.id
    and o.owner_user_id=v_user_id
    and o.projection_state='projected';
  get diagnostics v_updated=row_count;
  if v_updated<>1 then
    raise exception 'Rhythm opportunity changed while applying its existing Evidence.' using errcode='40001';
  end if;

  v_goal_evaluation := atlas.evaluate_person_goal_from_claim_evidence_api_v1(
    v_binding.goal_definition_id,
    'person_rhythm_goal_evaluation:' || v_evidence.id::text
  );

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'opportunityId',v_opportunity.id,
    'bindingId',v_binding.id,
    'rhythmDefinitionId',v_binding.rhythm_definition_id,
    'goalDefinitionId',v_binding.goal_definition_id,
    'goalRequirementKey',v_binding.goal_requirement_key,
    'evidenceId',v_evidence.id,
    'claimId',v_claim.id,
    'rhythmEventId',v_satisfaction_event_id,
    'rhythmEvaluation',v_satisfaction->'evaluation',
    'goalEvaluation',v_goal_evaluation,
    'truthBoundary',jsonb_build_object(
      'reusesExistingCanonicalEvidence',true,
      'requirementSelectorAuthorizesEvidence',true,
      'sameEvidenceFeedsRhythmAndGoal',true,
      'opportunitySatisfactionIsEvidenceBacked',true,
      'goalDefinitionIsNotRewritten',true,
      'opportunityIsNotTask',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.apply_person_rhythm_occurrence_evidence_api_v1(uuid,uuid,text) is
  'Apply already-existing canonical person Claim/Evidence to one current Rhythm opportunity only when the linked accepted Goal requirement Evidence selector explicitly authorizes that Claim.';

revoke all on function atlas.apply_person_rhythm_occurrence_evidence_api_v1(uuid,uuid,text) from public, anon;
grant execute on function atlas.apply_person_rhythm_occurrence_evidence_api_v1(uuid,uuid,text) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values (
  'atlas.apply_person_rhythm_occurrence_evidence_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',
  true,true,true,
  0,0,
  jsonb_build_object(
    'purpose','Reuse already-existing canonical person Claim/Evidence as satisfaction of one current Goal-linked Rhythm opportunity and immediately reevaluate the linked Goal.',
    'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); Evidence must belong to the person, back a current Claim, occur inside the selected accepted window, and exactly match the linked accepted Goal requirement Evidence selector. No recapture, Task, Consequence, or Clock placement is created.',
    'directSignedInEndpoint',true
  ),
  false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
