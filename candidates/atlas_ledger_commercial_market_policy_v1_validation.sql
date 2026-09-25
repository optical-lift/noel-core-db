begin;

do $validation$
declare
  v_practitioner uuid:=gen_random_uuid();
  v_feast_entity uuid:=gen_random_uuid();
  v_contractor_entity uuid:=gen_random_uuid();
  v_market_actor uuid:=gen_random_uuid();

  v_feast_case uuid;
  v_contractor_case uuid;
  v_feast_ledger uuid:=gen_random_uuid();
  v_contractor_ledger uuid:=gen_random_uuid();

  v_feast_policy_sep uuid;
  v_feast_policy_oct uuid;
  v_contractor_policy uuid;

  v_benchmark_obs uuid;
  v_unknown_obs uuid;

  v_envelope jsonb;
  v_eval jsonb;
  v_receipt jsonb;
  v_history jsonb;

  v_orders_before bigint:=null;
  v_orders_after bigint:=null;
  v_spend_before bigint:=null;
  v_spend_after bigint:=null;

  v_count integer;
begin
  if to_regclass('atlas.commercial_orders') is not null then
    execute 'select count(*) from atlas.commercial_orders' into v_orders_before;
  end if;
  if to_regclass('atlas.organization_spend_occurrences') is not null then
    execute 'select count(*) from atlas.organization_spend_occurrences' into v_spend_before;
  end if;

  insert into reality.entities(
    id,stable_key,entity_kind,display_name,identity_state,metadata
  ) values
    (v_practitioner,'fixture-commercial-policy-practitioner-v1','person',
      'Fixture Commercial Policy Practitioner','canonical','{}'::jsonb),
    (v_feast_entity,'fixture-feast-ledger-commercial-policy-v1','business',
      'Fixture Feast Wholesale Business','canonical','{}'::jsonb),
    (v_contractor_entity,'fixture-contractor-ledger-commercial-policy-v1','business',
      'Fixture Construction Materials Business','canonical','{}'::jsonb),
    (v_market_actor,'fixture-incumbent-market-actor-v1','business',
      'Fixture Incumbent Wholesaler','canonical','{}'::jsonb);

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
    desired_ledger_name,onboarding_state,onboarding_basis
  ) values (
    v_feast_entity,v_practitioner,v_practitioner,
    'Fixture Feast Commercial Ledger','ready_to_activate',
    '{"fixture":"ledger_commercial_market_policy_v1"}'::jsonb
  )
  returning id into v_feast_case;

  insert into ledger.ledgers(
    id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata
  ) values (
    v_feast_ledger,v_feast_entity,v_feast_case,
    'fixture-feast-commercial-ledger-v1','Fixture Feast Commercial Ledger',
    'active','{"fixture":true}'::jsonb
  );

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
    desired_ledger_name,onboarding_state,onboarding_basis
  ) values (
    v_contractor_entity,v_practitioner,v_practitioner,
    'Fixture Contractor Commercial Ledger','ready_to_activate',
    '{"fixture":"ledger_commercial_market_policy_v1"}'::jsonb
  )
  returning id into v_contractor_case;

  insert into ledger.ledgers(
    id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata
  ) values (
    v_contractor_ledger,v_contractor_entity,v_contractor_case,
    'fixture-contractor-commercial-ledger-v1','Fixture Contractor Commercial Ledger',
    'active','{"fixture":true}'::jsonb
  );

  v_feast_policy_sep:=atlas.record_ledger_commercial_pricing_policy_service_v1(
    v_feast_ledger,
    'primary_quote',
    'gross_margin',
    0.10,
    0.10,
    'USD',
    'strictly_below',
    null,
    jsonb_build_object(
      'requiredCostFamilies',
      jsonb_build_array(
        'merchandise','inbound_freight','package_fees',
        'unavoidable_overbuy','governed_shrink','absorbed_delivery'
      )
    ),
    '2026-09-01 00:00:00+00',
    '{"basis":"fixture representation of user-established Feast Guild launch economics"}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  begin
    perform atlas.record_ledger_commercial_pricing_policy_service_v1(
      v_feast_ledger,
      'primary_quote',
      'gross_margin',
      0.12,
      0.10,
      'USD',
      'strictly_below',
      null,
      '{}'::jsonb,
      '2026-09-15 00:00:00+00',
      '{"fixture":"overlap should fail"}'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Expected overlapping policy window to fail.';
  exception
    when sqlstate '23514' then
      null;
  end;

  v_feast_policy_oct:=atlas.supersede_ledger_commercial_pricing_policy_service_v1(
    v_feast_policy_sep,
    '2026-10-01 00:00:00+00',
    'gross_margin',
    0.20,
    0.15,
    'USD',
    'strictly_below',
    null,
    '{}'::jsonb,
    '{"basis":"fixture future policy change"}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  v_history:=atlas.ledger_commercial_pricing_policy_at_v1(
    v_feast_ledger,'primary_quote','2026-09-25 12:00:00+00'
  );
  if v_history->>'state'<>'resolved'
     or (v_history->>'policyId')::uuid<>v_feast_policy_sep
     or (v_history->>'targetRate')::numeric<>0.10 then
    raise exception 'Historical September policy did not remain resolvable.';
  end if;

  v_history:=atlas.ledger_commercial_pricing_policy_at_v1(
    v_feast_ledger,'primary_quote','2026-10-02 12:00:00+00'
  );
  if v_history->>'state'<>'resolved'
     or (v_history->>'policyId')::uuid<>v_feast_policy_oct
     or (v_history->>'targetRate')::numeric<>0.20 then
    raise exception 'Superseding October policy did not resolve.';
  end if;

  v_contractor_policy:=atlas.record_ledger_commercial_pricing_policy_service_v1(
    v_contractor_ledger,
    'primary_quote',
    'gross_margin',
    0.25,
    0.20,
    'USD',
    'none',
    null,
    '{"requiredCostFamilies":["materials","freight"]}'::jsonb,
    '2026-09-01 00:00:00+00',
    '{"basis":"cross-domain construction-material fixture"}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  v_benchmark_obs:=atlas.record_ledger_commercial_market_observation_service_v1(
    v_feast_ledger,
    v_market_actor,
    null,
    'Fixture incumbent 50cm rose benchmark',
    'incumbent_benchmark',
    '{"market":"Springfield, Missouri","buyerClass":"florist"}'::jsonb,
    '{"family":"rose","lengthCm":50,"color":"red"}'::jsonb,
    '2026-09-25 12:00:00+00',
    '2026-09-25 00:00:00+00',
    '2026-09-26 00:00:00+00',
    1.50,
    'USD',
    1,
    'stem',
    'confirmed',
    25,
    'stem',
    '{"confirmation":"fixture denominator explicitly confirmed for calculation"}'::jsonb,
    'manual_capture',
    'fixture:incumbent-price-sheet',
    '{"fixture":true,"sourceBacked":true}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  v_unknown_obs:=atlas.record_ledger_commercial_market_observation_service_v1(
    v_feast_ledger,
    v_market_actor,
    null,
    'Fixture source-faithful unknown-basis price row',
    'market_reference',
    '{"market":"Springfield, Missouri"}'::jsonb,
    '{"family":"carnation"}'::jsonb,
    '2026-09-25 12:00:00+00',
    '2026-09-25 00:00:00+00',
    '2026-09-26 00:00:00+00',
    0.65,
    null,
    null,
    null,
    'unknown',
    null,
    null,
    '{"sourceDidNotStateCurrencyOrDenominator":true}'::jsonb,
    'supplier_document',
    'fixture:source-faithful-unknown-row',
    '{"fixture":true}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  if not exists(
    select 1
    from atlas.ledger_commercial_market_observations
    where id=v_unknown_obs
      and currency is null
      and price_quantity is null
      and price_unit is null
      and price_basis_state='unknown'
  ) then
    raise exception 'Source-faithful unknown market observation was not preserved.';
  end if;

  v_envelope:=atlas.ledger_commercial_quote_envelope_v1(
    v_feast_policy_sep,150.00,'USD'
  );

  if v_envelope->>'state'<>'ready'
     or (v_envelope->>'marketQuoteCeiling')::numeric<>150.00
     or (v_envelope->>'marketQuoteCeilingInclusive')::boolean<>false
     or abs((v_envelope->>'targetProtectedCostCeiling')::numeric-135.00)>0.000001
     or abs((v_envelope->>'minimumProtectedCostCeiling')::numeric-135.00)>0.000001 then
    raise exception 'Strict-below 10 percent margin quote envelope is incorrect: %',v_envelope;
  end if;

  v_eval:=atlas.ledger_commercial_quote_evaluate_v1(
    v_feast_policy_sep,120.00,142.50,150.00,'USD'
  );

  if v_eval->>'decisionState'<>'eligible'
     or v_eval->>'pricingState'<>'target_met'
     or v_eval->>'marketState'<>'passes'
     or abs((v_eval->>'customerSavingsAmount')::numeric-7.50)>0.000001
     or abs((v_eval->>'customerSavingsRate')::numeric-0.05)>0.000001 then
    raise exception 'Expected eligible Feast Guild evaluation did not hold: %',v_eval;
  end if;

  v_receipt:=atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
    v_feast_ledger,
    'fixture-feast-eligible-quote',
    '{"sourceDomain":"florist_quote_intake","sourceRef":"fixture-request-1"}'::jsonb,
    v_feast_policy_sep,
    120.00,
    142.50,
    'USD',
    jsonb_build_array(
      jsonb_build_object(
        'marketObservationId',v_benchmark_obs,
        'benchmarkAmount',150.00,
        'lineRef',jsonb_build_object('lineKey','rose-red-50cm'),
        'metadata',jsonb_build_object('quantity',100,'unit','stem')
      )
    ),
    '{"protectedCostBasis":"fixture governed upstream"}'::jsonb,
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  );

  if v_receipt->>'decisionState'<>'eligible'
     or (v_receipt->>'benchmarkTotal')::numeric<>150.00 then
    raise exception 'Eligible quote receipt was not preserved correctly: %',v_receipt;
  end if;

  select count(*) into v_count
  from atlas.ledger_commercial_quote_evaluation_benchmarks b
  where b.receipt_id=(v_receipt->>'receiptId')::uuid
    and b.market_observation_id=v_benchmark_obs
    and b.benchmark_amount=150.00;
  if v_count<>1 then
    raise exception 'Quote receipt did not preserve exact benchmark observation link.';
  end if;

  v_eval:=atlas.ledger_commercial_quote_evaluate_v1(
    v_feast_policy_sep,100.00,151.00,150.00,'USD'
  );
  if v_eval->>'pricingState'<>'target_met'
     or v_eval->>'marketState'<>'fails'
     or v_eval->>'decisionState'<>'blocked' then
    raise exception 'Strong-margin quote above benchmark should be market-blocked: %',v_eval;
  end if;

  v_receipt:=atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
    v_feast_ledger,
    'fixture-feast-missing-benchmark',
    '{"sourceDomain":"florist_quote_intake","sourceRef":"fixture-request-2"}'::jsonb,
    v_feast_policy_sep,
    110.00,
    140.00,
    'USD',
    '[]'::jsonb,
    '{}'::jsonb,
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  );
  if v_receipt->>'decisionState'<>'incomplete_evidence'
     or v_receipt->>'marketState'<>'missing_benchmark' then
    raise exception 'Required missing benchmark should produce incomplete evidence: %',v_receipt;
  end if;

  begin
    perform atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
      v_feast_ledger,
      'fixture-unknown-basis-must-fail',
      '{"sourceDomain":"florist_quote_intake","sourceRef":"fixture-request-3"}'::jsonb,
      v_feast_policy_sep,
      100.00,
      130.00,
      'USD',
      jsonb_build_array(
        jsonb_build_object(
          'marketObservationId',v_unknown_obs,
          'benchmarkAmount',140.00
        )
      ),
      '{}'::jsonb,
      '{"fixture":true}'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Unknown-basis market observation should not be computational benchmark.';
  exception
    when sqlstate '23514' then
      null;
  end;

  v_receipt:=atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
    v_contractor_ledger,
    'fixture-contractor-review-required',
    '{"sourceDomain":"construction_quote_intake","sourceRef":"fixture-job-1"}'::jsonb,
    v_contractor_policy,
    800.00,
    1040.00,
    'USD',
    '[]'::jsonb,
    '{"domain":"construction_materials"}'::jsonb,
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  );

  if v_receipt->>'decisionState'<>'review_required'
     or v_receipt->>'pricingState'<>'minimum_met'
     or v_receipt->>'marketState'<>'not_required' then
    raise exception 'Non-flower cross-domain pricing policy did not use the same evaluator: %',v_receipt;
  end if;

  begin
    insert into atlas.ledger_commercial_quote_evaluation_benchmarks(
      receipt_id,market_observation_id,benchmark_amount,line_ref,metadata
    ) values (
      (v_receipt->>'receiptId')::uuid,
      v_benchmark_obs,
      150.00,
      '{}'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Cross-Ledger benchmark link should fail.';
  exception
    when sqlstate '23514' then
      null;
  end;

  select count(*) into v_count
  from information_schema.columns
  where table_schema='atlas'
    and table_name in (
      'ledger_commercial_pricing_policies',
      'ledger_commercial_market_observations',
      'ledger_commercial_quote_evaluation_receipts',
      'ledger_commercial_quote_evaluation_benchmarks'
    )
    and column_name='organization_id';
  if v_count<>0 then
    raise exception 'Ledger commercial market policy candidate must not depend on organization_id.';
  end if;

  if has_table_privilege('authenticated','atlas.ledger_commercial_pricing_policies','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_commercial_market_observations','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_commercial_quote_evaluation_receipts','SELECT')
     or has_table_privilege('authenticated','atlas.ledger_commercial_quote_evaluation_benchmarks','SELECT') then
    raise exception 'Authenticated browser role unexpectedly has direct SELECT access.';
  end if;

  if has_table_privilege('service_role','atlas.ledger_commercial_market_observations','UPDATE')
     or has_table_privilege('service_role','atlas.ledger_commercial_quote_evaluation_receipts','UPDATE')
     or has_table_privilege('service_role','atlas.ledger_commercial_quote_evaluation_benchmarks','UPDATE') then
    raise exception 'Append-only market/evaluation relations unexpectedly allow service UPDATE.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.ledger_commercial_quote_evaluate_v1(uuid,numeric,numeric,numeric,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(uuid,text,jsonb,uuid,numeric,numeric,text,jsonb,jsonb,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated browser role unexpectedly has direct function execution.';
  end if;

  if to_regclass('atlas.commercial_orders') is not null then
    execute 'select count(*) from atlas.commercial_orders' into v_orders_after;
    if v_orders_after<>v_orders_before then
      raise exception 'Quote policy/evaluation candidate created a Commercial Order.';
    end if;
  end if;

  if to_regclass('atlas.organization_spend_occurrences') is not null then
    execute 'select count(*) from atlas.organization_spend_occurrences' into v_spend_after;
    if v_spend_after<>v_spend_before then
      raise exception 'Quote policy/evaluation candidate created Organization Spend.';
    end if;
  end if;

  raise notice 'atlas_ledger_commercial_market_policy_v1 validation passed';
end
$validation$;

rollback;