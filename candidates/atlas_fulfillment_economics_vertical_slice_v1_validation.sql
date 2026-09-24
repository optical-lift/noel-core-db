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
