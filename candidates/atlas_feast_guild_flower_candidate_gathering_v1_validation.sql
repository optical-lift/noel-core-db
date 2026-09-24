begin;

do $validation$
declare
  v_line jsonb;
  v_ready jsonb;
  v_owned jsonb;
  v_eval jsonb;

  v_offering jsonb;
  v_observation jsonb;
  v_external jsonb;
  v_external_unknown_freight jsonb;
  v_external_fee_incomplete jsonb;
  v_external_no_delivery jsonb;
  v_external_no_tier_evidence jsonb;
  v_external_unavailable jsonb;

  v_policy_candidates jsonb;
  v_selection jsonb;
  v_quote jsonb;

  v_org_id uuid;
  v_farm_id uuid;
  v_subject_id uuid;
  v_relationship_id uuid;
  v_supply_offering_id uuid;
  v_supply_result jsonb;
  v_supply_observation_id uuid;
  v_basket jsonb;
  v_gathered jsonb;
  v_whole jsonb;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_work bigint;
  v_before_inventory bigint;
  v_before_snapshots bigint;
  v_before_acquisitions bigint;
begin
  v_line:='{
    "basketKey":"fixture-gather",
    "lineKey":"carnations",
    "description":"Standard Carnations",
    "requestedForDate":"2026-09-25",
    "quantity":90,
    "unit":"stem",
    "requirements":[
      {
        "requirementKey":"flower_family",
        "required":true,
        "evidenceRequired":true,
        "expected":{"equals":"carnation"}
      },
      {
        "requirementKey":"grade",
        "required":true,
        "evidenceRequired":true,
        "expected":{"equals":"standard"}
      }
    ]
  }'::jsonb;

  -- Elm Ready projection uses AVAILABLE quantity and refuses to invent owned economic cost.
  v_ready:='{
    "readyLotId":"00000000-0000-0000-0000-000000000101",
    "farmId":"00000000-0000-0000-0000-000000000102",
    "cropProfileId":"00000000-0000-0000-0000-000000000103",
    "cropLabel":"Carnation",
    "variety":"Standard",
    "productLabel":"Standard Carnation",
    "inventoryKind":"stem",
    "birthQuantity":100,
    "availableQuantity":95,
    "unit":"stem",
    "quantityExactness":"exact",
    "readyDate":"2026-09-24",
    "retailUnitValue":2.00,
    "retailCurrency":"USD",
    "metadata":{"flowerFamily":"carnation","grade":"standard","productForm":"stem"}
  }'::jsonb;

  v_owned:=atlas.feast_guild_flower_owned_ready_candidate_v1(v_line,v_ready);

  if (v_owned->'fulfillmentPacket'->'allocations'->0->>'sourceQuantity')::numeric<>90
     or v_owned->'sourcePreference'->>'tier'<>'elm_owned_or_grown'
     or not exists(
       select 1
       from jsonb_array_elements(v_owned->'qualificationNodes') n(value)
       where n.value->>'requirementKey'='source_quantity_capacity'
         and n.value->>'state'='satisfied'
         and n.value->'evidence'->0->>'fact' like '%available=95%'
     ) then
    raise exception 'Owned Ready candidate did not use current available quantity: %',v_owned;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_owned->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
    where c.value->>'componentKey'='owned_inventory_economic_cost'
      and c.value->>'state'='unresolved'
      and c.value->'details'->>'reason'='governed_owned_inventory_cost_basis_not_established'
  ) then
    raise exception 'Owned Ready candidate did not preserve unresolved cost basis: %',v_owned;
  end if;

  if exists(
    select 1
    from jsonb_array_elements(v_owned->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
    where c.value->>'state'='known'
      and (c.value->>'amount')::numeric=180
  ) then
    raise exception 'Owned Ready candidate improperly used retail valuation as cost.';
  end if;

  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line,v_owned);
  if v_eval->>'state'<>'excluded'
     or not exists(
       select 1 from jsonb_array_elements(v_eval->'reasons') r(value)
       where r.value->>'reason'='landed_economic_cost_not_known'
     ) then
    raise exception 'Owned Ready unresolved cost was allowed into automatic economic selection: %',v_eval;
  end if;

  -- Birth 100 but only 20 available: a 30-stem request is not lawfully covered.
  v_owned:=atlas.feast_guild_flower_owned_ready_candidate_v1(
    jsonb_set(v_line,'{quantity}','30'::jsonb,false),
    jsonb_set(v_ready,'{availableQuantity}','20'::jsonb,false)
  );

  if not exists(
    select 1
    from jsonb_array_elements(v_owned->'qualificationNodes') n(value)
    where n.value->>'requirementKey'='source_quantity_capacity'
      and n.value->>'state'='unsatisfied'
  ) then
    raise exception 'Owned Ready capacity used birth quantity instead of available quantity: %',v_owned;
  end if;

  -- A Ready lot after the florist requested date is not date-qualified.
  v_owned:=atlas.feast_guild_flower_owned_ready_candidate_v1(
    v_line,
    jsonb_set(v_ready,'{readyDate}','"2026-09-26"'::jsonb,false)
  );

  if not exists(
    select 1
    from jsonb_array_elements(v_owned->'qualificationNodes') n(value)
    where n.value->>'requirementKey'='source_requested_date'
      and n.value->>'state'='unsatisfied'
  ) then
    raise exception 'Owned Ready future date was treated as currently usable: %',v_owned;
  end if;

  -- Complete external offer: 90 requested, 100-stem pack, $38 per 100, complete landed terms.
  v_offering:='{
    "externalSupplyOfferingId":"00000000-0000-0000-0000-000000000201",
    "supplierRelationshipId":"00000000-0000-0000-0000-000000000202",
    "stableKey":"fixture-carnation",
    "sourceItemKey":"fixture-carnation-100",
    "sourceLabel":"Standard Carnation",
    "offeringKind":"cut_flower",
    "sourceUnit":"stem",
    "specification":{
      "flowerFamily":"carnation",
      "grade":"standard",
      "productLabel":"Standard Carnation",
      "productForm":"stem"
    }
  }'::jsonb;

  v_observation:='{
    "externalSupplyOfferObservationId":"00000000-0000-0000-0000-000000000203",
    "observationKey":"fixture-carnation-current",
    "observedAt":"2026-09-24T15:00:00Z",
    "effectiveFrom":"2026-09-24",
    "effectiveUntil":"2026-09-25",
    "priceAmount":38.00,
    "currency":"USD",
    "priceBasisState":"source_explicit",
    "priceQuantity":100,
    "priceUnit":"stem",
    "packQuantity":100,
    "packUnit":"stem",
    "availabilityState":"available",
    "terms":{
      "freightIncluded":true,
      "additionalFeesComplete":true
    },
    "sourceContext":{
      "availableQuantity":100,
      "availableQuantityUnit":"stem",
      "deliveryDate":"2026-09-25",
      "sourcePreference":{
        "tier":"imported",
        "evidence":[
          {"sourceRef":"fixture:provider:carnation","fact":"countryOfOrigin=CO"}
        ]
      },
      "originCountry":"CO",
      "grower":"Fixture Grower"
    }
  }'::jsonb;

  v_external:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,v_offering,v_observation,'2026-09-24'::date
  );

  if (v_external->'fulfillmentPacket'->'allocations'->0->>'sourceQuantity')::numeric<>100
     or (v_external->'fulfillmentPacket'->'allocations'->0->'excess'->>'quantity')::numeric<>10
     or not exists(
       select 1
       from jsonb_array_elements(v_external->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
       where c.value->>'componentKey'='supplier_merchandise'
         and c.value->>'state'='known'
         and (c.value->>'amount')::numeric=38.00
         and c.value->>'currency'='USD'
     ) then
    raise exception 'External pack/price arithmetic failed: %',v_external;
  end if;

  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line,v_external);
  if v_eval->>'state'<>'selectable'
     or (v_eval->>'landedEconomicCost')::numeric<>38.00 then
    raise exception 'Complete external candidate did not become selectable: %',v_eval;
  end if;

  -- Unknown freight remains unresolved.
  v_external_unknown_freight:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,
    v_offering,
    jsonb_set(
      v_observation,
      '{terms}',
      '{"freightIncluded":false,"additionalFeesComplete":true}'::jsonb,
      false
    ),
    '2026-09-24'::date
  );

  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line,v_external_unknown_freight);
  if v_eval->>'state'<>'excluded'
     or not exists(
       select 1 from jsonb_array_elements(v_external_unknown_freight->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
       where c.value->>'componentKey'='freight'
         and c.value->>'state'='unresolved'
     ) then
    raise exception 'Unknown freight became a usable landed cost: %',v_eval;
  end if;

  -- Freight-included source carries no second freight charge.
  if exists(
    select 1 from jsonb_array_elements(v_external->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
    where c.value->>'componentKey'='freight'
  ) then
    raise exception 'Freight-included offer received a duplicate freight component: %',v_external;
  end if;

  -- Missing fee completeness remains unresolved even when freight is included.
  v_external_fee_incomplete:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,
    v_offering,
    jsonb_set(
      v_observation,
      '{terms}',
      '{"freightIncluded":true}'::jsonb,
      false
    ),
    '2026-09-24'::date
  );

  if not exists(
    select 1 from jsonb_array_elements(v_external_fee_incomplete->'fulfillmentPacket'->'allocations'->0->'costComponents') c(value)
    where c.value->>'componentKey'='additional_fees'
      and c.value->>'state'='unresolved'
  ) then
    raise exception 'Missing fee completeness was silently treated as zero: %',v_external_fee_incomplete;
  end if;

  -- Explicit available quantity must cover SOURCE purchase quantity (100), not only customer quantity (90).
  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(
    v_line,
    atlas.feast_guild_flower_external_offer_candidate_v1(
      v_line,
      v_offering,
      jsonb_set(v_observation,'{sourceContext,availableQuantity}','95'::jsonb,false),
      '2026-09-24'::date
    )
  );

  if v_eval->>'state'<>'excluded'
     or not exists(
       select 1 from jsonb_array_elements(v_eval->'qualification'->'evaluation'->'requirements') n(value)
       where n.value->>'requirementKey'='source_quantity_capacity'
         and n.value->>'state'='unsatisfied'
     ) then
    raise exception 'Quantity capacity ignored pack purchase quantity: %',v_eval;
  end if;

  -- Unavailable source is incompatible.
  v_external_unavailable:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,
    v_offering,
    jsonb_set(v_observation,'{availabilityState}','"unavailable"'::jsonb,false),
    '2026-09-24'::date
  );
  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line,v_external_unavailable);

  if v_eval->>'state'<>'excluded' then
    raise exception 'Unavailable external source entered selection: %',v_eval;
  end if;

  -- Price-effective dates do not satisfy requested delivery date.
  v_external_no_delivery:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,
    v_offering,
    v_observation #- '{sourceContext,deliveryDate}',
    '2026-09-24'::date
  );

  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line,v_external_no_delivery);
  if v_eval->>'state'<>'excluded'
     or not exists(
       select 1 from jsonb_array_elements(v_external_no_delivery->'qualificationNodes') n(value)
       where n.value->>'requirementKey'='source_requested_date'
         and n.value->>'state'='unresolved'
     ) then
    raise exception 'Price effective date was treated as delivery promise: %',v_external_no_delivery;
  end if;

  -- Unsupported flower requirements remain unresolved rather than guessed.
  v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(
    jsonb_set(
      v_line,
      '{requirements}',
      (v_line->'requirements')||'[{"requirementKey":"petal_count","required":true,"expected":{"minimum":20}}]'::jsonb,
      false
    ),
    atlas.feast_guild_flower_external_offer_candidate_v1(
      jsonb_set(
        v_line,
        '{requirements}',
        (v_line->'requirements')||'[{"requirementKey":"petal_count","required":true,"expected":{"minimum":20}}]'::jsonb,
        false
      ),
      v_offering,
      v_observation,
      '2026-09-24'::date
    )
  );

  if v_eval->>'state'<>'excluded' then
    raise exception 'Unsupported flower requirement was guessed into qualification: %',v_eval;
  end if;

  -- Source preference without evidence cannot enter source-policy selection.
  v_external_no_tier_evidence:=atlas.feast_guild_flower_external_offer_candidate_v1(
    v_line,
    v_offering,
    jsonb_set(
      v_observation,
      '{sourceContext,sourcePreference,evidence}',
      '[]'::jsonb,
      false
    ),
    '2026-09-24'::date
  );

  v_selection:=atlas.feast_guild_flower_source_plan_select_v1(
    v_line,
    jsonb_build_array(v_external_no_tier_evidence)
  );

  if v_selection->>'state'<>'blocked' then
    raise exception 'Source tier without evidence entered automatic selection: %',v_selection;
  end if;

  -- Complete gathered-style candidate flows through source selection into protected quote.
  v_selection:=atlas.feast_guild_flower_source_plan_select_v1(
    v_line,
    jsonb_build_array(v_external)
  );

  if v_selection->>'state'<>'selected'
     or (v_selection->>'selectedLandedCost')::numeric<>38.00 then
    raise exception 'External gathered candidate did not flow through source policy: %',v_selection;
  end if;

  v_quote:=atlas.feast_guild_flower_quote_prepare_v1(
    jsonb_build_object(
      'contractVersion','feast_guild_flower_basket_v1',
      'basketKey','fixture-gather',
      'requestedForDate','2026-09-25',
      'lines',jsonb_build_array(v_line - 'basketKey')
    ),
    jsonb_build_array(v_selection->'selectedPlan'),
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30,
      "currency":"USD",
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb,
    '{
      "organizationId":"00000000-0000-0000-0000-000000000301",
      "organizationUnitId":null,
      "snapshotKey":"fixture-gather-quote",
      "title":"Fixture gathered quote",
      "validFrom":"2026-09-24T15:00:00Z",
      "validUntil":"2026-09-24T18:00:00Z",
      "sourceRef":"fixture:gather"
    }'::jsonb
  );

  if v_quote->>'state'<>'complete'
     or (v_quote->>'wholeOrderTotal')::numeric<>54.90 then
    raise exception 'Gathered candidate did not produce protected quote: %',v_quote;
  end if;

  -- Integration proof: real candidate gathering SERVICE reads source-owned rows,
  -- then source policy + quote preparation consume its output.
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_snapshots from atlas.commercial_offer_snapshots;
  select count(*) into v_before_acquisitions from atlas.external_acquisition_commitments;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_feast_guild_candidate_gathering_v1',
    'Fixture Candidate Gathering Organization',
    'active',
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.farms(stable_key,name,status,organization_id,metadata)
  values(
    'fixture-candidate-gather-farm',
    'Fixture Candidate Gather Farm',
    'active',
    v_org_id,
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  )
  returning id into v_farm_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(
    v_org_id,
    '{"fixture":"supplier_subject"}'::jsonb
  )
  returning id into v_subject_id;

  insert into atlas.external_relationships(
    organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,null,v_subject_id,
    'fixture-gather-supplier','active',
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  )
  returning id into v_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_relationship_id,'supplier','active',
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  );

  v_supply_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,
    null,
    v_relationship_id,
    'fixture-gather-standard-carnation',
    'fixture-gather-carnation-100',
    'Standard Carnation',
    'cut_flower',
    'stem',
    '{"flowerFamily":"carnation","grade":"standard","productLabel":"Standard Carnation","productForm":"stem"}'::jsonb,
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  );

  v_supply_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_supply_offering_id,
    'fixture-gather-20260924-carnation',
    '2026-09-24T15:00:00Z'::timestamptz,
    '2026-09-24',
    '2026-09-25',
    38.00,
    'USD',
    'source_explicit',
    100,
    'stem',
    100,
    'stem',
    null,
    null,
    null,
    null,
    'available',
    '{"freightIncluded":true,"additionalFeesComplete":true}'::jsonb,
    '{
      "availableQuantity":100,
      "availableQuantityUnit":"stem",
      "deliveryDate":"2026-09-25",
      "sourcePreference":{
        "tier":"imported",
        "evidence":[
          {"sourceRef":"fixture:gather:carnation","fact":"countryOfOrigin=CO"}
        ]
      },
      "originCountry":"CO"
    }'::jsonb,
    'supplier_quote',
    'fixture:gather:carnation',
    null,
    null,
    '{"fixture":"atlas_feast_guild_flower_candidate_gathering_v1"}'::jsonb
  );

  v_supply_observation_id:=(v_supply_result->>'externalSupplyOfferObservationId')::uuid;

  v_basket:='{
    "contractVersion":"feast_guild_flower_basket_v1",
    "basketKey":"fixture-gather-service",
    "requestedForDate":"2026-09-25",
    "lines":[
      {
        "lineKey":"carnations",
        "description":"Standard Carnations",
        "quantity":90,
        "unit":"stem",
        "requirements":[
          {"requirementKey":"flower_family","required":true,"evidenceRequired":true,"expected":{"equals":"carnation"}},
          {"requirementKey":"grade","required":true,"evidenceRequired":true,"expected":{"equals":"standard"}}
        ]
      }
    ]
  }'::jsonb;

  v_gathered:=atlas.feast_guild_flower_candidate_sets_gather_service_v1(
    v_basket,
    v_org_id,
    v_farm_id,
    '2026-09-24'::date
  );

  if v_gathered->>'contractVersion'<>'feast_guild_flower_candidate_sets_v1'
     or jsonb_array_length(v_gathered->'lineCandidateSets')<>1
     or (v_gathered->'lineCandidateSets'->0->>'externalCandidateCount')::integer<>1
     or (v_gathered->'lineCandidateSets'->0->>'ownedReadyCandidateCount')::integer<>0 then
    raise exception 'Candidate gathering service did not read fixture source truth: %',v_gathered;
  end if;

  v_whole:=atlas.feast_guild_flower_quote_prepare_from_candidates_v1(
    v_basket,
    v_gathered->'lineCandidateSets',
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30,
      "currency":"USD",
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb,
    jsonb_build_object(
      'organizationId',v_org_id,
      'organizationUnitId',null,
      'snapshotKey','fixture-gather-service-quote',
      'title','Fixture Gather Service Quote',
      'validFrom','2026-09-24T15:00:00Z',
      'validUntil','2026-09-24T18:00:00Z',
      'sourceRef','fixture:gather-service'
    )
  );

  if v_whole->>'state'<>'complete'
     or v_whole->'quote'->>'state'<>'complete'
     or (v_whole->'quote'->>'wholeOrderTotal')::numeric<>54.90
     or v_whole->'lineSelections'->0->'selectedCandidateRef'->>'sourceRef'<>v_supply_offering_id::text then
    raise exception 'Source truth -> gather -> select -> quote vertical slice failed: %',v_whole;
  end if;

  if not exists(
    select 1
    from atlas.external_supply_offer_observations o
    where o.id=v_supply_observation_id
  ) then
    raise exception 'Fixture supplier observation disappeared during read-only gather proof.';
  end if;

  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_offer_snapshots)<>v_before_snapshots
     or (select count(*) from atlas.external_acquisition_commitments)<>v_before_acquisitions then
    raise exception 'Candidate gathering / selection / quote preparation created downstream truth.';
  end if;

  raise notice 'PASS atlas_feast_guild_flower_candidate_gathering_v1: Ready availability projection is lossless, retail value is not cost, external pack/availability/date/landed-cost evidence fails closed, and source truth -> gather -> policy selection -> protected quote produces $54.90 without downstream writes';
end;
$validation$;

rollback;
