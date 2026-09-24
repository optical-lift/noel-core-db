begin;

create or replace function atlas.baisch_skinner_price_sheet_provider_contract_v1()
returns jsonb
language sql
immutable
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'contractVersion','baisch_skinner_price_sheet_provider_contract_v1',
    'providerKey','baisch_skinner',
    'providerObjectKind','published_price_sheet',
    'sourceFamily','cut_flower_price_list',
    'normalizationContract','baisch_skinner_cut_flower_price_sheet_normalized_v1',
    'sourceSemantics',jsonb_build_object(
      'currencyStatedGlobally',false,
      'globalPriceUnitStated',false,
      'listPresenceEstablishesAvailability',false,
      'priceSubjectToChange',true,
      'highlightMeaning','new_item_or_price_change'
    ),
    'quantityRules',jsonb_build_object(
      'explicitCountAndStemMayEstablishPriceBasis',true,
      'xCountWithoutUnitDoesNotEstablishPriceBasis',true,
      'unitWordWithoutCountIsOnlyHint',true,
      'providerShorthandRequiresConfirmation',true
    ),
    'originBoundary',jsonb_build_object(
      'localSubsectionEstablishesFeastGuildRegion',false,
      'placeNameInLabelEstablishesGrowOrigin',false
    ),
    'truthBoundary',jsonb_build_object(
      'priceSheetIsNotInventory',true,
      'priceSheetIsNotPurchaseAuthority',true,
      'priceSheetIsNotCustomerPrice',true,
      'unknownCurrencyIsNotUSD',true,
      'unknownPriceUnitIsNotStemOrBunch',true
    )
  );
$function$;


create or replace function atlas.baisch_skinner_price_sheet_document_key_v1(
  p_document jsonb
)
returns text
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_contract text;
  v_title text;
  v_valid_from date;
  v_valid_until date;
begin
  if p_document is null or jsonb_typeof(p_document)<>'object' then
    raise exception 'Baisch & Skinner normalized document must be a JSON object.'
      using errcode='22023';
  end if;

  v_contract:=nullif(btrim(coalesce(p_document->>'contractVersion','')),'');
  v_title:=nullif(btrim(coalesce(p_document->>'documentTitle','')),'');

  if v_contract<>'baisch_skinner_cut_flower_price_sheet_normalized_v1' then
    raise exception 'Unsupported Baisch & Skinner normalized document contract.'
      using errcode='22023';
  end if;

  if v_title is null
     or nullif(btrim(coalesce(p_document->>'validFrom','')),'') is null
     or nullif(btrim(coalesce(p_document->>'validUntil','')),'') is null then
    raise exception 'Baisch & Skinner document requires title and valid date range.'
      using errcode='22023';
  end if;

  v_valid_from:=(p_document->>'validFrom')::date;
  v_valid_until:=(p_document->>'validUntil')::date;

  if v_valid_until<v_valid_from then
    raise exception 'Baisch & Skinner document validUntil precedes validFrom.'
      using errcode='22023';
  end if;

  return 'baisch_skinner:cut_flower_price_list:'||
    v_valid_from::text||':'||v_valid_until::text;
end;
$function$;


