
do $$
declare
  v_owner uuid;
  v_farm uuid;
  v_event_center uuid;
  v_coffee uuid;
  v_kitchen uuid;
  v_dining uuid;
  v_water uuid;
begin
  select id into v_owner
  from reality.entities
  where stable_key='elm-farm' and entity_kind='business'
  limit 1;

  select id into v_farm
  from atlas.farms
  where stable_key='elm_farm'
  limit 1;

  select id into v_event_center
  from reality.resources
  where owner_entity_id=v_owner and stable_key='event_center'
  limit 1;

  select id into v_coffee
  from reality.resources
  where owner_entity_id=v_owner and stable_key='coffee_bar'
  limit 1;

  select id into v_kitchen
  from reality.resources
  where owner_entity_id=v_owner and stable_key='venue_kitchen'
  limit 1;

  select id into v_dining
  from reality.resources
  where owner_entity_id=v_owner and stable_key='venue_dining_room'
  limit 1;

  select id into v_water
  from reality.resources
  where owner_entity_id=v_owner and stable_key='venue_water_station'
  limit 1;

  if v_owner is null or v_event_center is null or v_coffee is null then
    raise exception 'Elm Event Center / Coffee Bar resource tree is incomplete.';
  end if;

  if exists (
    select 1
    from ledger.occurrence_resource_claims c
    where c.resource_id in (v_coffee,v_kitchen,v_dining,v_water)
  ) then
    raise exception 'Cannot simplify Elm Venue hierarchy while affected resources have claims.';
  end if;

  update reality.resources
  set parent_resource_id=v_event_center,
      resource_kind='station',
      reservable=true,
      capacity_mode='exclusive',
      capacity_quantity=null,
      capacity_unit=null,
      metadata=(
        metadata
        - 'openPlanGroup'
        - 'openPlanConnectedTo'
        - 'adjacentTo'
        - 'farmAtlasHistoricalLocationText'
      ) || jsonb_build_object(
        'canonicalBookingMeaning','Coffee Bar is the rentable resource; surrounding Kitchen/Dining physical areas are not separate booking resources.',
        'physicalPlacement','Farmhouse island / coffee-bar area',
        'hierarchyClarifiedBy','owner_instruction_20260925',
        'cutover','elm_venue_coffee_bar_resource_simplification_v3'
      ),
      updated_at=now()
  where id=v_coffee;

  -- Remove no-longer-meaningful open-plan booking semantics from the Living/Conference Room resource.
  update reality.resources
  set metadata=metadata - 'openPlanGroup' - 'openPlanConnectedTo',
      updated_at=now()
  where owner_entity_id=v_owner
    and stable_key='venue_conference_room';

  -- Water is not a rentable/resource concept for the Venue kernel.
  if v_water is not null then
    delete from reality.resources where id=v_water;
  end if;

  -- Dining Room was introduced only as an inferred booking resource; remove it.
  if v_dining is not null then
    delete from reality.resources where id=v_dining;
  end if;

  -- Coffee Bar has already been reparented, so Kitchen can leave the canonical resource tree.
  if v_kitchen is not null then
    delete from reality.resources where id=v_kitchen;
  end if;

  -- Preserve the old farm-atlas Kitchen record as historical provenance only.
  update atlas.growing_objects
  set guest_visible=false,
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'registry_hidden',true,
        'cutoverDisposition','excluded_by_owner',
        'excludedFromUniversalResourceKernel',true,
        'excludedAt',now(),
        'exclusionBasis','owner_instruction_20260925',
        'canonicalBookingSuccessor','coffee_bar'
      ),
      updated_at=now()
  where farm_id=v_farm
    and stable_key='venue_kitchen';
end $$;
