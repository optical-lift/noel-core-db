begin;

do $validation$
declare
  v_org_id uuid;

  v_o40 uuid;
  v_o30 uuid;
  v_o20 uuid;
  v_l40 uuid;
  v_l30 uuid;
  v_l20 uuid;

  v_wr40 uuid;
  v_wr30 uuid;
  v_wr20 uuid;

  v_commit_result jsonb;
  v_q40 jsonb;
  v_q30 jsonb;
  v_q20 jsonb;
  v_pool jsonb;

  v_total_customer_revenue numeric:=49.50;
  v_pool_cost numeric:=38.00;
  v_worst_case_gross_profit numeric;
  v_worst_case_gross_margin numeric;

  v_before_allocations bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_payments bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_break_bulk_business_model_v1',
    'Fixture Break-Bulk Business',
    'active',
    '{"fixture":"atlas_break_bulk_business_model_vertical_slice_v1"}'::jsonb
  )
  returning id into v_org_id;

  select count(*) into v_before_allocations from atlas.flower_demand_allocations;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_payments from atlas.commercial_payments;

  -- Three customer commitments at $0.55/stem.
  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata
  ) values (
    v_org_id,'sale','2026-09-24','fixture',22.00,0,0,22.00,'USD',
    'fixture-breakbulk-40','{"buyer":"wickmans"}'::jsonb
  )
  returning id into v_o40;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_o40,'recorded','2026-09-24T14:00:00Z',
    'fixture-breakbulk-40-recorded','{}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_o40,'Standard Carnations',40,'stem',0.55,22.00,
    '{"buyer":"wickmans"}'::jsonb
  )
  returning id into v_l40;

  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata
  ) values (
    v_org_id,'sale','2026-09-24','fixture',16.50,0,0,16.50,'USD',
    'fixture-breakbulk-30','{"buyer":"flowerama"}'::jsonb
  )
  returning id into v_o30;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_o30,'recorded','2026-09-24T14:05:00Z',
    'fixture-breakbulk-30-recorded','{}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_o30,'Standard Carnations',30,'stem',0.55,16.50,
    '{"buyer":"flowerama"}'::jsonb
  )
  returning id into v_l30;

  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata
  ) values (
    v_org_id,'sale','2026-09-24','fixture',11.00,0,0,11.00,'USD',
    'fixture-breakbulk-20','{"buyer":"buyer_c"}'::jsonb
  )
  returning id into v_o20;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_o20,'recorded','2026-09-24T14:10:00Z',
    'fixture-breakbulk-20-recorded','{}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_o20,'Standard Carnations',20,'stem',0.55,11.00,
    '{"buyer":"buyer_c"}'::jsonb
  )
  returning id into v_l20;

  -- Universal Commercial Order -> Company Work seam.
  v_commit_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_o40,
    jsonb_build_array(jsonb_build_object(
      'requirementKey','flowers',
      'sourceOrderLineId',v_l40,
      'requirementClass','product_coverage',
      'summary','Secure 40 qualifying standard carnations',
      'quantity',40,
      'unit','stem',
      'specification',jsonb_build_object('flowerFamily','carnation','grade','standard'),
      'latestSatisfactoryAt','2026-09-25T17:00:00Z',
      'consequenceOfDelay',jsonb_build_object('customerPromiseAtRisk',true),
      'jurisdictionKey','commerce.fulfillment_coverage'
    )),
    '{"adapterKey":"break_bulk_flower_fixture","adapterVersion":"1"}'::jsonb
  );
  v_wr40:=(v_commit_result->'requirements'->0->>'workRequirementId')::uuid;

  v_commit_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_o30,
    jsonb_build_array(jsonb_build_object(
      'requirementKey','flowers',
      'sourceOrderLineId',v_l30,
      'requirementClass','product_coverage',
      'summary','Secure 30 qualifying standard carnations',
      'quantity',30,
      'unit','stem',
      'specification',jsonb_build_object('flowerFamily','carnation','grade','standard'),
      'latestSatisfactoryAt','2026-09-25T17:00:00Z',
      'consequenceOfDelay',jsonb_build_object('customerPromiseAtRisk',true),
      'jurisdictionKey','commerce.fulfillment_coverage'
    )),
    '{"adapterKey":"break_bulk_flower_fixture","adapterVersion":"1"}'::jsonb
  );
  v_wr30:=(v_commit_result->'requirements'->0->>'workRequirementId')::uuid;

  v_commit_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_o20,
    jsonb_build_array(jsonb_build_object(
      'requirementKey','flowers',
      'sourceOrderLineId',v_l20,
      'requirementClass','product_coverage',
      'summary','Secure 20 qualifying standard carnations',
      'quantity',20,
      'unit','stem',
      'specification',jsonb_build_object('flowerFamily','carnation','grade','standard'),
      'latestSatisfactoryAt','2026-09-25T17:00:00Z',
      'consequenceOfDelay',jsonb_build_object('customerPromiseAtRisk',true),
      'jurisdictionKey','commerce.fulfillment_coverage'
    )),
    '{"adapterKey":"break_bulk_flower_fixture","adapterVersion":"1"}'::jsonb
  );
  v_wr20:=(v_commit_result->'requirements'->0->>'workRequirementId')::uuid;

  if v_wr40 is null or v_wr30 is null or v_wr20 is null then
    raise exception 'Break-bulk vertical slice did not establish all Company Work Requirements.';
  end if;

  -- Same source is qualified independently against each requirement.
  v_q40:=atlas.fulfillment_candidate_qualification_v1(
    jsonb_build_object('sourceDomain','company_work_requirement','sourceRef',v_wr40::text),
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier-carnation-100"}'::jsonb,
    '[
      {"requirementKey":"flower_family","state":"satisfied"},
      {"requirementKey":"grade","state":"satisfied"},
      {"requirementKey":"timing","state":"satisfied"}
    ]'::jsonb,
    '{"fixture":"break_bulk"}'::jsonb
  );

  v_q30:=atlas.fulfillment_candidate_qualification_v1(
    jsonb_build_object('sourceDomain','company_work_requirement','sourceRef',v_wr30::text),
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier-carnation-100"}'::jsonb,
    '[
      {"requirementKey":"flower_family","state":"satisfied"},
      {"requirementKey":"grade","state":"satisfied"},
      {"requirementKey":"timing","state":"satisfied"}
    ]'::jsonb,
    '{"fixture":"break_bulk"}'::jsonb
  );

  v_q20:=atlas.fulfillment_candidate_qualification_v1(
    jsonb_build_object('sourceDomain','company_work_requirement','sourceRef',v_wr20::text),
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier-carnation-100"}'::jsonb,
    '[
      {"requirementKey":"flower_family","state":"satisfied"},
      {"requirementKey":"grade","state":"satisfied"},
      {"requirementKey":"timing","state":"satisfied"}
    ]'::jsonb,
    '{"fixture":"break_bulk"}'::jsonb
  );

  if v_q40->>'qualificationState'<>'qualified'
     or v_q30->>'qualificationState'<>'qualified'
     or v_q20->>'qualificationState'<>'qualified' then
    raise exception 'Break-bulk source did not qualify for every customer requirement.';
  end if;

  -- One bulk pack now serves all three commitments in planning only.
  v_pool:=atlas.work_requirement_pool_position_v1(
    jsonb_build_object(
      'contractVersion','work_requirement_pool_v1',
      'poolKey','fixture:one-pack-three-buyers',
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
          'workRequirementId',v_wr40,
          'qualificationState',v_q40->>'qualificationState',
          'plannedQuantity',40,
          'unit','stem'
        ),
        jsonb_build_object(
          'useKey','flowerama',
          'workRequirementId',v_wr30,
          'qualificationState',v_q30->>'qualificationState',
          'plannedQuantity',30,
          'unit','stem'
        ),
        jsonb_build_object(
          'useKey','buyer-c',
          'workRequirementId',v_wr20,
          'qualificationState',v_q20->>'qualificationState',
          'plannedQuantity',20,
          'unit','stem'
        )
      ),
      'costComponents',jsonb_build_array(
        jsonb_build_object(
          'componentKey','landed_pool_cost',
          'state','known',
          'amount',v_pool_cost,
          'currency','USD'
        )
      ),
      'metadata',jsonb_build_object(
        'fixture','atlas_break_bulk_business_model_vertical_slice_v1'
      )
    )
  );

  if v_pool->>'state'<>'ready'
     or v_pool->>'demandPosition'<>'all_covered'
     or (v_pool->>'plannedOutputQuantity')::numeric<>90
     or (v_pool->>'excessOutputQuantity')::numeric<>10
     or (v_pool->>'sourceBasisUnitCost')::numeric<>0.38
     or round((v_pool->>'fullCostBurdenPerPlannedUnit')::numeric,6)<>0.422222 then
    raise exception 'Integrated break-bulk pool failed: %',v_pool;
  end if;

  -- Business-model stress result:
  -- quoting 90 sold stems at $0.55 based on a $0.38 source-basis unit cost
  -- does NOT preserve a 30% gross margin if all $38 must be recovered from
  -- those 90 stems because the 10 excess stems recover no value.
  v_worst_case_gross_profit:=v_total_customer_revenue-v_pool_cost;
  v_worst_case_gross_margin:=v_worst_case_gross_profit/v_total_customer_revenue;

  if v_total_customer_revenue<>49.50
     or v_worst_case_gross_profit<>11.50
     or round(v_worst_case_gross_margin,6)<>0.232323 then
    raise exception 'Break-bulk conservative margin scenario calculation failed.';
  end if;

  if v_worst_case_gross_margin>=0.30 then
    raise exception 'Fixture expected excess-risk margin compression did not occur.';
  end if;

  -- Planning must not have performed acquisition or source allocation.
  if (select count(*) from atlas.flower_demand_allocations)<>v_before_allocations
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_payments)<>v_before_payments then
    raise exception 'Break-bulk planning created allocation/purchase/spend/inventory/payment truth.';
  end if;

  raise notice 'PASS atlas_break_bulk_business_model_vertical_slice_v1: three Commercial Orders -> three Company Work Requirements -> one qualified 100-unit pool -> 90 planned / 10 excess; $0.55 quote yields only 23.2323%% gross margin in the zero-recovery excess scenario';
end;
$validation$;

rollback;
