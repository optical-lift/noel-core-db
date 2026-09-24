begin;

do $validation$
declare
  v_org_id uuid;
  v_quantified_requirement_id uuid;
  v_nonquantified_requirement_id uuid;
  v_result jsonb;

  v_before_flower_allocations bigint;
  v_before_capacity_reservations bigint;
  v_before_seed_allocations bigint;
  v_before_work_allocations bigint;
  v_before_purchases bigint;
  v_before_spend bigint;
begin
  select count(*) into v_before_flower_allocations from atlas.flower_demand_allocations;
  select count(*) into v_before_capacity_reservations from atlas.production_capacity_reservations;
  select count(*) into v_before_seed_allocations from atlas.seed_lot_allocations;
  select count(*) into v_before_work_allocations from atlas.work_allocations;
  select count(*) into v_before_purchases from atlas.implementation_purchases;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_company_work_coverage_position_v1',
    'Fixture Coverage Organization',
    'active',
    '{"fixture":"atlas_company_work_coverage_position_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values (
    v_org_id,
    'fixture:coverage:quantified',
    'fulfillment_coverage',
    'Secure 100 units',
    'commercial_order_line',
    gen_random_uuid(),
    'active',
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-25T14:00:00Z'::timestamptz,
    '{"customerPromiseAtRisk":true}'::jsonb,
    'commerce.fulfillment_coverage',
    '{
      "commercialFulfillment":{
        "contractVersion":"commercial_order_fulfillment_requirements_v1",
        "requirementKey":"units",
        "requirementClass":"product_coverage",
        "quantity":100,
        "unit":"unit",
        "specification":{}
      },
      "domain":{}
    }'::jsonb
  )
  returning id into v_quantified_requirement_id;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values (
    v_org_id,
    'fixture:coverage:nonquantified',
    'fulfillment_coverage',
    'Obtain final approval',
    'commercial_order',
    gen_random_uuid(),
    'active',
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-24T14:00:00Z'::timestamptz,
    '2026-09-25T14:00:00Z'::timestamptz,
    '{"customerPromiseAtRisk":true}'::jsonb,
    'commerce.fulfillment_coverage',
    '{
      "commercialFulfillment":{
        "contractVersion":"commercial_order_fulfillment_requirements_v1",
        "requirementKey":"approval",
        "requirementClass":"approval_coverage",
        "specification":{}
      },
      "domain":{}
    }'::jsonb
  )
  returning id into v_nonquantified_requirement_id;

  -- 1. Zero coverage facts means none, not failure.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[]'::jsonb
  );

  if v_result->>'state'<>'ready'
     or v_result->>'hardCoverageState'<>'none'
     or coalesce((v_result->>'fullySecured')::boolean,true)
     or (v_result->>'securedQuantity')::numeric<>0
     or (v_result->>'provisionalQuantity')::numeric<>0 then
    raise exception 'Zero-fact quantified coverage failed: %',v_result;
  end if;

  -- 2. Partial hard coverage.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"owned-40",
        "sourceRef":{"sourceDomain":"owned_inventory_allocation","sourceRef":"fixture:owned-40"},
        "state":"secured",
        "quantity":40,
        "unit":"unit",
        "evidence":[{"source":"fixture"}]
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'partial'
     or (v_result->>'securedQuantity')::numeric<>40
     or coalesce((v_result->>'fullySecured')::boolean,true) then
    raise exception 'Partial hard coverage failed: %',v_result;
  end if;

  -- 3. Mixed source facts can exactly secure one requirement.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"owned-40",
        "sourceRef":{"sourceDomain":"owned_inventory_allocation","sourceRef":"fixture:owned-40"},
        "state":"secured",
        "quantity":40,
        "unit":"unit"
      },
      {
        "coverageKey":"external-60",
        "sourceRef":{"sourceDomain":"external_acquisition_commitment","sourceRef":"fixture:external-60"},
        "state":"secured",
        "quantity":60,
        "unit":"unit"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'exact'
     or (v_result->>'securedQuantity')::numeric<>100
     or coalesce((v_result->>'fullySecured')::boolean,false)=false then
    raise exception 'Exact mixed-source coverage failed: %',v_result;
  end if;

  -- 4. Overcoverage remains explicit.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"source-a",
        "sourceRef":{"sourceDomain":"inventory","sourceRef":"fixture:a"},
        "state":"secured",
        "quantity":70,
        "unit":"unit"
      },
      {
        "coverageKey":"source-b",
        "sourceRef":{"sourceDomain":"supplier_commitment","sourceRef":"fixture:b"},
        "state":"secured",
        "quantity":40,
        "unit":"unit"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'overcovered'
     or (v_result->>'securedQuantity')::numeric<>110
     or coalesce((v_result->>'fullySecured')::boolean,false)=false then
    raise exception 'Overcoverage was not preserved: %',v_result;
  end if;

  -- 5. Provisional capacity never counts as hard coverage.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"tentative-capacity",
        "sourceRef":{"sourceDomain":"production_capacity_reservation","sourceRef":"fixture:tentative"},
        "state":"provisional",
        "quantity":100,
        "unit":"unit"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'none'
     or (v_result->>'securedQuantity')::numeric<>0
     or (v_result->>'provisionalQuantity')::numeric<>100
     or (v_result->>'provisionalFactCount')::integer<>1 then
    raise exception 'Provisional coverage incorrectly counted as secured: %',v_result;
  end if;

  -- 6. Unresolved/released/failed facts remain visible and do not count.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"unknown",
        "sourceRef":{"sourceDomain":"supplier_portal","sourceRef":"fixture:unknown"},
        "state":"unresolved"
      },
      {
        "coverageKey":"released",
        "sourceRef":{"sourceDomain":"capacity_reservation","sourceRef":"fixture:released"},
        "state":"released",
        "quantity":50,
        "unit":"unit"
      },
      {
        "coverageKey":"failed",
        "sourceRef":{"sourceDomain":"supplier_order","sourceRef":"fixture:failed"},
        "state":"failed"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'none'
     or (v_result->>'unresolvedFactCount')::integer<>1
     or (v_result->>'releasedFactCount')::integer<>1
     or (v_result->>'failedFactCount')::integer<>1
     or (v_result->>'securedQuantity')::numeric<>0 then
    raise exception 'Noncurrent coverage states were miscounted: %',v_result;
  end if;

  -- 7. Unit mismatch fails closed.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"wrong-unit",
        "sourceRef":{"sourceDomain":"fixture","sourceRef":"wrong"},
        "state":"secured",
        "quantity":100,
        "unit":"case"
      }
    ]'::jsonb
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='coverage_unit_mismatch'
     ) then
    raise exception 'Unit mismatch did not fail closed: %',v_result;
  end if;

  -- 8. Duplicate coverage identities fail closed.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_quantified_requirement_id,
    '[
      {
        "coverageKey":"dup",
        "sourceRef":{"sourceDomain":"fixture","sourceRef":"a"},
        "state":"secured",
        "quantity":50,
        "unit":"unit"
      },
      {
        "coverageKey":"dup",
        "sourceRef":{"sourceDomain":"fixture","sourceRef":"b"},
        "state":"secured",
        "quantity":50,
        "unit":"unit"
      }
    ]'::jsonb
  );

  if v_result->>'state'<>'invalid'
     or not exists(
       select 1 from jsonb_array_elements(v_result->'violations') x
       where x->>'key'='duplicate_coverage_key'
     ) then
    raise exception 'Duplicate coverage key did not fail closed: %',v_result;
  end if;

  -- 9. Nonquantified requirement: partial then full.
  v_result:=atlas.work_requirement_coverage_position_v1(
    v_nonquantified_requirement_id,
    '[
      {
        "coverageKey":"approval-progress",
        "sourceRef":{"sourceDomain":"approval_work","sourceRef":"fixture:partial"},
        "state":"secured",
        "extent":"partial"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'partial'
     or coalesce((v_result->>'fullySecured')::boolean,true) then
    raise exception 'Nonquantified partial coverage failed: %',v_result;
  end if;

  v_result:=atlas.work_requirement_coverage_position_v1(
    v_nonquantified_requirement_id,
    '[
      {
        "coverageKey":"approval-final",
        "sourceRef":{"sourceDomain":"approval_record","sourceRef":"fixture:full"},
        "state":"secured",
        "extent":"full"
      }
    ]'::jsonb
  );

  if v_result->>'hardCoverageState'<>'full'
     or coalesce((v_result->>'fullySecured')::boolean,false)=false then
    raise exception 'Nonquantified full coverage failed: %',v_result;
  end if;

  -- 10. Coverage evaluation does not close the Company Work Requirement.
  if (select state from atlas.work_requirements where id=v_quantified_requirement_id)<>'active'
     or (select state from atlas.work_requirements where id=v_nonquantified_requirement_id)<>'active' then
    raise exception 'Coverage evaluation changed Work Requirement state.';
  end if;

  -- 11. Evaluation creates no source-domain securing truth.
  if (select count(*) from atlas.flower_demand_allocations)<>v_before_flower_allocations
     or (select count(*) from atlas.production_capacity_reservations)<>v_before_capacity_reservations
     or (select count(*) from atlas.seed_lot_allocations)<>v_before_seed_allocations
     or (select count(*) from atlas.work_allocations)<>v_before_work_allocations
     or (select count(*) from atlas.implementation_purchases)<>v_before_purchases
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend then
    raise exception 'Coverage evaluator created source allocation/reservation/purchase/spend truth.';
  end if;

  -- 12. Internal service only, no SECURITY DEFINER.
  if has_function_privilege(
       'authenticated',
       'atlas.work_requirement_coverage_position_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.work_requirement_coverage_position_v1(uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Coverage position privilege boundary is incorrect.';
  end if;

  if exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='work_requirement_coverage_position_v1'
      and p.prosecdef
  ) then
    raise exception 'Coverage position unexpectedly uses SECURITY DEFINER.';
  end if;

  raise notice 'PASS atlas_company_work_coverage_position_v1: quantified/nonquantified, partial/exact/over, provisional/unresolved/released/failed semantics and no-write boundaries hold';
end;
$validation$;

rollback;