create or replace function atlas.baisch_skinner_price_sheet_connected_source_record_v1(
  p_document jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
begin
  if jsonb_typeof(p_document->'rows') is distinct from 'array'
     or jsonb_array_length(p_document->'rows')=0 then
    raise exception 'Baisch & Skinner normalized document requires non-empty rows.'
      using errcode='22023';
  end if;

  return jsonb_build_object(
    'key',atlas.baisch_skinner_price_sheet_document_key_v1(p_document),
    'payload',p_document
  );
end;
$function$;


create or replace function atlas.baisch_skinner_price_sheet_row_interpret_v1(
  p_document jsonb,
  p_row_key text,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_contract jsonb:=atlas.baisch_skinner_price_sheet_provider_contract_v1();
  v_document_key text;
  v_valid_from date;
  v_valid_until date;
  v_price_subject_to_change boolean;

  v_row jsonb;
  v_row_count integer;
  v_row_key text:=nullif(btrim(coalesce(p_row_key,'')),'');
  v_row_kind text;
  v_identity_state text;
  v_section text;
  v_subsection text;
  v_raw_label text;
  v_source_label text;
  v_highlighted boolean:=false;
  v_source_change_signal text;

  v_price numeric;
  v_price_text text;
  v_price_basis_state text:='unknown';
  v_price_quantity numeric;
  v_price_unit text;
  v_pack_quantity numeric;
  v_pack_unit text;
  v_source_unit text;

  v_explicit_stem_match text[];
  v_x_count_match text[];
  v_source_quantity_hint numeric;
  v_source_unit_hint text;
  v_provider_shorthand text;

  v_offering_kind text;
  v_specification jsonb;
  v_terms jsonb;
  v_source_context jsonb;
  v_provider_facts jsonb;
  v_unresolved jsonb:='[]'::jsonb;
  v_source_preference jsonb;
  v_admissible boolean:=false;
begin
  if p_document is null or jsonb_typeof(p_document)<>'object' then
    raise exception 'Baisch & Skinner normalized document must be a JSON object.'
      using errcode='22023';
  end if;

  if v_row_key is null or p_observed_at is null then
    raise exception 'Baisch & Skinner rowKey and observedAt are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_document->'rows') is distinct from 'array' then
    raise exception 'Baisch & Skinner normalized document rows must be an array.'
      using errcode='22023';
  end if;

  v_document_key:=atlas.baisch_skinner_price_sheet_document_key_v1(p_document);
  v_valid_from:=(p_document->>'validFrom')::date;
  v_valid_until:=(p_document->>'validUntil')::date;
  v_price_subject_to_change:=coalesce(
    case
      when jsonb_typeof(p_document->'priceSubjectToChange')='boolean'
        then (p_document->>'priceSubjectToChange')::boolean
      else null
    end,
    true
  );

  select count(*)
  into v_row_count
  from jsonb_array_elements(p_document->'rows') r(value)
  where r.value->>'rowKey'=v_row_key;

  if v_row_count<>1 then
    raise exception 'Baisch & Skinner rowKey must match exactly one normalized row; found %.',v_row_count
      using errcode='22023';
  end if;

  select r.value
  into v_row
  from jsonb_array_elements(p_document->'rows') r(value)
  where r.value->>'rowKey'=v_row_key
  limit 1;

  v_row_kind:=lower(btrim(coalesce(v_row->>'rowKind','unknown')));
  v_identity_state:=lower(btrim(coalesce(v_row->>'identityState','unresolved')));
  v_section:=nullif(btrim(coalesce(v_row->>'section','')),'');
  v_subsection:=nullif(btrim(coalesce(v_row->>'subsection','')),'');
  v_raw_label:=nullif(btrim(coalesce(v_row->>'rawLabel','')),'');
  v_price_text:=nullif(btrim(coalesce(v_row->>'displayPriceText','')),'');

  if jsonb_typeof(v_row->'sourcePath')='array'
     and jsonb_array_length(v_row->'sourcePath')>0 then
    select string_agg(x.value,' / ' order by x.ord)
    into v_source_label
    from jsonb_array_elements_text(v_row->'sourcePath')
      with ordinality as x(value,ord);
  end if;

  v_source_label:=coalesce(
    nullif(btrim(coalesce(v_source_label,'')),''),
    v_raw_label
  );

  v_highlighted:=coalesce(
    case
      when jsonb_typeof(v_row->'highlighted')='boolean'
        then (v_row->>'highlighted')::boolean
      else null
    end,
    false
  );

  if v_highlighted then
    v_source_change_signal:='new_item_or_price_change';
  end if;

  v_price:=case
    when jsonb_typeof(v_row->'displayPrice')='number'
      then (v_row->>'displayPrice')::numeric
    else null
  end;

  if v_raw_label is not null then
    v_explicit_stem_match:=regexp_match(
      v_raw_label,
      '([0-9]+)[[:space:]]*[Ss][Tt][Ee][Mm]'
    );

    if v_explicit_stem_match is not null then
      v_price_quantity:=(v_explicit_stem_match[1])::numeric;
      v_price_unit:='stem';
      v_pack_quantity:=v_price_quantity;
      v_pack_unit:='stem';
      v_source_unit:='stem';
      v_price_basis_state:='source_explicit';
    else
      v_x_count_match:=regexp_match(v_raw_label,'[xX][[:space:]]*([0-9]+)');
      if v_x_count_match is not null then
        v_source_quantity_hint:=(v_x_count_match[1])::numeric;
      end if;

      if lower(v_raw_label) ~ '(^|[^a-z])stem([^a-z]|$)' then
        v_source_unit_hint:='stem';
      end if;

      if lower(v_raw_label) ~ '-cs([^a-z]|$)' then
        v_provider_shorthand:='cs';
      end if;
    end if;
  end if;

  if v_price is null and v_row_kind='item' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','displayPrice',
      'reason','display_price_missing_or_invalid'
    ));
  end if;

  v_unresolved:=v_unresolved||jsonb_build_array(
    jsonb_build_object(
      'field','currency',
      'reason','source_currency_not_stated'
    ),
    jsonb_build_object(
      'field','availability',
      'reason','price_sheet_presence_does_not_establish_availability'
    ),
    jsonb_build_object(
      'field','delivery',
      'reason','requested_delivery_not_established'
    ),
    jsonb_build_object(
      'field','freight',
      'reason','freight_not_established'
    ),
    jsonb_build_object(
      'field','additionalFees',
      'reason','fee_completeness_not_established'
    )
  );

  if v_price_basis_state='unknown' and v_row_kind='item' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','priceBasis',
      'reason','price_denominator_not_stated'
    ));
  end if;

  if v_row_kind='context_ambiguous' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','rowIdentity',
      'reason','source_context_ambiguous'
    ));
  elsif v_row_kind='composite_unresolved' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','rowIdentity',
      'reason','composite_source_cell_not_losslessly_separated'
    ));
  elsif v_row_kind='subsection_header' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','rowKind',
      'reason','source_heading_not_offer'
    ));
  end if;

  if v_identity_state<>'resolved' and v_row_kind='item' then
    v_unresolved:=v_unresolved||jsonb_build_array(jsonb_build_object(
      'field','identityState',
      'reason','item_identity_not_resolved'
    ));
  end if;

  if upper(coalesce(v_section,''))='GREENS' then
    v_offering_kind:='floral_green';
  else
    v_offering_kind:='cut_flower';
  end if;

  v_specification:=jsonb_strip_nulls(jsonb_build_object(
    'productLabel',v_source_label,
    'providerSection',v_section,
    'providerSubsection',v_subsection,
    'providerSourcePath',v_row->'sourcePath',
    'providerRawLabel',v_raw_label,
    'sourceQuantityHint',v_source_quantity_hint,
    'sourceUnitHint',v_source_unit_hint,
    'providerShorthand',v_provider_shorthand
  ));

  v_terms:=jsonb_build_object(
    'priceSubjectToChange',v_price_subject_to_change,
    'additionalFeesComplete',false
  );

  v_source_context:=jsonb_strip_nulls(jsonb_build_object(
    'providerKey','baisch_skinner',
    'documentKey',v_document_key,
    'documentTitle',p_document->>'documentTitle',
    'documentValidFrom',v_valid_from::text,
    'documentValidUntil',v_valid_until::text,
    'priceSubjectToChange',v_price_subject_to_change,
    'rowKey',v_row_key,
    'rowKind',v_row_kind,
    'identityState',v_identity_state,
    'section',v_section,
    'subsection',v_subsection,
    'sourcePath',v_row->'sourcePath',
    'rawLabel',v_raw_label,
    'displayPriceText',v_price_text,
    'highlighted',v_highlighted,
    'sourceChangeSignal',v_source_change_signal,
    'sourceQuantityHint',v_source_quantity_hint,
    'sourceUnitHint',v_source_unit_hint,
    'providerShorthand',v_provider_shorthand,
    'providerLocalCategory',case
      when upper(coalesce(v_subsection,''))='LOCAL' then true
      else null
    end
  ));

  v_provider_facts:=jsonb_strip_nulls(jsonb_build_object(
    'rowKey',v_row_key,
    'rowKind',v_row_kind,
    'identityState',v_identity_state,
    'section',v_section,
    'subsection',v_subsection,
    'sourcePath',v_row->'sourcePath',
    'rawLabel',v_raw_label,
    'displayPriceText',v_price_text,
    'displayPrice',v_price,
    'highlighted',v_highlighted,
    'sourceChangeSignal',v_source_change_signal,
    'sourceQuantityHint',v_source_quantity_hint,
    'sourceUnitHint',v_source_unit_hint,
    'providerShorthand',v_provider_shorthand,
    'normalizationNotes',v_row->'normalizationNotes'
  ));

  if upper(coalesce(v_subsection,''))='LOCAL' then
    v_source_preference:=jsonb_build_object(
      'state','unresolved',
      'reason','provider_local_category_not_mapped_to_feast_guild_region',
      'providerCategory','LOCAL'
    );
  else
    v_source_preference:=jsonb_build_object(
      'state','unresolved',
      'reason','biological_grow_origin_not_established'
    );
  end if;

  v_admissible:=
    v_row_kind='item'
    and v_identity_state='resolved'
    and v_source_label is not null
    and v_price is not null;

  return jsonb_build_object(
    'contractVersion','baisch_skinner_price_sheet_row_interpretation_v1',
    'providerContract',v_contract,
    'rawDocumentIdentity',jsonb_build_object(
      'providerKey','baisch_skinner',
      'providerObjectKind','published_price_sheet',
      'providerObjectKey',v_document_key
    ),
    'rowIdentity',jsonb_build_object(
      'rowKey',v_row_key,
      'rowKind',v_row_kind,
      'identityState',v_identity_state,
      'admissible',v_admissible
    ),
    'offeringDraft',jsonb_build_object(
      'stableKey','baisch_skinner:price_sheet_item:'||v_row_key,
      'sourceItemKey',v_row_key,
      'sourceLabel',v_source_label,
      'offeringKind',v_offering_kind,
      'sourceUnit',v_source_unit,
      'specification',v_specification,
      'metadata',jsonb_build_object(
        'providerKey','baisch_skinner',
        'identityBasis','normalized_source_path'
      )
    ),
    'observationDraft',jsonb_build_object(
      'observationKey',v_document_key||':'||v_row_key,
      'observedAt',p_observed_at,
      'effectiveFrom',v_valid_from,
      'effectiveUntil',v_valid_until,
      'priceAmount',v_price,
      'currency',null,
      'priceBasisState',v_price_basis_state,
      'priceQuantity',v_price_quantity,
      'priceUnit',v_price_unit,
      'packQuantity',v_pack_quantity,
      'packUnit',v_pack_unit,
      'minimumOrderQuantity',null,
      'minimumOrderUnit',null,
      'availabilityState','unknown',
      'terms',v_terms,
      'sourceContext',v_source_context,
      'sourceKind','supplier_price_list',
      'sourceRef',v_document_key||'#'||v_row_key
    ),
    'providerFacts',v_provider_facts,
    'unresolvedSemantics',v_unresolved,
    'sourcePreference',v_source_preference,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'normalizedSourcePreserved',true,
      'displayedPricePreserved',true,
      'currencyNotInferred',true,
      'availabilityNotInferredFromListPresence',true,
      'localCategoryNotMappedToFeastGuildRegion',true,
      'xCountWithoutUnitDoesNotBecomePriceBasis',true,
      'doesNotWriteConnectedSourceObservation',true,
      'doesNotWriteExternalSupplyOffer',true,
      'doesNotPurchase',true
    )
  );
