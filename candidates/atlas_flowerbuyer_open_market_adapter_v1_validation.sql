begin;

do $validation$
declare
  v_acacia jsonb;
  v_rose jsonb;
  v_result jsonb;
  v_batch jsonb;
  v_raw_records jsonb;

  v_org_id uuid;
  v_source_id uuid;
  v_subject_id uuid;
  v_relationship_id uuid;
  v_raw_id uuid;
  v_admitted jsonb;
  v_offering_id uuid;
  v_offer_observation_id uuid;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_snapshots bigint;
begin
  v_acacia:='{
    "ACAllowPurchasing":"Y",
    "AllowPurchasing":"Y",
    "AuctionDate":"/Date(1790294400000)/",
    "AuctionPageNumber":15,
    "AuctionProductCode":19502,
    "BoxesForSale":2,
    "BudSize":"0.0",
    "ColorDescription":"Green",
    "ColorFilter":"Green",
    "Comment":"FedEx shipping cost of $xx.xx included in price.",
    "CountryCode":"US",
    "CustomerPrice":907,
    "DeliverDate":"/Date(1790380800000)/",
    "DirectShipping":"Y",
    "DirectShippingCharge":552.1,
    "FBProductCode":27072,
    "FedExGround":"N",
    "FedExOnly":"Y",
    "GrowerNumber":"1211",
    "Location":"USA",
    "OrderByDate":"September 24",
    "OriginatingCity":"Carlsbad1211",
    "Pack":20,
    "PointOfEntry":"MI",
    "ProductFilter":"Acacia",
    "ProductKeyId":1,
    "ProductName":"Acacia Knife Blade 30-36in 10st/bu",
    "ProductSource":"PO",
    "SoldOut":"N",
    "StemOrBunch":"BU",
    "StrAuctionDate":"09/25/2026",
    "StrDeliveryDate":"09/26/2026",
    "UnitPrice":338
  }'::jsonb;

  v_rose:='{
    "ACAllowPurchasing":"Y",
    "AllowPurchasing":"Y",
    "AuctionDate":"/Date(1790294400000)/",
    "AuctionPageNumber":59,
    "AuctionProductCode":15594,
    "BoxesForSale":2,
    "BudSize":"0.0",
    "ColorDescription":"Assorted",
    "ColorFilter":"Assorted",
    "Comment":"FedEx shipping cost of $xx.xx included in price.",
    "CountryCode":"US",
    "CustomerPrice":118,
    "DeliverDate":"/Date(1790380800000)/",
    "DirectShipping":"Y",
    "DirectShippingCharge":43.928,
    "FBProductCode":30220,
    "FedExGround":"N",
    "FedExOnly":"Y",
    "GrowerNumber":"4088",
    "GrowerRating":8,
    "Location":"USA",
    "OrderByDate":"September 24",
    "OriginatingCity":"Miami3",
    "Pack":125,
    "PointOfEntry":"MI",
    "ProductFilter":"Rose Assorted",
    "ProductKeyId":220,
    "ProductName":"Rose Assorted 40cm 25st/bu",
    "ProductSource":"PO",
    "SoldOut":"N",
    "StemOrBunch":"ST",
    "StrAuctionDate":"09/25/2026",
    "StrDeliveryDate":"09/26/2026",
    "UnitPrice":70
  }'::jsonb;

  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    v_acacia,'2026-09-24T17:30:00Z'::timestamptz
  );

  if (v_result->'observationDraft'->>'priceAmount')::numeric<>9.07
     or v_result->'observationDraft'->>'currency'<>'USD'
     or v_result->'observationDraft'->>'priceUnit'<>'bunch'
     or (v_result->'observationDraft'->>'packQuantity')::numeric<>20
     or (v_result->'derived'->>'boxCost')::numeric<>181.40
     or (v_result->'derived'->>'observableAvailableQuantity')::numeric<>40
     or (v_result->'derived'->>'stemsPerBunch')::numeric<>10
     or v_result->'observationDraft'->>'availabilityState'<>'available'
     or v_result->'observationDraft'->'sourceContext'->>'deliveryDate'<>'2026-09-26'
     or coalesce((v_result->'observationDraft'->'terms'->>'freightIncluded')::boolean,false)=false
     or coalesce((v_result->'observationDraft'->'terms'->>'additionalFeesComplete')::boolean,true)=true then
    raise exception 'Acacia Flowerbuyer interpretation failed: %',v_result;
  end if;

  if v_result->'sourcePreference'->>'state'<>'unresolved'
     or v_result->'observationDraft'->'sourceContext' ? 'sourcePreference' then
    raise exception 'Flowerbuyer logistics fields improperly created source preference: %',v_result;
  end if;

  if (v_result->'observationDraft'->'sourceContext'->>'providerUnitPriceRaw')::numeric<>338
     or (v_result->'observationDraft'->'sourceContext'->>'providerDirectShippingChargeRaw')::numeric<>552.1
     or (v_result->'observationDraft'->>'priceAmount')::numeric=3.38 then
    raise exception 'Flowerbuyer internal component fields replaced account acquisition price.';
  end if;

  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    v_rose,'2026-09-24T17:30:00Z'::timestamptz
  );

  if (v_result->'observationDraft'->>'priceAmount')::numeric<>1.18
     or v_result->'observationDraft'->>'priceUnit'<>'stem'
     or (v_result->'observationDraft'->>'packQuantity')::numeric<>125
     or (v_result->'derived'->>'boxCost')::numeric<>147.50
     or (v_result->'derived'->>'observableAvailableQuantity')::numeric<>250
     or (v_result->'derived'->>'stemLengthCm')::numeric<>40
     or (v_result->'derived'->>'stemsPerBunch')::numeric<>25 then
    raise exception 'Rose Flowerbuyer interpretation failed: %',v_result;
  end if;

  if v_result->'observationDraft'->'sourceContext'->>'providerCountryCode'<>'US'
     or v_result->'observationDraft'->'sourceContext'->>'providerLocation'<>'USA'
     or v_result->'observationDraft'->'sourceContext'->>'providerOriginatingCity'<>'Miami3'
     or v_result->'sourcePreference'->>'state'<>'unresolved' then
    raise exception 'Flowerbuyer logistics/origin boundary failed: %',v_result;
  end if;

  -- Sold-out or non-purchasable rows fail closed.
  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    jsonb_set(v_rose,'{SoldOut}','"Y"'::jsonb,false),
    '2026-09-24T17:30:00Z'::timestamptz
  );
  if v_result->'observationDraft'->>'availabilityState'<>'unavailable' then
    raise exception 'Sold-out Flowerbuyer listing remained available: %',v_result;
  end if;

  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    jsonb_set(v_rose,'{AllowPurchasing}','"N"'::jsonb,false),
    '2026-09-24T17:30:00Z'::timestamptz
  );
  if v_result->'observationDraft'->>'availabilityState'<>'unavailable' then
    raise exception 'Non-purchasable Flowerbuyer listing remained available: %',v_result;
  end if;

  -- Unknown units and malformed prices remain unresolved, never zero.
  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    jsonb_set(v_rose,'{StemOrBunch}','"BX"'::jsonb,false),
    '2026-09-24T17:30:00Z'::timestamptz
  );
  if v_result->'observationDraft'->>'priceBasisState'<>'unknown'
     or v_result->'observationDraft'->'priceAmount' is not null then
    raise exception 'Unknown Flowerbuyer unit became priced source truth: %',v_result;
  end if;

  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    v_rose - 'CustomerPrice',
    '2026-09-24T17:30:00Z'::timestamptz
  );
  if v_result->'observationDraft'->'priceAmount' is not null
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'unresolvedSemantics') x(value)
       where x.value->>'field'='CustomerPrice'
     ) then
    raise exception 'Missing Flowerbuyer CustomerPrice became known economics: %',v_result;
  end if;

  -- Without shipping-included source text, freight remains unresolved.
  v_result:=atlas.flowerbuyer_open_market_record_interpret_v1(
    v_rose - 'Comment',
    '2026-09-24T17:30:00Z'::timestamptz
  );
  if coalesce((v_result->'observationDraft'->'terms'->>'freightIncluded')::boolean,true)=true
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'unresolvedSemantics') x(value)
       where x.value->>'field'='Comment'
         and x.value->>'reason'='freight_inclusion_not_established'
     ) then
    raise exception 'Flowerbuyer freight was invented without source statement: %',v_result;
  end if;

  -- Raw Connected Source packaging preserves payload unchanged and deterministic identity.
  v_raw_records:=atlas.flowerbuyer_open_market_connected_source_records_v1(
    jsonb_build_array(v_acacia,v_rose)
  );

  if jsonb_array_length(v_raw_records)<>2
     or v_raw_records->0->'payload' is distinct from v_acacia
     or v_raw_records->1->'payload' is distinct from v_rose
     or v_raw_records->0->>'key'<>
        atlas.flowerbuyer_open_market_record_key_v1(v_acacia) then
    raise exception 'Flowerbuyer raw Connected Source packaging altered source payload.';
  end if;

  v_batch:=atlas.flowerbuyer_open_market_batch_interpret_v1(
    jsonb_build_array(v_acacia,v_rose),
    '2026-09-24T17:30:00Z'::timestamptz
  );

  if (v_batch->>'recordCount')::integer<>2
     or jsonb_array_length(v_batch->'items')<>2 then
    raise exception 'Flowerbuyer batch interpretation failed: %',v_batch;
  end if;

  -- Durable admission proof through existing raw Connected Source custody.
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_snapshots from atlas.commercial_offer_snapshots;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_flowerbuyer_open_market_v1',
    'Fixture Flowerbuyer Open Market Organization',
    'active',
    '{"fixture":"atlas_flowerbuyer_open_market_adapter_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.connected_sources(
    custodian_organization_id,
    provider_key,
    provider_account_key,
    display_label,
    authorization_state,
    granted_scopes,
    capabilities,
    metadata
  ) values (
    v_org_id,
    'flowerbuyer',
    'fixture-account',
    'Fixture Flowerbuyer',
    'connected',
    array['open_market_read']::text[],
    '{"openMarketStructuredData":true}'::jsonb,
    '{"fixture":"atlas_flowerbuyer_open_market_adapter_v1"}'::jsonb
  )
  returning id into v_source_id;

  perform atlas.record_connected_source_observation_batch_service_v1(
    v_source_id,
    'market_listing',
    atlas.flowerbuyer_open_market_connected_source_records_v1(
      jsonb_build_array(v_rose)
    ),
    '2026-09-24T17:30:00Z'::timestamptz,
    '{
      "captureMethod":"fixture_authorized_transport",
      "sourceSurface":"open_market",
      "accountScoped":true
    }'::jsonb
  );

  select o.id
  into v_raw_id
  from atlas.connected_source_observations o
  where o.connected_source_id=v_source_id
    and o.provider_object_kind='market_listing'
    and o.provider_object_key=atlas.flowerbuyer_open_market_record_key_v1(v_rose)
  order by o.observed_at desc,o.id desc
  limit 1;

  if v_raw_id is null then
    raise exception 'Flowerbuyer raw Connected Source Observation was not recorded.';
  end if;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(
    v_org_id,
    '{"fixture":"flowerbuyer_supplier_subject"}'::jsonb
  )
  returning id into v_subject_id;

  insert into atlas.external_relationships(
    organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,
    null,
    v_subject_id,
    'fixture-flowerbuyer-vendor-of-record',
    'active',
    '{"fixture":"atlas_flowerbuyer_open_market_adapter_v1"}'::jsonb
  )
  returning id into v_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_relationship_id,
    'supplier',
    'active',
    '{"fixture":"explicit_supplier_resolution_for_validation"}'::jsonb
  );

  v_admitted:=atlas.flowerbuyer_open_market_admit_observation_service_v1(
    v_raw_id,
    v_relationship_id,
    null
  );

  v_offering_id:=(v_admitted->>'externalSupplyOfferingId')::uuid;
  v_offer_observation_id:=(v_admitted->>'externalSupplyOfferObservationId')::uuid;

  if v_offering_id is null or v_offer_observation_id is null then
    raise exception 'Flowerbuyer raw observation did not admit into External Supply Offer truth: %',v_admitted;
  end if;

  if not exists(
    select 1
    from atlas.external_supply_offerings o
    where o.id=v_offering_id
      and o.source_item_key='30220'
      and o.source_label='Rose Assorted 40cm 25st/bu'
      and o.source_unit='stem'
  ) then
    raise exception 'Flowerbuyer admitted offering identity is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.external_supply_offer_observations o
    where o.id=v_offer_observation_id
      and o.connected_source_observation_id=v_raw_id
      and o.price_amount=1.18
      and o.currency='USD'
      and o.price_quantity=1
      and o.price_unit='stem'
      and o.pack_quantity=125
      and o.availability_state='available'
      and o.source_context->>'availableQuantity'='250'
      and o.source_context->>'growOriginEvidenceState'='unresolved'
      and o.terms->>'freightIncluded'='true'
      and o.terms->>'additionalFeesComplete'='false'
  ) then
    raise exception 'Flowerbuyer admitted source observation lost provider semantics.';
  end if;

  -- Changed payload under the same market listing becomes a second append-only raw version,
  -- not an overwrite.
  perform atlas.record_connected_source_observation_batch_service_v1(
    v_source_id,
    'market_listing',
    atlas.flowerbuyer_open_market_connected_source_records_v1(
      jsonb_build_array(jsonb_set(v_rose,'{BoxesForSale}','1'::jsonb,false))
    ),
    '2026-09-24T17:45:00Z'::timestamptz,
    '{"captureMethod":"fixture_authorized_transport","sourceSurface":"open_market"}'::jsonb
  );

  if (
    select count(*)
    from atlas.connected_source_observations o
    where o.connected_source_id=v_source_id
      and o.provider_object_key=atlas.flowerbuyer_open_market_record_key_v1(v_rose)
  )<>2 then
    raise exception 'Changed Flowerbuyer market state did not remain append-only.';
  end if;

  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_offer_snapshots)<>v_before_snapshots then
    raise exception 'Flowerbuyer adapter/admission created downstream commercial truth.';
  end if;

  raise notice 'PASS Flowerbuyer Open Market adapter: observed payload maps account price/pack/capacity/delivery/freight evidence, preserves logistics-vs-origin boundary, records append-only raw observations, and admits explicit source truth without purchase/Spend/inventory/customer-offer consequences';
end;
$validation$;

rollback;
