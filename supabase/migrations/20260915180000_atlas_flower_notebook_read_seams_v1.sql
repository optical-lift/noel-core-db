begin;

-- Package 4 / Flower Operations notebook read seams v1.
-- Durable notebook spreads remain presentation/retrieval objects. Harvest and Ready
-- truth stays in the existing flower source domains; these APIs add only governed,
-- member-safe read membranes for the composed Atlas runtime.

create or replace function atlas.flower_harvest_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 29),
  p_through_date date default current_date,
  p_limit integer default 250
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
  v_limit integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_farm_id is null then
    raise exception 'Farm is required.' using errcode='22023';
  end if;
  if p_from_date is null or p_through_date is null or p_through_date < p_from_date then
    raise exception 'A valid Harvest date window is required.' using errcode='22023';
  end if;
  if p_through_date - p_from_date > 366 then
    raise exception 'Harvest notebook windows may not exceed 367 days.' using errcode='22023';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if v_role is null or v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id and f.status='active';
  if v_farm.id is null then
    raise exception 'Active farm not found.' using errcode='P0002';
  end if;

  v_limit := greatest(1,least(coalesce(p_limit,250),500));

  with harvest_rows as (
    select
      o.id,
      o.batch_id,
      o.crop_cycle_id,
      o.task_id,
      o.observed_date,
      o.bucket_band,
      o.bucket_equivalent_floor,
      o.bucket_halves,
      o.harvest_grade,
      o.more_available,
      o.more_availability,
      o.note,
      o.created_at,
      c.crop_label,
      c.variety,
      coalesce(lineage.preparation_batch_count,0) as preparation_batch_count,
      coalesce(lineage.ready_lot_count,0) as ready_lot_count,
      coalesce(lineage.ready_products,'[]'::jsonb) as ready_products
    from atlas.flower_harvest_bucket_observations o
    left join atlas.crop_cycles c on c.id=o.crop_cycle_id
    left join lateral (
      select
        count(distinct i.preparation_batch_id)::integer as preparation_batch_count,
        count(distinct r.id)::integer as ready_lot_count,
        coalesce(
          jsonb_agg(distinct r.product_label) filter (where r.product_label is not null),
          '[]'::jsonb
        ) as ready_products
      from atlas.flower_preparation_inputs i
      left join atlas.flower_ready_inventory_identity_v1 r
        on r.preparation_batch_id=i.preparation_batch_id
       and r.farm_id=o.farm_id
      where i.harvest_observation_id=o.id
    ) lineage on true
    where o.farm_id=p_farm_id
      and o.observed_date between p_from_date and p_through_date
    order by o.observed_date desc,o.created_at desc,o.id desc
    limit v_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'harvestObservationId',h.id,
      'harvestBatchId',h.batch_id,
      'cropCycleId',h.crop_cycle_id,
      'taskId',h.task_id,
      'cropLabel',h.crop_label,
      'variety',h.variety,
      'observedDate',h.observed_date,
      'bucketBand',h.bucket_band,
      'bucketEquivalentFloor',h.bucket_equivalent_floor,
      'bucketHalves',h.bucket_halves,
      'harvestGrade',h.harvest_grade,
      'moreAvailable',h.more_available,
      'moreAvailability',coalesce(
        nullif(h.more_availability,''),
        case when h.more_available is true then 'yes' when h.more_available is false then 'no' else null end
      ),
      'note',h.note,
      'preparationBatchCount',h.preparation_batch_count,
      'readyLotCount',h.ready_lot_count,
      'readyProducts',h.ready_products,
      'createdAt',h.created_at
    ) order by h.observed_date desc,h.created_at desc,h.id desc
  ),'[]'::jsonb)
  into v_items
  from harvest_rows h;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','flower_harvest_notebook_self_api_v1',
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
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'harvestEvidenceIsSourceOwned',true,
      'companyWorkRequirementIsSeparate',true,
      'cutFlowerIsNotReadyUntilPreparation',true,
      'readyContinuationIsLineageOnly',true,
      'saleAndMoneyAreNotHarvestTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)
  from public,anon,authenticated,service_role;
grant execute on function atlas.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)
  to service_role;

create or replace function public.flower_harvest_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 29),
  p_through_date date default current_date,
  p_limit integer default 250
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.flower_harvest_notebook_self_api_v1(p_farm_id,p_from_date,p_through_date,p_limit);
$function$;

revoke all on function public.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)
  from public,anon;
grant execute on function public.flower_harvest_notebook_self_api_v1(uuid,date,date,integer)
  to authenticated,service_role;

