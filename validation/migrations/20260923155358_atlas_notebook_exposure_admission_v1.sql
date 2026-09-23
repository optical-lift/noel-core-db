-- Behavioral postconditions for Atlas Notebook Exposure Admission v1.
-- Requires canonical Person Position + Domain Exposure Evaluator v1.

do $validation$
declare
  v_life_user constant uuid := 'b1111111-1111-4111-8111-111111111111'::uuid;
  v_ledger_user constant uuid := 'b2222222-2222-4222-8222-222222222222'::uuid;
  v_bootstrap jsonb;
  v_signal jsonb;
  v_create jsonb;
  v_definition_id uuid;
  v_org jsonb;
  v_owner_org_id uuid;
  v_member_org_id uuid;
  v_member_membership_id uuid;
  v_index jsonb;
  v_address jsonb;
  v_raw jsonb;
  v_def text;
  v_count integer;
  v_hidden_key text;
  v_failed_closed boolean := false;
begin
  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    raise exception 'Notebook admission proof requires canonical Person Position.';
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null then
    raise exception 'Notebook admission proof requires canonical Domain Exposure evaluator.';
  end if;

  if to_regprocedure('atlas.notebook_index_admitted_self_api_v1()') is null
     or to_regprocedure('atlas.notebook_address_admitted_self_api_v1(text)') is null then
    raise exception 'Notebook exposure admission candidate functions are missing.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.notebook_index_admitted_self_api_v1()',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.notebook_address_admitted_self_api_v1(text)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role may execute admitted notebook reads.';
  end if;

  select pg_get_functiondef(
    'atlas.notebook_index_admitted_self_api_v1()'::regprocedure
  ) || E'\n' || pg_get_functiondef(
    'atlas.notebook_address_admitted_self_api_v1(text)'::regprocedure
  )
  into v_def;

  if position('insert into' in lower(v_def))>0
     or position('delete from' in lower(v_def))>0
     or position('update atlas.' in lower(v_def))>0 then
    raise exception 'Notebook admission reads contain a durable mutation path.';
  end if;

  if position('domain_exposure_evaluations_self_api_v1' in v_def)=0 then
    raise exception 'Notebook admission reads do not consume Domain Exposure.';
  end if;

  if position('from atlas.organization_memberships' in lower(v_def))>0
     or position('from atlas.principal_ledger_authorities' in lower(v_def))>0
     or position('from atlas.person_life_definitions' in lower(v_def))>0
     or position('from atlas.principals' in lower(v_def))>0 then
    raise exception 'Notebook admission re-derived upstream authority from raw domain tables.';
  end if;

  if position('not in (''listed'',''quiet'')' in lower(v_def))=0
     or position('index''->>''disposition'' <> ''listed''' in lower(v_def))=0 then
    raise exception 'Listed/quiet direct-address versus listed-only Index semantics are not encoded.';
  end if;

  -- Person Life + Connections positive proof.
  perform set_config('request.jwt.claim.sub',v_life_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_life_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Notebook Admission Life',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null then
    raise exception 'Life notebook-admission proof did not establish Principal.';
  end if;

  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_life_user::text),
    'subject',jsonb_build_object(
      'domain','proof',
      'kind','goal',
      'id','notebook-admission-goal'
    ),
    'signalKind','goal',
    'state',jsonb_build_object('explicitUserEnd','Prove notebook admission'),
    'timing','{}'::jsonb,
    'requirements','[]'::jsonb,
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object(
      'domain','proof',
      'kind','goal_definition',
      'id','notebook-admission-goal'
    ),
    'epistemic',jsonb_build_object(
      'factClass','explicit_goal',
      'interpretationAuthority','person'
    )
  );

  v_create := atlas.create_person_life_definition_api_v1(
    jsonb_build_object(
      'sourceKey','notebook-admission-goal',
      'signal',v_signal
    )
  );
  v_definition_id := (v_create->>'definitionId')::uuid;

  -- Exposure and admission must never manufacture notebook carriers. Establish
  -- the already-existing durable carrier explicitly so this proof tests only
  -- the Person-relative encounter/admission decision over canonical truth.
  perform atlas.set_notebook_spread_instance_v2(
    (v_bootstrap->>'principalId')::uuid,
    'life:'||v_definition_id::text,
    'person',
    v_life_user::text,
    'person',
    'life_definition',
    v_definition_id::text,
    'person-life-definition',
    'current',
    'life:'||v_definition_id::text,
    'Notebook Admission Life',
    'Life',
    null,
    'resolved',
    'open',
    '{}'::jsonb,
    jsonb_build_object(
      'proof','existing_carrier_for_admission',
      'definitionId',v_definition_id
    ),
    jsonb_build_object('validationOnly',true)
  );

  v_index := atlas.notebook_index_admitted_self_api_v1();

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_index->'items') i(value)
  where i.value->>'spreadKey'='life:'||v_definition_id::text;

  if v_count<>1 then
    raise exception 'Active Person Life spread was not listed by admitted Index: %',v_index;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_index->'items') i(value)
  where i.value->>'spreadKey'='connections';

  if v_count<>1 then
    raise exception 'Connections was not listed by admitted Index: %',v_index;
  end if;

  v_address := atlas.notebook_address_admitted_self_api_v1(
    'life:'||v_definition_id::text
  );

  if v_address->>'state'<>'listed'
     or v_address->'spread'->>'spreadKey'<>'life:'||v_definition_id::text
     or v_address->>'sourceRead'<>'atlas.person_life_state_api_v1' then
    raise exception 'Active Person Life direct address did not resolve through Exposure: %',v_address;
  end if;

  -- Organization Ledger positive + durable-carrier negative proof.
  perform set_config('request.jwt.claim.sub',v_ledger_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_ledger_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Notebook Admission Ledger',
    'America/Chicago'
  );

  v_org := atlas.establish_organization_ledger_self_api_v1(
    'Notebook Admission Owner Org',
    true,
    false
  );
  v_owner_org_id := (v_org->'organization'->>'id')::uuid;

  perform atlas.set_notebook_spread_instance_v2(
    (v_bootstrap->>'principalId')::uuid,
    'ledger:'||v_owner_org_id::text,
    'organization',
    v_owner_org_id::text,
    'organization',
    'organization_ledger',
    v_owner_org_id::text,
    'recent-ledger-orientation',
    'rolling-30-days',
    'thread:organization-ledger:'||v_owner_org_id::text,
    coalesce(v_org->'organization'->>'name','Notebook Admission Owner Org'),
    'Organizations',
    null,
    'resolved',
    'open',
    '{}'::jsonb,
    jsonb_build_object(
      'proof','existing_carrier_for_admission',
      'organizationId',v_owner_org_id
    ),
    jsonb_build_object('validationOnly',true)
  );

  v_org := atlas.establish_organization_ledger_self_api_v1(
    'Notebook Admission Member Org',
    true,
    false
  );
  v_member_org_id := (v_org->'organization'->>'id')::uuid;
  v_member_membership_id := (v_org->'membership'->>'id')::uuid;
  v_hidden_key := 'ledger:'||v_member_org_id::text;

  perform atlas.set_notebook_spread_instance_v2(
    (v_bootstrap->>'principalId')::uuid,
    v_hidden_key,
    'organization',
    v_member_org_id::text,
    'organization',
    'organization_ledger',
    v_member_org_id::text,
    'recent-ledger-orientation',
    'rolling-30-days',
    'thread:organization-ledger:'||v_member_org_id::text,
    coalesce(v_org->'organization'->>'name','Notebook Admission Member Org'),
    'Organizations',
    null,
    'resolved',
    'open',
    '{}'::jsonb,
    jsonb_build_object(
      'proof','existing_carrier_for_admission',
      'organizationId',v_member_org_id
    ),
    jsonb_build_object('validationOnly',true)
  );

  -- Prove the durable carrier really exists before removing exposure.
  v_raw := atlas.notebook_spread_instance_self_api_v1(v_hidden_key);
  if v_raw->'spread'->>'spreadKey'<>v_hidden_key then
    raise exception 'Expected transitional Ledger carrier was not established.';
  end if;

  update atlas.organization_memberships
  set role='member'
  where id=v_member_membership_id
    and organization_id=v_member_org_id;

  v_index := atlas.notebook_index_admitted_self_api_v1();

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_index->'items') i(value)
  where i.value->>'spreadKey'='ledger:'||v_owner_org_id::text;

  if v_count<>1 then
    raise exception 'Current owner Ledger was not listed: %',v_index;
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(v_index->'items') i(value)
  where i.value->>'spreadKey'=v_hidden_key;

  if v_count<>0 then
    raise exception 'Former owner Ledger remained advertised after exposure loss: %',v_index;
  end if;

  begin
    perform atlas.notebook_address_admitted_self_api_v1(v_hidden_key);
  exception
    when sqlstate 'P0002' then
      v_failed_closed := true;
  end;

  if not v_failed_closed then
    raise exception 'Former owner Ledger remained directly resolvable because its carrier still exists.';
  end if;

  -- Raw reader remains transitional and intentionally still sees the carrier.
  v_raw := atlas.notebook_spread_instance_self_api_v1(v_hidden_key);
  if v_raw->'spread'->>'spreadKey'<>v_hidden_key then
    raise exception 'Raw-reader retirement specimen no longer proves the bypass carrier.';
  end if;

  v_address := atlas.notebook_address_admitted_self_api_v1(
    'ledger:'||v_owner_org_id::text
  );

  if v_address->>'state'<>'listed'
     or v_address->'spread'->>'spreadKey'<>'ledger:'||v_owner_org_id::text
     or v_address->>'sourceRead'<>'atlas.organization_ledger_owner_recent_api_v1' then
    raise exception 'Current owner Ledger direct address did not resolve through Exposure: %',v_address;
  end if;

  if coalesce((v_index->'truthBoundary'->>'indexDoesNotGrantSourceAuthority')::boolean,false) is not true
     or coalesce((v_address->'truthBoundary'->>'addressAdmissionDoesNotGrantSourceAuthority')::boolean,false) is not true then
    raise exception 'Notebook admission widened source authority.';
  end if;
end;
$validation$;
