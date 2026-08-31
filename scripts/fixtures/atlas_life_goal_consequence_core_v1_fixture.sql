-- Atlas Life Goal + State Consequence Core v1 fixture
-- Pure evaluator verification. No application records are required or mutated.

begin;

do $$
declare
  v_signal jsonb;
  v_goal_packet jsonb;
  v_eval jsonb;
begin
  -- An explicit goal with no warranted requirements is defined, not magically
  -- nearly unlocked and not assigned a customary training plan.
  v_signal:=jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-goal-owner'),
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
  v_goal_packet:=atlas.life_signal_to_goal_packet_v1(v_signal);
  v_eval:=atlas.evaluate_life_goal_state_v1(v_goal_packet,'[]'::jsonb);

  if v_eval->>'state'<>'defined' then
    raise exception 'goal with no warranted requirements must remain defined';
  end if;
  if (v_eval->'progress'->>'total')::integer<>0 then
    raise exception 'generic Goal core must not invent requirements';
  end if;
  if not coalesce((v_eval->'truthBoundary'->>'farmNearThresholdPolicyNotPartOfGenericCore')::boolean,false) then
    raise exception 'farm near-threshold display policy must remain outside generic core';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_goal_packet jsonb;
  v_results jsonb;
  v_eval jsonb;
begin
  -- Gate + progress requirements are evaluated from independently supplied
  -- evidence results. The reducer never queries a farm or task table.
  v_signal:=jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-goal-progress-owner'),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k-progress'),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Complete a 5K'),
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(
      jsonb_build_object('requirementKey','registered','requirementKind','external_fact','phase','gate','label','Registration complete'),
      jsonb_build_object('requirementKey','training-base','requirementKind','evidence_threshold','phase','progress','label','Training base established')
    ),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','fixture-5k-progress'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );
  v_goal_packet:=atlas.life_signal_to_goal_packet_v1(v_signal);
  v_results:=jsonb_build_array(
    jsonb_build_object('requirementKey','registered','state','satisfied','source',jsonb_build_object('kind','registration_receipt')),
    jsonb_build_object('requirementKey','training-base','state','partial','source',jsonb_build_object('kind','training_evidence'))
  );
  v_eval:=atlas.evaluate_life_goal_state_v1(v_goal_packet,v_results);

  if v_eval->>'state'<>'in_production' then
    raise exception 'satisfied gate plus partial progress should be in_production';
  end if;
  if (v_eval->'progress'->>'satisfied')::integer<>1 or (v_eval->'progress'->>'partial')::integer<>1 then
    raise exception 'generic Goal reducer counts are wrong';
  end if;
  if coalesce((v_eval->'truthBoundary'->>'doesNotSelectNextTask')::boolean,false) is distinct from true then
    raise exception 'generic Goal reducer must not select a next task';
  end if;
end
$$;

do $$
declare
  v_signal jsonb;
  v_goal_packet jsonb;
  v_eval jsonb;
begin
  -- Missing provider evidence stays unknown instead of becoming unmet.
  v_signal:=jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id','fixture-goal-unknown-owner'),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-goal-unknown'),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Complete a 5K'),
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(
      jsonb_build_object('requirementKey','evidence-needed','requirementKind','evidence_threshold','phase','gate','label','Evidence needed')
    ),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','fixture-goal-unknown'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );
  v_goal_packet:=atlas.life_signal_to_goal_packet_v1(v_signal);
  v_eval:=atlas.evaluate_life_goal_state_v1(v_goal_packet,'[]'::jsonb);

  if v_eval->'requirements'->0->>'state'<>'unknown' then
    raise exception 'missing requirement result must remain unknown';
  end if;
  if v_eval->>'state'<>'tracking' then
    raise exception 'goal with unresolved evidence must remain tracking, not locked/playable';
  end if;
end
$$;

do $$
declare
  v_snapshot jsonb;
  v_policies jsonb;
  v_eval jsonb;
  v_consequence jsonb;
