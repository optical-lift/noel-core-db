-- Behavioral postconditions for Atlas Domain Exposure Evaluator v1.
-- Requires the Person Position dependency to exist in the receiving clone.

do $validation$
declare
  v_user_life constant uuid := 'a1111111-1111-4111-8111-111111111111'::uuid;
  v_user_ledger constant uuid := 'a2222222-2222-4222-8222-222222222222'::uuid;
  v_user_no_person constant uuid := 'a3333333-3333-4333-8333-333333333333'::uuid;

  v_bootstrap jsonb;
  v_result jsonb;
  v_goal_signal jsonb;
  v_goal_create jsonb;
  v_active_definition_id uuid;
  v_retired_definition_id uuid;
  v_org_result jsonb;
  v_owner_org_id uuid;
  v_member_org_id uuid;
  v_member_membership_id uuid;
  v_def text;
  v_count integer;
begin
  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    raise exception 'Domain Exposure evaluator requires canonical Person Position first.';
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null then
    raise exception 'Domain Exposure evaluator candidate is missing.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.domain_exposure_evaluations_self_api_v1()',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role may execute Domain Exposure evaluator.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.domain_exposure_evaluations_self_api_v1()',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Domain Exposure evaluator.';
  end if;

  select pg_get_functiondef(
    'atlas.domain_exposure_evaluations_self_api_v1()'::regprocedure
  )
  into v_def;

  if position('insert into' in lower(v_def))>0
     or position('delete from' in lower(v_def))>0
     or position('update atlas.' in lower(v_def))>0 then
    raise exception 'Domain Exposure evaluator contains a durable mutation path.';
  end if;

  if position('person_position_self_api_v1' in v_def)=0
     or position('person_life_state_api_v1' in v_def)=0 then
    raise exception 'Domain Exposure evaluator does not consume required governed reads.';
  end if;

  if position('from atlas.people' in lower(v_def))>0
     or position('from atlas.principals' in lower(v_def))>0
     or position('from atlas.organization_memberships' in lower(v_def))>0
     or position('from atlas.principal_ledger_authorities' in lower(v_def))>0
     or position('from atlas.person_life_definitions' in lower(v_def))>0
     or position('from atlas.connected_sources' in lower(v_def))>0
     or position('from atlas.notebook_spread_instances' in lower(v_def))>0 then
    raise exception 'Shared exposure evaluator reconstructed domain truth from raw tables.';
  end if;

  -- Credential alone may not become Person or exposure.
  perform set_config('request.jwt.claim.sub',v_user_no_person::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_no_person::text,'role','authenticated')::text,
    true
  );

  v_result := atlas.domain_exposure_evaluations_self_api_v1();

  if v_result->>'state' <> 'person_required'
     or jsonb_array_length(coalesce(v_result->'items','[]'::jsonb)) <> 0 then
    raise exception 'Credential without canonical Person received exposure: %',v_result;
  end if;

  -- Personal / Principal + active and retired Life definitions + Connections.
  perform set_config('request.jwt.claim.sub',v_user_life::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_life::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Domain Exposure Life',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null then
    raise exception 'Life exposure proof did not establish Principal.';
  end if;

  v_goal_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_life::text),
    'subject',jsonb_build_object(
      'domain','proof',
      'kind','goal',
      'id','domain-exposure-active'
    ),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Preserve active proof'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object(
      'domain','proof',
      'kind','goal_definition',
      'id','domain-exposure-active'
    ),
    'epistemic',jsonb_build_object(
      'factClass','explicit_goal',
      'interpretationAuthority','person'
    )
  );

  v_goal_create := atlas.create_person_life_definition_api_v1(
    jsonb_build_object(
      'sourceKey','domain-exposure-active-goal',
      'signal',v_goal_signal
    )
  );
  v_active_definition_id := (v_goal_create->>'definitionId')::uuid;

  v_goal_signal := jsonb_set(
    jsonb_set(
      v_goal_signal,
      '{subject,id}',
      to_jsonb('domain-exposure-retired'::text),
      false
    ),
    '{source,id}',
    to_jsonb('domain-exposure-retired'::text),
    false
  );

  v_goal_create := atlas.create_person_life_definition_api_v1(
    jsonb_build_object(
      'sourceKey','domain-exposure-retired-goal',
      'signal',v_goal_signal
    )
  );
  v_retired_definition_id := (v_goal_create->>'definitionId')::uuid;

  update atlas.person_life_definitions
  set status='retired',
      retired_at=now()
  where id=v_retired_definition_id
    and owner_user_id=v_user_life;

  v_result := atlas.domain_exposure_evaluations_self_api_v1();

  if v_result->>'state' <> 'ready'
     or coalesce((v_result->'truthBoundary'->>'personPositionConsumed')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'todayPlacementAuthorized')::boolean,true) is not false
     or coalesce((v_result->'truthBoundary'->>'actionAuthorityGranted')::boolean,true) is not false then
    raise exception 'Domain Exposure evaluator widened its shared authority: %',v_result;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='person.life_definition.v1'
    and i.value->'subjectRef'->>'id'=v_active_definition_id::text
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'disposition'='stable'
    and i.value->'place'->>'desiredCarrierState'='open'
    and i.value->'index'->>'disposition'='listed'
    and i.value->'attentionNomination'->>'disposition'='quiet';

  if v_count<>1 then
    raise exception 'Active Person Life definition did not emit stable/open/listed exposure: %',v_result;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='person.life_definition.v1'
    and i.value->'subjectRef'->>'id'=v_retired_definition_id::text
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'disposition'='stable'
    and i.value->'place'->>'desiredCarrierState'='closed'
    and i.value->'index'->>'disposition'='listed'
    and i.value->'attentionNomination'->>'disposition'='quiet';

  if v_count<>1 then
    raise exception 'Retired Person Life definition lost durable closed retrievability: %',v_result;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='principal.connections_orientation.v1'
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'durabilityKey'='connections'
    and i.value->'sourceBinding'->>'governedRead'='atlas.connected_sources_self_api_v1'
    and i.value->'attentionNomination'->>'disposition'='quiet';

  if v_count<>1 then
    raise exception 'Active Principal did not receive exactly one quiet Connections orientation: %',v_result;
  end if;

  -- One owner Organization and one downgraded ordinary-membership Organization.
  perform set_config('request.jwt.claim.sub',v_user_ledger::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_ledger::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Domain Exposure Ledger',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null then
    raise exception 'Ledger exposure proof did not establish Principal.';
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Domain Exposure Owner Organization',
    true,
    false
  );
  v_owner_org_id := (v_org_result->'organization'->>'id')::uuid;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Domain Exposure Member Organization',
    true,
    false
  );
  v_member_org_id := (v_org_result->'organization'->>'id')::uuid;
  v_member_membership_id := (v_org_result->'membership'->>'id')::uuid;

  update atlas.organization_memberships
  set role='member'
  where id=v_member_membership_id
    and organization_id=v_member_org_id;

  v_result := atlas.domain_exposure_evaluations_self_api_v1();

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='organization.ledger_owner_compatibility.v1'
    and i.value->'subjectRef'->>'id'=v_owner_org_id::text
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'desiredCarrierState'='open'
    and i.value->'index'->>'disposition'='listed'
    and i.value->'sourceBinding'->>'sourceId'=v_owner_org_id::text;

  if v_count<>1 then
    raise exception 'Owner + root Ledger context did not emit Ledger exposure: %',v_result;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='organization.ledger_owner_compatibility.v1'
    and i.value->'subjectRef'->>'id'=v_member_org_id::text
    and i.value->'encounter'->>'state'='ineligible'
    and i.value->'place'->>'disposition'='none'
    and i.value->'index'->>'disposition'='absent'
    and jsonb_typeof(i.value->'sourceBinding')='null';

  if v_count<>1 then
    raise exception 'Ordinary membership silently became Ledger exposure: %',v_result;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_result->'items') i(value)
    where i.value->'attentionNomination'->>'disposition'='eligible'
  ) then
    raise exception 'V1 Domain Exposure evaluator nominated current attention without domain attention law.';
  end if;
end;
$validation$;
