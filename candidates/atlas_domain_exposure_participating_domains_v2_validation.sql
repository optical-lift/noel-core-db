-- Behavioral postconditions for Atlas participating-domain Domain Exposure v2.
-- Requires canonical Person Position, Domain Exposure v1 and Notebook Exposure Admission v1.

do $validation$
declare
  v_household_user constant uuid := 'c1111111-1111-4111-8111-111111111111'::uuid;
  v_flower_user constant uuid := 'c2222222-2222-4222-8222-222222222222'::uuid;
  v_correspondence_user constant uuid := 'c3333333-3333-4333-8333-333333333333'::uuid;

  v_bootstrap jsonb;
  v_position jsonb;
  v_result jsonb;
  v_index jsonb;
  v_address jsonb;
  v_org jsonb;
  v_endpoint jsonb;

  v_household_id uuid;
  v_flower_principal_id uuid;
  v_flower_org_id uuid;
  v_flower_unit_id uuid := gen_random_uuid();
  v_owner_farm_id uuid := gen_random_uuid();
  v_hand_farm_id uuid := gen_random_uuid();

  v_correspondence_principal_id uuid;
  v_correspondence_org_id uuid;
  v_correspondence_membership_id uuid;
  v_endpoint_id uuid;

  v_defs text;
  v_shared_def text;
  v_domain_defs text;
  v_admission_defs text;
  v_count integer;
  v_denied boolean := false;
