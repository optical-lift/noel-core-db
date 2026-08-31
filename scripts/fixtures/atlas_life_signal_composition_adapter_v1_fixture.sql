-- Atlas Life Signal -> Shared Composition adapter v1 fixture
-- Pure contract verification. No application records are required or mutated.

begin;

do $$
declare
  v_signal jsonb;
  v_validation jsonb;
  v_composition jsonb;
begin
  -- A remembered dream is evidence, not automatically an operation.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-dream'),
    'subject',jsonb_build_object('domain','dream','kind','dream_record','id','fixture-dream-01'),
    'signalKind','observation',
    'state',jsonb_build_object('recorded',true),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('meaning_unresolved','cause_unresolved'),
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','dream','kind','dream_record','id','fixture-dream-01'),
    'epistemic',jsonb_build_object('factClass','remembered_experience','interpretationAuthority','none')
  );

  v_validation := atlas.validate_life_signal_v1(v_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'dream fixture should validate: %', v_validation;
  end if;

  v_composition := atlas.life_signal_to_composition_signals_v1(v_signal);
  if v_composition->>'signal_contract_version' <> 'composition_signals_v1' then
    raise exception 'dream fixture must enter composition_signals_v1';
  end if;
  if jsonb_array_length(v_composition->'active_claims') <> 0 then
    raise exception 'dream observation without requirements must not create an active claim';
  end if;
  if coalesce((v_composition->>'composition_delegated')::boolean,true) then
    raise exception 'dream observation must not delegate composition authority';
  end if;
  if jsonb_array_length(v_composition->'ambiguities') <> 2 then
    raise exception 'dream ambiguities must survive normalization';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_composition jsonb;
  v_claim jsonb;
begin
  -- An accepted practitioner recommendation may establish a requirement, but the
  -- adapter must not invent the human/task carrier or exact sequence.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-care'),
    'subject',jsonb_build_object('domain','care','kind','care_requirement','id','fixture-hip-mobility'),
    'signalKind','rhythm',
    'state',jsonb_build_object('authorizationState','accepted'),
    'timing',jsonb_build_object('mustBeSatisfiedBefore','2026-09-12','targetCount',4),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','qualifying_satisfaction',
      'requirementKey','fixture-hip-mobility-four-before-2026-09-12',
      'operationKey','hip_mobility_a',
      'claimStrength','required',
      'expectedAfterState',jsonb_build_object('qualifying_satisfaction_recorded',true)
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations',jsonb_build_array(jsonb_build_object(
      'relationKind','result_of',
      'relationBasis','explicit person acceptance',
      'relationStatus','established',
      'causal',false
    )),
    'source',jsonb_build_object('domain','care_relationship','kind','person_acceptance','id','fixture-acceptance-01'),
    'epistemic',jsonb_build_object('factClass','authorized_requirement','interpretationAuthority','explicit_relationship')
  );

  v_composition := atlas.life_signal_to_composition_signals_v1(v_signal);
  if jsonb_array_length(v_composition->'active_claims') <> 1 then
    raise exception 'accepted care rhythm must produce exactly one active claim';
  end if;

  v_claim := v_composition->'active_claims'->0;
  if v_claim->>'operation_hint' <> 'hip_mobility_a' then
    raise exception 'domain-supplied operation must survive normalization';
  end if;
  if v_claim ? 'carrier_ref' then
    raise exception 'adapter must not invent a carrier for an established requirement';
  end if;
  if coalesce((v_composition->'sequence_authority'->>'life_signal_may_create_sequence_authority')::boolean,true) then
    raise exception 'life signal must not create sequence authority';
  end if;
  if coalesce((v_composition->>'composition_delegated')::boolean,true) then
    raise exception 'accepted requirement must not itself delegate open composition';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_composition jsonb;
  v_claim jsonb;
