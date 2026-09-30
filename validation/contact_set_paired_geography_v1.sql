-- Rollback-only acceptance fixture for ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1.

begin;
set local lock_timeout='3s';
set local statement_timeout='45s';

do $fixture$
declare
  v_root uuid:='b425db2d-90da-4519-b03f-34bf4a3c5e95'; -- existing 2oddballs SI business
  v_branch_a uuid:='56000000-0000-4000-8000-000000000001';
  v_branch_b uuid:='56000000-0000-4000-8000-000000000002';
  v_place_a uuid:='56000000-0000-4000-8000-000000000011';
  v_place_b uuid:='56000000-0000-4000-8000-000000000012';
  v_request_ok uuid:='56000000-0000-4000-8000-000000000021';
  v_request_gap uuid:='56000000-0000-4000-8000-000000000022';
  v_prop jsonb;
  v_result jsonb;
  v_validation jsonb;
  v_interp jsonb;
  v_count integer;
begin
  -- New validator: ordinary local search remains valid and paired person-first target fails closed.
  v_interp:=jsonb_build_object(
    'intentFamily','build_target_contact_set','objective','retrieve',
    'target',jsonb_build_object('description','ordinary fixture','organizationKinds','[]'::jsonb,'personFunctions','[]'::jsonb,'titles','[]'::jsonb),
    'geography',jsonb_build_object('placeLabels',jsonb_build_array('Springfield')),
    'fields',jsonb_build_object('required',jsonb_build_array('name')),
    'unresolvedReferences','[]'::jsonb,'resolvedReferences','[]'::jsonb
  );
  v_validation:=atlas.validate_contact_set_intent_v2('ordinary fixture',v_interp);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'Ordinary contact-set validation regressed: %',v_validation; end if;

  v_interp:=jsonb_build_object(
    'intentFamily','build_target_contact_set','objective','retrieve',
    'target',jsonb_build_object('description','invalid paired person-first fixture','organizationKinds','[]'::jsonb,'personFunctions',jsonb_build_array('operations'),'titles','[]'::jsonb),
    'geography',jsonb_build_object('mode','paired_operating_presence','sideA',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('name','Springfield','administrativeHint','MO','countryCode','US','placeKind','locality'))),'sideB',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('name','Lebanon','administrativeHint','MO','countryCode','US','placeKind','locality')))),
    'fields',jsonb_build_object('required',jsonb_build_array('name')),
    'unresolvedReferences','[]'::jsonb,'resolvedReferences','[]'::jsonb
  );
  v_validation:=atlas.validate_contact_set_intent_v2('invalid paired fixture',v_interp);
  if coalesce((v_validation->>'valid')::boolean,true) or not (v_validation->'errors' ? 'paired_operating_presence_v1_requires_organization_first_target') then raise exception 'Paired person-first target must fail structural validation: %',v_validation; end if;

  -- Canonical root is a real Shared Intelligence business admitted only inside the rollback transaction.
  perform atlas.admit_shared_intelligence_entity_to_reality_service_v1(v_root,jsonb_build_object('fixture','contact_set_paired_geography_v1'));
  insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
    (v_branch_a,'fixture:paired-contact:branch-a','business','Fixture branch A','canonical','{}'),
    (v_branch_b,'fixture:paired-contact:branch-b','business','Fixture branch B','canonical','{}'),
    (v_place_a,'fixture:paired-contact:place-a','place','Fixture Place A','canonical','{}'),
    (v_place_b,'fixture:paired-contact:place-b','place','Fixture Place B','canonical','{}');
  perform reality.establish_place_profile_service_v1(v_place_a,'locality','US',null,null,null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'{}'::jsonb);
  perform reality.establish_place_profile_service_v1(v_place_b,'locality','US',null,null,null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'{}'::jsonb);

  v_prop:=reality.record_relationship_proposition_service_v1(v_branch_a,'branch_of',v_root,'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'fixture:paired-contact:branch-a-root');
  perform reality.adjudicate_relationship_proposition_service_v1((v_prop->>'propositionId')::uuid,'accept','fixture',jsonb_build_object('fixture',true),null);
  v_prop:=reality.record_relationship_proposition_service_v1(v_branch_b,'branch_of',v_root,'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'fixture:paired-contact:branch-b-root');
  perform reality.adjudicate_relationship_proposition_service_v1((v_prop->>'propositionId')::uuid,'accept','fixture',jsonb_build_object('fixture',true),null);
  v_prop:=reality.record_relationship_proposition_service_v1(v_branch_a,'located_in',v_place_a,'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'fixture:paired-contact:branch-a-place');
  perform reality.adjudicate_relationship_proposition_service_v1((v_prop->>'propositionId')::uuid,'accept','fixture',jsonb_build_object('fixture',true),null);
  v_prop:=reality.record_relationship_proposition_service_v1(v_branch_b,'located_in',v_place_b,'established',null,null,jsonb_build_object('fixture',true),jsonb_build_object('fixture',true),'fixture:paired-contact:branch-b-place');
  perform reality.adjudicate_relationship_proposition_service_v1((v_prop->>'propositionId')::uuid,'accept','fixture',jsonb_build_object('fixture',true),null);

  -- Fully resolved paired request: same root must qualify exactly once.
  v_interp:=jsonb_build_object(
    'intentFamily','build_target_contact_set','objective','retrieve',
    'target',jsonb_build_object('description','organizations spanning both governed sides','organizationKinds','[]'::jsonb,'namedOrganizations','[]'::jsonb,'personFunctions','[]'::jsonb,'titles','[]'::jsonb),
    'geography',jsonb_build_object('mode','paired_operating_presence','sideA',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('placeEntityId',v_place_a))),'sideB',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('placeEntityId',v_place_b))),'maxOperatingDepth',8,'maxSpatialDepth',8),
    'fields',jsonb_build_object('required',jsonb_build_array('name')),
    'population',jsonb_build_object('desiredCount',1),
    'ledgerEffect',jsonb_build_object('attachToLedger',false),
    'unresolvedReferences','[]'::jsonb,'resolvedReferences','[]'::jsonb
  );
  v_validation:=atlas.validate_contact_set_intent_v2('paired resolved fixture',v_interp);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'Resolved paired interpretation invalid: %',v_validation; end if;
  insert into atlas.contact_set_intent_requests(id,organization_id,organization_unit_id,requested_by_user_id,source_action_id,literal_request,request_state,interpretation,validation,execution_plan,interpreter_kind,interpreter_ref)
  values(v_request_ok,'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','4cd799e2-16d4-4020-9d21-ccf1a2b98553','fixture:paired-resolved','paired resolved fixture','ready',v_interp,v_validation,'{}'::jsonb,'rule','fixture');
  v_result:=atlas.prepare_contact_set_execution_service_v1(v_request_ok);
  if v_result->>'executionState'<>'ready' then raise exception 'Resolved paired execution should be ready: %',v_result; end if;
  if coalesce((v_result#>>'{directory,candidateCount}')::integer,0)<>1 then raise exception 'Resolved paired execution should return exactly one organization: %',v_result; end if;
  if (v_result#>>'{directory,items,0,entityId}')::uuid<>v_root then raise exception 'Paired execution returned wrong operating root.'; end if;
  if v_result#>>'{directory,items,0,qualificationMode}'<>'paired_operating_presence' then raise exception 'Paired qualification receipt missing.'; end if;

  -- Unresolved Place reference must become a geography gap, not an empty/negative population result.
  v_interp:=jsonb_build_object(
    'intentFamily','build_target_contact_set','objective','retrieve',
    'target',jsonb_build_object('description','fixture unresolved paired geography','organizationKinds','[]'::jsonb,'namedOrganizations','[]'::jsonb,'personFunctions','[]'::jsonb,'titles','[]'::jsonb),
    'geography',jsonb_build_object('mode','paired_operating_presence','sideA',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('name','Springfield','administrativeHint','MO','countryCode','US','placeKind','locality'))),'sideB',jsonb_build_object('places',jsonb_build_array(jsonb_build_object('name','Definitely Missing Atlas Fixture Place','administrativeHint','MO','countryCode','US','placeKind','locality')))),
    'fields',jsonb_build_object('required',jsonb_build_array('name')),
    'population',jsonb_build_object('desiredCount',5),
    'ledgerEffect',jsonb_build_object('attachToLedger',false),
    'unresolvedReferences','[]'::jsonb,'resolvedReferences','[]'::jsonb
  );
  v_validation:=atlas.validate_contact_set_intent_v2('paired unresolved fixture',v_interp);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'Unresolved paired reference is structurally valid and should reach acquisition state: %',v_validation; end if;
  insert into atlas.contact_set_intent_requests(id,organization_id,organization_unit_id,requested_by_user_id,source_action_id,literal_request,request_state,interpretation,validation,execution_plan,interpreter_kind,interpreter_ref)
  values(v_request_gap,'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','4cd799e2-16d4-4020-9d21-ccf1a2b98553','fixture:paired-gap','paired unresolved fixture','ready',v_interp,v_validation,'{}'::jsonb,'rule','fixture');
  v_result:=atlas.prepare_contact_set_execution_service_v1(v_request_gap);
  if v_result->>'executionState'<>'needs_acquisition' then raise exception 'Unresolved paired Place should need acquisition: %',v_result; end if;
  if coalesce((v_result#>>'{directory,candidateCount}')::integer,-1)<>0 then raise exception 'Unresolved paired geography must not run candidate qualification.'; end if;
  if not exists(select 1 from jsonb_array_elements(v_result#>'{gaps,researchTargets}') g where g->>'gapKind'='geography_resolution_gap') then raise exception 'Expected geography_resolution_gap missing.'; end if;
  if exists(select 1 from jsonb_array_elements(v_result#>'{gaps,researchTargets}') g where g->>'gapKind' in ('population_gap','paired_operating_presence_gap')) then raise exception 'Unresolved Place must not be misreported as population/topology gap.'; end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_contact_set_paired_geography_validation_v1','status','passed',
  'fixtureRunsInsideTransaction',(select count(*) from atlas.contact_set_execution_runs where request_id in ('56000000-0000-4000-8000-000000000021'::uuid,'56000000-0000-4000-8000-000000000022'::uuid)),
  'fixturePlaceProfilesInsideTransaction',(select count(*) from reality.place_profiles where entity_id in ('56000000-0000-4000-8000-000000000011'::uuid,'56000000-0000-4000-8000-000000000012'::uuid))
) as validation_receipt;

rollback;
