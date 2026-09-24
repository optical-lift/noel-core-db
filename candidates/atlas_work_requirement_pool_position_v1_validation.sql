begin;

do $validation$
declare
  v_org_id uuid;
  v_other_org_id uuid;

  v_r40 uuid;
  v_r30 uuid;
  v_r20 uuid;
  v_other_r uuid;

  v_c40 uuid;
  v_c30 uuid;
  v_c20 uuid;

  v_result jsonb;

  v_before_work_count bigint;
  v_before_flower_allocations bigint;
  v_before_capacity_reservations bigint;
  v_before_seed_allocations bigint;
  v_before_work_allocations bigint;
  v_before_purchases bigint;
  v_before_spend bigint;
  v_before_payments bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_pool_position_v1',
    'Fixture Pool Organization',
    'active',
    '{"fixture":"atlas_work_requirement_pool_position_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_pool_position_other_v1',
    'Fixture Other Pool Organization',
    'active',
    '{"fixture":"atlas_work_requirement_pool_position_v1"}'::jsonb
  )
  returning id into v_other_org_id;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:r40','fulfillment_coverage','Secure 40 standard carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{"customerPromiseAtRisk":true}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"flowers","requirementClass":"product_coverage","quantity":40,"unit":"stem","specification":{"flowerFamily":"carnation"}},"domain":{"buyer":"wickmans"}}'::jsonb
  )
  returning id into v_r40;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:r30','fulfillment_coverage','Secure 30 standard carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{"customerPromiseAtRisk":true}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"flowers","requirementClass":"product_coverage","quantity":30,"unit":"stem","specification":{"flowerFamily":"carnation"}},"domain":{"buyer":"flowerama"}}'::jsonb
  )
  returning id into v_r30;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:r20','fulfillment_coverage','Secure 20 standard carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{"customerPromiseAtRisk":true}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"flowers","requirementClass":"product_coverage","quantity":20,"unit":"stem","specification":{"flowerFamily":"carnation"}},"domain":{"buyer":"buyer_c"}}'::jsonb
  )
  returning id into v_r20;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_other_org_id,'fixture:pool:other','fulfillment_coverage','Other organization requirement',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"other","requirementClass":"product_coverage","quantity":10,"unit":"stem","specification":{}},"domain":{}}'::jsonb
  )
  returning id into v_other_r;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:c40','fulfillment_coverage','Secure 40 boxes tile',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-30T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"tile","requirementClass":"material_coverage","quantity":40,"unit":"box","specification":{"material":"tile"}},"domain":{"job":"A"}}'::jsonb
  )
  returning id into v_c40;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:c30','fulfillment_coverage','Secure 30 boxes tile',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-30T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"tile","requirementClass":"material_coverage","quantity":30,"unit":"box","specification":{"material":"tile"}},"domain":{"job":"B"}}'::jsonb
  )
  returning id into v_c30;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:pool:c20','fulfillment_coverage','Secure 20 boxes tile',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-30T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"tile","requirementClass":"material_coverage","quantity":20,"unit":"box","specification":{"material":"tile"}},"domain":{"job":"C"}}'::jsonb
  )
  returning id into v_c20;

  select count(*) into v_before_work_count from atlas.work_requirements;
  select count(*) into v_before_flower_allocations from atlas.flower_demand_allocations;
  select count(*) into v_before_capacity_reservations from atlas.production_capacity_reservations;
  select count(*) into v_before_seed_allocations from atlas.seed_lot_allocations;
  select count(*) into v_before_work_allocations from atlas.work_allocations;
  select count(*) into v_before_purchases from atlas.implementation_purchases;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_payments from atlas.commercial_payments;

  -- 1. Core flower proof: 40 + 30 + 20 out of a 100-stem pool.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:100-carnations',
      'sourceRef',jsonb_build_object(
        'sourceDomain','external_supply_offering',
        'sourceRef','fixture:supplier-carnation-100'
      ),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object(
          'useKey','wickmans',
          'workRequirementId',v_r40,
          'qualificationState','qualified',
          'plannedQuantity',40,
          'unit','stem',
          'existingCoverageFacts','[]'::jsonb
        ),
        jsonb_build_object(
          'useKey','flowerama',
          'workRequirementId',v_r30,
          'qualificationState','qualified',
          'plannedQuantity',30,
          'unit','stem',
          'existingCoverageFacts','[]'::jsonb
        ),
        jsonb_build_object(
          'useKey','buyer-c',
          'workRequirementId',v_r20,
          'qualificationState','qualified',
          'plannedQuantity',20,
          'unit','stem',
          'existingCoverageFacts','[]'::jsonb
        )
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object(
          'componentKey','landed_pool_cost',
          'state','known',
          'amount',38.00,
          'currency','USD'
        )
      ),
      'metadata',jsonb_build_object('fixture','flower_break_bulk')
    )
  );

  if v_result->>'state'<>'ready'
     or (v_result->>'plannedOutputQuantity')::numeric<>90
     or (v_result->>'excessOutputQuantity')::numeric<>10
     or v_result->>'poolUtilizationState'<>'partial_use'
     or (v_result->>'aggregateOutstandingBeforePool')::numeric<>90
     or (v_result->>'unallocatedDemandQuantity')::numeric<>0
     or v_result->>'demandPosition'<>'all_covered'
     or v_result->>'economicState'<>'known'
     or (v_result->>'knownPoolCost')::numeric<>38
     or (v_result->>'sourceBasisUnitCost')::numeric<>0.38
     or (v_result->>'allocatedOutputCostBasis')::numeric<>34.20
     or (v_result->>'excessOutputCostBasis')::numeric<>3.80
     or round((v_result->>'fullCostBurdenPerPlannedUnit')::numeric,6)<>0.422222 then
    raise exception 'Core flower break-bulk proof failed: %',v_result;
  end if;

  if jsonb_array_length(v_result->'requirementPositions')<>3
     or (
       select sum((x->>'proportionalCostBasis')::numeric)
       from jsonb_array_elements(v_result->'requirementPositions') x
     )<>34.20 then
    raise exception 'Requirement-level proportional cost basis failed: %',v_result;
  end if;

  -- 2. A smaller pool can be fully used while aggregate demand remains short.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:60-carnations',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:60'),
      'sourceQuantity',60,
      'sourceUnit','stem',
      'outputQuantity',60,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',20,'unit','stem'),
        jsonb_build_object('useKey','b','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',20,'unit','stem'),
        jsonb_build_object('useKey','c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'ready'
     or v_result->>'poolUtilizationState'<>'fully_used'
     or v_result->>'demandPosition'<>'partially_covered'
     or (v_result->>'unallocatedDemandQuantity')::numeric<>30
     or (v_result->>'excessOutputQuantity')::numeric<>0 then
    raise exception 'Pool-shorter-than-demand proof failed: %',v_result;
  end if;

  -- 3. Planned output cannot exceed pool output.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:overdrawn-pool',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:50'),
      'sourceQuantity',50,
      'sourceUnit','stem',
      'outputQuantity',50,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','b','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='planned_output_exceeds_pool_output'
     ) then
    raise exception 'Pool overdraw did not fail closed: %',v_result;
  end if;

  -- 4. Existing secured coverage reduces what the pool may plan.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:existing-coverage',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:existing'),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object(
          'useKey','wickmans',
          'workRequirementId',v_r40,
          'qualificationState','qualified',
          'plannedQuantity',30,
          'unit','stem',
          'existingCoverageFacts',jsonb_build_array(
            jsonb_build_object(
              'coverageKey','owned-10',
              'sourceRef',jsonb_build_object('sourceDomain','owned_inventory_allocation','sourceRef','fixture:owned-10'),
              'state','secured',
              'quantity',10,
              'unit','stem'
            )
          )
        ),
        jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'ready'
     or (v_result->>'aggregateOutstandingBeforePool')::numeric<>80
     or (v_result->>'plannedOutputQuantity')::numeric<>80
     or (v_result->>'excessOutputQuantity')::numeric<>20
     or (v_result->>'unallocatedDemandQuantity')::numeric<>0 then
    raise exception 'Existing secured coverage was not deducted from pool demand: %',v_result;
  end if;

  -- 5. Pool may not plan beyond outstanding demand after secured coverage.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:double-cover',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:double'),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object(
          'useKey','wickmans',
          'workRequirementId',v_r40,
          'qualificationState','qualified',
          'plannedQuantity',20,
          'unit','stem',
          'existingCoverageFacts',jsonb_build_array(
            jsonb_build_object(
              'coverageKey','owned-30',
              'sourceRef',jsonb_build_object('sourceDomain','owned_inventory_allocation','sourceRef','fixture:owned-30'),
              'state','secured',
              'quantity',30,
              'unit','stem'
            )
          )
        )
      )
    )
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='planned_quantity_exceeds_outstanding_requirement'
     ) then
    raise exception 'Pool double-coverage did not fail closed: %',v_result;
  end if;

  -- 6. Unresolved/incompatible candidate qualification cannot enter pool.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:unresolved-source',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:unknown'),
      'sourceQuantity',40,
      'sourceUnit','stem',
      'outputQuantity',40,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','unresolved','plannedQuantity',40,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='source_not_qualified_for_requirement'
     ) then
    raise exception 'Unresolved source entered pooled planning: %',v_result;
  end if;

  -- 7. Unit mismatch fails closed.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:wrong-unit',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:wrong-unit'),
      'sourceQuantity',1,
      'sourceUnit','case',
      'outputQuantity',10,
      'outputUnit','bunch',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',10,'unit','bunch')
      )
    )
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key' in ('requirement_pool_unit_mismatch','planned_use_unit_mismatch')
     ) then
    raise exception 'Pool unit mismatch did not fail closed: %',v_result;
  end if;

  -- 8. Source quantity may differ from usable output quantity when explicit.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:case-to-stems',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:case'),
      'sourceQuantity',1,
      'sourceUnit','case',
      'outputQuantity',90,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','b','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'ready'
     or (v_result->>'sourceQuantity')::numeric<>1
     or v_result->>'sourceUnit'<>'case'
     or (v_result->>'outputQuantity')::numeric<>90
     or v_result->>'outputUnit'<>'stem'
     or v_result->>'poolUtilizationState'<>'fully_used'
     or v_result->>'demandPosition'<>'all_covered' then
    raise exception 'Explicit source-to-output transformation shape failed: %',v_result;
  end if;

  -- 9. Unresolved cost preserves quantity math and blocks complete economics.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:unknown-freight',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:unknown-freight'),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','b','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','merchandise','state','known','amount',31,'currency','USD'),
        jsonb_build_object('componentKey','freight','state','unresolved')
      )
    )
  );

  if v_result->>'state'<>'ready'
     or v_result->>'economicState'<>'unresolved'
     or (v_result->>'plannedOutputQuantity')::numeric<>90
     or (v_result->>'excessOutputQuantity')::numeric<>10
     or v_result->>'sourceBasisUnitCost' is not null
     or (v_result->'knownCostTotalsByCurrency'->>'USD')::numeric<>31 then
    raise exception 'Unresolved cost semantics failed: %',v_result;
  end if;

  -- 10. Multi-currency remains multi-currency.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:multi-currency',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:multi'),
      'sourceQuantity',40,
      'sourceUnit','stem',
      'outputQuantity',40,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','a','state','known','amount',10,'currency','USD'),
        jsonb_build_object('componentKey','b','state','known','amount',8,'currency','EUR')
      )
    )
  );

  if v_result->>'economicState'<>'known_multi_currency'
     or v_result->>'sourceBasisUnitCost' is not null
     or (v_result->'knownCostTotalsByCurrency'->>'USD')::numeric<>10
     or (v_result->'knownCostTotalsByCurrency'->>'EUR')::numeric<>8 then
    raise exception 'Multi-currency pooled economics failed: %',v_result;
  end if;

  -- 11. One pool cannot cross Organization custody.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:cross-org',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:cross-org'),
      'sourceQuantity',50,
      'sourceUnit','stem',
      'outputQuantity',50,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','a','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','b','workRequirementId',v_other_r,'qualificationState','qualified','plannedQuantity',10,'unit','stem')
      )
    )
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='cross_organization_pool'
     ) then
    raise exception 'Cross-organization source pool was admitted: %',v_result;
  end if;

  -- 12. Construction leak test: same 40 + 30 + 20 pattern, 100-box pallet.
  v_result:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:tile-pallet',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:tile-pallet'),
      'sourceQuantity',1,
      'sourceUnit','pallet',
      'outputQuantity',100,
      'outputUnit','box',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','job-a','workRequirementId',v_c40,'qualificationState','qualified','plannedQuantity',40,'unit','box'),
        jsonb_build_object('useKey','job-b','workRequirementId',v_c30,'qualificationState','qualified','plannedQuantity',30,'unit','box'),
        jsonb_build_object('useKey','job-c','workRequirementId',v_c20,'qualificationState','qualified','plannedQuantity',20,'unit','box')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','pallet','state','known','amount',900,'currency','USD')
      )
    )
  );

  if v_result->>'state'<>'ready'
     or v_result->>'demandPosition'<>'all_covered'
     or (v_result->>'excessOutputQuantity')::numeric<>10
     or (v_result->>'sourceBasisUnitCost')::numeric<>9
     or (v_result->>'allocatedOutputCostBasis')::numeric<>810
     or (v_result->>'excessOutputCostBasis')::numeric<>90
     or (v_result->>'fullCostBurdenPerPlannedUnit')::numeric<>10 then
    raise exception 'Construction pooled-fulfillment leak test failed: %',v_result;
  end if;

  -- 13. Read-only means no requirement/source-domain mutation.
  if (select count(*) from atlas.work_requirements)<>v_before_work_count
     or (select count(*) from atlas.flower_demand_allocations)<>v_before_flower_allocations
     or (select count(*) from atlas.production_capacity_reservations)<>v_before_capacity_reservations
     or (select count(*) from atlas.seed_lot_allocations)<>v_before_seed_allocations
     or (select count(*) from atlas.work_allocations)<>v_before_work_allocations
     or (select count(*) from atlas.implementation_purchases)<>v_before_purchases
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.commercial_payments)<>v_before_payments then
    raise exception 'Pooled fulfillment evaluator created durable requirement/allocation/purchase/spend/payment truth.';
  end if;

  -- 14. Internal service only, no SECURITY DEFINER.
  if has_function_privilege(
       'authenticated',
       'atlas.work_requirement_pool_position_v1(jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.work_requirement_pool_position_v1(jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Pooled fulfillment evaluator privilege boundary is incorrect.';
  end if;

  if exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='work_requirement_pool_position_v1'
      and p.prosecdef
  ) then
    raise exception 'Pooled fulfillment evaluator unexpectedly uses SECURITY DEFINER.';
  end if;

  raise notice 'PASS atlas_work_requirement_pool_position_v1: multi-requirement break-bulk quantity, excess, existing coverage, shared economics, institutional scope, and no-write boundaries hold';
end;
$validation$;

rollback;
