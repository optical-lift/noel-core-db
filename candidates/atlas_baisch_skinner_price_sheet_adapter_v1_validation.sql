begin;

do $validation$
declare
  v_doc jsonb;
  v_result jsonb;
  v_batch jsonb;
  v_raw_record jsonb;

  v_org_id uuid;
  v_farm_id uuid;
  v_source_id uuid;
  v_subject_id uuid;
  v_relationship_id uuid;
  v_raw_id uuid;
  v_admission jsonb;
  v_carn_offering_id uuid;
  v_hybrid_offering_id uuid;
  v_gathered jsonb;
  v_selection jsonb;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_snapshots bigint;
begin
  v_doc:='{
    "contractVersion":"baisch_skinner_cut_flower_price_sheet_normalized_v1",
    "providerKey":"baisch_skinner",
    "documentTitle":"Cut Flower Price List",
    "validFrom":"2026-09-19",
    "validUntil":"2026-09-25",
    "priceSubjectToChange":true,
    "highlightMeaning":"new_item_or_price_change",
    "rows":[
      {
        "rowKey":"cut_flowers|carnations",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "sourcePath":["Carnations"],
        "rawLabel":"Carnations",
        "displayPriceText":"0.65",
        "displayPrice":0.65,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|carnations|tinted",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "parentRowKey":"cut_flowers|carnations",
        "sourcePath":["Carnations","Tinted"],
        "rawLabel":"Tinted",
        "displayPriceText":"0.95",
        "displayPrice":0.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|minicarnations",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "sourcePath":["MiniCarnations"],
        "rawLabel":"MiniCarnations",
        "displayPriceText":"6.25",
        "displayPrice":6.25,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|sunflowers_x5",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "sourcePath":["Sunflowers x5"],
        "rawLabel":"Sunflowers x5",
        "displayPriceText":"10.95",
        "displayPrice":10.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|sunflowers_x5|mini_x10",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "parentRowKey":"cut_flowers|sunflowers_x5",
        "sourcePath":["Sunflowers x5","Mini x10"],
        "rawLabel":"Mini x10",
        "displayPriceText":"12.95",
        "displayPrice":12.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|hellebores_x10",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "sourcePath":["Hellebores x10"],
        "rawLabel":"Hellebores x10",
        "displayPriceText":"32.95",
        "displayPrice":32.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|delphinium_sa",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "sourcePath":["Delphinium S.A."],
        "rawLabel":"Delphinium S.A.",
        "displayPriceText":"20.35",
        "displayPrice":20.35,
        "highlighted":true,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|delphinium_sa|hybrid_10_stem",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "parentRowKey":"cut_flowers|delphinium_sa",
        "sourcePath":["Delphinium S.A.","Hybrid-10 Stem"],
        "rawLabel":"Hybrid-10 Stem",
        "displayPriceText":"20.95",
        "displayPrice":20.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|delphinium_sa|hybrid_5_stem",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "parentRowKey":"cut_flowers|delphinium_sa",
        "sourcePath":["Delphinium S.A.","Hybrid-5 Stem"],
        "rawLabel":"Hybrid-5 Stem",
        "displayPriceText":"18.95",
        "displayPrice":18.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"cut_flowers|orphan_60cm_colors",
        "rowKind":"context_ambiguous",
        "section":"CUT FLOWERS",
        "sourcePath":["60CM Colors"],
        "rawLabel":"60CM Colors",
        "displayPriceText":"1.60",
        "displayPrice":1.60,
        "highlighted":true,
        "identityState":"unresolved"
      },
      {
        "rowKey":"cut_flowers|anthuriums|composite_mini_small",
        "rowKind":"composite_unresolved",
        "section":"CUT FLOWERS",
        "parentRowKey":"cut_flowers|anthuriums",
        "sourcePath":["Anthuriums"],
        "rawLabel":"Mini 6.95 Small 8.95",
        "displayPriceText":null,
        "displayPrice":null,
        "highlighted":false,
        "identityState":"unresolved"
      },
      {
        "rowKey":"cut_flowers|local",
        "rowKind":"subsection_header",
        "section":"CUT FLOWERS",
        "subsection":"LOCAL",
        "sourcePath":["LOCAL"],
        "rawLabel":"LOCAL",
        "displayPriceText":null,
        "displayPrice":null,
        "highlighted":false,
        "identityState":"not_applicable"
      },
      {
        "rowKey":"cut_flowers|local|sunflowers",
        "rowKind":"item",
        "section":"CUT FLOWERS",
        "subsection":"LOCAL",
        "sourcePath":["LOCAL","Sunflowers"],
        "rawLabel":"Sunflowers",
        "displayPriceText":"9.95",
        "displayPrice":9.95,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"greens|thai_leaves_stem",
        "rowKind":"item",
        "section":"GREENS",
        "sourcePath":["Thai Leaves-stem"],
        "rawLabel":"Thai Leaves-stem",
        "displayPriceText":"1.25",
        "displayPrice":1.25,
        "highlighted":false,
        "identityState":"resolved"
      },
      {
        "rowKey":"greens|mood_moss_cs",
        "rowKind":"item",
        "section":"GREENS",
        "sourcePath":["Mood Moss-cs"],
        "rawLabel":"Mood Moss-cs",
        "displayPriceText":"53.95",
        "displayPrice":53.95,
        "highlighted":false,
        "identityState":"resolved"
      }
    ]
  }'::jsonb;

  if atlas.baisch_skinner_price_sheet_document_key_v1(v_doc)
     <>'baisch_skinner:cut_flower_price_list:2026-09-19:2026-09-25' then
    raise exception 'Baisch & Skinner document key is not deterministic.';
  end if;

  v_raw_record:=atlas.baisch_skinner_price_sheet_connected_source_record_v1(v_doc);
  if v_raw_record->'payload' is distinct from v_doc
     or v_raw_record->>'key'<>
        'baisch_skinner:cut_flower_price_list:2026-09-19:2026-09-25' then
    raise exception 'Baisch & Skinner raw packaging altered normalized source.';
  end if;

  -- Plain price: source value survives, currency/denominator/availability do not get invented.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|carnations','2026-09-24T18:00:00Z'::timestamptz
  );

  if (v_result->'observationDraft'->>'priceAmount')::numeric<>0.65
     or v_result->'observationDraft'->>'currency' is not null
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown'
     or v_result->'observationDraft'->>'priceQuantity' is not null
     or v_result->'observationDraft'->>'priceUnit' is not null
     or v_result->'observationDraft'->>'availabilityState'<>'unknown'
     or v_result->'observationDraft'->>'effectiveFrom'<>'2026-09-19'
     or v_result->'observationDraft'->>'effectiveUntil'<>'2026-09-25'
     or coalesce((v_result->'observationDraft'->'terms'->>'priceSubjectToChange')::boolean,false)=false then
    raise exception 'Baisch Carnations source boundary failed: %',v_result;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_result->'unresolvedSemantics') x(value)
    where x.value->>'field'='currency'
      and x.value->>'reason'='source_currency_not_stated'
  ) or not exists(
    select 1
    from jsonb_array_elements(v_result->'unresolvedSemantics') x(value)
    where x.value->>'field'='availability'
      and x.value->>'reason'='price_sheet_presence_does_not_establish_availability'
  ) then
    raise exception 'Baisch Carnations unresolved facts were lost: %',v_result;
  end if;

  -- MiniCarnations remains denominator-unresolved.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|minicarnations','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'observationDraft'->>'priceAmount')::numeric<>6.25
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown' then
    raise exception 'MiniCarnations denominator was invented: %',v_result;
  end if;

  -- x5/x10/x10 preserve count hints but not units or price denominators.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|sunflowers_x5','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'providerFacts'->>'sourceQuantityHint')::numeric<>5
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown'
     or v_result->'observationDraft'->>'priceUnit' is not null then
    raise exception 'Sunflowers x5 was over-interpreted: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|sunflowers_x5|mini_x10','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'providerFacts'->>'sourceQuantityHint')::numeric<>10
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown' then
    raise exception 'Mini x10 was over-interpreted: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|hellebores_x10','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'providerFacts'->>'sourceQuantityHint')::numeric<>10
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown' then
    raise exception 'Hellebores x10 was over-interpreted: %',v_result;
  end if;

  -- Explicit source quantity + unit can establish a source price denominator.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|delphinium_sa|hybrid_10_stem','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'observationDraft'->>'priceBasisState'<>'source_explicit'
     or (v_result->'observationDraft'->>'priceQuantity')::numeric<>10
     or v_result->'observationDraft'->>'priceUnit'<>'stem'
     or (v_result->'observationDraft'->>'packQuantity')::numeric<>10
     or v_result->'observationDraft'->>'packUnit'<>'stem'
     or v_result->'observationDraft'->>'currency' is not null then
    raise exception 'Hybrid-10 Stem source denominator failed: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|delphinium_sa|hybrid_5_stem','2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_result->'observationDraft'->>'priceQuantity')::numeric<>5
     or v_result->'observationDraft'->>'priceUnit'<>'stem' then
    raise exception 'Hybrid-5 Stem source denominator failed: %',v_result;
  end if;

  -- Highlight means new OR changed, not one specific interpretation.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|delphinium_sa','2026-09-24T18:00:00Z'::timestamptz
  );
  if v_result->'providerFacts'->>'sourceChangeSignal'<>'new_item_or_price_change' then
    raise exception 'Baisch highlighted-source signal was narrowed incorrectly: %',v_result;
  end if;

  -- Provider LOCAL is not Feast Guild regional/domestic sourcing evidence.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|local|sunflowers','2026-09-24T18:00:00Z'::timestamptz
  );
  if v_result->'sourcePreference'->>'state'<>'unresolved'
     or v_result->'sourcePreference'->>'reason'<>
        'provider_local_category_not_mapped_to_feast_guild_region'
     or v_result->'observationDraft'->'sourceContext'->>'providerLocalCategory'<>'true' then
    raise exception 'Baisch LOCAL category was improperly mapped to source preference: %',v_result;
  end if;

  -- Unit hints and shorthand do not become denominators.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'greens|thai_leaves_stem','2026-09-24T18:00:00Z'::timestamptz
  );
  if v_result->'providerFacts'->>'sourceUnitHint'<>'stem'
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown'
     or v_result->'observationDraft'->>'priceUnit' is not null then
    raise exception 'Baisch -stem hint became price denominator: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'greens|mood_moss_cs','2026-09-24T18:00:00Z'::timestamptz
  );
  if v_result->'providerFacts'->>'providerShorthand'<>'cs'
     or v_result->'observationDraft'->>'priceBasisState'<>'unknown' then
    raise exception 'Baisch -cs shorthand was guessed: %',v_result;
  end if;

  -- Ambiguous/composite/header rows remain non-admissible.
  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|orphan_60cm_colors','2026-09-24T18:00:00Z'::timestamptz
  );
  if coalesce((v_result->'rowIdentity'->>'admissible')::boolean,true)=true then
    raise exception 'Context-ambiguous Baisch row became an offering: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|anthuriums|composite_mini_small','2026-09-24T18:00:00Z'::timestamptz
  );
  if coalesce((v_result->'rowIdentity'->>'admissible')::boolean,true)=true then
    raise exception 'Composite unresolved Baisch row became an offering: %',v_result;
  end if;

  v_result:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_doc,'cut_flowers|local','2026-09-24T18:00:00Z'::timestamptz
  );
  if coalesce((v_result->'rowIdentity'->>'admissible')::boolean,true)=true then
    raise exception 'Baisch subsection heading became an offering: %',v_result;
  end if;

  v_batch:=atlas.baisch_skinner_price_sheet_batch_interpret_v1(
    v_doc,'2026-09-24T18:00:00Z'::timestamptz
  );
  if (v_batch->>'rowCount')::integer<>15
     or jsonb_array_length(v_batch->'items')<>15 then
    raise exception 'Baisch batch interpretation lost rows: %',v_batch;
  end if;

  -- Durable raw-source and admission proof.
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_snapshots from atlas.commercial_offer_snapshots;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_baisch_skinner_sheet_v1',
    'Fixture Baisch Skinner Organization',
    'active',
    '{"fixture":"atlas_baisch_skinner_price_sheet_adapter_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.farms(stable_key,name,status,organization_id,metadata)
  values(
    'fixture-baisch-farm',
    'Fixture Baisch Farm',
    'active',
    v_org_id,
    '{"fixture":"atlas_baisch_skinner_price_sheet_adapter_v1"}'::jsonb
  )
  returning id into v_farm_id;

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
    'baisch_skinner',
    'fixture-account',
    'Fixture Baisch & Skinner',
    'connected',
    array['published_price_sheet_read']::text[],
    '{"publishedPriceSheet":true}'::jsonb,
    '{"fixture":"atlas_baisch_skinner_price_sheet_adapter_v1"}'::jsonb
  )
  returning id into v_source_id;

  perform atlas.record_connected_source_observation_batch_service_v1(
    v_source_id,
    'published_price_sheet',
    jsonb_build_array(
      atlas.baisch_skinner_price_sheet_connected_source_record_v1(v_doc)
    ),
    '2026-09-24T18:00:00Z'::timestamptz,
    '{
      "captureMethod":"fixture_normalized_published_sheet",
      "sourceSurface":"cut_flower_price_list",
      "accountScoped":true
    }'::jsonb
  );

  select o.id
  into v_raw_id
  from atlas.connected_source_observations o
  where o.connected_source_id=v_source_id
    and o.provider_object_kind='published_price_sheet'
    and o.provider_object_key=
      'baisch_skinner:cut_flower_price_list:2026-09-19:2026-09-25'
  order by o.observed_at desc,o.id desc
  limit 1;

  if v_raw_id is null then
    raise exception 'Baisch normalized raw document was not stored.';
  end if;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(
    v_org_id,
    '{"fixture":"baisch_supplier_subject"}'::jsonb
  )
  returning id into v_subject_id;

  insert into atlas.external_relationships(
    organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,
    null,
    v_subject_id,
    'fixture-baisch-supplier',
    'active',
    '{"fixture":"atlas_baisch_skinner_price_sheet_adapter_v1"}'::jsonb
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

  v_admission:=atlas.baisch_skinner_price_sheet_admit_document_service_v1(
    v_raw_id,
    v_relationship_id,
    null
  );

  if (v_admission->>'admittedCount')::integer<>12
     or (v_admission->>'skippedCount')::integer<>3 then
    raise exception 'Baisch document admission did not separate resolved/ambiguous rows: %',v_admission;
  end if;

  select o.id
  into v_carn_offering_id
  from atlas.external_supply_offerings o
  where o.supplier_relationship_id=v_relationship_id
    and o.source_item_key='cut_flowers|carnations';

  if v_carn_offering_id is null then
    raise exception 'Baisch Carnations row was not admitted.';
  end if;

  if not exists(
    select 1
    from atlas.external_supply_offer_observations o
    where o.external_supply_offering_id=v_carn_offering_id
      and o.connected_source_observation_id=v_raw_id
      and o.price_amount=0.65
      and o.currency is null
      and o.price_basis_state='unknown'
      and o.price_quantity is null
      and o.price_unit is null
      and o.availability_state='unknown'
      and o.source_context->>'priceSubjectToChange'='true'
  ) then
    raise exception 'Baisch admitted Carnations row lost unresolved source semantics.';
  end if;

  select o.id
  into v_hybrid_offering_id
  from atlas.external_supply_offerings o
  where o.supplier_relationship_id=v_relationship_id
    and o.source_item_key='cut_flowers|delphinium_sa|hybrid_10_stem';

  if v_hybrid_offering_id is null then
    raise exception 'Baisch Hybrid-10 Stem row was not admitted.';
  end if;

  if not exists(
    select 1
    from atlas.external_supply_offer_observations o
    where o.external_supply_offering_id=v_hybrid_offering_id
      and o.price_amount=20.95
      and o.currency is null
      and o.price_basis_state='source_explicit'
      and o.price_quantity=10
      and o.price_unit='stem'
      and o.pack_quantity=10
      and o.pack_unit='stem'
      and o.availability_state='unknown'
  ) then
    raise exception 'Baisch Hybrid-10 Stem admitted semantics failed.';
  end if;

  -- Same-period revised sheet stays under same document identity but creates another raw version.
  perform atlas.record_connected_source_observation_batch_service_v1(
    v_source_id,
    'published_price_sheet',
    jsonb_build_array(
      atlas.baisch_skinner_price_sheet_connected_source_record_v1(
        jsonb_set(
          v_doc,
          '{rows,0,displayPrice}',
          '0.70'::jsonb,
          false
        )
      )
    ),
    '2026-09-24T18:30:00Z'::timestamptz,
    '{
      "captureMethod":"fixture_normalized_published_sheet",
      "sourceSurface":"cut_flower_price_list",
      "accountScoped":true
    }'::jsonb
  );

  if (
    select count(*)
    from atlas.connected_source_observations o
    where o.connected_source_id=v_source_id
      and o.provider_object_key=
        'baisch_skinner:cut_flower_price_list:2026-09-19:2026-09-25'
  )<>2 then
    raise exception 'Revised Baisch same-period source did not remain append-only.';
  end if;

  -- Downstream source selection remains blocked: the sheet does not prove
  -- availability/capacity, delivery, currency, or landed cost completeness.
  v_gathered:=atlas.feast_guild_flower_candidate_sets_gather_service_v1(
    '{
      "contractVersion":"feast_guild_flower_basket_v1",
      "basketKey":"fixture-baisch-quote",
      "requestedForDate":"2026-09-24",
      "lines":[
        {
          "lineKey":"delphinium",
          "description":"Delphinium S.A. Hybrid-10 Stem",
          "quantity":10,
          "unit":"stem",
          "requirements":[
            {
              "requirementKey":"product_label",
              "required":true,
              "evidenceRequired":true,
              "expected":{"equals":"Delphinium S.A. / Hybrid-10 Stem"}
            }
          ]
        }
      ]
    }'::jsonb,
    v_org_id,
    v_farm_id,
    '2026-09-24'::date
  );

  if (v_gathered->'lineCandidateSets'->0->>'externalCandidateCount')::integer<1 then
    raise exception 'Baisch admitted row was not visible to candidate gathering: %',v_gathered;
  end if;

  v_selection:=atlas.feast_guild_flower_source_plan_select_v1(
    jsonb_build_object(
      'basketKey','fixture-baisch-quote',
      'lineKey','delphinium',
      'description','Delphinium S.A. Hybrid-10 Stem',
      'requestedForDate','2026-09-24',
      'quantity',10,
      'unit','stem',
      'requirements',jsonb_build_array(jsonb_build_object(
        'requirementKey','product_label',
        'required',true,
        'evidenceRequired',true,
        'expected',jsonb_build_object(
          'equals','Delphinium S.A. / Hybrid-10 Stem'
        )
      ))
    ),
    v_gathered->'lineCandidateSets'->0->'candidates'
  );

  if v_selection->>'state'<>'blocked'
     or v_selection->>'reason'<>'no_qualified_known_landed_cost_candidate' then
    raise exception 'Incomplete Baisch price sheet became automatically quotable: %',v_selection;
  end if;

  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_offer_snapshots)<>v_before_snapshots then
    raise exception 'Baisch adapter/admission created downstream commercial truth.';
  end if;

  raise notice 'PASS Baisch & Skinner price-sheet adapter: published source rows admit without inventing currency/availability/freight/origin, explicit stem denominators survive, ambiguous rows skip, revisions remain append-only, and protected source selection stays blocked until missing evidence is supplied';
end;
$validation$;

rollback;
