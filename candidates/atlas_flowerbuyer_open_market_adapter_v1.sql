begin;

create or replace function atlas.flowerbuyer_open_market_provider_contract_v1()
returns jsonb
language sql
immutable
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'contractVersion','flowerbuyer_open_market_provider_contract_v1',
    'providerKey','flowerbuyer',
    'providerObjectKind','market_listing',
    'sourceSurface','open_market',
    'currency','USD',
    'customerPriceScale',100,
    'unitCodes',jsonb_build_object(
      'ST','stem',
      'BU','bunch'
    ),
    'identity',jsonb_build_object(
      'productKey','FBProductCode',
      'marketListingKeyParts',jsonb_build_array(
        'AuctionProductCode',
        'StrAuctionDate',
        'StrDeliveryDate'
      )
    ),
    'commercialSemantics',jsonb_build_object(
      'authoritativeAccountPriceField','CustomerPrice',
      'packField','Pack',
      'boxesAvailableField','BoxesForSale',
      'unitField','StemOrBunch',
      'unitPriceRawField','UnitPrice',
      'directShippingChargeRawField','DirectShippingCharge',
      'freightIncludedEvidenceField','Comment',
      'additionalFeesComplete',false
    ),
    'originBoundary',jsonb_build_object(
      'countryCodeIsGrowOrigin',false,
      'locationIsGrowOrigin',false,
      'originatingCityIsGrowOrigin',false,
      'pointOfEntryIsGrowOrigin',false,
      'growerNumberIsOriginClassification',false
    ),
    'transportBoundary',jsonb_build_object(
      'transportRequiredByContract',false,
      'supportedArchitectureModes',jsonb_build_array(
        'official_api',
        'authorized_portal_endpoint',
        'authorized_browser_capture',
        'email_fallback'
      ),
      'automationPermissionAssumed',false
    )
  );
$function$;


create or replace function atlas.flowerbuyer_open_market_record_key_v1(
  p_record jsonb
)
returns text
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_auction_product_code text;
  v_auction_date text;
  v_delivery_date text;
begin
  if p_record is null or jsonb_typeof(p_record)<>'object' then
    raise exception 'Flowerbuyer Open Market record must be a JSON object.'
      using errcode='22023';
  end if;

  v_auction_product_code:=nullif(btrim(coalesce(p_record->>'AuctionProductCode','')),'');
  v_auction_date:=nullif(btrim(coalesce(p_record->>'StrAuctionDate','')),'');
  v_delivery_date:=nullif(btrim(coalesce(p_record->>'StrDeliveryDate','')),'');

  if v_auction_product_code is null
     or v_auction_date is null
     or v_delivery_date is null then
    raise exception 'Flowerbuyer Open Market record key requires AuctionProductCode, StrAuctionDate, and StrDeliveryDate.'
      using errcode='22023';
  end if;

  return 'flowerbuyer:open_market:'||
    regexp_replace(v_auction_product_code,'[^A-Za-z0-9._-]+','_','g')||':'||
    regexp_replace(v_auction_date,'[^A-Za-z0-9._-]+','_','g')||':'||
    regexp_replace(v_delivery_date,'[^A-Za-z0-9._-]+','_','g');
end;
$function$;


