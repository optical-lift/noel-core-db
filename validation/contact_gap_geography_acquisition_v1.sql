-- Rollback-only acceptance fixture for geography_resolution_gap acquisition and promotion.

begin;
set local lock_timeout='3s';
set local statement_timeout='45s';

do $fixture$
declare
  v_request_id uuid:='57000000-0000-4000-8000-000000000001';
  v_interp jsonb;
  v_validation jsonb;
  v_prepare jsonb;
  v_run_id uuid;
  v_gap jsonb;
  v_queue jsonb;
  v_work_id uuid;
  v_record jsonb;
  v_candidate_id uuid;
  v_promote jsonb;
  v_entity_id uuid;
  v_resolve jsonb;
  v_refresh jsonb;
  v_count integer;
begin
  v_interp:=jsonb_build_object(
    'intentFamily','build_target_contact_set','objective','retrieve',
    'target',jsonb_build_object(
      'description','fixture organizations spanning two governed Places',
      'organizationKinds','[]'::jsonb,'namedOrganizations','[]'::jsonb,
      'personFunctions','[]'::jsonb,'titles','[]'::jsonb
    ),
    'geography',jsonb_build_object(
      'mode','paired_operating_presence',
      'sideA',jsonb_build_object('places',jsonb_build_array(
        jsonb_build_object('name','Springfield','administrativeHint','MO','countryCode','US','placeKind','locality')
      )),
      'sideB',jsonb_build_object('places',jsonb_build_array(
        jsonb_build_object('name','Atlas Fixture City QZ','administrativeHint','MO','countryCode','US','placeKind','locality')
      ))
    ),
    'fields',jsonb_build_object('required',jsonb_build_array('name')),
    'ledgerEffect',jsonb_build_object('attachToLedger',false),
    'unresolvedReferences','[]'::jsonb,'resolvedReferences','[]'::jsonb
  );

  v_validation:=atlas.validate_contact_set_intent_v2('fixture geography acquisition',v_interp);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'Fixture interpretation invalid: %',v_validation;
  end if;

  insert into atlas.contact_set_intent_requests(
    id,organization_id,organization_unit_id,requested_by_user_id,source_action_id,
    literal_request,request_state,interpretation,validation,execution_plan,interpreter_kind,interpreter_ref
  ) values (
    v_request_id,'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2','1b65ac99-0f00-4ca2-9488-e8539cae2a1b',
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553','fixture:geography-acquisition',
    'fixture geography acquisition','ready',v_interp,v_validation,'{}'::jsonb,'rule','fixture'
  );

  v_prepare:=atlas.prepare_contact_set_execution_service_v1(v_request_id);
  if v_prepare->>'executionState'<>'needs_acquisition' then
    raise exception 'Missing Place must require acquisition: %',v_prepare;
  end if;
  v_run_id:=(v_prepare->>'runId')::uuid;

  select value into v_gap
  from jsonb_array_elements(v_prepare#>'{gaps,researchTargets}')
  where value->>'gapKind'='geography_resolution_gap'
    and value->>'side'='B'
  limit 1;
  if v_gap is null then raise exception 'Expected side-B geography_resolution_gap missing.'; end if;

  v_queue:=atlas.queue_contact_gap_acquisition_service_v1(v_run_id,v_gap);
  if v_queue->>'subjectKind'<>'place' or v_queue->>'gapKind'<>'geography_resolution_gap' then
    raise exception 'Geography gap did not route to bounded Place research: %',v_queue;
  end if;
  v_work_id:=(v_queue->>'discoveryWorkId')::uuid;

  v_record:=atlas.record_contact_gap_acquisition_service_v1(
    v_run_id,v_work_id,
    jsonb_build_object(
      'providerKey','validation_fixture','providerResponseId','fixture-geography-response-1',
      'outcome','evidence_found',
      'sources',jsonb_build_array(jsonb_build_object(
        'url','https://example.gov/atlas-fixture-city-qz',
        'sourceKind','geography_reference','publisher','Fixture Geography Authority',
        'title','Atlas Fixture City QZ official geography record'
      )),
      'findings',jsonb_build_array(jsonb_build_object(
        'sourceUrl','https://example.gov/atlas-fixture-city-qz',
        'subjectKind','place','sourceRecordKey','fixture-city-qz',
        'observedName','Atlas Fixture City QZ',
        'fields',jsonb_build_object(
          'name','Atlas Fixture City QZ','state','MO','countryCode','US','areaType','locality',
          'sourceIdentityNamespace','fixture.geography','sourceIdentityKey','atlas-fixture-city-qz',
          'centroidLatitude','37.1234','centroidLongitude','-92.1234','centroidPrecision','fixture'
        )
      ))
    )
  );
  if v_record#>>'{resultSummary,outcome}'<>'evidence_found' then
    raise exception 'Place acquisition result was not recorded: %',v_record;
  end if;
  v_candidate_id:=nullif(v_record#>>'{resultSummary,ingestionResults,0,ingestResult,ingestion_candidate_id}','')::uuid;
  if v_candidate_id is null then raise exception 'Place research did not create an ingestion candidate.'; end if;
  if not exists(
    select 1 from local_intel.entity_ingestion_candidates
    where id=v_candidate_id and proposed_entity_type='place' and review_state in ('pending','needs_review')
  ) then raise exception 'Place ingestion candidate is missing or prematurely promoted.'; end if;

  select count(*)::integer into v_count
  from local_intel.geographic_areas
  where lower(name)=lower('Atlas Fixture City QZ') and upper(coalesce(state,''))='MO';
  if v_count<>0 then raise exception 'Research recording must not create canonical Shared Intelligence geography before promotion.'; end if;
  if exists(select 1 from reality.entities where display_name='Atlas Fixture City QZ' and entity_kind='place') then
    raise exception 'Research recording must not create canonical Reality Place before promotion.';
  end if;

  v_promote:=atlas.promote_place_ingestion_candidate_to_reality_service_v1(
    v_candidate_id,jsonb_build_object('fixture','contact_gap_geography_acquisition_v1')
  );
  if v_promote->>'state'<>'promoted' then raise exception 'Place candidate promotion failed: %',v_promote; end if;
  v_entity_id:=(v_promote->>'entityId')::uuid;
  if not exists(
    select 1 from reality.place_identity_keys
    where entity_id=v_entity_id and identity_state='active'
      and identity_namespace='fixture.geography' and identity_key='atlas-fixture-city-qz'
  ) then raise exception 'Promoted Place is missing authoritative source identity key.'; end if;

  v_resolve:=atlas.resolve_or_admit_place_reference_service_v1(
    jsonb_build_object('name','Atlas Fixture City QZ','administrativeHint','MO','countryCode','US','placeKind','locality')
  );
  if v_resolve->>'state'<>'resolved' or (v_resolve->>'entityId')::uuid<>v_entity_id then
    raise exception 'Promoted Place did not resolve through the ordinary paired Place resolver: %',v_resolve;
  end if;

  v_refresh:=atlas.refresh_contact_set_execution_after_acquisition_service_v1(v_run_id);
  if v_refresh#>>'{directory,contractVersion}'='shared_directory_paired_operating_presence_pending_geography_v1' then
    raise exception 'Refresh remained stuck in pending geography after Place promotion.';
  end if;
  if exists(
    select 1 from jsonb_array_elements(coalesce(v_refresh#>'{gaps,researchTargets}','[]'::jsonb)) g
    where g->>'gapKind'='geography_resolution_gap'
  ) then raise exception 'Promoted Place geography gap survived refresh.'; end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','atlas_contact_gap_geography_acquisition_validation_v1',
  'status','passed',
  'fixtureCandidatesInsideTransaction',(select count(*) from local_intel.entity_ingestion_candidates where proposed_name='Atlas Fixture City QZ'),
  'fixtureGeographiesInsideTransaction',(select count(*) from local_intel.geographic_areas where name='Atlas Fixture City QZ'),
  'fixturePlacesInsideTransaction',(select count(*) from reality.entities where display_name='Atlas Fixture City QZ' and entity_kind='place')
) as validation_receipt;

rollback;
