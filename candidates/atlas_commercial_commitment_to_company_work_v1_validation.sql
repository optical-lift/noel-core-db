begin;

do $validation$
declare
  v_org_id uuid;

  v_construction_order_id uuid;
  v_construction_line_id uuid;
  v_flower_order_id uuid;
  v_flower_line_id uuid;
  v_cancelled_order_id uuid;
  v_cancelled_line_id uuid;
  v_fallback_order_id uuid;

  v_construction_requirements jsonb;
  v_flower_requirements jsonb;
  v_preview jsonb;
  v_result jsonb;

  v_commitment_at timestamptz:='2026-09-20T14:30:00Z'::timestamptz;

  v_before_work bigint;
  v_before_work_items bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_purchases bigint;
  v_before_capacity_reservations bigint;
  v_before_payments bigint;
begin
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_work_items from atlas.work_items;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_purchases from atlas.implementation_purchases;
  select count(*) into v_before_capacity_reservations from atlas.production_capacity_reservations;
  select count(*) into v_before_payments from atlas.commercial_payments;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_commercial_commitment_company_work_v1',
    'Fixture Commercial Commitment Organization',
    'active',
    '{"fixture":"atlas_commercial_commitment_to_company_work_v1"}'::jsonb
  )
  returning id into v_org_id;

  -- --------------------------------------------------------------------------
  -- Construction-shaped proof: one Commercial Order Line creates multiple
  -- institutional requirements plus one order-wide requirement.
  -- --------------------------------------------------------------------------
  insert into atlas.commercial_orders(
    organization_id,organization_unit_id,
    order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,note,metadata,created_at
  ) values (
    v_org_id,null,
    'sale','2026-09-20','fixture',
    12000,0,0,12000,'USD',
    'fixture-construction-order',
    'Construction fulfillment adapter proof',
    '{"fixture":"construction"}'::jsonb,
    '2026-09-24T15:00:00Z'::timestamptz
  )
  returning id into v_construction_order_id;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_construction_order_id,
    'recorded',
    v_commitment_at,
    'fixture-construction-recorded',
    '{"fixture":"construction"}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_construction_order_id,null,
    'Install 2,400 sq ft white-oak flooring',
    1,'job',12000,12000,
    '{"fixture":"construction"}'::jsonb
  )
  returning id into v_construction_line_id;

  v_construction_requirements:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','material',
      'sourceOrderLineId',v_construction_line_id,
      'requirementClass','material_coverage',
      'summary','Secure 2,600 sq ft qualifying white-oak flooring',
      'quantity',2600,
      'unit','sq_ft',
      'specification',jsonb_build_object(
        'material','flooring',
        'species','white_oak',
        'minimumGrade','select'
      ),
      'latestSatisfactoryAt','2026-10-01T17:00:00Z',
      'consequenceOfDelay',jsonb_build_object(
        'customerPromiseAtRisk',true,
        'workStartAtRisk',true
      ),
      'jurisdictionKey','commerce.fulfillment_coverage',
      'metadata',jsonb_build_object('fixtureRole','construction_material')
    ),
    jsonb_build_object(
      'requirementKey','installer_labor',
      'sourceOrderLineId',v_construction_line_id,
      'requirementClass','capacity_coverage',
      'summary','Secure 16 installer labor-hours',
      'quantity',16,
      'unit','labor_hour',
      'specification',jsonb_build_object(
        'capability','flooring_installation'
      ),
      'latestSatisfactoryAt','2026-10-02T13:00:00Z',
      'consequenceOfDelay',jsonb_build_object(
        'customerPromiseAtRisk',true
      ),
      'jurisdictionKey','commerce.fulfillment_coverage',
      'metadata',jsonb_build_object('fixtureRole','construction_labor')
    ),
    jsonb_build_object(
      'requirementKey','floor_roller',
      'sourceOrderLineId',v_construction_line_id,
      'requirementClass','equipment_coverage',
      'summary','Secure one floor roller for installation window',
      'quantity',1,
      'unit','equipment_day',
      'specification',jsonb_build_object(
        'equipmentClass','floor_roller'
      ),
      'latestSatisfactoryAt','2026-10-02T13:00:00Z',
      'consequenceOfDelay',jsonb_build_object(
        'workStartAtRisk',true
      ),
      'jurisdictionKey','commerce.fulfillment_coverage',
      'metadata',jsonb_build_object('fixtureRole','construction_equipment')
    ),
    jsonb_build_object(
      'requirementKey','order_completion',
      'requirementClass','completion_boundary',
      'summary','Complete committed flooring order',
      'specification',jsonb_build_object(
        'completionKind','customer_handoff'
      ),
      'latestSatisfactoryAt','2026-10-03T22:00:00Z',
      'consequenceOfDelay',jsonb_build_object(
        'customerPromiseAtRisk',true
      ),
      'jurisdictionKey','commerce.fulfillment_coverage',
      'metadata',jsonb_build_object('fixtureRole','order_wide_completion')
    )
  );

  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    v_construction_order_id,
    v_construction_requirements,
    '{"adapterKey":"construction_fixture","adapterVersion":"1"}'::jsonb
  );

  if v_preview->>'state'<>'ready'
     or (v_preview->>'wouldCreateCount')::integer<>4
     or (v_preview->>'commitmentOccurredAt')::timestamptz is distinct from v_commitment_at
     or v_preview->>'commitmentTimeBasis'<>'commercial_order_event_recorded'
     or jsonb_array_length(v_preview->'violations')<>0 then
    raise exception 'Construction commitment preview failed: %',v_preview;
  end if;

  -- Preview is read-only.
  if (select count(*) from atlas.work_requirements)<>v_before_work then
    raise exception 'Commitment preview created Work Requirement truth.';
  end if;

  v_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_construction_order_id,
    v_construction_requirements,
    '{"adapterKey":"construction_fixture","adapterVersion":"1"}'::jsonb
  );

  if (v_result->>'createdCount')::integer<>4
     or (v_result->>'existingCount')::integer<>0
     or jsonb_array_length(v_result->'requirements')<>4 then
    raise exception 'Construction Work Requirement establishment failed: %',v_result;
  end if;

  if (
    select count(*)
    from atlas.work_requirements wr
    where wr.organization_id=v_org_id
      and wr.requirement_kind='fulfillment_coverage'
      and wr.source_object_type='commercial_order_line'
      and wr.source_object_id=v_construction_line_id
  )<>3 then
    raise exception 'One construction line did not produce three distinct line-sourced requirements.';
  end if;

  if not exists(
    select 1
    from atlas.work_requirements wr
    where wr.organization_id=v_org_id
      and wr.stable_key='commercial_order:'||v_construction_order_id::text||':fulfillment:order_completion'
      and wr.source_object_type='commercial_order'
      and wr.source_object_id=v_construction_order_id
  ) then
    raise exception 'Order-wide fulfillment requirement was not sourced from Commercial Order.';
  end if;

  if exists(
    select 1
    from atlas.work_requirements wr
    where wr.organization_id=v_org_id
      and wr.stable_key like 'commercial_order:'||v_construction_order_id::text||':fulfillment:%'
      and wr.established_at is distinct from v_commitment_at
  ) then
    raise exception 'Work Requirement establishment time did not preserve recorded commitment occurrence.';
  end if;

  if not exists(
    select 1
    from atlas.work_requirements wr
    where wr.organization_id=v_org_id
      and wr.stable_key='commercial_order:'||v_construction_order_id::text||':fulfillment:material'
      and (wr.metadata->'commercialFulfillment'->>'quantity')::numeric=2600
      and wr.metadata->'commercialFulfillment'->>'unit'='sq_ft'
      and wr.metadata->'commercialFulfillment'->'specification'->>'species'='white_oak'
  ) then
    raise exception 'Quantified/specification requirement metadata was not preserved.';
  end if;

  -- Idempotent rerun returns existing requirements and creates none.
  v_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_construction_order_id,
    v_construction_requirements,
    '{"adapterKey":"construction_fixture","adapterVersion":"1"}'::jsonb
  );

  if (v_result->>'createdCount')::integer<>0
     or (v_result->>'existingCount')::integer<>4 then
    raise exception 'Commitment-to-Work adapter is not idempotent: %',v_result;
  end if;

  -- Same stable key with changed structural truth is a conflict, not a rewrite.
  begin
    perform atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
      v_construction_order_id,
      jsonb_build_array(
        jsonb_build_object(
          'requirementKey','material',
          'sourceOrderLineId',v_construction_line_id,
          'requirementClass','material_coverage',
          'summary','Secure 3,000 sq ft DIFFERENT flooring truth',
          'quantity',3000,
          'unit','sq_ft',
          'specification',jsonb_build_object('material','flooring'),
          'latestSatisfactoryAt','2026-10-01T17:00:00Z',
          'consequenceOfDelay',jsonb_build_object('customerPromiseAtRisk',true),
          'jurisdictionKey','commerce.fulfillment_coverage'
        )
      ),
      '{"adapterKey":"construction_fixture","adapterVersion":"1"}'::jsonb
    );
    raise exception 'Changed structural truth silently rewrote an existing Work Requirement.';
  exception when sqlstate '23505' then
    null;
  end;

  -- --------------------------------------------------------------------------
  -- Flower-shaped proof uses the same writer without flower knowledge in core.
  -- --------------------------------------------------------------------------
  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata,created_at
  ) values (
    v_org_id,'sale','2026-09-24','fixture',
    55,0,0,55,'USD',
    'fixture-flower-order',
    '{"fixture":"flower"}'::jsonb,
    '2026-09-24T15:10:00Z'::timestamptz
  )
  returning id into v_flower_order_id;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_flower_order_id,'recorded',
    '2026-09-24T14:45:00Z'::timestamptz,
    'fixture-flower-recorded',
    '{"fixture":"flower"}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_flower_order_id,'Standard Carnations',
    100,'stem',0.55,55,
    '{"fixture":"flower"}'::jsonb
  )
  returning id into v_flower_line_id;

  v_flower_requirements:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','flowers',
      'sourceOrderLineId',v_flower_line_id,
      'requirementClass','product_coverage',
      'summary','Secure 100 qualifying standard carnations',
      'quantity',100,
      'unit','stem',
      'specification',jsonb_build_object(
        'flowerFamily','carnation',
        'grade','standard'
      ),
      'latestSatisfactoryAt','2026-09-25T17:00:00Z',
      'consequenceOfDelay',jsonb_build_object(
        'customerPromiseAtRisk',true
      ),
      'jurisdictionKey','commerce.fulfillment_coverage',
      'metadata',jsonb_build_object('fixtureRole','flower_product')
    )
  );

  v_result:=atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
    v_flower_order_id,
    v_flower_requirements,
    '{"adapterKey":"feast_guild_flower_fixture","adapterVersion":"1"}'::jsonb
  );

  if (v_result->>'createdCount')::integer<>1
     or not exists(
       select 1
       from atlas.work_requirements wr
       where wr.organization_id=v_org_id
         and wr.source_object_type='commercial_order_line'
         and wr.source_object_id=v_flower_line_id
         and wr.metadata->'commercialFulfillment'->>'requirementClass'='product_coverage'
         and wr.metadata->'commercialFulfillment'->'specification'->>'flowerFamily'='carnation'
     ) then
    raise exception 'Flower-shaped requirement did not use universal Company Work adapter: %',v_result;
  end if;

  -- --------------------------------------------------------------------------
  -- Cancelled orders cannot create new active fulfillment requirements.
  -- --------------------------------------------------------------------------
  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata
  ) values (
    v_org_id,'sale','2026-09-24','fixture',
    10,0,0,10,'USD',
    'fixture-cancelled-order',
    '{"fixture":"cancelled"}'::jsonb
  )
  returning id into v_cancelled_order_id;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values
  (
    v_cancelled_order_id,'recorded',
    '2026-09-24T14:00:00Z'::timestamptz,
    'fixture-cancelled-recorded',
    '{}'::jsonb
  ),
  (
    v_cancelled_order_id,'cancelled',
    '2026-09-24T14:30:00Z'::timestamptz,
    'fixture-cancelled-cancelled',
    '{}'::jsonb
  );

  insert into atlas.commercial_order_lines(
    commercial_order_id,description,quantity,unit,unit_price,line_total,metadata
  ) values (
    v_cancelled_order_id,'Cancelled fixture item',
    1,'item',10,10,'{}'::jsonb
  )
  returning id into v_cancelled_line_id;

  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    v_cancelled_order_id,
    jsonb_build_array(
      jsonb_build_object(
        'requirementKey','item',
        'sourceOrderLineId',v_cancelled_line_id,
        'requirementClass','product_coverage',
        'summary','Secure cancelled item',
        'quantity',1,
        'unit','item',
        'latestSatisfactoryAt','2026-09-25T12:00:00Z',
        'consequenceOfDelay','{}'::jsonb,
        'jurisdictionKey','commerce.fulfillment_coverage'
      )
    ),
    '{"adapterKey":"cancelled_fixture","adapterVersion":"1"}'::jsonb
  );

  if v_preview->>'state'<>'blocked'
     or coalesce((v_preview->>'orderCancelled')::boolean,false)=false
     or not exists(
       select 1
       from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='commercial_order_cancelled'
     ) then
    raise exception 'Cancelled Commercial Order did not block new requirements: %',v_preview;
  end if;

  begin
    perform atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
      v_cancelled_order_id,
      jsonb_build_array(
        jsonb_build_object(
          'requirementKey','item',
          'sourceOrderLineId',v_cancelled_line_id,
          'requirementClass','product_coverage',
          'summary','Secure cancelled item',
          'quantity',1,
          'unit','item',
          'latestSatisfactoryAt','2026-09-25T12:00:00Z',
          'consequenceOfDelay','{}'::jsonb,
          'jurisdictionKey','commerce.fulfillment_coverage'
        )
      ),
      '{"adapterKey":"cancelled_fixture","adapterVersion":"1"}'::jsonb
    );
    raise exception 'Cancelled Commercial Order created fulfillment Work Requirement.';
  exception when sqlstate '22023' then
    null;
  end;

  if exists(
    select 1
    from atlas.work_requirements wr
    where wr.organization_id=v_org_id
      and wr.source_object_id=v_cancelled_line_id
  ) then
    raise exception 'Cancelled order produced an active Work Requirement.';
  end if;

  -- A line from a different order cannot be interpreted as this order's requirement.
  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    v_construction_order_id,
    jsonb_build_array(
      jsonb_build_object(
        'requirementKey','foreign_line',
        'sourceOrderLineId',v_cancelled_line_id,
        'requirementClass','product_coverage',
        'summary','Invalid foreign line',
        'quantity',1,
        'unit','item',
        'latestSatisfactoryAt','2026-10-01T12:00:00Z',
        'consequenceOfDelay','{}'::jsonb,
        'jurisdictionKey','commerce.fulfillment_coverage'
      )
    ),
    '{"adapterKey":"scope_fixture","adapterVersion":"1"}'::jsonb
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1
       from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='source_order_line_outside_order'
     ) then
    raise exception 'Foreign Commercial Order Line crossed order scope: %',v_preview;
  end if;

  -- No recorded event: fallback is explicit and warned, not silent.
  insert into atlas.commercial_orders(
    organization_id,order_kind,order_date,channel,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,
    idempotency_key,metadata,created_at
  ) values (
    v_org_id,'sale','2026-09-24','fixture',
    0,0,0,0,'USD',
    'fixture-fallback-order',
    '{"fixture":"fallback"}'::jsonb,
    '2026-09-24T16:00:00Z'::timestamptz
  )
  returning id into v_fallback_order_id;

  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    v_fallback_order_id,
    '[]'::jsonb,
    '{"adapterKey":"fallback_fixture","adapterVersion":"1"}'::jsonb
  );

  if v_preview->>'state'<>'ready'
     or v_preview->>'commitmentTimeBasis'<>'order_created_at_fallback'
     or (v_preview->>'commitmentOccurredAt')::timestamptz
          is distinct from '2026-09-24T16:00:00Z'::timestamptz
     or not exists(
       select 1
       from jsonb_array_elements(v_preview->'warnings') x
       where x->>'key'='commitment_time_fallback'
     ) then
    raise exception 'Commitment time fallback was not explicit: %',v_preview;
  end if;

  -- --------------------------------------------------------------------------
  -- Responsibility establishment must not execute or allocate anything.
  -- --------------------------------------------------------------------------
  if (select count(*) from atlas.work_items)<>v_before_work_items
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.implementation_purchases)<>v_before_purchases
     or (select count(*) from atlas.production_capacity_reservations)<>v_before_capacity_reservations
     or (select count(*) from atlas.commercial_payments)<>v_before_payments then
    raise exception 'Commercial commitment adapter created execution/payment/spend/inventory/capacity truth.';
  end if;

  if (select count(*) from atlas.work_requirements)
       <> v_before_work + 5 then
    raise exception 'Unexpected Work Requirement count after construction + flower proofs.';
  end if;

  -- Internal service only; browser roles receive no RPC surface.
  if has_function_privilege(
       'authenticated',
       'atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Commercial commitment Company Work privilege boundary is incorrect.';
  end if;

  if exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'commercial_order_fulfillment_requirements_preview_v1',
        'ensure_commercial_order_fulfillment_requirements_service_v1'
      )
      and p.prosecdef
  ) then
    raise exception 'Commercial commitment adapter unexpectedly uses SECURITY DEFINER.';
  end if;

  raise notice 'PASS atlas_commercial_commitment_to_company_work_v1: Commercial Order commitment creates only explicit idempotent Company Work Requirements, preserves real commitment time, supports flower/construction shapes, and creates no carrier/execution truth';
end;
$validation$;

rollback;