create or replace function atlas.flower_ready_inventory_notebook_self_api_v1(
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
    raise exception 'Owner or manager inventory authority required.' using errcode='42501';
  end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id and f.status='active';
  if v_farm.id is null then
    raise exception 'Active farm not found.' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'readyLotId',r.id,
      'preparationBatchId',r.preparation_batch_id,
      'inventoryKind',r.inventory_kind,
      'cropProfileId',r.crop_profile_id,
      'productLabel',r.product_label,
      'unit',r.unit,
      'quantityExactness',r.quantity_exactness,
      'readyDate',r.ready_date,
      'birthQuantity',r.birth_quantity,
      'availableQuantity',r.available_quantity,
      'demandReservedQuantity',r.demand_reserved_quantity,
      'activeClaimedQuantity',r.active_claimed_quantity,
      'onProspectRouteQuantity',r.on_prospect_route_quantity,
      'fulfilledQuantity',r.fulfilled_quantity,
      'disposedQuantity',r.disposed_quantity,
      'retailUnitValue',r.retail_unit_value,
      'retailCurrency',r.retail_currency,
      'retailValueSource',r.retail_value_source,
      'valuationState',r.valuation_state
    ) order by r.product_label nulls last,r.ready_date desc,r.id
  ),'[]'::jsonb)
  into v_items
  from atlas.flower_ready_inventory_position_v1 r
  where r.farm_id=p_farm_id
    and (
      coalesce(r.available_quantity,0)<>0
      or coalesce(r.demand_reserved_quantity,0)<>0
      or coalesce(r.active_claimed_quantity,0)<>0
      or coalesce(r.on_prospect_route_quantity,0)<>0
    );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','flower_ready_inventory_notebook_self_api_v1',
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
      'readyPositionIsSourceOwned',true,
      'readyBirthIsSeparateFromHarvest',true,
      'routeAvailabilityIsSeparateEvidence',true,
      'demandReservationIsNotSale',true,
      'saleIsNotFulfillment',true,
      'valuationIsNotTransactionPrice',true
    )
  );
end;
$function$;

revoke all on function atlas.flower_ready_inventory_notebook_self_api_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.flower_ready_inventory_notebook_self_api_v1(uuid)
  to service_role;

create or replace function public.flower_ready_inventory_notebook_self_api_v1(
  p_farm_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.flower_ready_inventory_notebook_self_api_v1(p_farm_id);
$function$;

revoke all on function public.flower_ready_inventory_notebook_self_api_v1(uuid)
  from public,anon;
grant execute on function public.flower_ready_inventory_notebook_self_api_v1(uuid)
  to authenticated,service_role;

-- Product-owned durable spreads are admitted through the same notebook registry as
-- the existing Household/Organization spreads. Admission must match the same farm
-- authority required by the source read membranes; an Organization role alone is
-- not treated as substitute farm authority.
do $body$
declare
  r record;
  v_spread_id uuid;
  v_harvest_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','dominant-supporting-pair',
    'forms',jsonb_build_array(
      jsonb_build_object(
        'formFamily','log','role','anchor','order',1,
        'supportedRelationships',jsonb_build_array('evidence','sequence'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep recent physical Harvest evidence chronological and preserve source dates.'
      ),
      jsonb_build_object(
        'formFamily','ledger','role','supporting','order',2,
        'supportedRelationships',jsonb_build_array('state'),
        'emptyBehavior','show-quiet-geometry',
        'phoneRule','Keep current Ready consequence separate from Harvest evidence.'
      )
    ),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',1,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('log','ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','package4-flower-notebook-read-seams-v1','page','harvest')
  );
  v_inventory_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(
      jsonb_build_object(
        'formFamily','ledger','role','anchor','order',1,
        'supportedRelationships',jsonb_build_array('state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep canonical Ready position compact; do not collapse reservations, claims, routes, and fulfillment into one balance.'
      )
    ),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','package4-flower-notebook-read-seams-v1','page','ready-inventory')
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
      'flower-harvest:'||r.farm_id::text,
      case when r.organization_unit_id is not null then 'organization_unit' else 'organization' end,
      coalesce(r.organization_unit_id,r.organization_id)::text,
      'flower','harvest',r.farm_id::text,
      'harvest-orientation','rolling-30-days','thread:flower-harvest:'||r.farm_id::text,
      'Harvest · '||r.farm_name,'Flower Operations',null,'resolved','open',
      v_harvest_contract,
      jsonb_build_object('kind','product_migration','package','4','readSeam','flower_harvest_notebook_self_api_v1'),
      jsonb_build_object('migration','package4-flower-notebook-read-seams-v1','farmId',r.farm_id)
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','harvest_recent_v1',r.farm_id::text,'evidence','active',
      jsonb_build_object('kind','governed_projection','readSeam','flower_harvest_notebook_self_api_v1','windowPolicy','rolling_30_days'),
      '{}'::jsonb
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','ready_inventory_position_v1',r.farm_id::text,'state','active',
      jsonb_build_object('kind','governed_projection','readSeam','flower_ready_inventory_notebook_self_api_v1'),
      jsonb_build_object('role','harvest-consequence')
    );

    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,
      'flower-ready:'||r.farm_id::text,
      case when r.organization_unit_id is not null then 'organization_unit' else 'organization' end,
      coalesce(r.organization_unit_id,r.organization_id)::text,
      'flower','ready_inventory',r.farm_id::text,
      'inventory-orientation','current','thread:flower-ready:'||r.farm_id::text,
      'Flowers ready · '||r.farm_name,'Flower Operations',null,'resolved','open',
      v_inventory_contract,
      jsonb_build_object('kind','product_migration','package','4','readSeam','flower_ready_inventory_notebook_self_api_v1'),
      jsonb_build_object('migration','package4-flower-notebook-read-seams-v1','farmId',r.farm_id)
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'flower','ready_inventory_position_v1',r.farm_id::text,'state','active',
      jsonb_build_object('kind','governed_projection','readSeam','flower_ready_inventory_notebook_self_api_v1'),
      '{}'::jsonb
    );
  end loop;
end;
$body$;

commit;