end;
$function$;


create or replace function atlas.baisch_skinner_price_sheet_batch_interpret_v1(
  p_document jsonb,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_row jsonb;
  v_items jsonb:='[]'::jsonb;
begin
  if p_document is null or jsonb_typeof(p_document)<>'object'
     or jsonb_typeof(p_document->'rows') is distinct from 'array' then
    raise exception 'Baisch & Skinner normalized document with rows is required.'
      using errcode='22023';
  end if;

  if p_observed_at is null then
    raise exception 'Observed-at timestamp is required.'
      using errcode='22023';
  end if;

  perform atlas.baisch_skinner_price_sheet_document_key_v1(p_document);

  for v_row in
    select value from jsonb_array_elements(p_document->'rows')
  loop
    if nullif(btrim(coalesce(v_row->>'rowKey','')),'') is null then
      raise exception 'Every normalized Baisch & Skinner row requires rowKey.'
        using errcode='22023';
    end if;

    v_items:=v_items||jsonb_build_array(
      atlas.baisch_skinner_price_sheet_row_interpret_v1(
        p_document,
        v_row->>'rowKey',
        p_observed_at
      )
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','baisch_skinner_price_sheet_batch_interpretation_v1',
    'providerKey','baisch_skinner',
    'providerObjectKey',atlas.baisch_skinner_price_sheet_document_key_v1(p_document),
    'observedAt',p_observed_at,
    'rowCount',jsonb_array_length(p_document->'rows'),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'normalizationIsUpstream',true,
      'doesNotCreateAvailability',true,
      'doesNotCompleteEconomics',true
    )
  );
