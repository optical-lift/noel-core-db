begin;

do $validation$
declare
  v_org_id uuid;
  v_supplier_subject_id uuid;
  v_supplier_relationship_id uuid;
  v_offering_id uuid;
  v_observation_id uuid;

  v_r40 uuid;
  v_r30 uuid;
  v_r20 uuid;

  v_pool_packet jsonb;
  v_pool_position jsonb;
  v_price_position jsonb;
  v_commitment_input jsonb;
  v_commitment_result jsonb;
  v_commitment_id uuid;
  v_coverage jsonb;
  v_fact jsonb;
  v_check jsonb;

  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_payments bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_acquisition_vertical_v1',
    'Fixture External Acquisition Vertical Slice',
    'active',
    '{"fixture":"atlas_external_acquisition_vertical_slice_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(v_org_id,'{"fixture":"supplier"}'::jsonb)
  returning id into v_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,v_supplier_subject_id,'fixture-supplier','active',
    '{"fixture":"atlas_external_acquisition_vertical_slice_v1"}'::jsonb
  )
  returning id into v_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_external_acquisition_vertical_slice_v1"}'::jsonb
  );

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,null,v_supplier_relationship_id,
    'fixture-carnation-100','fixture-carnation-100','Standard Carnations',
    'item','stem',
    '{"flowerFamily":"carnation","grade":"standard"}'::jsonb,
    '{"fixture":"atlas_external_acquisition_vertical_slice_v1"}'::jsonb
  );

  v_check:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    'fixture-carnation-100-quote',
    '2026-09-24T13:00:00Z',
    '2026-09-24','2026-09-25',
    38,'USD','source_explicit',
    100,'stem',
    100,'stem',
    100,'stem',
    1,'day',
    'available',
    '{"freightIncluded":true}'::jsonb,
    '{"fixture":"atlas_external_acquisition_vertical_slice_v1"}'::jsonb,
    'supplier_quote',
    'fixture:quote:100',
    null,null,
    '{}'::jsonb
  );
  v_observation_id:=(v_check->>'externalSupplyOfferObservationId')::uuid;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:vertical:r40','fulfillment_coverage','Secure 40 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":40,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation","grade":"standard"}}}'::jsonb
  )
  returning id into v_r40;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:vertical:r30','fulfillment_coverage','Secure 30 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":30,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation","grade":"standard"}}}'::jsonb
  )
  returning id into v_r30;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:vertical:r20','fulfillment_coverage','Secure 20 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":20,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation","grade":"standard"}}}'::jsonb
  )
  returning id into v_r20;

  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_payments from atlas.commercial_payments;

  v_pool_packet:=jsonb_build_object(
    'contractVersion','work_requirement_pool_v1',
    'poolKey','fixture:vertical:one-pack-three-buyers',
    'sourceRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id::text
    ),
    'sourceQuantity',100,
    'sourceUnit','stem',
    'outputQuantity',100,
    'outputUnit','stem',
    'plannedUses',jsonb_build_array(
      jsonb_build_object('useKey','buyer-40','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
      jsonb_build_object('useKey','buyer-30','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
      jsonb_build_object('useKey','buyer-20','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
    ),
    'costComponents',jsonb_build_array(
      jsonb_build_object('componentKey','landed_pool_cost','state','known','amount',38,'currency','USD')
    )
  );

  v_pool_position:=atlas.work_requirement_pool_position_v1(v_pool_packet);

  if v_pool_position->>'state'<>'ready'
     or (v_pool_position->>'plannedOutputQuantity')::numeric<>90
     or (v_pool_position->>'excessOutputQuantity')::numeric<>10
     or v_pool_position->>'demandPosition'<>'all_covered' then
    raise exception 'Vertical slice pooled plan failed: %',v_pool_position;
  end if;

  v_price_position:=atlas.work_requirement_pool_price_evaluate_v1(
    v_pool_packet,
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"full_pool_on_planned_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30,
        "currency":"USD",
        "rounding":{"mode":"ceil","increment":0.01}
      }
    }'::jsonb
  );

  if v_price_position->>'state'<>'priced'
     or (v_price_position->>'protectedProposedUnitPrice')::numeric<>0.61 then
    raise exception 'Vertical slice protected pool price failed: %',v_price_position;
  end if;

  v_commitment_input:=jsonb_build_object(
    'contractVersion','external_acquisition_commitment_input_v1',
    'organizationId',v_org_id,
    'supplierRelationshipId',v_supplier_relationship_id,
    'commitmentKey','fixture:vertical:supplier-order-100',
    'commitmentKind','supplier_order',
    'committedAt','2026-09-24T14:00:00Z',
    'expectedFulfillmentFromAt','2026-09-25T13:00:00Z',
    'expectedFulfillmentByAt','2026-09-25T16:00:00Z',
    'acceptedTerms',jsonb_build_object('freightIncluded',true),
    'economics',jsonb_build_object(
      'state','known',
      'knownCommittedAmount',38,
      'currency','USD',
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','landed_pool_cost','state','known','amount',38,'currency','USD')
      )
    ),
    'source',jsonb_build_object(
      'kind','supplier_confirmation',
      'ref','fixture:vertical:supplier-order-100'
    ),
    'authorizationBasis',jsonb_build_object(
      'authorityRef','fixture:purchasing-authority',
      'decisionRef','fixture:vertical:one-pack-three-buyers',
      'authorizedAt','2026-09-24T13:55:00Z'
    ),
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'description','100 Standard Carnations',
        'orderedQuantity',100,
        'orderedUnit','stem',
        'coverageOutputQuantity',100,
        'coverageOutputUnit','stem',
        'knownLineAmount',38,
        'currency','USD',
        'acceptedTerms',jsonb_build_object('freightIncluded',true),
        'metadata',jsonb_build_object(
          'poolKey','fixture:vertical:one-pack-three-buyers',
          'protectedUnitPrice',0.61,
          'costRecoveryBasis','full_pool_on_planned_output'
        ),
        'allocations',jsonb_build_array(
          jsonb_build_object(
            'allocationKey','buyer-40',
            'workRequirementId',v_r40,
            'coverageQuantity',40,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:vertical:one-pack-three-buyers')
          ),
          jsonb_build_object(
            'allocationKey','buyer-30',
            'workRequirementId',v_r30,
            'coverageQuantity',30,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:vertical:one-pack-three-buyers')
          ),
          jsonb_build_object(
            'allocationKey','buyer-20',
            'workRequirementId',v_r20,
            'coverageQuantity',20,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:vertical:one-pack-three-buyers')
          )
        )
      )
    ),
    'metadata',jsonb_build_object(
      'sourcePoolKey','fixture:vertical:one-pack-three-buyers',
      'protectedPricingBasis','full_pool_on_planned_output'
    )
  );

  v_commitment_result:=atlas.record_external_acquisition_commitment_service_v1(v_commitment_input);
  v_commitment_id:=(v_commitment_result->>'externalAcquisitionCommitmentId')::uuid;

  if v_commitment_id is null
     or coalesce((v_commitment_result->>'created')::boolean,false)=false then
    raise exception 'Vertical slice acquisition commitment failed: %',v_commitment_result;
  end if;

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if v_coverage->>'normalizedCoverageState'<>'secured'
     or jsonb_array_length(v_coverage->'facts')<>3 then
    raise exception 'Vertical slice acquisition coverage facts failed: %',v_coverage;
  end if;

  for v_fact in select value from jsonb_array_elements(v_coverage->'facts')
  loop
    v_check:=atlas.work_requirement_coverage_position_v1(
      (v_fact->>'workRequirementId')::uuid,
      jsonb_build_array(v_fact->'coverageFact')
    );

    if v_check->>'hardCoverageState'<>'exact'
       or coalesce((v_check->>'fullySecured')::boolean,false)=false then
      raise exception 'Vertical slice supplier commitment did not fully secure requirement: %',v_check;
    end if;
  end loop;

  if (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_payments)<>v_before_payments then
    raise exception 'Vertical slice supplier commitment created Spend/inventory/payment truth.';
  end if;

  raise notice 'PASS atlas_external_acquisition_vertical_slice_v1: pooled plan -> protected pooled price -> authorized 100-unit supplier commitment -> 40/30/20 exact secured Company Work coverage, with 10-unit remainder and no Spend/inventory/payment side effects';
end;
$validation$;

rollback;
