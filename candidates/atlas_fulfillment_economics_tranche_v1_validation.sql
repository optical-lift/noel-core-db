-- Atlas Fulfillment Economics Tranche v1 — rollback validation bundle
-- Candidate-only. Runs each disposable proof against a schema clone after the candidate install bundle.

-- ============================================================================
-- BEGIN candidates/atlas_external_supply_offer_v1_validation.sql
-- ============================================================================
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
-- ============================================================================
-- END candidates/atlas_external_supply_offer_v1_validation.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_fulfillment_candidate_qualification_v1_validation.sql
-- ============================================================================
begin;

do $validation$
declare
  v_result jsonb;

  v_before_work bigint;
  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_ready bigint;
  v_before_composition bigint;
begin
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_ready from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_composition from atlas.composition_runs;

  -- 1. All required nodes satisfied -> qualified.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"all-satisfied"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-a"}'::jsonb,
    '[
      {"requirementKey":"identity","required":true,"state":"satisfied","evidence":[]},
      {"requirementKey":"quantity","required":true,"state":"satisfied","evidence":[]},
      {"requirementKey":"timing","required":true,"state":"satisfied","evidence":[]}
    ]'::jsonb,
    '{"fixture":"all_required_satisfied"}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,false)=false
     or v_result->'evaluation'->>'state'<>'satisfied' then
    raise exception 'All-satisfied qualification failed: %',v_result;
  end if;

  -- 2. Required unsatisfied -> incompatible.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"incompatible"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-b"}'::jsonb,
    '[
      {"requirementKey":"identity","state":"satisfied"},
      {"requirementKey":"minimum_length","state":"unsatisfied","details":{"minimum":50,"candidate":40}},
      {"requirementKey":"availability","state":"unresolved"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'incompatible'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,true)
     or v_result->'evaluation'->>'state'<>'unsatisfied' then
    raise exception 'Required-unsatisfied precedence failed: %',v_result;
  end if;

  -- 3. No known failure but one required unresolved -> unresolved.
  -- This is the real first flower-source shape: a price-list row can satisfy
  -- source/spec facts while availability remains unknown.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"feast_guild_flower_requirement","sourceRef":"fixture:white-standard-rose"}'::jsonb,
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier-white-rose-60cm"}'::jsonb,
    '[
      {
        "requirementKey":"flower_family",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","value":"rose"}]
      },
      {
        "requirementKey":"color",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","value":"white"}]
      },
      {
        "requirementKey":"stem_length_minimum",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","valueCm":60}],
        "details":{"minimumCm":50,"candidateCm":60}
      },
      {
        "requirementKey":"availability_for_required_window",
        "required":true,
        "state":"unresolved",
        "evidence":[{"source":"supplier_price_list","availabilityStated":false}]
      }
    ]'::jsonb,
    '{"stage":"quote_planning"}'::jsonb
  );

  if v_result->>'qualificationState'<>'unresolved'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,true)
     or (v_result->'evaluation'->>'requiredUnresolvedCount')::integer<>1 then
    raise exception 'Unresolved flower-source fixture was not preserved: %',v_result;
  end if;

  -- 4. Optional soft preference does not block a candidate.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"soft-preference"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-c"}'::jsonb,
    '[
      {"requirementKey":"material_spec","required":true,"state":"satisfied"},
      {"requirementKey":"delivery_window","required":true,"state":"satisfied"},
      {"requirementKey":"domestic_preference","required":false,"state":"unsatisfied"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or (v_result->'evaluation'->>'optionalUnsatisfiedCount')::integer<>1 then
    raise exception 'Optional unsatisfied preference incorrectly blocked qualification: %',v_result;
  end if;

  -- 5. Optional unresolved preference also does not block.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"optional-unresolved"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-d"}'::jsonb,
    '[
      {"requirementKey":"hard_spec","required":true,"state":"satisfied"},
      {"requirementKey":"preferred_origin","required":false,"state":"unresolved"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or (v_result->'evaluation'->>'optionalUnresolvedCount')::integer<>1 then
    raise exception 'Optional unresolved preference incorrectly blocked qualification: %',v_result;
  end if;

  -- 6. A materially different, non-flower shape uses the same evaluator.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"accepted_scope_requirement","sourceRef":"fixture:flooring-material"}'::jsonb,
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:oak-flooring"}'::jsonb,
    '[
      {
        "requirementKey":"material_species",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_specification","value":"white_oak"}]
      },
      {
        "requirementKey":"minimum_grade",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_specification","value":"select"}]
      },
      {
        "requirementKey":"finish_color_preference",
        "required":false,
        "state":"unresolved"
      }
    ]'::jsonb,
    '{"adapter":"construction_leak_test"}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,false)=false
     or (v_result->'evaluation'->>'optionalUnresolvedCount')::integer<>1 then
    raise exception 'Construction-shaped qualification leak test failed: %',v_result;
  end if;

  -- 7. Empty set fails closed.
  begin
    perform atlas.requirement_set_evaluate_v2('[]'::jsonb);
    raise exception 'Empty requirement set was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 8. Duplicate keys fail closed.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[
        {"requirementKey":"same","state":"satisfied"},
        {"requirementKey":"same","state":"satisfied"}
      ]'::jsonb
    );
    raise exception 'Duplicate requirement keys were admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 9. Malformed state fails closed.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad","state":"probably"}]'::jsonb
    );
    raise exception 'Invalid requirement state was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 10. Evidence must remain structured.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad_evidence","state":"satisfied","evidence":"because I said so"}]'::jsonb
    );
    raise exception 'Non-array evidence was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 11. Details must remain structured.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad_details","state":"satisfied","details":"50cm"}]'::jsonb
    );
    raise exception 'Non-object details were admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 12. All-optional set fails closed: qualification needs at least one hard requirement.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"preference_only","required":false,"state":"satisfied"}]'::jsonb
    );
    raise exception 'All-optional requirement set was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 13. Opaque refs still require identity.
  begin
    perform atlas.fulfillment_candidate_qualification_v1(
      '{"sourceDomain":"fixture"}'::jsonb,
      '{"sourceDomain":"fixture_candidate","sourceRef":"x"}'::jsonb,
      '[{"requirementKey":"x","state":"satisfied"}]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Requirement ref without sourceRef was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.fulfillment_candidate_qualification_v1(
      '{"sourceDomain":"fixture","sourceRef":"x"}'::jsonb,
      '{"sourceRef":"y"}'::jsonb,
      '[{"requirementKey":"x","state":"satisfied"}]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Candidate ref without sourceDomain was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 14. Read-only means exactly that.
  if (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_ready
     or (select count(*) from atlas.composition_runs)<>v_before_composition then
    raise exception 'Qualification evaluation created durable operational/commercial truth.';
  end if;

  -- 15. Browser roles do not receive the internal evaluator.
  if has_function_privilege(
       'authenticated',
       'atlas.requirement_set_evaluate_v2(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.requirement_set_evaluate_v2(jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Qualification service/browser privilege boundary is incorrect.';
  end if;

  raise notice 'PASS atlas_fulfillment_candidate_qualification_v1: three-state qualification is read-only, fail-closed, resource-compatible, and flower-agnostic';
end;
$validation$;

rollback;
-- ============================================================================
-- END candidates/atlas_fulfillment_candidate_qualification_v1_validation.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_neutral_fulfillment_composition_v1_validation.sql
-- ============================================================================
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
-- ============================================================================
-- END candidates/atlas_neutral_fulfillment_composition_v1_validation.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_commercial_price_evaluation_v1_validation.sql
-- ============================================================================
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
-- ============================================================================
-- END candidates/atlas_commercial_price_evaluation_v1_validation.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_fulfillment_economics_vertical_slice_v1_validation.sql
-- ============================================================================
begin;

do $validation$
declare
  v_org_id uuid;
  v_supplier_subject_id uuid;
  v_supplier_relationship_id uuid;
  v_connected_source_id uuid;
  v_raw_observation_id uuid;
  v_supply_offering_id uuid;
  v_supply_observation_result jsonb;
  v_supply_observation_id uuid;

  v_qualification jsonb;
  v_packet jsonb;
  v_position jsonb;
  v_price jsonb;
  v_snapshot jsonb;
  v_snapshot_id uuid;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_work bigint;
  v_before_inventory bigint;
begin
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;

  -- Schema-only clone fixture: establish one Organization, one supplier relationship,
  -- and one provider observation entirely inside this rollback transaction.
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_fulfillment_economics_vertical_v1',
    'Fixture Fulfillment Economics Organization',
    'active',
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
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
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
  )
  returning id into v_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
  );

  insert into atlas.connected_sources(
    custodian_user_id,custodian_organization_id,custodian_organization_unit_id,
    provider_key,provider_account_key,display_label,authorization_state,
    granted_scopes,capabilities,metadata
  ) values (
    null,v_org_id,null,
    'fixture_wholesale_provider','fixture-account',
    'Fixture Wholesale Provider','connected',
    '{}'::text[],
    '{"catalogRead":true,"priceRead":true,"availabilityRead":true}'::jsonb,
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
  )
  returning id into v_connected_source_id;

  perform atlas.record_connected_source_observation_batch_service_v1(
    v_connected_source_id,
    'market_listing',
    jsonb_build_array(
      jsonb_build_object(
        'key','fixture-carnation-100',
        'payload',jsonb_build_object(
          'sourceLabel','Standard Carnation',
          'priceAmount',38.00,
          'currency','USD',
          'priceQuantity',100,
          'priceUnit','stem',
          'packQuantity',100,
          'packUnit','stem',
          'availability','available'
        )
      )
    ),
    '2026-09-23T20:00:00Z'::timestamptz,
    '{"captureMethod":"validation_fixture"}'::jsonb
  );

  select id into v_raw_observation_id
  from atlas.connected_source_observations
  where connected_source_id=v_connected_source_id
    and provider_object_kind='market_listing'
    and provider_object_key='fixture-carnation-100'
  order by created_at desc,id desc
  limit 1;

  if v_raw_observation_id is null then
    raise exception 'Vertical slice did not create raw provider observation.';
  end if;

  -- External source truth.
  v_supply_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,
    null,
    v_supplier_relationship_id,
    'fixture-standard-carnation',
    'fixture-carnation-100',
    'Standard Carnation',
    'cut_flower',
    'stem',
    '{"flowerFamily":"carnation","grade":"standard"}'::jsonb,
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
  );

  v_supply_observation_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_supply_offering_id,
    'fixture-20260923-carnation-100',
    '2026-09-23T20:00:00Z'::timestamptz,
    '2026-09-23',
    '2026-09-24',
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
    '{"freightIncluded":true}'::jsonb,
    '{"rawLabel":"Standard Carnation","providerObjectKey":"fixture-carnation-100"}'::jsonb,
    'supplier_quote',
    'fixture:provider:fixture-carnation-100',
    null,
    v_raw_observation_id,
    '{"fixture":"atlas_fulfillment_economics_vertical_slice_v1"}'::jsonb
  );

  v_supply_observation_id:=
    (v_supply_observation_result->>'externalSupplyOfferObservationId')::uuid;

  if v_supply_observation_id is null then
    raise exception 'Vertical slice did not create interpreted supplier observation.';
  end if;

  -- Universal qualification: source facts establish candidate eligibility.
  v_qualification:=atlas.fulfillment_candidate_qualification_v1(
    jsonb_build_object(
      'sourceDomain','customer_requirement_fixture',
      'sourceRef','fixture:100-standard-carnations'
    ),
    jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_supply_offering_id::text
    ),
    '[
      {"requirementKey":"flower_family","required":true,"state":"satisfied"},
      {"requirementKey":"grade","required":true,"state":"satisfied"},
      {"requirementKey":"quantity","required":true,"state":"satisfied"},
      {"requirementKey":"availability","required":true,"state":"satisfied"}
    ]'::jsonb,
    jsonb_build_object(
      'sourceObservationId',v_supply_observation_id,
      'fixture','atlas_fulfillment_economics_vertical_slice_v1'
    )
  );

  if v_qualification->>'qualificationState'<>'qualified'
     or coalesce((v_qualification->>'mayEnterPlanning')::boolean,false)=false then
    raise exception 'Vertical slice candidate qualification failed: %',v_qualification;
  end if;

  -- Neutral composition: one qualified source covers the quantified requirement.
  v_packet:=jsonb_build_object(
    'contractVersion','neutral_fulfillment_composition_v1',
    'requirementRef',jsonb_build_object(
      'sourceDomain','customer_requirement_fixture',
      'sourceRef','fixture:100-standard-carnations'
    ),
    'requirement',jsonb_build_object(
      'quantity',100,
      'unit','stem',
      'requiredBy','2026-09-24T12:00:00Z'
    ),
    'planKey','fixture:single-source-carnation',
    'allocations',jsonb_build_array(
      jsonb_build_object(
        'allocationKey','fixture-supplier-100',
        'candidateRef',jsonb_build_object(
          'sourceDomain','external_supply_offering',
          'sourceRef',v_supply_offering_id::text
        ),
        'qualificationState','qualified',
        'sourceQuantity',100,
        'sourceUnit','stem',
        'outputQuantity',100,
        'outputUnit','stem',
        'costComponents',jsonb_build_array(
          jsonb_build_object(
            'componentKey','landed_supplier_cost',
            'state','known',
            'amount',38.00,
            'currency','USD',
            'sourceRef',v_supply_observation_id::text
          )
        )
      )
    ),
    'metadata',jsonb_build_object(
      'fixture','atlas_fulfillment_economics_vertical_slice_v1'
    )
  );

  v_position:=atlas.fulfillment_composition_position_v1(v_packet);

  if v_position->>'coverageState'<>'exact'
     or v_position->>'economicState'<>'known'
     or (v_position->'knownCostTotalsByCurrency'->>'USD')::numeric<>38.00 then
    raise exception 'Vertical slice neutral composition failed: %',v_position;
  end if;

  -- Universal price evaluation: 30% gross margin, upward cent rounding.
  v_price:=atlas.commercial_price_evaluate_v1(
    v_packet,
    '{
      "contractVersion":"commercial_price_policy_input_v1",
      "method":"gross_margin",
      "rate":0.30,
      "currency":"USD",
      "rounding":{"mode":"ceil","increment":0.01}
    }'::jsonb
  );

  if v_price->>'state'<>'priced'
     or (v_price->>'proposedUnitPrice')::numeric<>0.55
     or (v_price->>'proposedTotal')::numeric<>55.00 then
    raise exception 'Vertical slice price evaluation failed: %',v_price;
  end if;

  -- Reuse existing immutable Commercial Offer Snapshot authority.
  v_snapshot:=atlas.record_commercial_offer_snapshot_service_v1(
    v_org_id,
    null,
    'fixture-carnation-offer-v1',
    'Fixture 100 Carnations',
    'complete',
    '2026-09-23T20:00:00Z'::timestamptz,
    '2026-09-24T00:00:00Z'::timestamptz,
    jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations',
        'description','Standard Carnations',
        'quantityAvailable',100,
        'unit','stem',
        'unitPrice',0.55,
        'currency','USD',
        'priceBasis','derived_from_fulfillment_economics',
        'terms',jsonb_build_object(
          'quotedQuantity',100,
          'proposedTotal',55.00,
          'fulfillmentPlanKey',v_packet->>'planKey'
        ),
        'sourceRef',v_supply_observation_id::text,
        'metadata',jsonb_build_object(
          'priceEvaluationContract','commercial_price_evaluation_v1',
          'sourceOfferingId',v_supply_offering_id
        )
      )
    ),
    '[]'::jsonb,
    'domain_snapshot',
    'fixture:fulfillment-economics-vertical-slice',
    jsonb_build_object(
      'fixture','atlas_fulfillment_economics_vertical_slice_v1',
      'truthBoundary',jsonb_build_object(
        'doesNotCreateOrder',true,
        'doesNotAuthorizePurchase',true,
        'doesNotCreateInventory',true
      )
    )
  );

  v_snapshot_id:=(v_snapshot->>'offerSnapshotId')::uuid;

  if v_snapshot_id is null
     or coalesce((v_snapshot->>'created')::boolean,false)=false then
    raise exception 'Vertical slice did not create offer snapshot: %',v_snapshot;
  end if;

  if not exists(
    select 1
    from atlas.commercial_offer_snapshot_lines l
    where l.offer_snapshot_id=v_snapshot_id
      and l.line_key='carnations'
      and l.quantity_available=100
      and l.unit='stem'
      and l.unit_price=0.55
      and l.currency='USD'
      and l.price_basis='derived_from_fulfillment_economics'
  ) then
    raise exception 'Vertical slice offer snapshot line did not preserve priced terms.';
  end if;

  -- Prepared offer evidence still must not create downstream commitment/execution truth.
  if (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory then
    raise exception 'Prepared offer vertical slice created downstream commitment/execution truth.';
  end if;

  raise notice 'PASS atlas_fulfillment_economics_vertical_slice_v1: source observation -> qualification -> neutral composition -> protected price -> existing offer snapshot, with no order/purchase/inventory/work consequences';
end;
$validation$;

rollback;
-- ============================================================================
-- END candidates/atlas_fulfillment_economics_vertical_slice_v1_validation.sql
-- ============================================================================
