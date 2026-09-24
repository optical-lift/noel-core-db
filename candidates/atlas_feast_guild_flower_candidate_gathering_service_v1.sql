begin;

create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
  v_at_date date:=coalesce(p_at_date,current_date);
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  if nullif(btrim(coalesce(p_basket->>'requestedForDate','')),'') is null then
    raise exception 'Basket requestedForDate is required.' using errcode='22023';
  end if;
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=v_at_date)
          and (x.effective_until is null or x.effective_until>=v_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and exists(
          select 1
          from atlas.external_relationship_roles rr
          where rr.external_relationship_id=r.id
            and rr.role_key='supplier'
            and rr.role_state='active'
        )
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,v_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',v_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
    )
  );
end;
$function$;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_service_v1","purpose":"Service-only read of current Elm Ready inventory position and admitted external supplier observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
