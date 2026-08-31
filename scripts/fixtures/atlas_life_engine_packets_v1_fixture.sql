-- Atlas Life Engine Packets v1 fixture
-- Pure JSON contract verification. No application records are required or mutated.

begin;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
begin
  -- Accepted practitioner homework expressed as four satisfactions before a date
  -- is a finite Goal requirement. It is not automatically a Rhythm and does not
  -- become four pre-created tasks or an automatic Clock placement.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-care-goal'),
    'subject',jsonb_build_object('domain','care','kind','care_goal','id','fixture-mobility-goal'),
    'signalKind','goal',
    'state',jsonb_build_object(
      'authorizationState','accepted',
      'explicitUserEnd','Complete the accepted hip mobility practice four times before 2026-09-12'
    ),
    'timing',jsonb_build_object('mustBeSatisfiedBefore','2026-09-12'),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKey','hip_mobility_a_count',
      'requirementKind','qualifying_satisfaction_count',
      'phase','realize',
      'operationKey','hip_mobility_a',
      'targetCount',4
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','care_relationship','kind','person_acceptance','id','fixture-acceptance-goal'),
    'epistemic',jsonb_build_object('factClass','authorized_requirement','interpretationAuthority','explicit_relationship')
  );

  v_packet := atlas.life_signal_to_goal_packet_v1(v_signal);
  if v_packet->>'definitionState' <> 'bounded' then
    raise exception 'accepted finite care goal should be bounded';
  end if;
  if (v_packet->>'requirementCount')::integer <> 1 then
    raise exception 'accepted finite care goal must preserve one bounded requirement';
  end if;
  if coalesce((v_packet->'truthBoundary'->>'taskGenerationAuthority')::boolean,true) then
    raise exception 'finite care goal packet must not generate task fanout';
  end if;
  if coalesce((v_packet->'truthBoundary'->>'clockPlacementAuthority')::boolean,true) then
    raise exception 'finite care goal packet must not place Clock claims';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_failed boolean := false;
begin
  -- Record-when-remembered is event-triggered Observation capture. It may not be
  -- silently routed through Rhythm merely because the behavior can recur.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-dream-observation'),
    'subject',jsonb_build_object('domain','dream','kind','dream_record','id','fixture-dream-record'),
    'signalKind','observation',
    'state',jsonb_build_object('recorded',true),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('meaning_unresolved','cause_unresolved'),
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','dream','kind','dream_record','id','fixture-dream-record'),
    'epistemic',jsonb_build_object('factClass','remembered_experience','interpretationAuthority','none')
  );

  begin
    perform atlas.life_signal_to_rhythm_packet_v1(v_signal);
  exception when sqlstate '22023' then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'dream observation must not be silently promoted to Rhythm';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_packet jsonb;
  v_eval jsonb;
  v_last_satisfied timestamptz := '2026-09-01T09:00:00-05:00'::timestamptz;
begin
  -- An actual recurring cadence uses the explicit lease strategy. Each qualifying
  -- satisfaction renews a seven-day validity interval. The generic evaluator
  -- derives state only; it does not create tasks, transitions, or Clock slots.
  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-person-weekly-review'),
    'subject',jsonb_build_object('domain','journal','kind','practice','id','weekly_review'),
    'signalKind','rhythm',
    'state',jsonb_build_object('authorizationState','self_selected','rhythmModel','lease'),
    'timing',jsonb_build_object(
      'boundaryMode','exact_timestamp',
      'validityIntervalSeconds',604800,
      'warningWindowSeconds',86400,
      'graceWindowSeconds',86400
    ),
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','qualifying_satisfaction',
      'operationKey','complete_weekly_review'
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','journal','kind','practice_definition','id','weekly-review-practice'),
    'epistemic',jsonb_build_object('factClass','explicit_practice','interpretationAuthority','person')
  );

  v_packet := atlas.life_signal_to_rhythm_packet_v1(v_signal);
  if v_packet->>'definitionState' <> 'bounded' or v_packet->>'rhythmModel' <> 'lease' or v_packet->>'strategyState' <> 'supported' then
    raise exception 'explicit lease Rhythm must produce a supported bounded packet';
  end if;

  v_eval := atlas.evaluate_life_lease_rhythm_v1(v_packet,null,'2026-09-10T09:00:00-05:00'::timestamptz);
  if v_eval->>'state' <> 'uninitialized' then
    raise exception 'no prior satisfaction must remain uninitialized, not failed';
  end if;

  v_eval := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_last_satisfied,'2026-09-07T08:59:00-05:00'::timestamptz);
  if v_eval->>'state' <> 'resting' then
    raise exception 'lease Rhythm should be resting before warning boundary';
  end if;

  v_eval := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_last_satisfied,'2026-09-07T10:00:00-05:00'::timestamptz);
  if v_eval->>'state' <> 'coming_due' then
    raise exception 'lease Rhythm should become coming_due after warning boundary';
  end if;

  v_eval := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_last_satisfied,'2026-09-08T10:00:00-05:00'::timestamptz);
  if v_eval->>'state' <> 'due' then
    raise exception 'lease Rhythm should become due after validity boundary';
  end if;

  v_eval := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_last_satisfied,'2026-09-09T10:00:00-05:00'::timestamptz);
  if v_eval->>'state' <> 'fallen_out_of_rhythm' then
    raise exception 'lease Rhythm should cross failure boundary after grace interval';
  end if;
  if not coalesce((v_eval->'truthBoundary'->>'doesNotCreateTask')::boolean,false) then
    raise exception 'generic lease evaluator must not create a task';
  end if;
  if not coalesce((v_eval->'truthBoundary'->>'doesNotArbitrateClock')::boolean,false) then
    raise exception 'generic lease evaluator must not arbitrate Clock';
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