begin
  -- A condition may establish truth-acquisition work while leaving the carrier
  -- unresolved. Requirement and task/person carrier are separate truths.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-condition'),
    'subject',jsonb_build_object('domain','body','kind','body_region','id','left_hip'),
    'signalKind','consequence',
    'state',jsonb_build_object('reportedState','tight_after_run'),
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','truth_acquisition',
      'operationKey','reassess_condition',
      'exitCondition','new domain evidence establishes present functional state'
    )),
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('cause_not_established'),
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','body','kind','person_condition_observation','id','fixture-body-observation-01'),
    'epistemic',jsonb_build_object('factClass','reported_observation','interpretationAuthority','none')
  );

  v_composition := atlas.life_signal_to_composition_signals_v1(v_signal);
  v_claim := v_composition->'active_claims'->0;
  if v_claim->>'claim_type' <> 'truth_acquisition' then
    raise exception 'condition consequence role must survive normalization';
  end if;
  if v_claim ? 'carrier_ref' then
    raise exception 'truth-acquisition requirement must remain carrierless when no carrier is established';
  end if;
  if jsonb_array_length(v_composition->'ambiguities') <> 1 then
    raise exception 'cause-not-established ambiguity must survive normalization';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_validation jsonb;
begin
  -- Generic relation links may not be used to smuggle a causal conclusion.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-causal'),
    'subject',jsonb_build_object('domain','journal','kind','person_reflection','id','fixture-reflection-01'),
    'signalKind','observation',
    'state',jsonb_build_object('reportedSleep','poor'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations',jsonb_build_array(jsonb_build_object(
      'relationKind','candidate_related',
      'relationBasis','same research window',
      'causal',true
    )),
    'source',jsonb_build_object('domain','journal','kind','person_reflection','id','fixture-reflection-01'),
    'epistemic',jsonb_build_object('factClass','reported_observation','interpretationAuthority','none')
  );

  v_validation := atlas.validate_life_signal_v1(v_signal);
  if v_validation->>'validation_state' <> 'rejected' then
    raise exception 'causal promotion through generic relation must be rejected';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v_validation->'violations') v
    where v->>'key'='causal_promotion_not_allowed_in_generic_relation'
  ) then
    raise exception 'causal promotion rejection reason missing';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_validation jsonb;
begin
  -- Invalid causal types must fail as contract violations, not as cast errors.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-invalid-causal'),
    'subject',jsonb_build_object('domain','sky_research','kind','external_observation','id','fixture-sky-01'),
    'signalKind','observation',
    'state','{}'::jsonb,
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations',jsonb_build_array(jsonb_build_object(
      'relationKind','candidate_related',
      'causal','maybe'
    )),
    'source',jsonb_build_object('domain','sky_research','kind','external_sky_observation','id','fixture-sky-01'),
    'epistemic',jsonb_build_object('factClass','external_observation','interpretationAuthority','none')
  );

  v_validation := atlas.validate_life_signal_v1(v_signal);
  if v_validation->>'validation_state' <> 'rejected' then
    raise exception 'non-boolean relation causal flag must be rejected';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v_validation->'violations') v
    where v->>'key'='invalid_relation_causal_flag'
  ) then
    raise exception 'invalid causal flag rejection reason missing';
  end if;
end
$$;

do $$
declare
  v_goal_without_explicit_end jsonb;
  v_goal_with_explicit_end jsonb;
  v_composition jsonb;
begin
  -- Goal signal kind is not itself enough to authorize every state field as the
  -- user's intended fruit. Only an explicitly marked user end crosses that seam.
  v_goal_without_explicit_end := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-goal'),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
    'signalKind','goal',
    'state',jsonb_build_object('raceDistanceKm',5),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','fixture-5k'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );

  v_composition := atlas.life_signal_to_composition_signals_v1(v_goal_without_explicit_end);
  if v_composition->'explicit_user_end' <> 'null'::jsonb then
    raise exception 'GoalSignal alone must not promote arbitrary state into explicit user end';
  end if;

  v_goal_with_explicit_end := jsonb_set(
    v_goal_without_explicit_end,
    '{state,explicitUserEnd}',
    to_jsonb('Complete a 5K'::text),
    true
  );
  v_composition := atlas.life_signal_to_composition_signals_v1(v_goal_with_explicit_end);
  if v_composition->'explicit_user_end' <> to_jsonb('Complete a 5K'::text) then
    raise exception 'explicitUserEnd must survive when explicitly supplied';
  end if;
end
$$;

rollback;
