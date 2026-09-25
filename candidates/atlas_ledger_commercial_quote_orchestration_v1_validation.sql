begin;

do $validation$
declare
  v_person uuid:=gen_random_uuid();
  v_business uuid:=gen_random_uuid();
  v_market_actor uuid:=gen_random_uuid();
  v_case uuid;
  v_ledger uuid:=gen_random_uuid();
  v_policy uuid;
  v_obs uuid;
  v_obs_new uuid;
  v_policy_input jsonb;
  v_envelope jsonb;
  v_packet jsonb;
  v_assessment jsonb;
  v_receipt jsonb;
  v_has_feast_dependencies boolean:=false;

  v_basket jsonb;
  v_plan jsonb;
  v_feast_quote jsonb;
  v_feast_assessment jsonb;
begin
  insert into reality.entities(
    id,stable_key,entity_kind,display_name,identity_state,metadata
  ) values
    (v_person,'fixture-quote-orchestration-person-'||replace(v_person::text,'-',''),
      'person','Fixture Quote Operator','canonical','{}'::jsonb),
    (v_business,'fixture-quote-orchestration-business-'||replace(v_business::text,'-',''),
      'business','Fixture Quote Business','canonical','{}'::jsonb),
    (v_market_actor,'fixture-quote-orchestration-market-'||replace(v_market_actor::text,'-',''),
      'business','Fixture Market Benchmark','canonical','{}'::jsonb);

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
    desired_ledger_name,onboarding_state,onboarding_basis
  ) values (
    v_business,v_person,v_person,
    'Fixture Quote Ledger','ready_to_activate',
    '{"fixture":"ledger_commercial_quote_orchestration_v1"}'::jsonb
  ) returning id into v_case;

  insert into ledger.ledgers(
    id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata
  ) values (
    v_ledger,v_business,v_case,
    'fixture-quote-ledger-'||replace(v_ledger::text,'-',''),
    'Fixture Quote Ledger','active','{"fixture":true}'::jsonb
  );

  v_policy:=atlas.record_ledger_commercial_pricing_policy_service_v1(
    v_ledger,
    'primary_quote',
    'gross_margin',
    0.10,
    0.10,
    'USD',
    'strictly_below',
    null,
    '{"rounding":{"mode":"ceil","increment":0.01},"requiredCostFamilies":["merchandise","freight","pack_excess"]}'::jsonb,
    '2026-09-01 00:00:00+00',
    '{"fixture":"10 percent target and minimum, strictly below incumbent"}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  v_policy_input:=atlas.ledger_commercial_pricing_policy_input_v1(v_policy);
  if v_policy_input->>'contractVersion'<>'commercial_price_policy_input_v1'
     or v_policy_input->>'method'<>'gross_margin'
     or (v_policy_input->>'rate')::numeric<>0.10
     or v_policy_input->>'currency'<>'USD'
     or v_policy_input->'rounding'->>'mode'<>'ceil'
     or (v_policy_input->'rounding'->>'increment')::numeric<>0.01
     or (v_policy_input->'policyRef'->>'policyId')::uuid<>v_policy then
    raise exception 'Persisted policy did not translate faithfully to pricing input: %',v_policy_input;
  end if;

  v_obs:=atlas.record_ledger_commercial_market_observation_service_v1(
    v_ledger,
    v_market_actor,
    null,
    'Fixture incumbent basket benchmark',
    'incumbent_benchmark',
    '{"market":"fixture"}'::jsonb,
    '{"family":"fixture-product"}'::jsonb,
    '2026-09-25 12:00:00+00',
    '2026-09-25 00:00:00+00',
    '2026-09-26 00:00:00+00',
    1.50,
    'USD',
    1,
    'unit',
    'confirmed',
    null,
    null,
    '{}'::jsonb,
    'manual_capture',
    'fixture:benchmark',
    '{"fixture":true}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  v_envelope:=atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
    v_ledger,
    'primary_quote',
    '2026-09-25 13:00:00+00',
    'USD',
    jsonb_build_array(
      jsonb_build_object(
        'marketObservationId',v_obs,
        'benchmarkAmount',150.00,
        'lineRef',jsonb_build_object('lineKey','fixture-line')
      )
    )
  );

  if v_envelope->>'state'<>'ready'
     or (v_envelope->>'benchmarkTotal')::numeric<>150.00
     or (v_envelope->'envelope'->>'targetProtectedCostCeiling')::numeric<>135.00
     or (v_envelope->'envelope'->>'marketQuoteCeilingInclusive')::boolean<>false then
    raise exception 'Benchmark envelope did not produce expected strict 10 percent budget: %',v_envelope;
  end if;

  v_packet:=jsonb_build_object(
    'contractVersion','fixture_ledger_quote_packet_v1',
    'state','complete',
    'currency','USD',
    'protectedCostTotal',120.00,
    'wholeOrderTotal',142.50,
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','a',
        'state','priced',
        'currency','USD',
        'totalKnownFulfillmentCost',70.00,
        'proposedTotal',82.50
      ),
      jsonb_build_object(
        'lineKey','b',
        'state','priced',
        'currency','USD',
        'totalKnownFulfillmentCost',50.00,
        'proposedTotal',60.00
      )
    )
  );

  v_assessment:=atlas.ledger_commercial_quote_packet_evaluate_v1(
    v_ledger,
    'primary_quote',
    '2026-09-25 13:00:00+00',
    v_packet,
    jsonb_build_array(
      jsonb_build_object(
        'marketObservationId',v_obs,
        'benchmarkAmount',150.00,
        'lineRef',jsonb_build_object('lineKey','fixture-line')
      )
    )
  );

  if v_assessment->>'state'<>'evaluated'
     or v_assessment->>'decisionState'<>'eligible'
     or v_assessment->'evaluation'->>'pricingState'<>'target_met'
     or v_assessment->'evaluation'->>'marketState'<>'passes'
     or (v_assessment->'evaluation'->>'customerSavingsAmount')::numeric<>7.50 then
    raise exception 'Complete quote packet did not pass both commercial gates: %',v_assessment;
  end if;

  begin
    perform atlas.ledger_commercial_quote_packet_evaluate_v1(
      v_ledger,
      'primary_quote',
      '2026-09-25 13:00:00+00',
      jsonb_set(v_packet,'{protectedCostTotal}','119'::jsonb,true),
      jsonb_build_array(
        jsonb_build_object('marketObservationId',v_obs,'benchmarkAmount',150.00)
      )
    );
    raise exception 'Inconsistent packet protected-cost total should fail.';
  exception when sqlstate '23514' then
    null;
  end;

  v_receipt:=atlas.record_ledger_commercial_quote_packet_receipt_service_v1(
    v_ledger,
    'fixture-orchestrated-quote',
    '{"sourceDomain":"fixture_quote_intake","sourceRef":"fixture-request"}'::jsonb,
    'primary_quote',
    '2026-09-25 13:00:00+00',
    v_packet,
    jsonb_build_array(
      jsonb_build_object(
        'marketObservationId',v_obs,
        'benchmarkAmount',150.00,
        'lineRef',jsonb_build_object('lineKey','fixture-line')
      )
    ),
    '{"fixture":true}'::jsonb,
    '{}'::jsonb
  );

  if v_receipt->>'state'<>'recorded'
     or v_receipt->'receipt'->>'decisionState'<>'eligible' then
    raise exception 'Orchestrated quote receipt was not recorded: %',v_receipt;
  end if;

  v_obs_new:=atlas.record_ledger_commercial_market_observation_service_v1(
    v_ledger,
    v_market_actor,
    v_obs,
    'Fixture replacement incumbent benchmark',
    'incumbent_benchmark',
    '{"market":"fixture"}'::jsonb,
    '{"family":"fixture-product"}'::jsonb,
    '2026-09-25 14:00:00+00',
    '2026-09-25 14:00:00+00',
    '2026-09-26 00:00:00+00',
    1.45,
    'USD',
    1,
    'unit',
    'confirmed',
    null,
    null,
    '{}'::jsonb,
    'manual_capture',
    'fixture:benchmark:new',
    '{"fixture":true}'::jsonb,
    '{"fixture":true}'::jsonb
  );

  begin
    perform atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
      v_ledger,
      'primary_quote',
      '2026-09-25 15:00:00+00',
      'USD',
      jsonb_build_array(
        jsonb_build_object('marketObservationId',v_obs,'benchmarkAmount',150.00)
      )
    );
    raise exception 'Superseded benchmark should not be usable after replacement observation.';
  exception when sqlstate '23514' then
    null;
  end;

  if has_function_privilege(
       'authenticated',
       'atlas.ledger_commercial_quote_packet_evaluate_v1(uuid,text,timestamptz,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.feast_guild_flower_quote_under_ledger_policy_v1(uuid,text,timestamptz,jsonb,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated browser role unexpectedly has direct orchestration execution.';
  end if;

  select (
    to_regprocedure('atlas.feast_guild_flower_source_candidate_evaluate_v1(jsonb,jsonb)') is not null
    and to_regprocedure('atlas.commercial_price_evaluate_v1(jsonb,jsonb)') is not null
  ) into v_has_feast_dependencies;

  if v_has_feast_dependencies then
    v_basket:='{
      "contractVersion":"feast_guild_flower_basket_v1",
      "basketKey":"fixture-ledger-native-feast-quote",
      "requestedForDate":"2026-09-26",
      "lines":[
        {
          "lineKey":"carnations",
          "description":"Standard Carnations",
          "quantity":90,
          "unit":"stem",
          "requirements":[
            {"requirementKey":"flower_family","required":true,"evidenceRequired":true,"expected":{"equals":"carnation"}},
            {"requirementKey":"grade","required":true,"evidenceRequired":true,"expected":{"equals":"standard"}},
            {"requirementKey":"requested_date","required":true,"evidenceRequired":true,"expected":{"onOrBefore":"2026-09-26"}}
          ]
        }
      ]
    }'::jsonb;

    v_plan:='[
      {
        "lineKey":"carnations",
        "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:carnation-standard"},
        "qualificationNodes":[
          {"requirementKey":"flower_family","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"flowerFamily=carnation"}]},
          {"requirementKey":"grade","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"grade=standard"}]},
          {"requirementKey":"requested_date","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"availableBy=2026-09-26"}]}
        ],
        "fulfillmentPacket":{
          "contractVersion":"neutral_fulfillment_composition_v1",
          "requirementRef":{"sourceDomain":"feast_guild_flower_basket_v1","sourceRef":"fixture-ledger-native-feast-quote:carnations"},
          "requirement":{"quantity":90,"unit":"stem","requiredBy":"2026-09-26T12:00:00Z"},
          "planKey":"fixture-plan:carnations:100-pack",
          "allocations":[
            {
              "allocationKey":"fixture-carnation-pack",
              "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:carnation-standard"},
              "qualificationState":"qualified",
              "sourceQuantity":100,
              "sourceUnit":"stem",
              "outputQuantity":90,
              "outputUnit":"stem",
              "excess":{"quantity":10,"unit":"stem","dispositionState":"unresolved_recovery"},
              "costComponents":[
                {"componentKey":"landed_supplier_cost","state":"known","required":true,"amount":100.00,"currency":"USD"}
              ]
            }
          ]
        },
        "sourcePreference":{
          "tier":"imported",
          "evidence":[{"sourceRef":"fixture:supplier:carnation-standard","fact":"originClass=imported"}]
        },
        "customerFacingSourceFacts":{"sourceClass":"imported"},
        "selectionBasis":{"decisionKind":"fixture_explicit"}
      }
    ]'::jsonb;

    v_feast_quote:=atlas.feast_guild_flower_ledger_quote_prepare_v1(
      v_basket,
      v_plan,
      v_policy_input
    );

    if v_feast_quote->>'state'<>'complete'
       or (v_feast_quote->>'protectedCostTotal')::numeric<>100.00
       or v_feast_quote ? 'snapshotDraft' then
      raise exception 'Ledger-native Feast quote packet failed or leaked legacy snapshot context: %',v_feast_quote;
    end if;

    begin
      perform atlas.feast_guild_flower_quote_under_ledger_policy_v1(
        v_ledger,
        'primary_quote',
        '2026-09-25 13:00:00+00',
        v_basket,
        v_plan,
        jsonb_build_array(
          jsonb_build_object(
            'marketObservationId',v_obs_new,
            'benchmarkAmount',145.00,
            'lineRef',jsonb_build_object('lineKey','carnations')
          )
        )
      );
      raise exception 'Expected future benchmark observation to be rejected during Feast assessment.';
    exception when sqlstate '23514' then
      null;
    end;

    v_feast_assessment:=atlas.feast_guild_flower_quote_under_ledger_policy_v1(
      v_ledger,
      'primary_quote',
      '2026-09-25 15:00:00+00',
      v_basket,
      v_plan,
      jsonb_build_array(
        jsonb_build_object(
          'marketObservationId',v_obs_new,
          'benchmarkAmount',145.00,
          'lineRef',jsonb_build_object('lineKey','carnations')
        )
      )
    );

    if v_feast_assessment->>'state'<>'eligible'
       or v_feast_assessment->'commercialAssessment'->>'decisionState'<>'eligible'
       or (v_feast_assessment->'quotePacket'->>'protectedCostTotal')::numeric<>100.00 then
      raise exception 'Policy-bound Feast quote did not pass the Ledger market/margin gates: %',v_feast_assessment;
    end if;

    raise notice 'Feast Guild cross-branch adapter proof passed.';
  else
    raise notice 'Feast Guild cross-branch adapter proof deferred: sibling fulfillment candidate functions are not installed in this validation database.';
  end if;

  raise notice 'atlas_ledger_commercial_quote_orchestration_v1 validation passed';
end
$validation$;

rollback;