begin
  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null
     or to_regprocedure('atlas.notebook_index_admitted_self_api_v1()') is null
     or to_regprocedure('atlas.notebook_address_admitted_self_api_v1(text)') is null then
    raise exception 'Participating-domain Exposure v2 requires canonical v1 Exposure and Notebook admission first.';
  end if;

  if to_regprocedure('atlas.household_domain_exposure_self_api_v1()') is null
     or to_regprocedure('atlas.flower_domain_exposure_self_api_v1()') is null
     or to_regprocedure('atlas.correspondence_domain_exposure_self_api_v1()') is null
     or to_regprocedure('atlas.domain_exposure_evaluations_self_api_v2()') is null then
    raise exception 'Participating-domain Exposure v2 candidate functions are missing.';
  end if;

  if has_function_privilege('anon','atlas.household_domain_exposure_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.flower_domain_exposure_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.correspondence_domain_exposure_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.domain_exposure_evaluations_self_api_v2()','EXECUTE') then
    raise exception 'Anonymous role may execute participating-domain Exposure functions.';
  end if;

  select pg_get_functiondef('atlas.domain_exposure_evaluations_self_api_v2()'::regprocedure)
  into v_shared_def;

  if position('domain_exposure_evaluations_self_api_v1' in v_shared_def)=0
     or position('household_domain_exposure_self_api_v1' in v_shared_def)=0
     or position('flower_domain_exposure_self_api_v1' in v_shared_def)=0
     or position('correspondence_domain_exposure_self_api_v1' in v_shared_def)=0 then
    raise exception 'Shared v2 composer does not consume all governed exposure membranes.';
  end if;

  if position('from atlas.' in lower(v_shared_def))>0
     or position('join atlas.' in lower(v_shared_def))>0 then
    raise exception 'Shared v2 composer directly reconstructed domain truth from tables.';
  end if;

  select pg_get_functiondef('atlas.household_domain_exposure_self_api_v1()'::regprocedure)
      || E'\n' || pg_get_functiondef('atlas.flower_domain_exposure_self_api_v1()'::regprocedure)
      || E'\n' || pg_get_functiondef('atlas.correspondence_domain_exposure_self_api_v1()'::regprocedure)
  into v_domain_defs;

  if position('notebook_spread_instances' in lower(v_domain_defs))>0
     or position('notebook_spread_source_bindings' in lower(v_domain_defs))>0
     or position('notebook_spread_instance_self_api' in lower(v_domain_defs))>0 then
    raise exception 'Domain exposure membrane used notebook carrier existence as authority.';
  end if;

  select v_shared_def || E'\n' || v_domain_defs
  into v_defs;

  if position('insert into' in lower(v_defs))>0
     or position('delete from' in lower(v_defs))>0
     or position('update atlas.' in lower(v_defs))>0 then
    raise exception 'Participating-domain Exposure production functions contain durable mutation.';
  end if;

  select pg_get_functiondef('atlas.notebook_index_admitted_self_api_v1()'::regprocedure)
      || E'\n' || pg_get_functiondef('atlas.notebook_address_admitted_self_api_v1(text)'::regprocedure)
  into v_admission_defs;

  if position('domain_exposure_evaluations_self_api_v2' in v_admission_defs)=0 then
    raise exception 'Notebook admission was not retargeted to shared Domain Exposure v2.';
  end if;

  if position('from atlas.farms' in lower(v_admission_defs))>0
     or position('from atlas.communication_endpoints' in lower(v_admission_defs))>0
     or position('from atlas.households' in lower(v_admission_defs))>0 then
    raise exception 'Notebook admission learned domain-specific authority semantics.';
  end if;

  -- Household: active Principal household yields exactly three stable orientations.
  perform set_config('request.jwt.claim.sub',v_household_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_household_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Exposure V2 Household',
    'America/Chicago'
  );
  v_position := atlas.person_position_self_api_v1();
  v_household_id := (
    select (value->>'householdId')::uuid
    from jsonb_array_elements(v_position->'householdContexts')
    where value->>'positionKind'='active_principal_household'
    limit 1
  );

  if v_household_id is null then
    raise exception 'Household proof did not establish active Principal household.';
  end if;

  v_result := atlas.domain_exposure_evaluations_self_api_v2();

  select count(*)::integer into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey' in (
    'household.care_orientation.v1',
    'household.rhythm_orientation.v1',
    'household.laundry_kernel_orientation.v1'
  )
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'disposition'='stable'
    and i.value->'place'->>'desiredCarrierState'='open'
    and i.value->'index'->>'disposition'='listed'
    and i.value->'attentionNomination'->>'disposition'='quiet'
    and i.value->'contextRef'->>'id'=v_household_id::text;

  if v_count<>3 then
    raise exception 'Active household did not emit exactly three stable listed orientations: %',v_result;
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_result->'items') i(value)
    where i.value->'place'->>'durabilityKey'='home-care'
      and i.value->'sourceBinding'->>'governedRead'='atlas.principal_household_care_snapshot_v1'
  ) or not exists (
    select 1 from jsonb_array_elements(v_result->'items') i(value)
    where i.value->'place'->>'durabilityKey'='household-rhythm'
      and i.value->'sourceBinding'->>'governedRead'='public.personal_setup_self_api_v1'
  ) or not exists (
    select 1 from jsonb_array_elements(v_result->'items') i(value)
    where i.value->'place'->>'durabilityKey'='laundry'
      and i.value->'sourceBinding'->>'governedRead'='atlas.personal_laundry_kernel_self_api_v1'
  ) then
    raise exception 'Household exposure did not preserve governed source-read identity: %',v_result;
  end if;

  -- Flower: one owner farm and one farm-hand farm under the same Person.
  perform set_config('request.jwt.claim.sub',v_flower_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_flower_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Exposure V2 Flower',
    'America/Chicago'
  );
  v_flower_principal_id := (v_bootstrap->>'principalId')::uuid;

  v_org := atlas.establish_organization_ledger_self_api_v1(
    'Exposure V2 Flower Organization',
    true,
    false
  );
  v_flower_org_id := (v_org->'organization'->>'id')::uuid;

  insert into atlas.organization_units(
    id,organization_id,stable_key,name,unit_kind,status,metadata
  ) values (
    v_flower_unit_id,v_flower_org_id,'exposure-v2-flower-unit','Exposure V2 Flower Unit',
    'operating_unit','active','{}'::jsonb
  );

  insert into atlas.farms(id,stable_key,name,status,organization_id,organization_unit_id,metadata)
  values
    (v_owner_farm_id,'exposure-v2-owner-farm','Exposure V2 Owner Farm','active',v_flower_org_id,v_flower_unit_id,'{}'::jsonb),
    (v_hand_farm_id,'exposure-v2-hand-farm','Exposure V2 Hand Farm','active',v_flower_org_id,v_flower_unit_id,'{}'::jsonb);

  insert into atlas.farm_memberships(user_id,farm_id,role,active,permissions)
  values
    (v_flower_user,v_owner_farm_id,'owner',true,'{}'::jsonb),
    (v_flower_user,v_hand_farm_id,'farm_hand',true,'{}'::jsonb);

  -- Prove the exposure role law matches the actual governed reads.
  perform atlas.flower_harvest_notebook_self_api_v1(v_owner_farm_id,current_date-1,current_date,10);
  perform atlas.flower_ready_inventory_notebook_self_api_v1(v_owner_farm_id);
  perform atlas.flower_commercial_commitments_notebook_self_api_v1(v_owner_farm_id,current_date-1,current_date);
  perform atlas.flower_harvest_notebook_self_api_v1(v_hand_farm_id,current_date-1,current_date,10);

  v_denied := false;
  begin
    perform atlas.flower_ready_inventory_notebook_self_api_v1(v_hand_farm_id);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Farm hand unexpectedly received Ready inventory source authority.';
  end if;

  v_result := atlas.domain_exposure_evaluations_self_api_v2();

  select count(*)::integer into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->'subjectRef'->>'id'=v_owner_farm_id::text
    and i.value->>'contractKey' in (
      'flower.harvest_orientation.v1',
      'flower.ready_inventory_orientation.v1',
      'flower.commercial_commitments_orientation.v1'
    )
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'index'->>'disposition'='listed'
    and i.value->'contextRef'->>'kind'='organization_unit'
    and i.value->'contextRef'->>'id'=v_flower_unit_id::text;

  if v_count<>3 then
    raise exception 'Flower owner did not receive all three Organization Unit-scoped exposures: %',v_result;
  end if;

  select count(*)::integer into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->'subjectRef'->>'id'=v_hand_farm_id::text
    and i.value->>'contractKey'='flower.harvest_orientation.v1'
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'index'->>'disposition'='listed';

  if v_count<>1 then
    raise exception 'Farm hand did not receive Harvest exposure: %',v_result;
  end if;

  select count(*)::integer into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->'subjectRef'->>'id'=v_hand_farm_id::text
    and i.value->>'contractKey' in (
      'flower.ready_inventory_orientation.v1',
      'flower.commercial_commitments_orientation.v1'
    )
    and i.value->'encounter'->>'state'='ineligible'
    and i.value->'index'->>'disposition'='absent'
    and jsonb_typeof(i.value->'sourceBinding')='null';

  if v_count<>2 then
    raise exception 'Farm hand silently gained commercial notebook exposure: %',v_result;
  end if;

  -- Seed one owner Flower carrier and prove the generic admitted Index sees it via v2.
  perform atlas.set_notebook_spread_instance_v2(
    v_flower_principal_id,
    'flower-harvest:'||v_owner_farm_id::text,
    'organization_unit',
    v_flower_unit_id::text,
    'flower',
    'harvest',
    v_owner_farm_id::text,
    'flower-harvest',
    'current',
    'flower-harvest:'||v_owner_farm_id::text,
    'Exposure V2 Harvest',
    'Flower Operations',
    null,
    'resolved',
    'open',
    '{}'::jsonb,
    jsonb_build_object('proof','existing_carrier_for_v2_admission'),
    jsonb_build_object('validationOnly',true)
  );

  v_index := atlas.notebook_index_admitted_self_api_v1();

  if not exists (
    select 1 from jsonb_array_elements(v_index->'items') i(value)
    where i.value->>'spreadKey'='flower-harvest:'||v_owner_farm_id::text
  ) then
    raise exception 'Generic admitted Index did not consume Flower exposure v2: %',v_index;
  end if;

  v_address := atlas.notebook_address_admitted_self_api_v1(
    'flower-harvest:'||v_owner_farm_id::text
  );
  if v_address->>'state'<>'listed'
     or v_address->'spread'->'scope'->>'kind'<>'organization_unit' then
    raise exception 'Direct admitted Flower address did not preserve Organization Unit scope: %',v_address;
  end if;

  -- Correspondence: real endpoint creation/grant path, then revoke view.
  perform set_config('request.jwt.claim.sub',v_correspondence_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_correspondence_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Exposure V2 Correspondence',
    'America/Chicago'
  );
  v_correspondence_principal_id := (v_bootstrap->>'principalId')::uuid;

  v_org := atlas.establish_organization_ledger_self_api_v1(
    'Exposure V2 Correspondence Organization',
    true,
    false
  );
  v_correspondence_org_id := (v_org->'organization'->>'id')::uuid;
  v_correspondence_membership_id := (v_org->'membership'->>'id')::uuid;

  v_endpoint := atlas.upsert_communication_endpoint_self_api_v1(
    v_correspondence_org_id,
    null,
    'email',
    'exposure-v2-correspondence@example.test',
    'Exposure V2 Correspondence',
    '{}'::jsonb
  );
  v_endpoint_id := (v_endpoint->>'communicationEndpointId')::uuid;

  perform atlas.organization_correspondence_list_self_api_v4(
    v_correspondence_org_id,
    v_endpoint_id,
    10
  );

  v_result := atlas.domain_exposure_evaluations_self_api_v2();

  select count(*)::integer into v_count
  from jsonb_array_elements(v_result->'items') i(value)
  where i.value->>'contractKey'='communication.correspondence_endpoint_view.v1'
    and i.value->'subjectRef'->>'id'=v_endpoint_id::text
    and i.value->'encounter'->>'state'='eligible'
    and i.value->'place'->>'durabilityKey'='letters:'||v_endpoint_id::text
    and i.value->'contextRef'->>'id'=v_correspondence_org_id::text
    and i.value->'sourceBinding'->>'governedRead'='atlas.organization_correspondence_list_self_api_v4';

  if v_count<>1 then
    raise exception 'View-authorized endpoint did not emit Correspondence exposure: %',v_result;
  end if;

  perform atlas.set_notebook_spread_instance_v2(
    v_correspondence_principal_id,
    'letters:'||v_endpoint_id::text,
    'organization',
    v_correspondence_org_id::text,
    'communication',
    'correspondence',
    v_endpoint_id::text,
    'correspondence',
    'current',
    'letters:'||v_endpoint_id::text,
    'Exposure V2 Correspondence',
    'Correspondence',
    null,
    'resolved',
    'open',
    '{}'::jsonb,
    jsonb_build_object('proof','existing_carrier_for_v2_admission'),
    jsonb_build_object('validationOnly',true)
  );

  v_index := atlas.notebook_index_admitted_self_api_v1();
  if not exists (
    select 1 from jsonb_array_elements(v_index->'items') i(value)
    where i.value->>'spreadKey'='letters:'||v_endpoint_id::text
  ) then
    raise exception 'Generic admitted Index did not consume Correspondence exposure v2: %',v_index;
  end if;

  update atlas.communication_endpoint_member_grants
  set grant_state='revoked',
      revoked_at=now(),
      updated_at=now()
  where communication_endpoint_id=v_endpoint_id
    and membership_id=v_correspondence_membership_id
    and capability='view'
    and grant_state='active';

  if atlas.communication_endpoint_authorized_self_v1(v_endpoint_id,'view') then
    raise exception 'Correspondence proof failed to revoke endpoint view authority.';
  end if;

  v_result := atlas.domain_exposure_evaluations_self_api_v2();
  if exists (
    select 1 from jsonb_array_elements(v_result->'items') i(value)
    where i.value->>'contractKey'='communication.correspondence_endpoint_view.v1'
      and i.value->'subjectRef'->>'id'=v_endpoint_id::text
  ) then
    raise exception 'Correspondence remained exposed after endpoint view authority was revoked: %',v_result;
  end if;

  v_index := atlas.notebook_index_admitted_self_api_v1();
  if exists (
    select 1 from jsonb_array_elements(v_index->'items') i(value)
    where i.value->>'spreadKey'='letters:'||v_endpoint_id::text
  ) then
    raise exception 'Durable Correspondence carrier became knowledge authority after view revocation: %',v_index;
  end if;

  v_denied := false;
  begin
    perform atlas.notebook_address_admitted_self_api_v1('letters:'||v_endpoint_id::text);
  exception when sqlstate 'P0002' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Direct Correspondence address remained resolvable after view revocation.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_result->'items') i(value)
    where i.value->'attentionNomination'->>'disposition'='eligible'
       or coalesce((i.value->'truthBoundary'->>'todayPlacementAuthorized')::boolean,false)
  ) then
    raise exception 'Participating-domain Exposure widened attention or Today authority.';
  end if;

  if coalesce((v_result->'truthBoundary'->>'tableBlindSharedComposer')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'carrierExistenceIsNotKnowledgeAuthority')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'actionAuthorityGranted')::boolean,true) is not false then
    raise exception 'Shared v2 truth boundary is incomplete: %',v_result->'truthBoundary';
  end if;
end;
$validation$;
