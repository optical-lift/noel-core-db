do $validation$
declare
  v_owner_uid constant uuid := 'f1910000-0000-4000-8000-000000000001'::uuid;
  v_other_uid constant uuid := 'f1910000-0000-4000-8000-000000000099'::uuid;
  v_owner_principal constant uuid := 'f1920000-0000-4000-8000-000000000001'::uuid;
  v_other_principal constant uuid := 'f1920000-0000-4000-8000-000000000099'::uuid;
  v_goal_signal jsonb;
  v_rhythm_signal jsonb;
  v_consequence_signal jsonb;
  v_consequence_subject jsonb;
  v_consequence_requirements jsonb;
  v_consequence_claim jsonb;
  v_consequence_claim_id uuid;
  v_goal_id uuid;
  v_rhythm_id uuid;
  v_consequence_id uuid;
  v_index jsonb;
  v_state jsonb;
  v_shell jsonb;
  v_count integer;
begin
  if to_regprocedure('atlas.ensure_person_life_notebook_spread_v1(uuid)') is null then
    raise exception 'Person Life durable spread helper is missing.';
  end if;

  if has_function_privilege('anon','atlas.ensure_person_life_notebook_spread_v1(uuid)','execute')
     or has_function_privilege('authenticated','atlas.ensure_person_life_notebook_spread_v1(uuid)','execute') then
    raise exception 'Person Life durable spread helper became browser-callable.';
  end if;

  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_owner_uid,'life-spread-owner@example.test',now(),now()),
    (v_other_uid,'life-spread-other@example.test',now(),now());

  insert into atlas.principals(
    id,user_id,stable_key,name,home_timezone,status,metadata
  ) values
    (
      v_owner_principal,v_owner_uid,'life-spread-owner:'||v_owner_uid::text,
      'Life Spread Owner','America/Chicago','active','{}'::jsonb
    ),
    (
      v_other_principal,v_other_uid,'life-spread-other:'||v_other_uid::text,
      'Life Spread Other','America/Chicago','active','{}'::jsonb
    );

  perform set_config('request.jwt.claim.sub',v_owner_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_owner_uid::text,'role','authenticated')::text,
    true
  );

  v_goal_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_owner_uid::text),
    'subject',jsonb_build_object('domain','training','kind','training_goal','id','proof-5k'),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Complete a 5K'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object('domain','training','kind','goal_definition','id','proof-5k-goal'),
    'epistemic',jsonb_build_object('factClass','explicit_goal','interpretationAuthority','person')
  );

  v_goal_id := (
    atlas.create_person_life_definition_api_v1(jsonb_build_object(
      'sourceKey','proof-life-goal',
      'signal',v_goal_signal,
      'metadata',jsonb_build_object('proof','person-life-durable-spread-v1')
    ))->>'definitionId'
  )::uuid;

  v_rhythm_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_owner_uid::text),
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

  v_rhythm_id := (
    atlas.create_person_life_definition_api_v1(jsonb_build_object(
      'sourceKey','proof-life-rhythm',
      'signal',v_rhythm_signal,
      'metadata',jsonb_build_object('proof','person-life-durable-spread-v1')
    ))->>'definitionId'
  )::uuid;

  v_consequence_subject := jsonb_build_object(
    'domain','body',
    'kind','body_region',
    'id','left_hip'
  );

  v_consequence_requirements := jsonb_build_array(jsonb_build_object(
    'requirementKey','left-hip-function-truth',
    'requirementKind','truth_acquisition',
    'operationKey','reassess_condition',
    'policy',jsonb_build_object(
      'stableKey','left-hip-reassess-v1',
      'subjectSelector',jsonb_build_object(
        'subjectDomain','body',
        'subjectKind','body_region'
      ),
      'stateMatch',jsonb_build_object('functionalState','unknown'),
      'consequenceRole','truth_acquisition',
      'consequenceKind','knowledge_acquisition',
      'actionKey','reassess_condition',
      'priority',50,
      'actionSpec',jsonb_build_object('factNeeded','present functional state')
    )
  ));

  v_consequence_claim := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey','proof-life-consequence-policy-claim',
    'subject',v_consequence_subject,
    'evidence',jsonb_build_object(
      'kind','person_acceptance',
      'value',jsonb_build_object(
        'accepted',true,
        'policyKey','left-hip-reassess-v1'
      ),
      'observedAt','2026-09-18T08:30:00-05:00',
      'provenance',jsonb_build_object(
        'proof','person-life-durable-spread-v1',
        'authority','explicit_person_acceptance'
      )
    ),
    'claim',jsonb_build_object(
      'claimType','consequence_policy',
      'lifecycleState','accepted',
      'value',jsonb_build_object(
        'signalKind','consequence',
        'subject',v_consequence_subject,
        'requirements',v_consequence_requirements
      ),
      'metadata',jsonb_build_object(
        'proof','person-life-durable-spread-v1'
      )
    )
  ));

  v_consequence_claim_id := (v_consequence_claim->>'claimId')::uuid;
  if v_consequence_claim->>'lifecycleState' <> 'accepted'
     or v_consequence_claim->>'authorityKind' <> 'person_acceptance'
     or v_consequence_claim_id is null then
    raise exception 'Person Consequence proof did not establish accepted consequence_policy Claim authority: %',v_consequence_claim;
  end if;

  v_consequence_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_owner_uid::text),
    'subject',v_consequence_subject,
    'signalKind','consequence',
    'state',jsonb_build_object('reportedState','tight_after_run','functionalState','unknown'),
    'timing','{}'::jsonb,
    'requirements',v_consequence_requirements,
    'constraints','[]'::jsonb,
    'ambiguities',jsonb_build_array('cause_not_established'),
    'relations','[]'::jsonb,
    'source',jsonb_build_object(
      'domain','claim_evidence',
      'kind','claim',
      'id',v_consequence_claim_id::text
    ),
    'epistemic',jsonb_build_object(
      'factClass','explicit_policy',
      'interpretationAuthority','person'
    )
  );

  v_consequence_id := (
    atlas.create_person_life_definition_api_v1(jsonb_build_object(
      'sourceKey','proof-life-consequence',
      'signal',v_consequence_signal,
      'metadata',jsonb_build_object('proof','person-life-durable-spread-v1')
    ))->>'definitionId'
  )::uuid;

  if (
    select count(*)
    from atlas.notebook_spread_instances s
    where s.principal_id=v_owner_principal
      and s.spread_key in (
        'life:'||v_goal_id::text,
        'life:'||v_rhythm_id::text,
        'life:'||v_consequence_id::text
      )
      and s.scope_kind='person'
      and s.scope_id=v_owner_uid::text
      and s.spread_state='open'
  ) <> 3 then
    raise exception 'Active Person Life definitions were not admitted as durable spreads.';
  end if;

  if not exists (
    select 1 from atlas.notebook_spread_instances s
    where s.principal_id=v_owner_principal
      and s.spread_key='life:'||v_goal_id::text
      and s.recipe_key='life-progress'
      and s.composition_contract->'forms'->0->>'formFamily'='free-field'
      and s.composition_contract->'forms'->1->>'formFamily'='path'
  ) then
    raise exception 'Goal did not select the Progress composition.';
  end if;

  if not exists (
    select 1 from atlas.notebook_spread_instances s
    where s.principal_id=v_owner_principal
      and s.spread_key='life:'||v_rhythm_id::text
      and s.recipe_key='life-occurrence'
      and s.composition_contract->'forms'->1->>'formFamily'='timeline'
  ) then
    raise exception 'Rhythm did not select the Occurrence composition.';
  end if;

  if not exists (
    select 1 from atlas.notebook_spread_instances s
    where s.principal_id=v_owner_principal
      and s.spread_key='life:'||v_consequence_id::text
      and s.recipe_key='life-log'
      and s.composition_contract->'forms'->1->>'formFamily'='log'
  ) then
    raise exception 'Consequence did not select the Life Log composition.';
  end if;

  if (
    select count(*)
    from atlas.notebook_spread_source_bindings b
    join atlas.notebook_spread_instances s on s.id=b.spread_instance_id
    where s.principal_id=v_owner_principal
      and b.source_domain='person'
      and b.source_kind='life_definition_v1'
      and b.source_id in (v_goal_id::text,v_rhythm_id::text,v_consequence_id::text)
      and b.binding_state='active'
  ) <> 3 then
    raise exception 'Person Life durable spreads did not retain exact governed source bindings.';
  end if;

  v_index := atlas.atlas_notebook_index_self_api_v1();

  if (
    select count(*)
    from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
    where item->>'spreadKey' in (
      'life:'||v_goal_id::text,
      'life:'||v_rhythm_id::text,
      'life:'||v_consequence_id::text
    )
  ) <> 3 then
    raise exception 'Signed-in owner Index did not expose all active Person Life spreads: %',v_index;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v_index->'items') item
    where item->>'spreadKey'='life:'||v_goal_id::text
      and item->>'recipeKey'='life-progress'
  ) or not exists (
    select 1
    from jsonb_array_elements(v_index->'items') item
    where item->>'spreadKey'='life:'||v_rhythm_id::text
      and item->>'recipeKey'='life-occurrence'
  ) or not exists (
    select 1
    from jsonb_array_elements(v_index->'items') item
    where item->>'spreadKey'='life:'||v_consequence_id::text
      and item->>'recipeKey'='life-log'
  ) then
    raise exception 'Index did not preserve Person Life recipe identity: %',v_index;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1('life:'||v_goal_id::text);
  if v_shell->'spread'->'scope'->>'id' <> v_owner_uid::text
     or v_shell->'sourceBindings'->0->>'sourceId' <> v_goal_id::text then
    raise exception 'Person Life spread shell lost owner or exact definition custody: %',v_shell;
  end if;

  v_state := atlas.person_life_state_api_v1();
  if jsonb_array_length(v_state->'definitions') <> 3
     or v_state->'scope'->>'id' <> v_owner_uid::text then
    raise exception 'Governed Person Life read did not return only owner-scoped definitions: %',v_state;
  end if;

  perform set_config('request.jwt.claim.sub',v_other_uid::text,true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_other_uid::text,'role','authenticated')::text,
    true
  );

  v_index := atlas.atlas_notebook_index_self_api_v1();
  if exists (
    select 1
    from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
    where item->>'spreadKey' in (
      'life:'||v_goal_id::text,
      'life:'||v_rhythm_id::text,
      'life:'||v_consequence_id::text
    )
  ) then
    raise exception 'Another signed-in person saw owner Person Life definitions in Index.';
  end if;

  v_state := atlas.person_life_state_api_v1();
  if jsonb_array_length(v_state->'definitions') <> 0 then
    raise exception 'Another signed-in person received owner Person Life state.';
  end if;

  -- Retiring a definition closes its durable spread while preserving history.
  perform set_config('request.jwt.claim.sub',v_owner_uid::text,true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_owner_uid::text,'role','authenticated')::text,
    true
  );

  update atlas.person_life_definitions
  set status='retired',
      retired_at=now()
  where id=v_consequence_id;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    where s.principal_id=v_owner_principal
      and s.spread_key='life:'||v_consequence_id::text
      and s.spread_state='closed'
  ) then
    raise exception 'Retired Person Life definition did not close its durable spread.';
  end if;
end;
$validation$;
