begin;

-- Package 4 / Flower Operations commercial notebook read seams v1.
-- Route availability remains source-stamped custody evidence separate from Ready.
-- Demand, Sale, Fulfillment, and buyer context remain distinct source-owned realities.

create or replace function atlas.flower_route_availability_notebook_self_api_v1(
  p_farm_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_role text;
  v_membership_id uuid;
  v_farm atlas.farms%rowtype;
  v_items jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_farm_id is null then
    raise exception 'Farm is required.' using errcode='22023';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if v_role not in ('owner','manager') then
    raise exception 'Owner or manager commercial authority required.' using errcode='42501';
  end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id and f.status='active';
  if v_farm.id is null then
    raise exception 'Active farm not found.' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'routeLaneId',r.route_lane_id,
      'routeLaneKey',r.route_lane_key,
      'laneLabel',r.lane_label,
      'custodianLabel',r.custodian_label,
      'locationLabel',r.location_label,
      'marketLabel',r.market_label,
      'snapshotId',r.snapshot_id,
      'effectiveDate',r.effective_date,
      'observedAt',r.observed_at,
      'sourcePerson',r.source_person,
      'lineId',r.line_id,
      'reportedProductLabel',r.reported_product_label,
      'productLabel',r.product_label,
      'quantity',r.quantity,
      'unit',r.unit,
      'containerLabel',r.container_label,
      'floristSellable',r.florist_sellable,
      'unitPrice',r.unit_price,
      'priceMin',r.price_min,
      'priceMax',r.price_max,
      'priceBasis',r.price_basis,
      'priceNote',r.price_note
    ) order by r.effective_date desc,r.observed_at desc,r.lane_label,r.product_label,r.line_id
  ),'[]'::jsonb)
  into v_items
  from atlas.v_flower_route_availability_current_v1 r
  where r.farm_id=p_farm_id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','flower_route_availability_notebook_self_api_v1',
    'farm',jsonb_build_object(
      'id',v_farm.id,
      'stableKey',v_farm.stable_key,
      'name',v_farm.name,
      'organizationId',v_farm.organization_id,
      'organizationUnitId',v_farm.organization_unit_id
    ),
    'audience',jsonb_build_object('membershipId',v_membership_id,'role',v_role),
    'asOf',now(),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'routeAvailabilityIsSourceStampedSnapshot',true,
      'routeAvailabilityIsSeparateFromReadyPosition',true,
      'snapshotDoesNotAuthorizeInventoryTransfer',true,
      'snapshotPriceIsNotSalePrice',true
    )
  );
end;
$function$;

revoke all on function atlas.flower_route_availability_notebook_self_api_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.flower_route_availability_notebook_self_api_v1(uuid)
  to service_role;