create or replace function atlas.flowerbuyer_open_market_connected_source_records_v1(
  p_open_market_data jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_record jsonb;
  v_records jsonb:='[]'::jsonb;
begin
  if p_open_market_data is null
     or jsonb_typeof(p_open_market_data)<>'array' then
    raise exception 'Flowerbuyer OpenMarketData must be a JSON array.'
      using errcode='22023';
  end if;

  for v_record in
    select value from jsonb_array_elements(p_open_market_data)
  loop
    v_records:=v_records||jsonb_build_array(jsonb_build_object(
      'key',atlas.flowerbuyer_open_market_record_key_v1(v_record),
      'payload',v_record
    ));
  end loop;

  return v_records;
end;
$function$;


create or replace function atlas.flowerbuyer_open_market_record_interpret_v1(
  p_record jsonb,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_contract jsonb:=atlas.flowerbuyer_open_market_provider_contract_v1();
  v_record_key text;

  v_fb_product_code text;
  v_auction_product_code text;
  v_product_name text;
  v_product_filter text;
  v_color text;
  v_color_description text;
  v_grower_number text;
  v_country_code text;
  v_location text;
  v_originating_city text;
  v_point_of_entry text;

  v_unit_code text;
  v_unit text;
  v_customer_price_raw numeric;
  v_price numeric;
  v_pack numeric;
  v_boxes numeric;
  v_available_quantity numeric;
  v_box_cost numeric;

  v_allow_purchasing text;
  v_ac_allow_purchasing text;
  v_sold_out text;
  v_availability_state text;

  v_comment text;
  v_freight_included boolean:=false;

  v_delivery_date date;
  v_auction_date date;
  v_order_by_text text;

  v_stem_length_cm numeric;
  v_stems_per_bunch numeric;
  v_match text[];

  v_specification jsonb;
  v_terms jsonb;
  v_source_context jsonb;
  v_provider_facts jsonb;
  v_unresolved jsonb:='[]'::jsonb;

  v_unit_price_raw numeric;
  v_direct_shipping_charge_raw numeric;
begin
  if p_record is null or jsonb_typeof(p_record)<>'object' then
    raise exception 'Flowerbuyer Open Market record must be a JSON object.'
      using errcode='22023';
  end if;

  if p_observed_at is null then
    raise exception 'Observed-at timestamp is required for Flowerbuyer interpretation.'
      using errcode='22023';
  end if;

  v_record_key:=atlas.flowerbuyer_open_market_record_key_v1(p_record);

  v_fb_product_code:=nullif(btrim(coalesce(p_record->>'FBProductCode','')),'');
  v_auction_product_code:=nullif(btrim(coalesce(p_record->>'AuctionProductCode','')),'');
  v_product_name:=nullif(btrim(coalesce(p_record->>'ProductName','')),'');
  v_product_filter:=nullif(btrim(coalesce(p_record->>'ProductFilter','')),'');
  v_color:=nullif(btrim(coalesce(p_record->>'ColorFilter','')),'');
  v_color_description:=nullif(btrim(coalesce(p_record->>'ColorDescription','')),'');
  v_grower_number:=nullif(btrim(coalesce(p_record->>'GrowerNumber','')),'');
  v_country_code:=nullif(btrim(coalesce(p_record->>'CountryCode','')),'');
  v_location:=nullif(btrim(coalesce(p_record->>'Location','')),'');
  v_originating_city:=nullif(btrim(coalesce(p_record->>'OriginatingCity','')),'');
  v_point_of_entry:=nullif(btrim(coalesce(p_record->>'PointOfEntry','')),'');

  if v_fb_product_code is null then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','FBProductCode',
      'reason','product_identity_missing'
    ));
  end if;

  if v_product_name is null then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','ProductName',
      'reason','product_label_missing'
    ));
  end if;

  v_unit_code:=upper(btrim(coalesce(p_record->>'StemOrBunch','')));
  v_unit:=case v_unit_code
    when 'ST' then 'stem'
    when 'BU' then 'bunch'
    else null
  end;

  if v_unit is null then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','StemOrBunch',
      'reason','unknown_price_unit_code',
      'rawValue',nullif(v_unit_code,'')
    ));
  end if;

  v_customer_price_raw:=case
    when jsonb_typeof(p_record->'CustomerPrice')='number'
      then (p_record->>'CustomerPrice')::numeric
    else null
  end;

  if v_customer_price_raw is null or v_customer_price_raw<0 then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','CustomerPrice',
      'reason','account_price_missing_or_invalid'
    ));
  elsif v_unit is not null then
    v_price:=v_customer_price_raw/100.0;
  end if;

  v_pack:=case
    when jsonb_typeof(p_record->'Pack')='number'
      then (p_record->>'Pack')::numeric
    else null
  end;

  if v_pack is null or v_pack<=0 then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','Pack',
      'reason','pack_missing_or_invalid'
    ));
  end if;

  v_boxes:=case
    when jsonb_typeof(p_record->'BoxesForSale')='number'
      then (p_record->>'BoxesForSale')::numeric
    else null
  end;

  if v_boxes is null or v_boxes<0 then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','BoxesForSale',
      'reason','box_availability_missing_or_invalid'
    ));
  end if;

  if v_pack is not null and v_pack>0
     and v_boxes is not null and v_boxes>=0
     and v_unit is not null then
    v_available_quantity:=v_pack*v_boxes;
  end if;

  if v_pack is not null and v_pack>0
     and v_price is not null then
    v_box_cost:=v_pack*v_price;
  end if;

  v_allow_purchasing:=upper(btrim(coalesce(p_record->>'AllowPurchasing','')));
  v_ac_allow_purchasing:=upper(btrim(coalesce(p_record->>'ACAllowPurchasing','')));
  v_sold_out:=upper(btrim(coalesce(p_record->>'SoldOut','')));

  v_availability_state:=case
    when v_sold_out='Y' then 'unavailable'
    when v_boxes is not null and v_boxes<=0 then 'unavailable'
    when v_allow_purchasing='N' or v_ac_allow_purchasing='N' then 'unavailable'
    when v_boxes is not null and v_boxes>0
      and v_sold_out='N'
      and v_allow_purchasing='Y'
      and v_ac_allow_purchasing='Y' then 'available'
    else 'unknown'
  end;

  v_comment:=nullif(btrim(coalesce(p_record->>'Comment','')),'');
  if v_comment is not null
     and lower(v_comment) like '%shipping cost%'
     and lower(v_comment) like '%included in price%' then
    v_freight_included:=true;
  else
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','Comment',
      'reason','freight_inclusion_not_established'
    ));
  end if;

  v_delivery_date:=case
    when coalesce(p_record->>'StrDeliveryDate','') ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      then to_date(p_record->>'StrDeliveryDate','MM/DD/YYYY')
    else null
  end;

  v_auction_date:=case
    when coalesce(p_record->>'StrAuctionDate','') ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      then to_date(p_record->>'StrAuctionDate','MM/DD/YYYY')
    else null
  end;

  v_order_by_text:=nullif(btrim(coalesce(p_record->>'OrderByDate','')),'');

  if v_delivery_date is null then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','StrDeliveryDate',
      'reason','delivery_date_missing_or_invalid'
    ));
  end if;

  if v_product_name is not null then
    v_match:=regexp_match(v_product_name,'(^|[^0-9])([0-9]+)cm([^A-Za-z]|$)','i');
    if v_match is not null then
      v_stem_length_cm:=(v_match[2])::numeric;
    end if;

    v_match:=regexp_match(v_product_name,'(^|[^0-9])([0-9]+)st/bu([^A-Za-z]|$)','i');
    if v_match is not null then
      v_stems_per_bunch:=(v_match[2])::numeric;
    end if;
  end if;

  v_unit_price_raw:=case
    when jsonb_typeof(p_record->'UnitPrice')='number'
      then (p_record->>'UnitPrice')::numeric
    else null
  end;

  v_direct_shipping_charge_raw:=case
    when jsonb_typeof(p_record->'DirectShippingCharge')='number'
      then (p_record->>'DirectShippingCharge')::numeric
    else null
  end;

  v_specification:=jsonb_strip_nulls(jsonb_build_object(
    'productLabel',v_product_name,
    'providerProductFilter',v_product_filter,
    'color',v_color,
    'providerColorDescription',v_color_description,
    'stemLengthCm',v_stem_length_cm,
    'stemsPerBunch',v_stems_per_bunch,
    'providerProductKeyId',p_record->'ProductKeyId',
    'providerBudSize',nullif(btrim(coalesce(p_record->>'BudSize','')),'')
  ));

  v_terms:=jsonb_build_object(
    'freightIncluded',v_freight_included,
    'freightBasis',case
      when v_freight_included then 'flowerbuyer_source_comment'
      else 'unresolved'
    end,
    'additionalFeesComplete',false,
    'authoritativeAcquisitionPrice','CustomerPrice',
    'providerPriceDecompositionComplete',false
  );

  v_source_context:=jsonb_strip_nulls(jsonb_build_object(
    'availableQuantity',v_available_quantity,
    'availableQuantityUnit',v_unit,
    'deliveryDate',case when v_delivery_date is null then null else v_delivery_date::text end,
    'auctionDate',case when v_auction_date is null then null else v_auction_date::text end,
    'orderByText',v_order_by_text,
    'providerGrowerRef',v_grower_number,
    'providerCountryCode',v_country_code,
    'providerLocation',v_location,
    'providerOriginatingCity',v_originating_city,
    'providerPointOfEntry',v_point_of_entry,
    'providerProductSource',nullif(btrim(coalesce(p_record->>'ProductSource','')),''),
    'providerDirectShipping',nullif(btrim(coalesce(p_record->>'DirectShipping','')),''),
    'providerFedExOnly',nullif(btrim(coalesce(p_record->>'FedExOnly','')),''),
    'providerFedExGround',nullif(btrim(coalesce(p_record->>'FedExGround','')),''),
    'providerUnitPriceRaw',v_unit_price_raw,
    'providerDirectShippingChargeRaw',v_direct_shipping_charge_raw,
    'accountPurchasable',case
      when v_availability_state='available' then true
      when v_availability_state='unavailable' then false
      else null
    end,
    'growOriginEvidenceState','unresolved'
  ));

  v_provider_facts:=jsonb_strip_nulls(jsonb_build_object(
    'FBProductCode',v_fb_product_code,
    'AuctionProductCode',v_auction_product_code,
    'ProductName',v_product_name,
    'ProductFilter',v_product_filter,
    'CustomerPrice',v_customer_price_raw,
    'Pack',v_pack,
    'StemOrBunch',nullif(v_unit_code,''),
    'BoxesForSale',v_boxes,
    'UnitPrice',v_unit_price_raw,
    'DirectShippingCharge',v_direct_shipping_charge_raw,
    'Comment',v_comment,
    'CountryCode',v_country_code,
    'Location',v_location,
    'OriginatingCity',v_originating_city,
    'PointOfEntry',v_point_of_entry,
    'GrowerNumber',v_grower_number,
    'AllowPurchasing',nullif(v_allow_purchasing,''),
    'ACAllowPurchasing',nullif(v_ac_allow_purchasing,''),
    'SoldOut',nullif(v_sold_out,''),
    'StrAuctionDate',p_record->>'StrAuctionDate',
    'StrDeliveryDate',p_record->>'StrDeliveryDate',
    'OrderByDate',v_order_by_text
  ));

  return jsonb_build_object(
    'contractVersion','flowerbuyer_open_market_interpretation_v1',
    'providerContract',v_contract,
    'rawRecordIdentity',jsonb_build_object(
      'providerKey','flowerbuyer',
      'providerObjectKind','market_listing',
      'providerObjectKey',v_record_key,
      'FBProductCode',v_fb_product_code,
      'AuctionProductCode',v_auction_product_code
    ),
    'offeringDraft',jsonb_build_object(
      'stableKey',case
        when v_fb_product_code is null then null
        else 'flowerbuyer:product:'||v_fb_product_code
      end,
      'sourceItemKey',v_fb_product_code,
      'sourceLabel',v_product_name,
      'offeringKind','cut_flower',
      'sourceUnit',v_unit,
      'specification',v_specification,
      'metadata',jsonb_build_object(
        'providerKey','flowerbuyer',
        'providerProductIdentity','FBProductCode'
      )
    ),
    'observationDraft',jsonb_build_object(
      'observationKey',v_record_key,
      'observedAt',p_observed_at,
      'effectiveFrom',null,
      'effectiveUntil',null,
      'priceAmount',v_price,
      'currency',case when v_price is null then null else 'USD' end,
      'priceBasisState',case
        when v_price is not null and v_unit is not null then 'source_explicit'
        else 'unknown'
      end,
      'priceQuantity',case when v_price is null or v_unit is null then null else 1 end,
      'priceUnit',v_unit,
      'packQuantity',v_pack,
      'packUnit',v_unit,
      'minimumOrderQuantity',v_pack,
      'minimumOrderUnit',v_unit,
      'availabilityState',v_availability_state,
      'terms',v_terms,
      'sourceContext',v_source_context,
      'sourceKind','supplier_portal',
      'sourceRef',v_record_key
    ),
    'derived',jsonb_strip_nulls(jsonb_build_object(
      'accountUnitPrice',v_price,
      'boxCost',v_box_cost,
      'observableAvailableQuantity',v_available_quantity,
      'observableAvailableUnit',v_unit,
      'stemLengthCm',v_stem_length_cm,
      'stemsPerBunch',v_stems_per_bunch
    )),
    'providerFacts',v_provider_facts,
    'unresolvedSemantics',v_unresolved,
    'sourcePreference',jsonb_build_object(
      'state','unresolved',
      'reason','flowerbuyer_logistics_fields_do_not_establish_grow_origin'
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'transportIndependent',true,
      'customerPriceIsAuthoritativeAccountPrice',true,
      'unitPriceNotUsedAsAcquisitionPrice',true,
      'directShippingChargeNotAddedSeparately',true,
      'countryCodeDoesNotEstablishGrowOrigin',true,
      'locationDoesNotEstablishGrowOrigin',true,
      'originatingCityDoesNotEstablishGrowOrigin',true,
      'pointOfEntryDoesNotEstablishGrowOrigin',true,
      'doesNotResolveSupplierRelationship',true,
      'doesNotWriteConnectedSourceObservation',true,
      'doesNotWriteExternalSupplyOffer',true,
      'doesNotPurchase',true
    )
  );