begin
  -- Explicit condition snapshot activates an explicit truth-acquisition policy.
  -- The policy establishes what is needed, not who performs it or when.
  v_snapshot:=jsonb_build_object(
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'reportedState','tight_after_run',
    'functionalState','unknown'
  );
  v_policies:=jsonb_build_array(jsonb_build_object(
    'stableKey','body-left-hip-reassess-v1',
    'subjectSelector',jsonb_build_object('subjectDomain','body','subjectKind','body_region'),
    'stateMatch',jsonb_build_object('functionalState','unknown'),
    'consequenceRole','truth_acquisition',
    'consequenceKind','knowledge_acquisition',
    'actionKey','reassess_condition',
    'priority',50,
    'actionSpec',jsonb_build_object('factNeeded','present functional state'),
    'metadata',jsonb_build_object('causeNotEstablished',true)
  ));
  v_eval:=atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
  if (v_eval->>'openCount')::integer<>1 then
    raise exception 'matching body snapshot should activate one consequence';
  end if;
  v_consequence:=v_eval->'openConsequences'->0;
  if v_consequence->>'consequenceRole'<>'truth_acquisition' then
    raise exception 'truth-acquisition role must survive generic policy match';
  end if;
  if v_consequence->>'carrierState'<>'unresolved' or v_consequence->>'placementState'<>'unresolved' then
    raise exception 'generic consequence match must leave carrier and placement unresolved';
  end if;
  if v_consequence->>'executionReadiness'<>'not_evaluated' then
    raise exception 'generic consequence match must not pretend readiness was evaluated';
  end if;
end
$$;

do $$
declare
  v_snapshot jsonb;
  v_policies jsonb;
  v_eval jsonb;
begin
  -- A nonmatching state creates no consequence. Relation or label similarity is
  -- irrelevant because matching is against the explicit snapshot predicate.
  v_snapshot:=jsonb_build_object('subjectDomain','body','subjectKind','body_region','functionalState','clear');
  v_policies:=jsonb_build_array(jsonb_build_object(
    'stableKey','body-reassess-only-when-unknown-v1',
    'subjectSelector',jsonb_build_object('subjectDomain','body'),
    'stateMatch',jsonb_build_object('functionalState','unknown'),
    'consequenceRole','truth_acquisition',
    'actionKey','reassess_condition',
    'actionSpec','{}'::jsonb
  ));
  v_eval:=atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
  if (v_eval->>'openCount')::integer<>0 then
    raise exception 'nonmatching explicit state must not activate consequence';
  end if;
end
$$;

do $$
declare
  v_snapshot jsonb;
  v_policies jsonb;
  v_eval jsonb;
  v_consequence jsonb;
begin
  -- An explicitly policy-selected carrier may survive, but still does not create
  -- a placement or execution warrant.
  v_snapshot:=jsonb_build_object('subjectDomain','care','authorizationState','accepted','repairRequired',true);
  v_policies:=jsonb_build_array(jsonb_build_object(
    'stableKey','accepted-care-repair-v1',
    'subjectSelector',jsonb_build_object('subjectDomain','care'),
    'stateMatch',jsonb_build_object('repairRequired',true),
    'consequenceRole','repair',
    'actionKey','authorized_care_operation',
    'actionSpec',jsonb_build_object('carrierRef','practitioner:fixture-practitioner')
  ));
  v_eval:=atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
  v_consequence:=v_eval->'openConsequences'->0;
  if v_consequence->>'carrierState'<>'established' then
    raise exception 'explicit carrier in policy must survive';
  end if;
  if v_consequence->>'placementState'<>'unresolved' then
    raise exception 'explicit carrier must not imply placement';
  end if;
  if not coalesce((v_eval->'truthBoundary'->>'policyMatchDoesNotPlaceClockClaim')::boolean,false) then
    raise exception 'Clock boundary missing from consequence core';
  end if;
end
$$;

rollback;
