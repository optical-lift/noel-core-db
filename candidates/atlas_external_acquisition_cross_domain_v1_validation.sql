begin;

do $validation$
declare
  v_org_id uuid;
  v_supplier_subject_id uuid;
  v_supplier_relationship_id uuid;
  v_offering_id uuid;
  v_requirement_id uuid;
  v_result jsonb;
  v_commitment_id uuid;
  v_coverage jsonb;
  v_fact jsonb;
  v_position jsonb;
  v_before_spend bigint;
  v_before_inventory bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_acquisition_service_v1',
    'Fixture Service Acquisition Organization',
    'active',
    '{"fixture":"atlas_external_acquisition_cross_domain_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(v_org_id,'{"fixture":"subcontractor"}'::jsonb)
  returning id into v_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,v_supplier_subject_id,'fixture-subcontractor','active',
    '{"fixture":"atlas_external_acquisition_cross_domain_v1"}'::jsonb
  )
  returning id into v_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_external_acquisition_cross_domain_v1"}'::jsonb
  );

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,null,v_supplier_relationship_id,
    'fixture-installation-labor','fixture-installation-labor',
    'External Installation Labor',
    'service','labor_hour',
    '{"capability":"flooring_installation"}'::jsonb,
    '{"fixture":"atlas_external_acquisition_cross_domain_v1"}'::jsonb
  );

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values (
    v_org_id,'fixture:service:16-hours','fulfillment_coverage',
    'Secure 16 external installer labor-hours',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z',
    '2026-09-24T12:00:00Z','2026-10-02T13:00:00Z',
    '{"customerPromiseAtRisk":true}'::jsonb,
    'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":16,"unit":"labor_hour","requirementKey":"installer_labor","requirementClass":"capacity_coverage","specification":{"capability":"flooring_installation"}}}'::jsonb
  )
  returning id into v_requirement_id;

  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;

  v_result:=atlas.record_external_acquisition_commitment_service_v1(
    jsonb_build_object(
      'contractVersion','external_acquisition_commitment_input_v1',
      'organizationId',v_org_id,
      'supplierRelationshipId',v_supplier_relationship_id,
      'commitmentKey','fixture:subcontract-16-hours',
      'commitmentKind','subcontract_service',
      'committedAt','2026-09-24T14:00:00Z',
      'expectedFulfillmentFromAt','2026-10-02T13:00:00Z',
      'expectedFulfillmentByAt','2026-10-02T21:00:00Z',
      'acceptedTerms',jsonb_build_object(
        'scope','flooring installation labor',
        'performanceWindow','2026-10-02'
      ),
      'economics',jsonb_build_object(
        'state','known',
        'knownCommittedAmount',1200,
        'currency','USD',
        'costComponents',jsonb_build_array(
          jsonb_build_object(
            'componentKey','subcontract_labor',
            'state','known',
            'amount',1200,
            'currency','USD'
          )
        )
      ),
      'source',jsonb_build_object(
        'kind','supplier_confirmation',
        'ref','fixture:subcontract-confirmation'
      ),
      'authorizationBasis',jsonb_build_object(
        'authorityRef','fixture:project-purchasing-authority',
        'decisionRef','fixture:secure-installer-capacity',
        'authorizedAt','2026-09-24T13:50:00Z'
      ),
      'lines',jsonb_build_array(
        jsonb_build_object(
          'lineKey','installer-labor',
          'externalSupplyOfferingId',v_offering_id,
          'description','16 external installer labor-hours',
          'orderedQuantity',16,
          'orderedUnit','labor_hour',
          'coverageOutputQuantity',16,
          'coverageOutputUnit','labor_hour',
          'knownLineAmount',1200,
          'currency','USD',
          'acceptedTerms',jsonb_build_object('scope','flooring_installation'),
          'allocations',jsonb_build_array(
            jsonb_build_object(
              'allocationKey','installer-capacity',
              'workRequirementId',v_requirement_id,
              'coverageQuantity',16,
              'coverageUnit','labor_hour',
              'qualificationBasis',jsonb_build_object(
                'state','qualified',
                'capability','flooring_installation'
              ),
              'planningBasis',jsonb_build_object(
                'planKey','fixture:construction-service-plan'
              )
            )
          )
        )
      ),
      'metadata',jsonb_build_object(
        'fixture','atlas_external_acquisition_cross_domain_v1'
      )
    )
  );

  v_commitment_id:=(v_result->>'externalAcquisitionCommitmentId')::uuid;

  if v_commitment_id is null
     or coalesce((v_result->>'created')::boolean,false)=false then
    raise exception 'Service-shaped acquisition commitment failed: %',v_result;
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(v_commitment_id);

  if v_position->>'commitmentKind'<>'subcontract_service'
     or (v_position->>'knownCommittedAmount')::numeric<>1200
     or v_position->'lines'->0->>'orderedUnit'<>'labor_hour'
     or v_position->'lines'->0->>'coverageOutputUnit'<>'labor_hour'
     or (v_position->'lines'->0->>'allocatedCoverageQuantity')::numeric<>16 then
    raise exception 'Service-shaped acquisition position leaked goods assumptions: %',v_position;
  end if;

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);
  select value into v_fact
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_requirement_id
  limit 1;

  v_position:=atlas.work_requirement_coverage_position_v1(
    v_requirement_id,
    jsonb_build_array(v_fact->'coverageFact')
  );

  if v_position->>'hardCoverageState'<>'exact'
     or (v_position->>'securedQuantity')::numeric<>16
     or coalesce((v_position->>'fullySecured')::boolean,false)=false then
    raise exception 'Service acquisition did not secure labor requirement: %',v_position;
  end if;

  if (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory then
    raise exception 'Service acquisition created Spend or flower inventory.';
  end if;

  raise notice 'PASS atlas_external_acquisition_cross_domain_v1: one external subcontract-service commitment secures 16 labor-hours with no goods/flower-specific schema or Spend/inventory side effects';
end;
$validation$;

rollback;
