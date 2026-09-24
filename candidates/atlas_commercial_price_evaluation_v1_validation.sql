begin;

do $validation$
declare
  v_result jsonb;
  v_flower_packet jsonb;
  v_construction_packet jsonb;
  v_before_offers bigint;
  v_before_prices bigint;
  v_before_orders bigint;
  v_before_payments bigint;
  v_before_work bigint;
  v_before_spend bigint;
begin
  select count(*) into v_before_offers from atlas.commercial_offer_snapshots;
  select count(*) into v_before_prices from atlas.commercial_offering_prices;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;

  v_flower_packet:='{
    "contractVersion":"neutral_fulfillment_composition_v1",
    "requirementRef":{
      "sourceDomain":"commercial_order_line",
      "sourceRef":"fixture:carnation-line"
    },
    "requirement":{
      "quantity":100,
      "unit":"stem"
    },
    "planKey":"fixture:carnation-known-cost",
    "allocations":[
      {
        "allocationKey":"source",
        "candidateRef":{
          "sourceDomain":"external_supply_offering",
          "sourceRef":"fixture:carnation-source"
        },
        "qualificationState":"qualified",
        "sourceQuantity":100,
        "sourceUnit":"stem",
        "outputQuantity":100,
        "outputUnit":"stem",
        "costComponents":[
          {
            "componentKey":"landed_merchandise_and_freight",
            "state":"known",
            "amount":38.00,
            "currency":"USD"
          }
        ]
      }
    ]
  }'::jsonb;

  -- 1. Gross-margin formula + upward cent rounding.
  v_result:=atlas.commercial_price_evaluate_v1(
    v_flower_packet,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30,
      "currency":"USD",
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb
  );

  if v_result->>'state'<>'priced'
     or (v_result->>'totalKnownFulfillmentCost')::numeric<>38
     or (v_result->>'costPerUnit')::numeric<>0.38
     or (v_result->>'proposedUnitPrice')::numeric<>0.55
     or (v_result->>'proposedTotal')::numeric<>55
     or (v_result->>'realizedGrossMargin')::numeric<0.30 then
    raise exception 'Gross-margin flower pricing failed: %',v_result;
  end if;

  -- 2. Markup is not gross margin.
  v_result:=atlas.commercial_price_evaluate_v1(
    v_flower_packet,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.30,
      "currency":"USD",
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb
  );

  if (v_result->>'proposedUnitPrice')::numeric<>0.50
     or (v_result->>'proposedTotal')::numeric<>50
     or (v_result->>'proposedUnitPrice')::numeric=0.55 then
    raise exception 'Markup/gross-margin distinction failed: %',v_result;
  end if;

  -- 3. Minimum unit price is a floor, then upward rounding remains safe.
  v_result:=atlas.commercial_price_evaluate_v1(
    v_flower_packet,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.10,
      "minimumUnitPrice":0.565,
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb
  );

  if (v_result->>'proposedUnitPrice')::numeric<>0.57 then
    raise exception 'Minimum unit price / rounding floor failed: %',v_result;
  end if;

  -- 4. Construction leak test uses the same evaluator.
  v_construction_packet:='{
    "contractVersion":"neutral_fulfillment_composition_v1",
    "requirementRef":{
      "sourceDomain":"accepted_scope_requirement",
      "sourceRef":"fixture:flooring"
    },
    "requirement":{
      "quantity":2600,
      "unit":"sq_ft"
    },
    "planKey":"fixture:flooring-known-cost",
    "allocations":[
      {
        "allocationKey":"supplier-b",
        "candidateRef":{
          "sourceDomain":"external_supply_offering",
          "sourceRef":"fixture:flooring-source"
        },
        "qualificationState":"qualified",
        "sourceQuantity":2808,
        "sourceUnit":"sq_ft",
        "outputQuantity":2600,
        "outputUnit":"sq_ft",
        "excess":{
          "quantity":208,
          "unit":"sq_ft",
          "dispositionState":"expected_waste_or_remainder"
        },
        "costComponents":[
          {
            "componentKey":"material",
            "state":"known",
            "amount":7020,
            "currency":"USD"
          },
          {
            "componentKey":"freight",
            "state":"known",
            "amount":320,
            "currency":"USD"
          }
        ]
      }
    ]
  }'::jsonb;

  v_result:=atlas.commercial_price_evaluate_v1(
    v_construction_packet,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.25,
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb
  );

  if v_result->>'state'<>'priced'
     or (v_result->>'totalKnownFulfillmentCost')::numeric<>7340
     or (v_result->>'proposedUnitPrice')::numeric<>3.53
     or (v_result->>'proposedTotal')::numeric<>9178
     or (v_result->>'realizedMarkup')::numeric<0.25 then
    raise exception 'Construction pricing leak test failed: %',v_result;
  end if;

  -- 5. Unknown required cost blocks pricing.
  v_result:=atlas.commercial_price_evaluate_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"unknown-cost"},
      "requirement":{"quantity":10,"unit":"unit"},
      "planKey":"unknown-cost",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":10,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"merchandise","state":"known","amount":10,"currency":"USD"},
            {"componentKey":"freight","state":"unresolved"}
          ]
        }
      ]
    }'::jsonb,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'required_cost_unresolved' then
    raise exception 'Unknown cost did not block price: %',v_result;
  end if;

  -- 6. No cost evidence blocks pricing.
  v_result:=atlas.commercial_price_evaluate_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"no-cost"},
      "requirement":{"quantity":1,"unit":"job"},
      "planKey":"no-cost",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"job"
        }
      ]
    }'::jsonb,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.20
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'no_cost_evidence' then
    raise exception 'Absent cost evidence did not block price: %',v_result;
  end if;

  -- 7. Multi-currency blocks without a governed conversion rule.
  v_result:=atlas.commercial_price_evaluate_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"multi"},
      "requirement":{"quantity":2,"unit":"unit"},
      "planKey":"multi",
      "allocations":[
        {
          "allocationKey":"usd",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"usd"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"usd-cost","state":"known","amount":10,"currency":"USD"}
          ]
        },
        {
          "allocationKey":"eur",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"eur"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"eur-cost","state":"known","amount":8,"currency":"EUR"}
          ]
        }
      ]
    }'::jsonb,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.20
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'multi_currency_without_governed_conversion' then
    raise exception 'Multi-currency did not block price: %',v_result;
  end if;

  -- 8. Undercoverage blocks pricing.
  v_result:=atlas.commercial_price_evaluate_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"under"},
      "requirement":{"quantity":100,"unit":"unit"},
      "planKey":"under",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":80,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"cost","state":"known","amount":20,"currency":"USD"}
          ]
        }
      ]
    }'::jsonb,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.20
    }'::jsonb
  );

  if v_result->>'state'<>'blocked'
     or v_result->>'reason'<>'fulfillment_not_exactly_covered' then
    raise exception 'Undercoverage did not block price: %',v_result;
  end if;

  -- 9. Explicit known zero cost remains known zero, not "no cost evidence".
  v_result:=atlas.commercial_price_evaluate_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"zero"},
      "requirement":{"quantity":10,"unit":"unit"},
      "planKey":"known-zero",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":10,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"explicit-zero","state":"known","amount":0,"currency":"USD"}
          ]
        }
      ]
    }'::jsonb,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"markup",
      "rate":0.20,
      "minimumUnitPrice":0.10
    }'::jsonb
  );

  if v_result->>'state'<>'priced'
     or (v_result->>'totalKnownFulfillmentCost')::numeric<>0
     or (v_result->>'proposedUnitPrice')::numeric<>0.10
     or v_result->>'realizedMarkup' is not null then
    raise exception 'Explicit known zero-cost semantics failed: %',v_result;
  end if;

  -- 10. Invalid margin/markup policies fail closed.
  begin
    perform atlas.commercial_price_evaluate_v1(
      v_flower_packet,
      '{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"gross_margin",
        "rate":1.00
      }'::jsonb
    );
    raise exception 'Invalid gross margin >= 1 was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.commercial_price_evaluate_v1(
      v_flower_packet,
      '{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"markup",
        "rate":-0.01
      }'::jsonb
    );
    raise exception 'Negative markup was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.commercial_price_evaluate_v1(
      v_flower_packet,
      '{
        "contractVersion":"commercial_price_policy_input_v1",
        "method":"markup",
        "rate":0.20,
        "rounding":{"mode":"nearest","increment":0.01}
      }'::jsonb
    );
    raise exception 'Unsupported rounding mode was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 11. Pure evaluation creates no durable commercial/financial/work truth.
  if (select count(*) from atlas.commercial_offer_snapshots)<>v_before_offers
     or (select count(*) from atlas.commercial_offering_prices)<>v_before_prices
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend then
    raise exception 'Commercial price evaluation created durable truth.';
  end if;

  -- 12. Browser roles do not gain internal evaluator access.
  if has_function_privilege(
       'authenticated',
       'atlas.commercial_price_evaluate_v1(jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.commercial_price_evaluate_v1(jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Commercial price evaluator privilege boundary is incorrect.';
  end if;

  raise notice 'PASS atlas_commercial_price_evaluation_v1: gross margin, markup, rounding, minimum price, unknown-cost blocking, multi-currency blocking, and no-write boundaries hold';
end;
$validation$;

rollback;
