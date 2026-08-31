-- Atlas Life Engine Packets v1 fixture
-- Pure JSON contract verification. No application records are required or mutated.

begin;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
begin
  -- Accepted practitioner homework is a bounded rhythm requirement, not four
  -- pre-created tasks and not an automatic Clock placement.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-rhythm'),
    'subject',jsonb_build_object('domain','care','kind','care_requirement','id','fixture-mobility-rhythm'),
    'signalKind','rhythm',
    'state',jsonb_build_object('authorizationState','accepted'),
    'timing',jsonb_build_object('mustBeSatisfiedBefore','2026-09-12','targetCount',4),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','qualifying_satisfaction',
      'operationKey','hip_mobility_a',
      'count',4
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','care_relationship','kind','person_acceptance','id','fixture-acceptance-rhythm'),
    'epistemic',jsonb_build_object('factClass','authorized_requirement','interpretationAuthority','explicit_relationship')
  );

  v_packet := atlas.life_signal_to_rhythm_packet_v1(v_signal);
  if v_packet->>'definitionState' <> 'bounded' then
    raise exception 'accepted care rhythm should be bounded';
  end if;
  if v_packet->>'authorizationState' <> 'accepted' then
    raise exception 'rhythm authorization state must survive';
  end if;
  if jsonb_array_length(v_packet->'qualifyingRequirements') <> 1 then
    raise exception 'rhythm qualifying requirement must survive without task fanout';
  end if;
  if v_packet->>'satisfactionState' <> 'not_evaluated' or v_packet->>'missState' <> 'unknown' then
    raise exception 'packet must not invent satisfaction or miss state';
  end if;
  if coalesce((v_packet->'truthBoundary'->>'taskGenerationAuthority')::boolean,true) then
    raise exception 'rhythm packet must not generate tasks';
  end if;
  if coalesce((v_packet->'truthBoundary'->>'clockPlacementAuthority')::boolean,true) then
    raise exception 'rhythm packet must not place Clock claims';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
begin
  -- A dream-capture rhythm may remain bounded by a conditional timing rule; lack
  -- of a remembered dream is not inferred to be a failure from missing evidence.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-dream-rhythm'),
    'subject',jsonb_build_object('domain','dream','kind','capture_practice','id','remembered-dream-capture'),
    'signalKind','rhythm',
    'state',jsonb_build_object('authorizationState','self_selected'),
    'timing',jsonb_build_object('condition','when_a_dream_is_remembered'),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','qualifying_satisfaction',
      'operationKey','record_remembered_dream',
      'entryCondition','a dream is actually remembered'
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','dream','kind','practice_definition','id','remembered-dream-capture'),
    'epistemic',jsonb_build_object('factClass','explicit_practice','interpretationAuthority','person')
  );

  v_packet := atlas.life_signal_to_rhythm_packet_v1(v_signal);
  if v_packet->>'missState' <> 'unknown' then
    raise exception 'absence of a remembered dream may not be promoted to rhythm failure';
  end if;
  if not coalesce((v_packet->'truthBoundary'->>'absenceOfSatisfactionEvidenceDoesNotProveFailure')::boolean,false) then
    raise exception 'rhythm absence/failure boundary missing';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
begin
  -- Explicit 5K end does not manufacture a training program.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-goal'),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Complete a 5K'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','fixture-5k'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );

  v_packet := atlas.life_signal_to_goal_packet_v1(v_signal);
  if v_packet->>'definitionState' <> 'bounded' then
    raise exception 'explicit 5K goal should be bounded';
  end if;
  if v_packet->>'explicitUserEnd' <> 'Complete a 5K' then
    raise exception 'explicit 5K end must survive';
  end if;
  if (v_packet->>'requirementCount')::integer <> 0 then
    raise exception '5K goal must not invent customary training requirements';
  end if;
  if not coalesce((v_packet->'truthBoundary'->>'goalLabelDoesNotInventRequirements')::boolean,false) then
    raise exception 'goal no-invented-requirements boundary missing';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
