-- Atlas Person 5K + Body Vertical Slice v1 fixture
-- Rollback-only proof of:
-- accepted goal -> accepted timed requirement -> run evidence -> first-party
-- body condition -> accepted consequence policy -> persisted consequence ->
-- explicit temporal carrier -> unified Principal Clock -> explainable trace.
--
-- The fixture also proves that an uncarried consequence cannot enter Clock,
-- Rhythm evaluation does not create work/Clock claims, and no task is created.

begin isolation level repeatable read;

DO $$
declare
  v_user uuid;
  v_principal uuid;
  v_now timestamptz:=now();
  v_harder_run_at timestamptz:=now()+interval '2 days';
  v_tasks_before bigint;
  v_tasks_after bigint;
  v_result jsonb;
  v_goal_intent_event uuid;
  v_goal uuid;
  v_requirement_accept_event uuid;
  v_requirement uuid;
  v_run_event uuid;
  v_condition_result jsonb;
  v_observation uuid;
  v_condition_event uuid;
  v_policy_accept_event uuid;
  v_policy uuid;
  v_uncarried_policy uuid;
  v_reconcile jsonb;
  v_consequence uuid;
  v_uncarried_consequence uuid;
  v_claim_result jsonb;
  v_claim uuid;
  v_trace jsonb;
  v_goal_eval jsonb;
  v_rhythm_event uuid;
  v_rhythm_binding uuid;
  v_rhythm_eval jsonb;
  v_failed boolean:=false;
