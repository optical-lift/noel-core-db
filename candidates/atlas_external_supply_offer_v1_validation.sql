begin;

do $validation$
declare
  v_org_id uuid;
  v_supplier_subject_id uuid;
  v_non_supplier_subject_id uuid;
  v_supplier atlas.external_relationships%rowtype;
  v_non_supplier atlas.external_relationships%rowtype;
  v_offering_id uuid;
  v_result jsonb;
  v_read jsonb;
  v_current jsonb;
  v_observation_id uuid;
  v_connected_source_id uuid;
  v_raw_observation_id uuid;
  v_before_orders integer;
  v_before_spend integer;
  v_before_ready integer;
  v_before_sell_prices integer;
begin
  -- Production-clone validation is schema-only, so create all fixture identity
  -- and relationship truth inside this rollback transaction.
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_supply_validation_v1',
    'Fixture External Supply Organization',
    'active',
    '{"fixture":"atlas_external_supply_offer_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(
    v_org_id,
    '{"fixture":"supplier_subject"}'::jsonb
  )
  returning id into v_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,null,v_supplier_subject_id,
    'fixture-supplier','active',
    '{"fixture":"atlas_external_supply_offer_v1"}'::jsonb
  )
  returning * into v_supplier;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier.id,'supplier','active',
    '{"fixture":"atlas_external_supply_offer_v1"}'::jsonb
  );

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(
    v_org_id,
    '{"fixture":"non_supplier_subject"}'::jsonb
  )
  returning id into v_non_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,null,v_non_supplier_subject_id,
    'fixture-non-supplier','active',
    '{"fixture":"atlas_external_supply_offer_v1"}'::jsonb
  )
  returning * into v_non_supplier;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_non_supplier.id,'customer','active',
    '{"fixture":"atlas_external_supply_offer_v1"}'::jsonb
  );

  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_ready from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_sell_prices from atlas.commercial_offering_prices;

  insert into atlas.connected_sources(
    custodian_user_id,custodian_organization_id,custodian_organization_unit_id,
    provider_key,provider_account_key,display_label,authorization_state,
    granted_scopes,capabilities,metadata
  ) values (
    null,v_supplier.organization_id,v_supplier.organization_unit_id,
    'validation_supplier_source','validation-account','Validation Supplier Source',
    'connected','{}'::text[],
    '{"catalogRead":true,"priceRead":true}'::jsonb,
    '{"fixture":"external_supply_validation"}'::jsonb
  )
  returning id into v_connected_source_id;

  perform atlas.record_connected_source_observation_batch_service_v1(
    v_connected_source_id,
    'price_listing',
    jsonb_build_array(
      jsonb_build_object(
        'key','baisch-20260919-carnations',
        'payload',jsonb_build_object(
          'sourceLabel','Carnations',
          'priceAmount',0.65,
          'priceBasisText',null,
          'documentTitle','Cut Flower Price List',
          'validFrom','2026-09-19',
          'validUntil','2026-09-25'
        )
      )
    ),
    '2026-09-23T12:00:00Z'::timestamptz,
    '{"captureMethod":"uploaded_supplier_artifact","fixture":"baisch_price_list_2026_09_19"}'::jsonb
  );

  select id into v_raw_observation_id
  from atlas.connected_source_observations
  where connected_source_id=v_connected_source_id
    and provider_object_kind='price_listing'
    and provider_object_key='baisch-20260919-carnations'
  order by created_at desc,id desc
  limit 1;

  if v_raw_observation_id is null then
    raise exception 'Raw connected-source observation fixture was not recorded.';
  end if;

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_supplier.organization_id,
    v_supplier.organization_unit_id,
    v_supplier.id,
    'validation-baisch-carnations',
    null,
    'Carnations',
    'cut_flower',
    null,
    '{"sourceFamily":"carnation"}'::jsonb,
    '{"fixture":"baisch_price_list_2026_09_19"}'::jsonb
  );

  if v_offering_id is null then
    raise exception 'External supply offering was not created.';
  end if;

  -- Second real-source shape: the supplier label itself explicitly states a
  -- 10-stem denominator (Delphinium S.A. / Hybrid-10 Stem, 20.95).
  declare
    v_explicit_offering_id uuid;
    v_explicit_result jsonb;
  begin
    v_explicit_offering_id:=atlas.ensure_external_supply_offering_service_v1(
      v_supplier.organization_id,
      v_supplier.organization_unit_id,
      v_supplier.id,
      'validation-baisch-delphinium-hybrid-10-stem',
      null,
      'Delphinium S.A. / Hybrid-10 Stem',
      'cut_flower',
      'stem',
      '{"sourceFamily":"delphinium","sourceVariant":"Hybrid-10 Stem"}'::jsonb,
      '{"fixture":"baisch_price_list_2026_09_19"}'::jsonb
    );

    v_explicit_result:=atlas.record_external_supply_offer_observation_service_v1(
      v_explicit_offering_id,
      'validation-baisch-20260919-delphinium-hybrid-10-stem',
      '2026-09-23T12:00:00Z'::timestamptz,
      '2026-09-19',
      '2026-09-25',
      20.95,
      null,
      'source_explicit',
      10,
      'stem',
      10,
      'stem',
      null,
      null,
      null,
      null,
      'unknown',
      '{"priceSubjectToChange":true}'::jsonb,
      '{"supplier":"Baisch & Skinner Wholesale Floral Distributor","documentTitle":"Cut Flower Price List","sourceSection":"CUT FLOWERS","parentLabel":"Delphinium S.A.","rawLabel":"Hybrid-10 Stem","highlighted":false}'::jsonb,
      'supplier_price_list',
      'validation:baisch-cut-flower-price-list:2026-09-19_2026-09-25',
      null,
      null,
      '{"fixture":"real_source_explicit_denominator"}'::jsonb
    );

    if coalesce((v_explicit_result->>'created')::boolean,false)=false then
      raise exception 'Source-explicit denominator observation was not created: %',v_explicit_result;
    end if;
  end;

  if atlas.ensure_external_supply_offering_service_v1(
    v_supplier.organization_id,
    v_supplier.organization_unit_id,
    v_supplier.id,
    'validation-baisch-carnations',
    null,
    'Carnations',
    'cut_flower',
    null,
    '{"sourceFamily":"carnation"}'::jsonb,
    '{"fixture":"baisch_price_list_2026_09_19"}'::jsonb
  ) is distinct from v_offering_id then
    raise exception 'External supply offering ensure is not idempotent.';
  end if;

  v_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    'validation-baisch-20260919-carnations',
    '2026-09-23T12:00:00Z'::timestamptz,
    '2026-09-19',
    '2026-09-25',
    0.65,
    null,
    'unknown',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    'unknown',
    '{"priceSubjectToChange":true}'::jsonb,
    '{"supplier":"Baisch & Skinner Wholesale Floral Distributor","documentTitle":"Cut Flower Price List","sourceSection":"CUT FLOWERS","rawLabel":"Carnations","highlighted":false}'::jsonb,
    'supplier_price_list',
    'validation:baisch-cut-flower-price-list:2026-09-19_2026-09-25',
    null,
    v_raw_observation_id,
    '{"fixture":"real_source_shape"}'::jsonb
  );

  if coalesce((v_result->>'created')::boolean,false)=false then
    raise exception 'First supply observation was not created: %',v_result;
  end if;

  v_observation_id:=(v_result->>'externalSupplyOfferObservationId')::uuid;

  v_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    'validation-baisch-20260919-carnations',
    '2026-09-23T12:00:00Z'::timestamptz,
    '2026-09-19',
    '2026-09-25',
    0.65,
    null,
    'unknown',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    'unknown',
    '{"priceSubjectToChange":true}'::jsonb,
    '{"supplier":"Baisch & Skinner Wholesale Floral Distributor","documentTitle":"Cut Flower Price List","sourceSection":"CUT FLOWERS","rawLabel":"Carnations","highlighted":false}'::jsonb,
    'supplier_price_list',
    'validation:baisch-cut-flower-price-list:2026-09-19_2026-09-25',
    null,
    v_raw_observation_id,
    '{"fixture":"real_source_shape"}'::jsonb
  );

  if coalesce((v_result->>'created')::boolean,true)
     or (v_result->>'externalSupplyOfferObservationId')::uuid is distinct from v_observation_id then
    raise exception 'Supply observation idempotency failed: %',v_result;
  end if;

  begin
    perform atlas.record_external_supply_offer_observation_service_v1(
      v_offering_id,
      'validation-baisch-20260919-carnations',
      '2026-09-23T12:00:00Z'::timestamptz,
      '2026-09-19',
      '2026-09-25',
      0.66,
      null,
      'unknown',
      null,null,null,null,null,null,null,null,
      'unknown',
      '{"priceSubjectToChange":true}'::jsonb,
      '{"rawLabel":"Carnations"}'::jsonb,
      'supplier_price_list',
      'validation:baisch-cut-flower-price-list:changed',
      null,
      v_raw_observation_id,
      '{}'::jsonb
    );
    raise exception 'Observation key accepted different source terms.';
  exception when sqlstate '23505' then
    null;
  end;

  v_read:=atlas.external_supply_offers_for_supplier_service_v1(
    v_supplier.id,'2026-09-23'
  );
  v_current:=v_read->'offers'->0->'currentObservation';

  if v_current is null
     or (v_current->>'priceAmount')::numeric<>0.65
     or v_current->>'priceBasisState'<>'unknown'
     or v_current->>'currency' is not null
     or v_current->>'availabilityState'<>'unknown'
     or (v_current->>'connectedSourceObservationId')::uuid is distinct from v_raw_observation_id
     or coalesce((v_current->'terms'->>'priceSubjectToChange')::boolean,false)=false then
    raise exception 'Real-source-shaped current observation was not preserved faithfully: %',v_read;
  end if;

  v_read:=atlas.external_supply_offers_for_supplier_service_v1(
    v_supplier.id,'2026-09-26'
  );

  if (v_read->'offers'->0->'currentObservation') is not null then
    raise exception 'Expired source window still resolved as current: %',v_read;
  end if;

  begin
    perform atlas.record_external_supply_offer_observation_service_v1(
      v_offering_id,
      'validation-explicit-basis-missing-denominator',
      now(),
      null,null,
      10,
      'USD',
      'source_explicit',
      null,null,
      null,null,null,null,null,null,
      'unknown',
      '{}'::jsonb,'{}'::jsonb,
      'supplier_quote',null,null,null,'{}'::jsonb
    );
    raise exception 'Source-explicit price basis without denominator was admitted.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    perform atlas.record_external_supply_offer_observation_service_v1(
      v_offering_id,
      'validation-unknown-basis-with-denominator',
      now(),
      null,null,
      10,
      'USD',
      'unknown',
      10,'stem',
      null,null,null,null,null,null,
      'unknown',
      '{}'::jsonb,'{}'::jsonb,
      'supplier_quote',null,null,null,'{}'::jsonb
    );
    raise exception 'Unknown price basis with a normalized denominator was admitted.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    perform atlas.record_external_supply_offer_observation_service_v1(
      v_offering_id,
      'validation-bad-window',
      now(),
      '2026-09-25','2026-09-19',
      10,
      null,
      'unknown',
      null,null,null,null,null,null,null,null,
      'unknown',
      '{}'::jsonb,'{}'::jsonb,
      'supplier_price_list',null,null,null,'{}'::jsonb
    );
    raise exception 'Invalid effective window was admitted.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    update atlas.external_supply_offer_observations
    set price_amount=0.70
    where id=v_observation_id;
    raise exception 'Append-only supply observation was mutated.';
  exception when sqlstate '55000' then
    null;
  end;

  if v_non_supplier.id is not null then
    begin
      perform atlas.ensure_external_supply_offering_service_v1(
        v_non_supplier.organization_id,
        v_non_supplier.organization_unit_id,
        v_non_supplier.id,
        'validation-not-supplier',
        null,
        'Not supplier',
        'item',
        null,
        '{}'::jsonb,
        '{}'::jsonb
      );
      raise exception 'Non-supplier relationship created an external supply offering.';
    exception when sqlstate '23514' then
      null;
    end;
  end if;

  if has_table_privilege(
       'authenticated','atlas.external_supply_offerings','SELECT'
     )
     or has_table_privilege(
       'authenticated','atlas.external_supply_offer_observations','SELECT'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.external_supply_offers_for_supplier_service_v1(uuid,date)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.external_supply_offers_for_supplier_service_v1(uuid,date)',
       'EXECUTE'
     ) then
    raise exception 'External supply browser/service privilege boundary is incorrect.';
  end if;

  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_ready
     or (select count(*) from atlas.commercial_offering_prices)<>v_before_sell_prices then
    raise exception 'External supply observation created downstream commerce/spend/inventory/sell-price truth.';
  end if;
end;
$validation$;

rollback;
