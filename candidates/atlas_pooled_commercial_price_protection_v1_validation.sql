begin;

do $validation$
declare
  v_org_id uuid;
  v_r40 uuid;
  v_r30 uuid;
  v_r20 uuid;
  v_c40 uuid;
  v_c30 uuid;
  v_c20 uuid;

  v_flower_pool jsonb;
  v_construction_pool jsonb;
  v_result jsonb;
  v_shared jsonb;

  v_before_orders bigint;
  v_before_offers bigint;
  v_before_work bigint;
  v_before_allocations bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_payments bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_pooled_price_protection_v1',
    'Fixture Pooled Price Protection Organization',
    'active',
    '{"fixture":"atlas_pooled_commercial_price_protection_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:poolprice:r40','fulfillment_coverage','Secure 40 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
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
    v_org_id,'fixture:poolprice:r30','fulfillment_coverage','Secure 30 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
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
    v_org_id,'fixture:poolprice:r20','fulfillment_coverage','Secure 20 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-25T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
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
    v_org_id,'fixture:poolprice:c40','fulfillment_coverage','Secure 40 tile boxes',
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
    v_org_id,'fixture:poolprice:c30','fulfillment_coverage','Secure 30 tile boxes',
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
    v_org_id,'fixture:poolprice:c20','fulfillment_coverage','Secure 20 tile boxes',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-24T14:00:00Z','2026-09-30T14:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"contractVersion":"commercial_order_fulfillment_requirements_v1","requirementKey":"tile","requirementClass":"material_coverage","quantity":20,"unit":"box","specification":{"material":"tile"}},"domain":{"job":"C"}}'::jsonb
  )
  returning id into v_c20;

  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_offers from atlas.commercial_offer_snapshots;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_allocations from atlas.flower_demand_allocations;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_payments from atlas.commercial_payments;

  -- Shared pricing law: gross-margin and markup remain different.
  v_shared:=atlas.commercial_price_from_cost_basis_v1(
    100,'stem',38,'USD',
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30,
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb,
    '{"fixture":"shared_gross_margin"}'::jsonb
  );

  if (v_shared->>'proposedUnitPrice')::numeric<>0.55
     or (v_shared->>'proposedTotal')::numeric<>55
     or (v_shared->>'realizedGrossMarginAgainstCostBasis')::numeric<0.30 then
    raise exception 'Shared gross-margin pricing law failed: %',v_shared;
  end if;

  v_shared:=atlas.commercial_price_from_cost_basis_v1(
    100,'stem',38,'USD',
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.30,
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb,
    '{"fixture":"shared_markup"}'::jsonb
  );

  if (v_shared->>'proposedUnitPrice')::numeric<>0.50
     or (v_shared->>'proposedTotal')::numeric<>50 then
    raise exception 'Shared markup pricing law failed: %',v_shared;
  end if;

  v_flower_pool:=jsonb_build_object(
    'contractVersion','work_requirement_pool_v1',
    'poolKey','fixture:flower-100',
    'sourceRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef','fixture:carnation-100'
    ),
    'sourceQuantity',100,
    'sourceUnit','stem',
    'outputQuantity',100,
    'outputUnit','stem',
    'plannedUses',jsonb_build_array(
      jsonb_build_object('useKey','wickmans','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
      jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
      jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
    ),
    'costComponents',jsonb_build_array(
      jsonb_build_object('componentKey','landed_pool_cost','state','known','amount',38,'currency','USD')
    )
  );

  -- 1. Conservative full-pool basis protects 30% margin on current 90 units.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    v_flower_pool,
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

  if v_result->>'state'<>'priced'
     or v_result->>'selectedCostRecoveryBasis'<>'full_pool_on_planned_output'
     or (v_result->>'protectedCostBasisQuantity')::numeric<>90
     or round((v_result->>'protectedCostPerUnit')::numeric,6)<>0.422222
     or (v_result->>'protectedProposedUnitPrice')::numeric<>0.61
     or (v_result->>'protectedProposedRevenueOnPlannedOutput')::numeric<>54.90
     or (v_result->>'protectedWholePoolGrossProfit')::numeric<>16.90
     or (v_result->>'protectedWholePoolGrossMargin')::numeric<0.30 then
    raise exception 'Full-pool protected pricing failed: %',v_result;
  end if;

  if (v_result->'scenarioComparison'->'sourceOutput'->'priceResult'->>'proposedUnitPrice')::numeric<>0.55
     or (v_result->'scenarioComparison'->'sourceOutput'->>'currentPlannedRevenue')::numeric<>49.50
     or round((v_result->'scenarioComparison'->'sourceOutput'->>'wholePoolGrossMarginIfExcessRecoversZero')::numeric,6)<>0.232323
     or v_result->'scenarioComparison'->'sourceOutput'->>'protectionState'<>'unprotected_without_excess_recovery' then
    raise exception 'Source-output risk scenario was not preserved: %',v_result;
  end if;

  if jsonb_array_length(v_result->'requirementPrices')<>3
     or (
       select sum((x->>'proposedTotal')::numeric)
       from jsonb_array_elements(v_result->'requirementPrices') x
     )<>54.90 then
    raise exception 'Per-requirement protected totals failed: %',v_result;
  end if;

  -- 2. Source-output basis is blocked while unresolved excess remains.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    v_flower_pool,
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"source_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30,
        "currency":"USD",
        "rounding":{"mode":"ceil","increment":0.01}
      }
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'excess_recovery_not_established'
     or (v_result->'scenarioComparison'->'sourceOutput'->'priceResult'->>'proposedUnitPrice')::numeric<>0.55
     or (v_result->'scenarioComparison'->'fullPoolOnPlannedOutput'->'priceResult'->>'proposedUnitPrice')::numeric<>0.61 then
    raise exception 'Source-output excess protection boundary failed: %',v_result;
  end if;

  -- 3. Source-output basis is lawful when the pool is actually fully used.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:flower-90-no-excess',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:carnation-90'),
      'sourceQuantity',90,
      'sourceUnit','stem',
      'outputQuantity',90,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','wickmans','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','landed_pool_cost','state','known','amount',34.20,'currency','USD')
      )
    ),
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"source_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30,
        "rounding":{"mode":"ceil","increment":0.01}
      }
    }'::jsonb
  );

  if v_result->>'state'<>'priced'
     or (v_result->>'excessOutputQuantity')::numeric<>0
     or (v_result->>'protectedProposedUnitPrice')::numeric<>0.55
     or (v_result->>'protectedWholePoolGrossMargin')::numeric<0.30 then
    raise exception 'Fully-used source-output pricing failed: %',v_result;
  end if;

  -- 4. Unresolved pool cost blocks price protection but preserves pool truth.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:unresolved-freight',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:unresolved'),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','wickmans','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','merchandise','state','known','amount',31,'currency','USD'),
        jsonb_build_object('componentKey','freight','state','unresolved')
      )
    ),
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"full_pool_on_planned_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30
      }
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'required_pool_cost_unresolved' then
    raise exception 'Unresolved pooled economics did not block pricing: %',v_result;
  end if;

  -- 5. Multi-currency blocks without governed conversion.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:multi-currency',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:multi'),
      'sourceQuantity',100,
      'sourceUnit','stem',
      'outputQuantity',100,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','wickmans','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',40,'unit','stem'),
        jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',30,'unit','stem'),
        jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','a','state','known','amount',31,'currency','USD'),
        jsonb_build_object('componentKey','b','state','known','amount',5,'currency','EUR')
      )
    ),
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"full_pool_on_planned_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30
      }
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'multi_currency_without_governed_conversion' then
    raise exception 'Multi-currency pooled economics did not block pricing: %',v_result;
  end if;

  -- 6. Incomplete aggregate demand blocks customer-price protection.
  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:partial-demand',
      'sourceRef',jsonb_build_object('sourceDomain','external_supply_offering','sourceRef','fixture:partial'),
      'sourceQuantity',60,
      'sourceUnit','stem',
      'outputQuantity',60,
      'outputUnit','stem',
      'plannedUses',jsonb_build_array(
        jsonb_build_object('useKey','wickmans','workRequirementId',v_r40,'qualificationState','qualified','plannedQuantity',20,'unit','stem'),
        jsonb_build_object('useKey','flowerama','workRequirementId',v_r30,'qualificationState','qualified','plannedQuantity',20,'unit','stem'),
        jsonb_build_object('useKey','buyer-c','workRequirementId',v_r20,'qualificationState','qualified','plannedQuantity',20,'unit','stem')
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object('componentKey','cost','state','known','amount',24,'currency','USD')
      )
    ),
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"full_pool_on_planned_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":0.30
      }
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'aggregate_demand_not_fully_covered' then
    raise exception 'Incomplete aggregate demand did not block customer pricing: %',v_result;
  end if;

  -- 7. Construction leak test: 100-box pallet, 90 current boxes, $900 pool cost.
  v_construction_pool:=jsonb_build_object(
    'contractVersion','work_requirement_pool_v1',
    'poolKey','fixture:tile-100',
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
  );

  v_result:=atlas.work_requirement_pool_price_evaluate_v1(
    v_construction_pool,
    '{
      "contractVersion":"work_requirement_pool_price_policy_v1",
      "costRecoveryBasis":"full_pool_on_planned_output",
      "pricingPolicy":{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"markup",
        "rate":0.25,
        "rounding":{"mode":"ceil","increment":0.01}
      }
    }'::jsonb
  );

  if v_result->>'state'<>'priced'
     or (v_result->>'protectedCostPerUnit')::numeric<>10
     or (v_result->>'protectedProposedUnitPrice')::numeric<>12.50
     or (v_result->'scenarioComparison'->'sourceOutput'->'priceResult'->>'proposedUnitPrice')::numeric<>11.25 then
    raise exception 'Construction pooled price protection leak test failed: %',v_result;
  end if;

  -- 8. Read-only pricing creates no commercial/source truth.
  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_offer_snapshots)<>v_before_offers
     or (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.flower_demand_allocations)<>v_before_allocations
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_payments)<>v_before_payments then
    raise exception 'Pooled price protection created durable truth.';
  end if;

  -- 9. Internal service only, no SECURITY DEFINER.
  if has_function_privilege(
       'authenticated',
       'atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Pooled pricing privilege boundary is incorrect.';
  end if;

  if exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'commercial_price_from_cost_basis_v1',
        'work_requirement_pool_price_evaluate_v1'
      )
      and p.prosecdef
  ) then
    raise exception 'Pooled pricing unexpectedly uses SECURITY DEFINER.';
  end if;

  raise notice 'PASS atlas_pooled_commercial_price_protection_v1: shared price law, $0.55 vs $0.61 excess-risk scenarios, explicit recovery basis, full-pool margin protection, cross-domain leak test, and no-write boundaries hold';
end;
$validation$;

rollback;