end;
$function$;


create or replace function atlas.flowerbuyer_open_market_batch_interpret_v1(
  p_open_market_data jsonb,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_record jsonb;
  v_items jsonb:='[]'::jsonb;
begin
  if p_open_market_data is null
     or jsonb_typeof(p_open_market_data)<>'array' then
    raise exception 'Flowerbuyer OpenMarketData must be a JSON array.'
      using errcode='22023';
  end if;

  if p_observed_at is null then
    raise exception 'Observed-at timestamp is required.'
      using errcode='22023';
  end if;

  for v_record in
    select value from jsonb_array_elements(p_open_market_data)
  loop
    v_items:=v_items||jsonb_build_array(
      atlas.flowerbuyer_open_market_record_interpret_v1(
        v_record,p_observed_at
      )
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','flowerbuyer_open_market_batch_interpretation_v1',
    'providerKey','flowerbuyer',
    'observedAt',p_observed_at,
    'recordCount',jsonb_array_length(p_open_market_data),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'transportIndependent',true,
      'doesNotWriteRawObservations',true,
      'doesNotAdmitCommercialTruth',true
    )
  );
end;
$function$;


revoke all on function atlas.flowerbuyer_open_market_provider_contract_v1()
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_provider_contract_v1()
  to service_role;

revoke all on function atlas.flowerbuyer_open_market_record_key_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_record_key_v1(jsonb)
  to service_role;