create or replace function public.flower_route_availability_notebook_self_api_v1(
  p_farm_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.flower_route_availability_notebook_self_api_v1(p_farm_id);
$function$;

revoke all on function public.flower_route_availability_notebook_self_api_v1(uuid)
  from public,anon;
grant execute on function public.flower_route_availability_notebook_self_api_v1(uuid)
  to authenticated,service_role;

create or replace function atlas.flower_commercial_commitments_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 89),
  p_through_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_role text;
  v_membership_id uuid;
  v_farm atlas.farms%rowtype;
  v_demands jsonb := '[]'::jsonb;
  v_sales jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_farm_id is null then
    raise exception 'Farm is required.' using errcode='22023';
  end if;
  if p_from_date is null or p_through_date is null or p_through_date < p_from_date then
    raise exception 'A valid commercial date window is required.' using errcode='22023';
  end if;
  if p_through_date - p_from_date > 366 then
    raise exception 'Commercial notebook windows may not exceed 367 days.' using errcode='22023';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if v_role not in ('owner','manager') then
    raise exception 'Owner or manager commercial authority required.' using errcode='42501';
  end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id and f.status='active';
  if v_farm.id is null then
    raise exception 'Active farm not found.' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'demandOrderId',d.demand_order_id,
      'demandLineId',d.demand_line_id,
      'buyerRelationshipId',d.buyer_relationship_id,
      'customerLabel',d.customer_label,
      'buyerBusinessName',b.business_name,
      'buyerLane',b.buyer_lane,
      'buyingStage',b.buying_stage,
      'buyingCadence',b.buying_cadence,
      'demandStrength',d.demand_strength,
      'demandState',d.demand_state,
      'salesChannel',d.sales_channel,
      'requestedForDate',d.requested_for_date,
      'fulfillmentMode',d.fulfillment_mode,
      'fulfillmentDueTime',d.fulfillment_due_time,
      'inventoryKind',d.inventory_kind,
      'cropProfileId',d.crop_profile_id,
      'productLabel',d.product_label,
      'quantity',d.quantity,
      'unit',d.unit,
      'targetUnitPrice',coalesce(c.target_unit_price,d.target_unit_price),
      'currency',d.currency,
      'reservedQuantity',coalesce(c.reserved_quantity,0),
      'soldQuantity',coalesce(c.sold_quantity,0),
      'fulfilledQuantity',coalesce(c.fulfilled_quantity,0),
      'shortQuantity',coalesce(c.short_quantity,d.quantity),
      'coverageState',c.coverage_state,
      'targetLineValue',coalesce(c.target_demand_value,d.target_line_value),
      'createdAt',d.created_at
    ) order by d.requested_for_date,d.customer_label,d.product_label,d.demand_line_id
  ),'[]'::jsonb)
  into v_demands
  from atlas.flower_demand_line_position_v1 d
  left join atlas.flower_demand_coverage_v1 c
    on c.demand_line_id=d.demand_line_id
  left join atlas.v_flower_buyer_position_v1 b
    on b.farm_id=d.farm_id
   and b.buyer_relationship_id=d.buyer_relationship_id
  where d.farm_id=p_farm_id
    and d.requested_for_date between p_from_date and p_through_date;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'saleOrderId',s.id,
      'buyerRelationshipId',s.buyer_relationship_id,
      'customerLabel',s.customer_label,
      'buyerBusinessName',b.business_name,
      'buyerLane',b.buyer_lane,
      'buyingStage',b.buying_stage,
      'buyingCadence',b.buying_cadence,
      'purchaseCount',b.purchase_count,
      'lifetimeSpend',b.lifetime_spend,
      'salesChannel',s.sales_channel,
      'eventKey',s.event_key,
      'saleDate',s.sale_date,
      'fulfillmentMode',s.fulfillment_mode,
      'fulfillmentDueDate',s.fulfillment_due_date,
      'fulfillmentDueTime',s.fulfillment_due_time,
      'fulfillmentMembershipId',s.fulfillment_membership_id,
      'subtotalAmount',s.subtotal_amount,
      'taxAmount',s.tax_amount,
      'tipAmount',s.tip_amount,
      'totalAmount',s.total_amount,
      'currency',s.currency,
      'sourceTaskId',s.source_task_id,
      'originDemandOrderId',origin.demand_order_id,
      'cancelled',coalesce(cancelled.is_cancelled,false),
      'fulfillmentEventCount',coalesce(fulfillment.event_count,0),
      'fulfilledAt',fulfillment.fulfilled_at,
      'effectiveFulfillmentDate',fulfillment.effective_fulfillment_date,
      'fulfillmentMethod',fulfillment.fulfillment_method,
      'lines',coalesce(lines.items,'[]'::jsonb),
      'note',s.note,
      'createdAt',s.created_at
    ) order by s.sale_date desc,s.created_at desc,s.id desc
  ),'[]'::jsonb)
  into v_sales
  from atlas.flower_sale_orders s
  left join atlas.v_flower_buyer_position_v1 b
    on b.farm_id=s.farm_id
   and b.buyer_relationship_id=s.buyer_relationship_id
  left join lateral (
    select l.demand_order_id
    from atlas.flower_demand_sale_order_links l
    where l.sale_order_id=s.id
    order by l.created_at desc,l.id desc
    limit 1
  ) origin on true
  left join lateral (
    select true as is_cancelled
    from atlas.flower_sale_order_cancellation_events c
    where c.sale_order_id=s.id
    order by c.created_at desc,c.id desc
    limit 1
  ) cancelled on true
  left join lateral (
    select
      count(*)::integer as event_count,
      max(fe.fulfilled_at) as fulfilled_at,
      max(fe.effective_fulfillment_date) as effective_fulfillment_date,
      (array_agg(fe.fulfillment_method order by fe.fulfilled_at desc,fe.id desc))[1] as fulfillment_method
    from atlas.flower_fulfillment_events fe
    where fe.sale_order_id=s.id
  ) fulfillment on true
  left join lateral (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'saleLineId',sl.id,
        'readyLotId',sl.ready_lot_id,
        'inventoryKind',sl.inventory_kind,
        'cropProfileId',ri.crop_profile_id,
        'productLabel',ri.product_label,
        'quantity',sl.quantity,
        'unit',sl.unit,
        'unitPrice',sl.unit_price,
        'lineTotal',sl.line_total
      ) order by ri.product_label nulls last,sl.id
    ),'[]'::jsonb) as items
    from atlas.flower_sale_order_lines sl
    left join atlas.flower_ready_inventory_identity_v1 ri on ri.id=sl.ready_lot_id
    where sl.sale_order_id=s.id
  ) lines on true
  where s.farm_id=p_farm_id
    and (
      s.sale_date between p_from_date and p_through_date
      or (coalesce(cancelled.is_cancelled,false)=false and coalesce(fulfillment.event_count,0)=0)
    );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','flower_commercial_commitments_notebook_self_api_v1',
    'farm',jsonb_build_object(
      'id',v_farm.id,
      'stableKey',v_farm.stable_key,
      'name',v_farm.name,
      'organizationId',v_farm.organization_id,
      'organizationUnitId',v_farm.organization_unit_id
    ),
    'audience',jsonb_build_object('membershipId',v_membership_id,'role',v_role),
    'fromDate',p_from_date,
    'throughDate',p_through_date,
    'demands',v_demands,
    'sales',v_sales,
    'truthBoundary',jsonb_build_object(
      'buyerRelationshipIsNotCRM',true,
      'requestedDemandIsNotCommittedDemand',true,
      'demandReservationIsNotSale',true,
      'saleIsNotFulfillment',true,
      'fulfillmentIsNotPayment',true,
      'actualSalePriceIsSeparateFromStandingValuation',true,
      'emptyDemandDoesNotEraseSaleHistory',true
    )
  );