begin
  select p.user_id,p.id into v_user,v_principal
  from atlas.principals p
  where p.status='active'
  order by p.created_at
  limit 1;

  if v_user is null then
    raise exception 'Fixture requires one active Principal/auth user.';
  end if;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  select count(*) into v_tasks_before from atlas.tasks;

  -- 1. The person states the Goal. This is accepted first-party intent; Atlas
  -- does not infer a plan from it.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture',
    'sourceKey','person-5k-goal-intent-v1',
    'eventKind','goal_intent',
    'claimState','accepted',
    'authorityKind','first_party',
    'occurredAt',v_now,
    'payload',jsonb_build_object('statement','I want to run a 5K.'),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','person','kind','person','id',v_user::text,'relationKind','owner'),
      jsonb_build_object('domain','training','kind','goal_intent','id','run_5k','relationKind','about')
    ),
    'provenance',jsonb_build_object('fixture','atlas_person_5k_body_vertical_slice_v1')
  ));
  v_goal_intent_event:=(v_result->>'eventId')::uuid;

  v_result:=atlas.upsert_person_life_goal_api_v1(jsonb_build_object(
    'stableKey','fixture_run_5k',
    'title','Run a 5K',
    'authorizationState','accepted',
    'sourceEventId',v_goal_intent_event,
    'goalPacket',jsonb_build_object(
      'contractVersion','life_goal_packet_v1',
      'scope',jsonb_build_object('kind','person','id',v_user::text),
      'subject',jsonb_build_object('domain','training','kind','goal','id','fixture_run_5k'),
      'explicitUserEnd','Run a 5K',
      'requirements','[]'::jsonb,
      'provenance',jsonb_build_object('sourceEventId',v_goal_intent_event)
    ),
    'provenance',jsonb_build_object('authority','first_party_acceptance')
  ));
  v_goal:=(v_result->>'goalId')::uuid;

  if exists(select 1 from atlas.person_life_goal_requirements where goal_id=v_goal) then
    raise exception 'Goal intent manufactured a requirement.';
  end if;

  -- 2. A timed training requirement exists only because the person explicitly
  -- accepts it. This supplies the future temporal carrier used later.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture',
    'sourceKey','person-5k-harder-run-acceptance-v1',
    'eventKind','plan_requirement_acceptance',
    'claimState','accepted',
    'authorityKind','first_party',
    'occurredAt',v_now+interval '1 second',
    'payload',jsonb_build_object(
      'statement','I accept one harder run as part of this test plan.',
      'mustBeginBy',v_harder_run_at
    ),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','training','kind','goal','id',v_goal::text,'relationKind','requirement_for')
    )
  ));
  v_requirement_accept_event:=(v_result->>'eventId')::uuid;

  v_result:=atlas.upsert_person_life_goal_requirement_api_v1(jsonb_build_object(
    'goalId',v_goal,
    'stableKey','fixture_harder_run',
    'label','Harder run',
    'authorizationState','accepted',
    'sourceEventId',v_requirement_accept_event,
    'mustBeginBy',v_harder_run_at,
    'mustFinishBy',v_harder_run_at+interval '40 minutes',
    'expectedMinutes',40,
    'requirementPacket',jsonb_build_object(
      'requirementKey','fixture_harder_run',
      'label','Harder run',
      'phase','progress',
      'required',true
    ),
    'provenance',jsonb_build_object('authority','first_party_acceptance')
  ));
  v_requirement:=(v_result->>'requirementId')::uuid;

  v_goal_eval:=atlas.evaluate_person_life_goal_v1(v_goal,'[]'::jsonb);
  if v_goal_eval->>'state'<>'tracking' then
    raise exception 'Missing requirement evidence should remain unknown/tracking, got %',v_goal_eval->>'state';
  end if;
  if v_goal_eval->'requirements'->0->>'state'<>'unknown' then
    raise exception 'Goal reducer manufactured requirement satisfaction.';
  end if;

  -- 3. Record a run. The run is explicitly related to the accepted Goal, but
  -- it does not automatically satisfy the separate harder-run requirement.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture',
    'sourceKey','person-5k-run-2-1-v1',
    'eventKind','activity_recorded',
    'claimState','reported',
    'authorityKind','first_party',
    'occurredAt',v_now+interval '2 seconds',
    'payload',jsonb_build_object('activityLabel','run','distance',2.1,'distanceUnit','mile'),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','person','kind','person','id',v_user::text,'relationKind','actor'),
      jsonb_build_object('domain','training','kind','goal','id',v_goal::text,'relationKind','associated_with')
    )
  ));
  v_run_event:=(v_result->>'eventId')::uuid;

  -- 4. Record the body observation through the already-live generic Care
  -- condition scope. It is first-party evidence, not a diagnosis and not a
  -- causal claim about the run.
  v_condition_result:=atlas.record_person_condition_observation_api_v1(jsonb_build_object(
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'conditionState','tight',
    'disposition','reassess',
    'sourceKey','fixture-left-hip-tight-v1',
    'observedAt',v_now+interval '3 seconds',
    'note','left hip tight afterward',
    'metadata',jsonb_build_object('fixture','atlas_person_5k_body_vertical_slice_v1')
  ));
  v_observation:=(v_condition_result->>'observationId')::uuid;

  if (select inferred_from_clock from atlas.care_observation_events where id=v_observation) then
    raise exception 'Person condition observation was incorrectly inferred from Clock.';
  end if;

  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','care_observation',
    'sourceKey','fixture-left-hip-life-event-v1',
    'sourceRecordId',v_observation,
    'eventKind','condition_observation',
    'claimState','reported',
    'authorityKind','first_party',
    'occurredAt',v_now+interval '3 seconds',
    'payload',jsonb_build_object(
      'statement','left hip tight afterward',
      'snapshot',jsonb_build_object(
        'subject',jsonb_build_object('domain','body','kind','body_region','id','left_hip'),
        'condition',jsonb_build_object('state','tight','disposition','reassess')
      )
    ),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','body','kind','body_region','id','left_hip','relationKind','about'),
      jsonb_build_object('domain','person','kind','person','id',v_user::text,'relationKind','owner')
    ),
    'relations',jsonb_build_array(
      jsonb_build_object('toEventId',v_run_event,'relationKind','reported_after')
    ),
    'provenance',jsonb_build_object('sourceObservationId',v_observation)
  ));
  v_condition_event:=(v_result->>'eventId')::uuid;

  if (select payload->'snapshot' ? 'diagnosis' from atlas.person_life_events where id=v_condition_event) then
    raise exception 'Condition capture manufactured a diagnosis.';
  end if;
  if (select payload->'snapshot' ? 'cause' from atlas.person_life_events where id=v_condition_event) then
    raise exception 'Condition capture manufactured causation.';
  end if;
  if not exists(select 1 from atlas.person_life_event_relations where from_event_id=v_condition_event and to_event_id=v_run_event and relation_kind='reported_after') then
    raise exception 'Temporal context relation was not preserved.';
  end if;
  if exists(select 1 from atlas.person_life_event_relations where from_event_id=v_condition_event and relation_kind in ('caused_by','cause')) then
    raise exception 'Temporal context was promoted to causation.';
  end if;

  -- No observation or condition state gets a Clock claim by itself.
  if exists(select 1 from atlas.person_life_clock_claims where person_user_id=v_user and created_at>=v_now) then
    raise exception 'Observation created a Clock claim directly.';
  end if;

  -- 5. The person separately accepts a consequence rule. This is the authority
  -- that may establish preparation; the body observation itself does not.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture',
    'sourceKey','person-left-hip-policy-acceptance-v1',
    'eventKind','consequence_policy_acceptance',
    'claimState','accepted',
    'authorityKind','first_party',
    'occurredAt',v_now+interval '4 seconds',
    'payload',jsonb_build_object(
      'statement','If I report my left hip as tight, reassess it before this accepted harder run.'
    ),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','body','kind','body_region','id','left_hip','relationKind','governs'),
      jsonb_build_object('domain','training','kind','requirement','id',v_requirement::text,'relationKind','prepares_for')
    )
  ));
  v_policy_accept_event:=(v_result->>'eventId')::uuid;

  v_result:=atlas.upsert_person_life_consequence_policy_api_v1(jsonb_build_object(
    'stableKey','fixture_left_hip_reassess_before_harder_run',
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'authorizationState','accepted',
    'sourceEventId',v_policy_accept_event,
    'policyPacket',jsonb_build_object(
      'stableKey','fixture_left_hip_reassess_before_harder_run',
      'active',true,
      'subjectSelector',jsonb_build_object('subject',jsonb_build_object('domain','body','kind','body_region','id','left_hip')),
      'stateMatch',jsonb_build_object('condition',jsonb_build_object('state','tight')),
      'consequenceRole','preparation',
      'consequenceKind','reassessment_required',
      'actionKey','reassess_before_harder_run',
      'priority',30,
      'actionSpec',jsonb_build_object(
        'carrierRef',v_requirement::text,
        'clockEligible',true,
        'temporalRelation','before_carrier_start',
        'domain','life',
        'title','Reassess left hip before harder run',
        'floorClass',3,
        'expectedMinutes',5,
        'protectionLevel','protected',
        'interruptibility','movable',
        'consequence','Accepted preparation remains unresolved before the harder run.',
        'reasonForFloor','An accepted preparation policy requires reassessment before an accepted timed requirement begins.'
      ),
      'metadata',jsonb_build_object('authority','first_party_acceptance','diagnosticClaim',false,'causalClaim',false)
    )
  ));
  v_policy:=(v_result->>'policyId')::uuid;

  -- A second accepted matching policy intentionally has no carrier. It may
  -- establish a consequence, but that consequence must be barred from Clock.
  v_result:=atlas.upsert_person_life_consequence_policy_api_v1(jsonb_build_object(
    'stableKey','fixture_left_hip_uncarried_attention',
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'authorizationState','accepted',
    'sourceEventId',v_policy_accept_event,
    'policyPacket',jsonb_build_object(
      'stableKey','fixture_left_hip_uncarried_attention',
      'active',true,
      'subjectSelector',jsonb_build_object('subject',jsonb_build_object('domain','body','kind','body_region','id','left_hip')),
      'stateMatch',jsonb_build_object('condition',jsonb_build_object('state','tight')),
      'consequenceRole','truth_acquisition',
      'consequenceKind','attention_without_carrier',
      'actionKey','notice_tightness',
      'priority',80,
      'actionSpec',jsonb_build_object(
        'clockEligible',true,
        'temporalRelation','before_carrier_start',
        'domain','life',
        'title','Notice left hip condition',
        'floorClass',3,
        'expectedMinutes',5,
        'protectionLevel','standard',
        'interruptibility','movable',
        'reasonForFloor','Fixture-only uncarried consequence.'
      )
    )
  ));
  v_uncarried_policy:=(v_result->>'policyId')::uuid;

  v_reconcile:=atlas.reconcile_person_life_consequences_api_v1(v_condition_event);
  if (v_reconcile->>'persistedCount')::integer<>2 then
    raise exception 'Expected two explicit matching consequences, got %',v_reconcile->>'persistedCount';
  end if;

  select id into v_consequence from atlas.person_life_consequence_instances
  where person_user_id=v_user and policy_id=v_policy and source_event_id=v_condition_event;
  select id into v_uncarried_consequence from atlas.person_life_consequence_instances
  where person_user_id=v_user and policy_id=v_uncarried_policy and source_event_id=v_condition_event;

  if v_consequence is null or v_uncarried_consequence is null then
    raise exception 'Expected persisted consequence instances.';
  end if;
  if exists(select 1 from atlas.person_life_clock_claims where consequence_instance_id in (v_consequence,v_uncarried_consequence)) then
    raise exception 'Consequence reconciliation placed Clock claims automatically.';
  end if;

  v_failed:=false;
  begin
    perform atlas.claim_person_life_consequence_for_clock_api_v1(v_uncarried_consequence);
  exception when sqlstate '22023' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Uncarried observation consequence incorrectly entered Clock.';
  end if;

  -- 6. The carried consequence can now produce one eligible temporal claim.
  v_claim_result:=atlas.claim_person_life_consequence_for_clock_api_v1(v_consequence);
  v_claim:=(v_claim_result->>'clockClaimId')::uuid;

  if not exists(select 1 from atlas.person_life_clock_candidates_v1 where source_id=v_claim and source_type='person_life_consequence') then
    raise exception 'Person-life Clock candidate missing.';
  end if;
  if not exists(select 1 from atlas.principal_clock_candidates_v1 where source_id=v_claim and source_type='person_life_consequence' and principal_id=v_principal) then
    raise exception 'Person-life claim did not enter unified Principal Clock candidates.';
  end if;
  if not exists(select 1 from atlas.principal_clock_arbitration_v1(v_principal,current_date,v_now+interval '10 seconds') where source_id=v_claim and source_type='person_life_consequence') then
    raise exception 'Unified Principal Clock arbitration did not see person-life claim.';
  end if;

  -- 7. Explainability: the claim traces to consequence, accepted policy,
  -- source observation, temporal run context, accepted requirement, and Goal.
  v_trace:=atlas.person_life_clock_claim_trace_v1(v_claim);
  if v_trace->'clockClaim'->>'id'<>v_claim::text then raise exception 'Trace missing Clock claim.'; end if;
  if v_trace->'consequence'->>'id'<>v_consequence::text then raise exception 'Trace missing consequence.'; end if;
  if v_trace->'acceptedPolicy'->>'id'<>v_policy::text then raise exception 'Trace missing accepted policy.'; end if;
  if v_trace->'sourceObservation'->>'id'<>v_condition_event::text then raise exception 'Trace missing source observation.'; end if;
  if v_trace->'acceptedRequirement'->>'id'<>v_requirement::text then raise exception 'Trace missing accepted requirement.'; end if;
  if v_trace->'goal'->>'id'<>v_goal::text then raise exception 'Trace missing Goal.'; end if;
  if not exists(
    select 1 from jsonb_array_elements(v_trace->'contextEvents') x
    where x->>'relationKind'='reported_after' and x->'event'->>'id'=v_run_event::text
  ) then raise exception 'Trace missing temporal run context.'; end if;

  -- Idempotency: retrying source event, reconciliation, and Clock claim does
  -- not duplicate canonical truth.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture','sourceKey','person-5k-run-2-1-v1','eventKind','activity_recorded',
    'claimState','reported','authorityKind','first_party','occurredAt',v_now+interval '2 seconds',
    'payload',jsonb_build_object('activityLabel','run','distance',2.1,'distanceUnit','mile'),
    'subjects',jsonb_build_array(
      jsonb_build_object('domain','person','kind','person','id',v_user::text,'relationKind','actor'),
      jsonb_build_object('domain','training','kind','goal','id',v_goal::text,'relationKind','associated_with')
    )
  ));
  if (v_result->>'eventId')::uuid<>v_run_event then raise exception 'Event idempotency failed.'; end if;

  perform atlas.reconcile_person_life_consequences_api_v1(v_condition_event);
  if (select count(*) from atlas.person_life_consequence_instances where person_user_id=v_user and source_event_id=v_condition_event)<>2 then
    raise exception 'Consequence reconciliation duplicated instances.';
  end if;
  v_claim_result:=atlas.claim_person_life_consequence_for_clock_api_v1(v_consequence);
  if (v_claim_result->>'clockClaimId')::uuid<>v_claim then raise exception 'Clock claim idempotency failed.'; end if;

  -- 8. Person-owned Rhythm persistence uses the pure lease reducer and cannot
  -- create tasks or Clock claims by itself.
  v_result:=atlas.record_person_life_event_api_v1(jsonb_build_object(
    'sourceKind','fixture',
    'sourceKey','person-rhythm-acceptance-v1',
    'eventKind','rhythm_acceptance',
    'claimState','accepted',
    'authorityKind','first_party',
    'occurredAt',v_now+interval '5 seconds',
    'payload',jsonb_build_object('statement','I accept this fixture lease rhythm.'),
    'subjects',jsonb_build_array(jsonb_build_object('domain','life','kind','fixture_rhythm','id','lease_test','relationKind','governs'))
  ));
  v_rhythm_event:=(v_result->>'eventId')::uuid;

  v_result:=atlas.upsert_person_life_rhythm_binding_api_v1(jsonb_build_object(
    'stableKey','fixture_person_lease_rhythm',
    'subjectDomain','life',
    'subjectKind','fixture_rhythm',
    'subjectId','lease_test',
    'authorizationState','accepted',
    'sourceEventId',v_rhythm_event,
    'rhythmPacket',jsonb_build_object(
      'contractVersion','life_rhythm_packet_v1',
      'scope',jsonb_build_object('kind','person','id',v_user::text),
      'subject',jsonb_build_object('domain','life','kind','fixture_rhythm','id','lease_test'),
      'authorizationState','accepted',
      'rhythmModel','lease',
      'strategyState','supported',
      'timing',jsonb_build_object('boundaryMode','exact_timestamp','validityIntervalSeconds',259200,'warningWindowSeconds',86400,'graceWindowSeconds',43200),
      'qualifyingRequirements','[]'::jsonb
    )
  ));
  v_rhythm_binding:=(v_result->>'bindingId')::uuid;
  v_rhythm_eval:=atlas.evaluate_person_life_rhythm_api_v1(v_rhythm_binding,v_now-interval '1 day',v_now);
  if v_rhythm_eval->>'state'<>'resting' then raise exception 'Unexpected lease Rhythm state: %',v_rhythm_eval->>'state'; end if;
  if not exists(select 1 from atlas.person_life_rhythm_state where binding_id=v_rhythm_binding and person_user_id=v_user) then raise exception 'Person Rhythm state was not persisted.'; end if;
  if (select count(*) from atlas.person_life_clock_claims where person_user_id=v_user and created_at>=v_now)<>1 then
    raise exception 'Rhythm evaluation created a Clock claim.';
  end if;

  select count(*) into v_tasks_after from atlas.tasks;
  if v_tasks_after<>v_tasks_before then
    raise exception 'Person-life vertical slice created a task; before %, after %',v_tasks_before,v_tasks_after;
  end if;

  raise notice 'PASS atlas_person_5k_body_vertical_slice_v1: goal %, run %, observation %, consequence %, claim %',v_goal,v_run_event,v_observation,v_consequence,v_claim;
end;
$$;

rollback;
