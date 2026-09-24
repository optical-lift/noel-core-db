begin;

do $validation$
declare
  v_basket jsonb;
  v_plans jsonb;
  v_policy jsonb;
  v_context jsonb;

  v_result jsonb;
  v_incomplete_plans jsonb;
  v_missing_plan_plans jsonb;
  v_missing_evidence_plans jsonb;
  v_mismatched_quantity_plans jsonb;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_work bigint;
  v_before_inventory bigint;
  v_before_snapshots bigint;
  v_before_acquisitions bigint;

  v_after_orders bigint;
  v_after_payments bigint;
  v_after_spend bigint;
  v_after_work bigint;
  v_after_inventory bigint;
  v_after_snapshots bigint;
  v_after_acquisitions bigint;

  v_price numeric;
  v_total numeric;
begin
  v_basket:=$basket$
  {
    "contractVersion":"feast_guild_flower_basket_v1",
    "basketKey":"fixture-whole-order-complete",
    "requestedForDate":"2026-09-25",
    "lines":[
      {
        "lineKey":"carnations",
        "description":"Standard Carnations",
        "quantity":90,
        "unit":"stem",
        "requirements":[
          {"requirementKey":"flower_family","required":true,"evidenceRequired":true,"expected":{"equals":"carnation"}},
          {"requirementKey":"grade","required":true,"evidenceRequired":true,"expected":{"equals":"standard"}},
          {"requirementKey":"requested_date","required":true,"evidenceRequired":true,"expected":{"onOrBefore":"2026-09-25"}}
        ]
      },
      {
        "lineKey":"white-roses-60cm",
        "description":"White Roses 60 cm",
        "quantity":50,
        "unit":"stem",
        "requirements":[
          {"requirementKey":"flower_family","required":true,"evidenceRequired":true,"expected":{"equals":"rose"}},
          {"requirementKey":"color","required":true,"evidenceRequired":true,"expected":{"equals":"white"}},
          {"requirementKey":"stem_length_cm","required":true,"evidenceRequired":true,"expected":{"minimum":60}},
          {"requirementKey":"requested_date","required":true,"evidenceRequired":true,"expected":{"onOrBefore":"2026-09-25"}}
        ]
      },
      {
        "lineKey":"eucalyptus",
        "description":"Eucalyptus",
        "quantity":5,
        "unit":"bunch",
        "requirements":[
          {"requirementKey":"product_family","required":true,"evidenceRequired":true,"expected":{"equals":"eucalyptus"}},
          {"requirementKey":"requested_date","required":true,"evidenceRequired":true,"expected":{"onOrBefore":"2026-09-25"}}
        ]
      }
    ]
  }
  $basket$::jsonb;

  v_plans:=$plans$
  [
    {
      "lineKey":"carnations",
      "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:carnation-standard"},
      "qualificationNodes":[
        {"requirementKey":"flower_family","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"flowerFamily=carnation"}]},
        {"requirementKey":"grade","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"grade=standard"}]},
        {"requirementKey":"requested_date","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:carnation-standard","fact":"availableBy=2026-09-25"}]}
      ],
      "fulfillmentPacket":{
        "contractVersion":"neutral_fulfillment_composition_v1",
        "requirementRef":{"sourceDomain":"feast_guild_flower_basket_v1","sourceRef":"fixture-whole-order-complete:carnations"},
        "requirement":{"quantity":90,"unit":"stem","requiredBy":"2026-09-25T12:00:00Z"},
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
              {"componentKey":"landed_supplier_cost","state":"known","required":true,"amount":38.00,"currency":"USD","details":{"fixture":true,"includesFreight":true}}
            ]
          }
        ],
        "metadata":{"fixture":"feast_guild_whole_order_quote_v1"}
      },
      "customerFacingSourceFacts":{"sourceClass":"imported","originCountry":"fixture-country","originEvidenceState":"fixture_explicit"},
      "selectionBasis":{"decisionKind":"fixture_selected","reason":"pack-excess proof"}
    },
    {
      "lineKey":"white-roses-60cm",
      "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:white-rose-60"},
      "qualificationNodes":[
        {"requirementKey":"flower_family","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:white-rose-60","fact":"flowerFamily=rose"}]},
        {"requirementKey":"color","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:white-rose-60","fact":"color=white"}]},
        {"requirementKey":"stem_length_cm","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:white-rose-60","fact":"stemLengthCm=60"}]},
        {"requirementKey":"requested_date","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:white-rose-60","fact":"availableBy=2026-09-25"}]}
      ],
      "fulfillmentPacket":{
        "contractVersion":"neutral_fulfillment_composition_v1",
        "requirementRef":{"sourceDomain":"feast_guild_flower_basket_v1","sourceRef":"fixture-whole-order-complete:white-roses-60cm"},
        "requirement":{"quantity":50,"unit":"stem","requiredBy":"2026-09-25T12:00:00Z"},
        "planKey":"fixture-plan:white-roses-60cm",
        "allocations":[
          {
            "allocationKey":"fixture-white-rose-source",
            "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:white-rose-60"},
            "qualificationState":"qualified",
            "sourceQuantity":50,
            "sourceUnit":"stem",
            "outputQuantity":50,
            "outputUnit":"stem",
            "costComponents":[
              {"componentKey":"landed_supplier_cost","state":"known","required":true,"amount":55.00,"currency":"USD","details":{"fixture":true,"includesFreight":true}}
            ]
          }
        ],
        "metadata":{"fixture":"feast_guild_whole_order_quote_v1"}
      },
      "customerFacingSourceFacts":{"sourceClass":"american_grown","originCountry":"US","originState":"CA","originEvidenceState":"fixture_explicit"},
      "selectionBasis":{"decisionKind":"fixture_selected","reason":"specification proof"}
    },
    {
      "lineKey":"eucalyptus",
      "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:eucalyptus"},
      "qualificationNodes":[
        {"requirementKey":"product_family","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:eucalyptus","fact":"productFamily=eucalyptus"}]},
        {"requirementKey":"requested_date","required":true,"state":"satisfied","evidence":[{"sourceRef":"fixture:eucalyptus","fact":"availableBy=2026-09-25"}]}
      ],
      "fulfillmentPacket":{
        "contractVersion":"neutral_fulfillment_composition_v1",
        "requirementRef":{"sourceDomain":"feast_guild_flower_basket_v1","sourceRef":"fixture-whole-order-complete:eucalyptus"},
        "requirement":{"quantity":5,"unit":"bunch","requiredBy":"2026-09-25T12:00:00Z"},
        "planKey":"fixture-plan:eucalyptus",
        "allocations":[
          {
            "allocationKey":"fixture-eucalyptus-source",
            "candidateRef":{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier:eucalyptus"},
            "qualificationState":"qualified",
            "sourceQuantity":5,
            "sourceUnit":"bunch",
            "outputQuantity":5,
            "outputUnit":"bunch",
            "costComponents":[
              {"componentKey":"landed_supplier_cost","state":"known","required":true,"amount":25.00,"currency":"USD","details":{"fixture":true,"includesFreight":true}}
            ]
          }
        ],
        "metadata":{"fixture":"feast_guild_whole_order_quote_v1"}
      },
      "customerFacingSourceFacts":{"sourceClass":"regional_us","originCountry":"US","originEvidenceState":"fixture_explicit"},
      "selectionBasis":{"decisionKind":"fixture_selected","reason":"whole-order aggregation proof"}
    }
  ]
  $plans$::jsonb;

  v_policy:='{
    "contractVersion":"commercial_price_policy_input_v1",
    "method":"gross_margin",
    "rate":0.30,
    "currency":"USD",
    "rounding":{"mode":"ceil","increment":0.01}
  }'::jsonb;

  v_context:='{
    "organizationId":"00000000-0000-0000-0000-000000000001",
    "organizationUnitId":null,
    "snapshotKey":"fixture-thursday-whole-order-v1",
    "title":"Fixture Thursday florist order",
    "validFrom":"2026-09-24T15:00:00Z",
    "validUntil":"2026-09-24T18:00:00Z",
    "sourceRef":"fixture:feast-guild-whole-order-quote-v1"
  }'::jsonb;

  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_snapshots from atlas.commercial_offer_snapshots;
  select count(*) into v_before_acquisitions from atlas.external_acquisition_commitments;

  -- Complete multi-line quote.
  v_result:=atlas.feast_guild_flower_quote_prepare_v1(
    v_basket,v_plans,v_policy,v_context
  );

  if v_result->>'state'<>'complete'
     or (v_result->>'lineCount')::integer<>3
     or (v_result->>'pricedLineCount')::integer<>3
     or (v_result->>'blockedLineCount')::integer<>0
     or v_result->>'currency'<>'USD'
     or (v_result->>'wholeOrderTotal')::numeric<>169.65 then
    raise exception 'Complete whole-order quote failed: %',v_result;
  end if;

  select (l.value->>'proposedUnitPrice')::numeric,
         (l.value->>'proposedTotal')::numeric
  into v_price,v_total
  from jsonb_array_elements(v_result->'lines') as l(value)
  where l.value->>'lineKey'='carnations';

  if v_price<>0.61 or v_total<>54.90 then
    raise exception 'Carnation pack-excess price was not protected: %',v_result;
  end if;

  select (l.value->>'proposedUnitPrice')::numeric,
         (l.value->>'proposedTotal')::numeric
  into v_price,v_total
  from jsonb_array_elements(v_result->'lines') as l(value)
  where l.value->>'lineKey'='white-roses-60cm';

  if v_price<>1.58 or v_total<>79.00 then
    raise exception 'White rose price failed: %',v_result;
  end if;

  select (l.value->>'proposedUnitPrice')::numeric,
         (l.value->>'proposedTotal')::numeric
  into v_price,v_total
  from jsonb_array_elements(v_result->'lines') as l(value)
  where l.value->>'lineKey'='eucalyptus';

  if v_price<>7.15 or v_total<>35.75 then
    raise exception 'Eucalyptus price failed: %',v_result;
  end if;

  if v_result->'snapshotDraft'->>'offerState'<>'complete'
     or jsonb_array_length(v_result->'snapshotDraft'->'lines')<>3
     or v_result->'snapshotDraft'->>'snapshotKey'<>'fixture-thursday-whole-order-v1' then
    raise exception 'Complete snapshot draft failed: %',v_result->'snapshotDraft';
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_result->'lines') as l(value)
    where l.value->>'lineKey'='white-roses-60cm'
      and l.value->'customerFacingSourceFacts'->>'sourceClass'='american_grown'
      and l.value->'customerFacingSourceFacts'->>'originState'='CA'
  ) then
    raise exception 'Customer-facing source facts were not preserved.';
  end if;

  -- Unknown freight must block the entire quote total rather than become zero.
  v_incomplete_plans:=jsonb_set(
    v_plans,
    '{2,fulfillmentPacket,allocations,0,costComponents}'::text[],
    '[
      {"componentKey":"supplier_merchandise","state":"known","required":true,"amount":25.00,"currency":"USD"},
      {"componentKey":"freight","state":"unresolved","required":true,"details":{"reason":"supplier has not supplied freight quote"}}
    ]'::jsonb,
    false
  );

  v_result:=atlas.feast_guild_flower_quote_prepare_v1(
    v_basket,v_incomplete_plans,v_policy,v_context
  );

  if v_result->>'state'<>'incomplete'
     or (v_result->>'pricedLineCount')::integer<>2
     or (v_result->>'blockedLineCount')::integer<>1
     or (v_result->>'pricedSubtotal')::numeric<>133.90
     or v_result->'wholeOrderTotal'<>'null'::jsonb
     or v_result->'snapshotDraft'->>'offerState'<>'incomplete_evidence' then
    raise exception 'Unresolved freight did not block whole-order quote: %',v_result;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_result->'lines') as l(value),
         jsonb_array_elements(l.value->'blockingReasons') as b(value)
    where l.value->>'lineKey'='eucalyptus'
      and b.value->>'reason'='line_pricing_blocked'
      and b.value->>'pricingReason'='required_cost_unresolved'
  ) then
    raise exception 'Unresolved freight block reason was not preserved: %',v_result;
  end if;

  -- Missing selected source plan must stay visible and block the total.
  v_missing_plan_plans:=v_plans-2;
  v_result:=atlas.feast_guild_flower_quote_prepare_v1(
    v_basket,v_missing_plan_plans,v_policy,v_context
  );

  if v_result->>'state'<>'incomplete'
     or (v_result->>'blockedLineCount')::integer<>1
     or v_result->'wholeOrderTotal'<>'null'::jsonb then
    raise exception 'Missing selected plan did not block quote: %',v_result;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_result->'lines') as l(value),
         jsonb_array_elements(l.value->'blockingReasons') as b(value)
    where l.value->>'lineKey'='eucalyptus'
      and b.value->>'reason'='missing_selected_line_plan'
  ) then
    raise exception 'Missing plan reason not preserved: %',v_result;
  end if;

  -- A satisfied required qualification without evidence must block.
  v_missing_evidence_plans:=jsonb_set(
    v_plans,
    '{0,qualificationNodes,0,evidence}'::text[],
    '[]'::jsonb,
    false
  );

  v_result:=atlas.feast_guild_flower_quote_prepare_v1(
    v_basket,v_missing_evidence_plans,v_policy,v_context
  );

  if v_result->>'state'<>'incomplete'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'lines') as l(value),
            jsonb_array_elements(l.value->'blockingReasons') as b(value)
       where l.value->>'lineKey'='carnations'
         and b.value->>'reason'='required_qualification_evidence_missing'
     ) then
    raise exception 'Evidence-required qualification leak: %',v_result;
  end if;

  -- Fulfillment quantity/unit must match the florist request exactly.
  v_mismatched_quantity_plans:=jsonb_set(
    v_plans,
    '{1,fulfillmentPacket,requirement,quantity}'::text[],
    '49'::jsonb,
    false
  );

  v_result:=atlas.feast_guild_flower_quote_prepare_v1(
    v_basket,v_mismatched_quantity_plans,v_policy,v_context
  );

  if v_result->>'state'<>'incomplete'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'lines') as l(value),
            jsonb_array_elements(l.value->'blockingReasons') as b(value)
       where l.value->>'lineKey'='white-roses-60cm'
         and b.value->>'reason'='fulfillment_quantity_or_unit_mismatch'
     ) then
    raise exception 'Fulfillment quantity mismatch leak: %',v_result;
  end if;

  select count(*) into v_after_orders from atlas.commercial_orders;
  select count(*) into v_after_payments from atlas.commercial_payments;
  select count(*) into v_after_spend from atlas.organization_spend_occurrences;
  select count(*) into v_after_work from atlas.work_requirements;
  select count(*) into v_after_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_after_snapshots from atlas.commercial_offer_snapshots;
  select count(*) into v_after_acquisitions from atlas.external_acquisition_commitments;

  if v_after_orders<>v_before_orders
     or v_after_payments<>v_before_payments
     or v_after_spend<>v_before_spend
     or v_after_work<>v_before_work
     or v_after_inventory<>v_before_inventory
     or v_after_snapshots<>v_before_snapshots
     or v_after_acquisitions<>v_before_acquisitions then
    raise exception 'Read-only quote preparation created durable commercial/execution truth.';
  end if;

  raise notice 'PASS atlas_feast_guild_whole_order_quote_v1: 3-line quote = $169.65; pack excess protected; unresolved freight, missing plan/evidence, and quantity mismatch fail closed; no downstream writes';
end;
$validation$;

rollback;