end;
$function$;

revoke all on function atlas.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)
  from public,anon,authenticated,service_role;
grant execute on function atlas.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)
  to service_role;

create or replace function public.flower_commercial_commitments_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 89),
  p_through_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.flower_commercial_commitments_notebook_self_api_v1(p_farm_id,p_from_date,p_through_date);
$function$;

revoke all on function public.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)
  from public,anon;
grant execute on function public.flower_commercial_commitments_notebook_self_api_v1(uuid,date,date)
  to authenticated,service_role;

-- Extend Ready with route-custody evidence and admit one durable commercial commitments spread.
do $body$
declare
  r record;
  v_spread_id uuid;
  v_inventory_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','dominant-supporting-pair',
    'forms',jsonb_build_array(
      jsonb_build_object(
        'formFamily','ledger','role','anchor','order',1,
        'supportedRelationships',jsonb_build_array('state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep canonical Ready position compact; preserve reservations, claims, routes, fulfillment, and disposition as distinct quantities.'
      ),
      jsonb_build_object(
        'formFamily','log','role','supporting','order',2,
        'supportedRelationships',jsonb_build_array('evidence'),
        'emptyBehavior','show-quiet-geometry',
        'phoneRule','Show source-stamped route availability as dated custody evidence, never as a second Ready balance.'
      )
    ),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',1,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger','log'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','package4-flower-commercial-notebook-read-seams-v1','page','ready-inventory')
  );
  v_orders_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','dominant-supporting-pair',
    'forms',jsonb_build_array(
      jsonb_build_object(
        'formFamily','ledger','role','anchor','order',1,
        'supportedRelationships',jsonb_build_array('state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep requested/committed Demand and coverage state distinct from Sale.'
      ),
      jsonb_build_object(
        'formFamily','log','role','supporting','order',2,
        'supportedRelationships',jsonb_build_array('state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep Sale chronology and Fulfillment state together without treating handoff as payment.'
      )
    ),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',1,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger','log'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','package4-flower-commercial-notebook-read-seams-v1','page','commercial-commitments')
  );
begin
  for r in
    select distinct
      p.id as principal_id,
      f.id as farm_id,
      f.name as farm_name,
      f.organization_id,
      f.organization_unit_id
    from atlas.principals p
    join atlas.organization_memberships m
      on m.user_id=p.user_id
     and m.active=true
     and m.role='owner'
    join atlas.farms f
      on f.organization_id=m.organization_id
     and f.status='active'
    join atlas.farm_memberships fm
      on fm.user_id=p.user_id
     and fm.farm_id=f.id
     and fm.active=true
     and fm.role in ('owner','manager')
    where p.status='active'
  loop
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,
      'flower-ready:'||r.farm_id::text,
      case when r.organization_unit_id is not null then 'organization_unit' else 'organization' end,
      coalesce(r.organization_unit_id,r.organization_id)::text,
      'flower','ready_inventory',r.farm_id::text,
      'inventory-orientation','current','thread:flower-ready:'||r.farm_id::text,
      'Flowers ready · '||r.farm_name,'Flower Operations',null,'resolved','open',
      v_inventory_contract,
      jsonb_build_object('kind','product_migration','package','4','readSeams',jsonb_build_array('flower_ready_inventory_notebook_self_api_v1','flower_route_availability_notebook_self_api_v1')),
      jsonb_build_object('migration','package4-flower-commercial-notebook-read-seams-v1','farmId',r.farm_id)
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','ready_inventory_position_v1',r.farm_id::text,'state','active',
      jsonb_build_object('kind','governed_projection','readSeam','flower_ready_inventory_notebook_self_api_v1'),
      '{}'::jsonb
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','route_availability_current_v1',r.farm_id::text,'evidence','active',
      jsonb_build_object('kind','governed_projection','readSeam','flower_route_availability_notebook_self_api_v1'),
      jsonb_build_object('meaning','source-stamped distribution custody snapshot')
    );

    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,
      'flower-orders:'||r.farm_id::text,
      case when r.organization_unit_id is not null then 'organization_unit' else 'organization' end,
      coalesce(r.organization_unit_id,r.organization_id)::text,
      'flower','commercial_commitments',r.farm_id::text,
      'commercial-orientation','current-and-recent','thread:flower-orders:'||r.farm_id::text,
      'Flower orders · '||r.farm_name,'Flower Operations',null,'resolved','open',
      v_orders_contract,
      jsonb_build_object('kind','product_migration','package','4','readSeam','flower_commercial_commitments_notebook_self_api_v1'),
      jsonb_build_object('migration','package4-flower-commercial-notebook-read-seams-v1','farmId',r.farm_id)
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','commercial_commitments_v1',r.farm_id::text,'state','active',
      jsonb_build_object(
        'kind','governed_projection',
        'readSeam','flower_commercial_commitments_notebook_self_api_v1',
        'sources',jsonb_build_array('Flower Demand','Flower Sale','Flower Fulfillment','Buyer commercial position')
      ),
      '{}'::jsonb
    );
  end loop;
end;
$body$;

commit;