begin
  -- A GoalSignal without an explicit end remains incomplete rather than having a
  -- desired end guessed from other state fields.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-incomplete-goal'),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-incomplete-goal'),
    'signalKind','goal',
    'state',jsonb_build_object('raceDistanceKm',5),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('desired_end_not_explicit'),
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','draft_goal_state','id','fixture-incomplete-goal'),
    'epistemic',jsonb_build_object('factClass','partial_goal_definition','interpretationAuthority','none')
  );

  v_packet := atlas.life_signal_to_goal_packet_v1(v_signal);
  if v_packet->>'definitionState' <> 'incomplete' then
    raise exception 'goal without explicitUserEnd must remain incomplete';
  end if;
  if v_packet->'explicitUserEnd' <> 'null'::jsonb then
    raise exception 'goal adapter must not infer desired end from arbitrary state';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
  v_requirement jsonb;
begin
  -- Known truth-acquisition consequence may exist without a selected carrier or
  -- placement. This is the life-domain equivalent of Atlas capability hold.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-consequence'),
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
    'source',jsonb_build_object('domain','body','kind','person_condition_observation','id','fixture-body-consequence'),
    'epistemic',jsonb_build_object('factClass','reported_observation','interpretationAuthority','none')
  );

  v_packet := atlas.life_signal_to_consequence_packet_v1(v_signal);
  v_requirement := v_packet->'requirements'->0;

  if v_requirement->>'consequenceRole' <> 'truth_acquisition' then
    raise exception 'truth-acquisition consequence role must survive';
  end if;
  if v_requirement->>'requirementState' <> 'established' then
    raise exception 'supplied consequence requirement must remain established';
  end if;
  if v_requirement->>'carrierState' <> 'unresolved' then
    raise exception 'carrier must remain unresolved when domain supplied none';
  end if;
  if v_requirement->>'placementState' <> 'unresolved' then
    raise exception 'placement must remain unresolved';
  end if;
  if v_requirement->>'executionReadiness' <> 'not_evaluated' then
    raise exception 'consequence packet may not pretend execution readiness was evaluated';
  end if;
  if not coalesce((v_packet->'truthBoundary'->>'notReadyDoesNotMeanNotRequired')::boolean,false) then
    raise exception 'requirement/readiness truth boundary missing';
  end if;
  if not coalesce((v_packet->'truthBoundary'->>'capabilityHoldMayBlockExecutionWithoutDeletingObligation')::boolean,false) then
    raise exception 'capability-hold truth boundary missing';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
  v_requirement jsonb;
begin
  -- A domain may establish a carrier without thereby establishing a Clock slot.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-carrier'),
    'subject',jsonb_build_object('domain','care','kind','care_requirement','id','fixture-repair'),
    'signalKind','consequence',
    'state',jsonb_build_object('authorizationState','accepted'),
    'timing',jsonb_build_object('window','this_week'),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','repair',
      'operationKey','authorized_care_operation',
      'carrierRef','practitioner:fixture-practitioner'
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','care_relationship','kind','accepted_repair_requirement','id','fixture-repair'),
    'epistemic',jsonb_build_object('factClass','authorized_requirement','interpretationAuthority','explicit_relationship')
  );

  v_packet := atlas.life_signal_to_consequence_packet_v1(v_signal);
  v_requirement := v_packet->'requirements'->0;
  if v_requirement->>'carrierState' <> 'established' then
    raise exception 'explicit domain-supplied carrier must survive';
  end if;
  if v_requirement->>'placementState' <> 'unresolved' then
    raise exception 'carrier establishment must not silently place work';
  end if;
  if coalesce((v_packet->'truthBoundary'->>'clockPlacementAuthority')::boolean,true) then
    raise exception 'consequence packet must not have Clock placement authority';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_failed boolean := false;
begin
  -- Consequence vocabulary is deliberately bounded in v1. A random domain label
  -- cannot masquerade as a shared consequence role.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-invalid-consequence'),
    'subject',jsonb_build_object('domain','journal','kind','reflection','id','fixture-reflection'),
    'signalKind','consequence',
    'state','{}'::jsonb,
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(jsonb_build_object('requirementKind','interpret_my_life')),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','journal','kind','reflection','id','fixture-reflection'),
    'epistemic',jsonb_build_object('factClass','reflection','interpretationAuthority','none')
  );

  begin
    perform atlas.life_signal_to_consequence_packet_v1(v_signal);
  exception when sqlstate '22023' then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'unsupported consequence role must be rejected';
  end if;
end
$$;

rollback;