revoke all on function atlas.flowerbuyer_open_market_connected_source_records_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_connected_source_records_v1(jsonb)
  to service_role;

revoke all on function atlas.flowerbuyer_open_market_record_interpret_v1(jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_record_interpret_v1(jsonb,timestamptz)
  to service_role;

revoke all on function atlas.flowerbuyer_open_market_batch_interpret_v1(jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_batch_interpret_v1(jsonb,timestamptz)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.flowerbuyer_open_market_provider_contract_v1()',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_adapter_v1","purpose":"Immutable provider semantics observed from authenticated Flowerbuyer Open Market records; transport remains separately authorized.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.flowerbuyer_open_market_record_key_v1(jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_adapter_v1","purpose":"Deterministic Flowerbuyer Open Market raw listing identity from provider-issued listing/date fields.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.flowerbuyer_open_market_connected_source_records_v1(jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_adapter_v1","purpose":"Prepare raw Flowerbuyer Open Market rows for the existing generic Connected Source Observation batch writer without altering payloads.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.flowerbuyer_open_market_record_interpret_v1(jsonb,timestamptz)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_adapter_v1","purpose":"Pure Flowerbuyer Open Market record interpretation into source-offer admission drafts; no source or commercial writes.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.flowerbuyer_open_market_batch_interpret_v1(jsonb,timestamptz)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_adapter_v1","purpose":"Read-only batch interpretation of Flowerbuyer Open Market records independent of retrieval transport.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