end;
$function$;


revoke all on function atlas.baisch_skinner_price_sheet_provider_contract_v1()
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_provider_contract_v1()
  to service_role;

revoke all on function atlas.baisch_skinner_price_sheet_document_key_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_document_key_v1(jsonb)
  to service_role;

revoke all on function atlas.baisch_skinner_price_sheet_connected_source_record_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_connected_source_record_v1(jsonb)
  to service_role;

revoke all on function atlas.baisch_skinner_price_sheet_row_interpret_v1(jsonb,text,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_row_interpret_v1(jsonb,text,timestamptz)
  to service_role;

revoke all on function atlas.baisch_skinner_price_sheet_batch_interpret_v1(jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_batch_interpret_v1(jsonb,timestamptz)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.baisch_skinner_price_sheet_provider_contract_v1()',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_adapter_v1","purpose":"Immutable Baisch & Skinner published price-sheet semantics; preserves unresolved currency, availability, units, logistics, and origin.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.baisch_skinner_price_sheet_document_key_v1(jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_adapter_v1","purpose":"Deterministic identity for one published Baisch & Skinner price-list period.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.baisch_skinner_price_sheet_connected_source_record_v1(jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_adapter_v1","purpose":"Package one losslessly normalized Baisch & Skinner price sheet for generic Connected Source raw custody.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.baisch_skinner_price_sheet_row_interpret_v1(jsonb,text,timestamptz)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_adapter_v1","purpose":"Pure row interpretation of Baisch & Skinner source price evidence without inventing missing currency, availability, denominator, freight, or origin.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.baisch_skinner_price_sheet_batch_interpret_v1(jsonb,timestamptz)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_adapter_v1","purpose":"Read-only batch interpretation of one normalized Baisch & Skinner published price sheet.","classificationRuleVersion":3}'::jsonb,
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
