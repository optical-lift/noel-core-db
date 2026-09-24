begin;

do $validation$
declare
  v_result jsonb;
  v_before_composition bigint;
  v_before_work bigint;
  v_before_orders bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
begin
  select count(*) into v_before_composition from atlas.composition_runs;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;

  -- 1. Mixed-source flower proof: exact physical coverage, unresolved economics.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{
        "sourceDomain":"commercial_order_line",
        "sourceRef":"fixture:flower-line-100-carnations"
      },
      "requirement":{
        "quantity":100,
        "unit":"stem",
        "requiredBy":"2026-09-24T12:00:00Z"
      },
      "planKey":"fixture:mixed-owned-external",
      "allocations":[
        {
          "allocationKey":"owned-ready-40",
          "candidateRef":{
            "sourceDomain":"flower_ready_inventory",
            "sourceRef":"fixture:ready-lot"
          },
          "qualificationState":"qualified",
          "sourceQuantity":40,
          "sourceUnit":"stem",
          "outputQuantity":40,
          "outputUnit":"stem",
          "costComponents":[]
        },
        {
          "allocationKey":"supplier-60",
          "candidateRef":{
            "sourceDomain":"external_supply_offering",
            "sourceRef":"fixture:supplier-carnation"
          },
          "qualificationState":"qualified",
          "sourceQuantity":75,
          "sourceUnit":"stem",
          "outputQuantity":60,
          "outputUnit":"stem",
          "excess":{
            "quantity":15,
            "unit":"stem",
            "dispositionState":"unresolved"
          },
          "costComponents":[
            {
              "componentKey":"merchandise",
              "state":"known",
              "amount":25.50,
              "currency":"USD",
              "sourceRef":"fixture:source-observation"
            },
            {
              "componentKey":"freight",
              "state":"unresolved",
              "sourceRef":"fixture:shipping-not-yet-known"
            }
          ]
        }
      ],
      "unresolved":[
        {
          "key":"freight",
          "blockingFor":["customer_price"],
          "sourceRef":"fixture:shipping-not-yet-known"
        }
      ],
      "metadata":{"fixture":"mixed_source_flower"}
    }'::jsonb
  );

  if v_result->>'state'<>'ready'
     or v_result->>'coverageState'<>'exact'
     or coalesce((v_result->>'completeForPlanning')::boolean,false)=false
     or v_result->>'economicState'<>'unresolved'
     or (v_result->>'unresolvedRequiredCostComponentCount')::integer<>1
     or (v_result->'knownCostTotalsByCurrency'->>'USD')::numeric<>25.50 then
    raise exception 'Mixed-source flower composition failed: %',v_result;
  end if;

  -- 2. Construction leak test: same contract, no flower vocabulary.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{
        "sourceDomain":"accepted_scope_requirement",
        "sourceRef":"fixture:flooring-material"
      },
      "requirement":{
        "quantity":2600,
        "unit":"sq_ft"
      },
      "planKey":"fixture:flooring-supplier-b",
      "allocations":[
        {
          "allocationKey":"supplier-b-flooring",
          "candidateRef":{
            "sourceDomain":"external_supply_offering",
            "sourceRef":"fixture:supplier-b-flooring"
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
    }'::jsonb
  );

  if v_result->>'coverageState'<>'exact'
     or v_result->>'economicState'<>'known'
     or (v_result->'knownCostTotalsByCurrency'->>'USD')::numeric<>7340
     or coalesce((v_result->>'completeForPlanning')::boolean,false)=false then
    raise exception 'Construction leak test failed: %',v_result;
  end if;

  -- 3. Undercoverage remains explicit.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"under"},
      "requirement":{"quantity":100,"unit":"unit"},
      "planKey":"undercovered",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":80,
          "outputUnit":"unit"
        }
      ]
    }'::jsonb
  );

  if v_result->>'coverageState'<>'undercovered'
     or coalesce((v_result->>'completeForPlanning')::boolean,true) then
    raise exception 'Undercoverage was not preserved: %',v_result;
  end if;

  -- 4. Overallocated output is explicit; source overbuy belongs in excess instead.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"over"},
      "requirement":{"quantity":100,"unit":"unit"},
      "planKey":"overcovered",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":120,
          "outputUnit":"unit"
        }
      ]
    }'::jsonb
  );

  if v_result->>'coverageState'<>'overcovered'
     or coalesce((v_result->>'completeForPlanning')::boolean,true)
     or jsonb_array_length(v_result->'validation'->'warnings')<1 then
    raise exception 'Overcoverage warning/position failed: %',v_result;
  end if;

  -- 5. Unknown cost never becomes zero.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"unknown-cost"},
      "requirement":{"quantity":1,"unit":"job"},
      "planKey":"unknown-cost",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"external_service","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"job",
          "costComponents":[
            {
              "componentKey":"subcontractor",
              "state":"unresolved"
            }
          ]
        }
      ]
    }'::jsonb
  );

  if v_result->>'economicState'<>'unresolved'
     or v_result->'knownCostTotalsByCurrency'<>'{}'::jsonb
     or (v_result->>'unresolvedRequiredCostComponentCount')::integer<>1 then
    raise exception 'Unknown cost was not preserved: %',v_result;
  end if;

  -- 6. No cost evidence is not called free/known.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"no-cost"},
      "requirement":{"quantity":1,"unit":"equipment_day"},
      "planKey":"no-cost-evidence",
      "allocations":[
        {
          "allocationKey":"owned-equipment",
          "candidateRef":{"sourceDomain":"owned_equipment","sourceRef":"roller"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"equipment_day"
        }
      ]
    }'::jsonb
  );

  if v_result->>'economicState'<>'no_cost_evidence'
     or v_result->'knownCostTotalsByCurrency'<>'{}'::jsonb then
    raise exception 'Absent cost evidence was misclassified: %',v_result;
  end if;

  -- 7. Multi-currency stays multi-currency; no implicit FX conversion.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"multi-currency"},
      "requirement":{"quantity":2,"unit":"unit"},
      "planKey":"multi-currency",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"a-cost","state":"known","amount":10,"currency":"USD"}
          ]
        },
        {
          "allocationKey":"b",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"b"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"unit",
          "costComponents":[
            {"componentKey":"b-cost","state":"known","amount":8,"currency":"EUR"}
          ]
        }
      ]
    }'::jsonb
  );

  if v_result->>'economicState'<>'known_multi_currency'
     or (v_result->'knownCostTotalsByCurrency'->>'USD')::numeric<>10
     or (v_result->'knownCostTotalsByCurrency'->>'EUR')::numeric<>8 then
    raise exception 'Multi-currency position failed: %',v_result;
  end if;

  -- 8. An unresolved/incompatible candidate cannot be smuggled into a plan.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"bad-qualification"},
      "requirement":{"quantity":1,"unit":"unit"},
      "planKey":"bad-qualification",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"unresolved",
          "outputQuantity":1,
          "outputUnit":"unit"
        }
      ]
    }'::jsonb
  );

  if v_result->>'state'<>'invalid'
     or coalesce((v_result->>'completeForPlanning')::boolean,true) then
    raise exception 'Unqualified candidate entered planning: %',v_result;
  end if;

  -- 9. Unit conversion cannot be silently invented.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"unit-mismatch"},
      "requirement":{"quantity":10,"unit":"serving"},
      "planKey":"unit-mismatch",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"ingredient","sourceRef":"a"},
          "qualificationState":"qualified",
          "sourceQuantity":20,
          "sourceUnit":"lb",
          "outputQuantity":10,
          "outputUnit":"lb"
        }
      ]
    }'::jsonb
  );

  if v_result->>'state'<>'invalid' then
    raise exception 'Silent unit conversion was admitted: %',v_result;
  end if;

  -- 10. A planning-blocking unresolved fact blocks plan completeness.
  v_result:=atlas.fulfillment_composition_position_v1(
    '{
      "contractVersion":"neutral_fulfillment_composition_v1",
      "requirementRef":{"sourceDomain":"fixture","sourceRef":"blocking"},
      "requirement":{"quantity":1,"unit":"job"},
      "planKey":"blocking-unresolved",
      "allocations":[
        {
          "allocationKey":"a",
          "candidateRef":{"sourceDomain":"fixture_candidate","sourceRef":"a"},
          "qualificationState":"qualified",
          "outputQuantity":1,
          "outputUnit":"job"
        }
      ],
      "unresolved":[
        {
          "key":"required_permit",
          "blockingFor":["planning"]
        }
      ]
    }'::jsonb
  );

  if v_result->>'coverageState'<>'exact'
     or (v_result->>'blockingPlanningUnresolvedCount')::integer<>1
     or coalesce((v_result->>'completeForPlanning')::boolean,true) then
    raise exception 'Planning-blocking unresolved fact did not block completeness: %',v_result;
  end if;

  -- 11. Pure evaluator creates no source/operational/commercial truth.
  if (select count(*) from atlas.composition_runs)<>v_before_composition
     or (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory then
    raise exception 'Neutral fulfillment composition created durable truth.';
  end if;

  -- 12. Browser roles do not receive internal evaluator access.
  if has_function_privilege(
       'authenticated',
       'atlas.fulfillment_composition_validate_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.fulfillment_composition_position_v1(jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.fulfillment_composition_validate_v1(jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.fulfillment_composition_position_v1(jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Neutral fulfillment composition privilege boundary is incorrect.';
  end if;

  raise notice 'PASS atlas_neutral_fulfillment_composition_v1: exact/under/over coverage, unresolved economics, multi-currency, domain-neutrality, and no-write boundaries hold';
end;
$validation$;

rollback;
