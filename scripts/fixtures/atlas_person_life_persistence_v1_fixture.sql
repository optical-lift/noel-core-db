-- Atlas Person-Owned Life Persistence v1 fixture
-- Proves the human-root 5K + body-observation slice without creating farm,
-- organization, task, practitioner, or Clock authority. Everything rolls back.

begin;

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_principal_id uuid := gen_random_uuid();
  v_goal_signal jsonb;
  v_goal_create jsonb;
  v_goal_id uuid;
  v_goal_eval jsonb;
  v_body_observation jsonb;
  v_consequence_signal jsonb;
  v_consequence_create jsonb;
  v_consequence_id uuid;
  v_consequence_eval jsonb;
  v_nonmatch_eval jsonb;
  v_resolution jsonb;
  v_state jsonb;
  v_count integer;
begin
  insert into auth.users(id) values (v_user_id);

  insert into atlas.principals (
    id,
    user_id,
    stable_key,
    name,
    home_timezone,
    status,
    metadata
  ) values (
    v_principal_id,
    v_user_id,
    'fixture-person-life-' || v_user_id::text,
    'Person Life Fixture',
    'America/Chicago',
    'active',
    '{}'::jsonb
  );

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  -- The person's explicit 5K end is canonical. With no independently warranted
  -- requirements, Atlas must persist the Goal without inventing a training plan.
  v_goal_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_id::text),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Complete a 5K'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','fixture-5k-goal-definition'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );

  v_goal_create := atlas.create_person_life_definition_api_v1(jsonb_build_object(
    'sourceKey','fixture-5k-goal-create',
    'signal',v_goal_signal
  ));
  v_goal_id := (v_goal_create->>'definitionId')::uuid;

  if v_goal_create->>'signalKind' <> 'goal'
     or v_goal_create->'initialEvaluation'->>'state' <> 'defined'
     or (v_goal_create->'initialEvaluation'->'progress'->>'total')::integer <> 0 then
    raise exception '5K Goal persistence invented requirements or wrong initial state';
  end if;

  select count(*)
  into v_count
  from atlas.person_life_definitions d
  where d.owner_user_id = v_user_id
    and d.signal_kind = 'rhythm';

  if v_count <> 0 then
    raise exception 'Creating a bounded 5K Goal must not invent a Rhythm';
  end if;

  -- Replaying the same source key and same canonical definition is idempotent.
  if coalesce((atlas.create_person_life_definition_api_v1(jsonb_build_object(
    'sourceKey','fixture-5k-goal-create',
    'signal',v_goal_signal
  ))->>'created')::boolean, true) then
    raise exception 'Exact person-life definition replay should return created=false';
  end if;

  v_goal_eval := atlas.record_person_life_state_api_v1(v_goal_id, jsonb_build_object(
    'sourceKey','fixture-5k-goal-eval-1',
    'eventKind','goal_evaluation',
    'observedAt','2026-09-01T08:00:00-05:00',
    'requirementResults','[]'::jsonb,
    'evidence',jsonb_build_object('kind','explicit_goal_review')
  ));

  if v_goal_eval->'evaluation'->>'state' <> 'defined' then
    raise exception '5K Goal with no warranted requirements must remain defined';
  end if;

  -- A body observation can coexist in the same person's custody without being
  -- treated as proof that the Goal caused it or that the Goal must be cancelled.
  v_body_observation := atlas.record_person_condition_observation_api_v1(jsonb_build_object(
    'subjectDomain','body',
    'subjectKind','body_region',
    'subjectId','left_hip',
    'conditionState','tight_after_run',
    'disposition','reassess',
    'sourceKey','fixture-left-hip-observation-1',
    'observedAt','2026-09-01T08:30:00-05:00',
    'note','fixture observation only',
    'metadata',jsonb_build_object('causeEstablished',false,'relatedGoalDefinitionId',v_goal_id)
  ));

  if v_body_observation->>'scopeKind' <> 'person'
     or v_body_observation->>'conditionState' <> 'tight_after_run' then
    raise exception 'Person body observation did not remain first-party condition truth';
  end if;

  select count(*)
  into v_count
  from atlas.care_current_state s
  where s.scope_kind = 'person'
    and s.scope_id = v_user_id
    and s.subject_domain = 'body'
    and s.subject_kind = 'body_region'
    and s.subject_id = 'left_hip'
    and s.condition_state = 'tight_after_run';

  if v_count <> 1 then
    raise exception 'Body current-state projection missing after person observation';
  end if;

  -- A separately supplied consequence definition may establish a need to acquire
  -- truth about present function, but it still cannot select a carrier or Clock.
  v_consequence_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_id::text),
    'subject',jsonb_build_object('domain','body','kind','body_region','id','left_hip'),
    'signalKind','consequence',
    'state',jsonb_build_object('reportedState','tight_after_run','functionalState','unknown'),
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKey','left-hip-function-truth',
      'requirementKind','truth_acquisition',
      'operationKey','reassess_condition'
    )),
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('cause_not_established'),
    'relations',jsonb_build_array(jsonb_build_object(
      'relationKind','context_for',
      'target',jsonb_build_object('domain','training','kind','training_goal','id','fixture-5k'),
      'relationBasis','same person training context',
      'relationStatus','observed_context',
      'causal',false
    )),
    'source',jsonb_build_object('domain','body','kind','condition_consequence_definition','id','fixture-left-hip-reassess'),
    'epistemic',jsonb_build_object('factClass','explicit_policy','interpretationAuthority','person')
  );

  v_consequence_create := atlas.create_person_life_definition_api_v1(jsonb_build_object(
    'sourceKey','fixture-left-hip-consequence-create',
    'signal',v_consequence_signal
  ));
  v_consequence_id := (v_consequence_create->>'definitionId')::uuid;

  select count(*)
  into v_count
  from atlas.person_life_relations r
  where r.definition_id = v_consequence_id
    and r.owner_user_id = v_user_id
    and r.relation_kind = 'context_for'
    and r.target_domain = 'training'
    and r.target_kind = 'training_goal'
    and r.target_id = 'fixture-5k';

  if v_count <> 1 then
    raise exception 'Neutral person-life relation was not persisted';
  end if;

  v_consequence_eval := atlas.record_person_life_state_api_v1(v_consequence_id, jsonb_build_object(
    'sourceKey','fixture-left-hip-consequence-eval-1',
    'eventKind','consequence_evaluation',
    'observedAt','2026-09-01T08:35:00-05:00',
    'snapshot',jsonb_build_object(
      'subjectDomain','body',
      'subjectKind','body_region',
      'subjectId','left_hip',
      'reportedState','tight_after_run',
      'functionalState','unknown'
    ),
    'policies',jsonb_build_array(jsonb_build_object(
      'stableKey','left-hip-reassess-v1',
      'subjectSelector',jsonb_build_object('subjectDomain','body','subjectKind','body_region'),
      'stateMatch',jsonb_build_object('functionalState','unknown'),
      'consequenceRole','truth_acquisition',
      'consequenceKind','knowledge_acquisition',
      'actionKey','reassess_condition',
      'priority',50,
      'actionSpec',jsonb_build_object('factNeeded','present functional state')
    )),
    'evidence',jsonb_build_object('conditionObservationId',v_body_observation->>'observationId')
  ));

  if (v_consequence_eval->'evaluation'->>'openCount')::integer <> 1 then
    raise exception 'Explicit matching consequence policy did not create one open consequence';
  end if;

  select count(*)
  into v_count
  from atlas.person_life_consequence_instances i
  where i.definition_id = v_consequence_id
    and i.owner_user_id = v_user_id
    and i.stable_key = 'left-hip-reassess-v1'
    and i.status = 'open'
    and i.carrier_state = 'unresolved'
    and i.placement_state = 'unresolved'
    and i.execution_readiness = 'not_evaluated';

  if v_count <> 1 then
    raise exception 'Consequence persistence collapsed requirement/carrier/readiness/placement boundaries';
  end if;

  -- A later non-match does not prove that an already-established consequence was
  -- satisfied. It stays open until an explicit resolution event arrives.
  v_nonmatch_eval := atlas.record_person_life_state_api_v1(v_consequence_id, jsonb_build_object(
    'sourceKey','fixture-left-hip-consequence-eval-2',
    'eventKind','consequence_evaluation',
    'observedAt','2026-09-01T09:00:00-05:00',
    'snapshot',jsonb_build_object(
      'subjectDomain','body',
      'subjectKind','body_region',
      'subjectId','left_hip',
      'functionalState','clear'
    ),
    'policies',jsonb_build_array(jsonb_build_object(
      'stableKey','left-hip-reassess-v1',
      'subjectSelector',jsonb_build_object('subjectDomain','body','subjectKind','body_region'),
      'stateMatch',jsonb_build_object('functionalState','unknown'),
      'consequenceRole','truth_acquisition',
      'actionKey','reassess_condition',
      'actionSpec','{}'::jsonb
    ))
  ));

  if (v_nonmatch_eval->'evaluation'->>'openCount')::integer <> 0 then
    raise exception 'Nonmatching consequence snapshot should evaluate to zero new matches';
  end if;

  select count(*)
  into v_count
  from atlas.person_life_consequence_instances i
  where i.definition_id = v_consequence_id
    and i.stable_key = 'left-hip-reassess-v1'
    and i.status = 'open';

  if v_count <> 1 then
    raise exception 'Consequence absence must not silently resolve established requirement';
  end if;

  v_resolution := atlas.record_person_life_state_api_v1(v_consequence_id, jsonb_build_object(
    'sourceKey','fixture-left-hip-consequence-resolution-1',
    'eventKind','consequence_resolution',
    'stableKey','left-hip-reassess-v1',
    'resolvedAt','2026-09-01T09:05:00-05:00',
    'evidence',jsonb_build_object('kind','explicit_reassessment_complete')
  ));

  if v_resolution->'evaluation'->>'state' <> 'resolved' then
    raise exception 'Explicit consequence resolution did not persist';
  end if;

  v_state := atlas.person_life_state_api_v1();
  if jsonb_array_length(v_state->'definitions') <> 2 then
    raise exception 'Person-life read membrane should return the persisted Goal and Consequence definitions';
  end if;
  if jsonb_array_length(v_state->'consequenceInstances') <> 1
     or v_state->'consequenceInstances'->0->>'status' <> 'resolved' then
    raise exception 'Person-life read membrane returned wrong consequence projection';
  end if;

  if coalesce((v_state->'truthBoundary'->>'clockPlacementAuthority')::boolean,true)
     or coalesce((v_state->'truthBoundary'->>'practitionerAccessGranted')::boolean,true) then
    raise exception 'Person-life read membrane widened Clock or practitioner authority';
  end if;
end
$$;

rollback;
