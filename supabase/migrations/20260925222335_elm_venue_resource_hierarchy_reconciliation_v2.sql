
do $$
declare
  v_owner constant uuid := 'de584041-a636-424d-b8f5-2ff90ba3685e'::uuid;
  v_site uuid;
  v_event_center uuid;
  v_kitchen uuid;
  v_dining uuid;
begin
  select id into v_site
  from reality.resources
  where owner_entity_id=v_owner and stable_key='elm_farm_site';

  select id into v_event_center
  from reality.resources
  where owner_entity_id=v_owner and stable_key='event_center';

  if v_site is null or v_event_center is null then
    raise exception 'Elm Farm site/event center resource tree is incomplete.';
  end if;

  -- Canonical physical identity: Conference Room = Living Room = Meeting Room.
  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_conference_room','Conference Room','room',
    'active',true,'exclusive',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','5556dc37-fa5a-4953-8276-ea212c90a905',
      'legacyAtlasStableKey','venue_conference_room',
      'legacyAtlasObjectMode','rental_room',
      'physicalName','Living Room',
      'aliases',jsonb_build_array('Living Room','Meeting Room'),
      'openPlanGroup','farmhouse_main_open_plan',
      'openPlanConnectedTo',jsonb_build_array('venue_kitchen','venue_dining_room'),
      'identityClarifiedBy','owner_instruction_20260925',
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Kitchen is part of the same physical open floorplan.
  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_kitchen','Kitchen','room',
    'active',true,'exclusive',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','3997baf0-fe98-4c7f-a37e-164b5086b6ab',
      'legacyAtlasStableKey','venue_kitchen',
      'legacyAtlasObjectMode','rental_room',
      'openPlanGroup','farmhouse_main_open_plan',
      'openPlanConnectedTo',jsonb_build_array('venue_dining_room','venue_conference_room'),
      'identityClarifiedBy','owner_instruction_20260925',
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Dining Room is physically distinct but was never one of the six July rentable-room records.
  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_dining_room','Dining Room','room',
    'active',true,'exclusive',null,null,'America/Chicago',
    jsonb_build_object(
      'source','owner_instruction_20260925',
      'physicalTruth','distinct space in open floorplan between Kitchen and Living Room / Conference Room',
      'openPlanGroup','farmhouse_main_open_plan',
      'openPlanConnectedTo',jsonb_build_array('venue_kitchen','venue_conference_room'),
      'legacyAtlasRecord','none; recovered from later farm-atlas Venue station location text',
      'farmAtlasEvidence','Coffee bar and Water station location = Dining room',
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  select id into v_kitchen
  from reality.resources
  where owner_entity_id=v_owner and stable_key='venue_kitchen';

  select id into v_dining
  from reality.resources
  where owner_entity_id=v_owner and stable_key='venue_dining_room';

  -- Coffee Bar is a hospitality station on the Kitchen island, not a room.
  perform reality.upsert_resource_service_v1(
    v_owner,v_kitchen,'coffee_bar','Coffee Bar','station',
    'active',false,'shared',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.places',
      'legacyAtlasPlaceId','8d5c243d-e024-4b97-9986-34c1018a2f51',
      'legacyAtlasPlaceType','work_station',
      'operationFamily','hospitality',
      'physicalLocation','Kitchen island',
      'adjacentTo','Dining Room',
      'farmAtlasHistoricalLocationText','Dining room',
      'locationClarifiedBy','owner_instruction_20260925',
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Water is another hospitality station historically located in the Dining Room.
  perform reality.upsert_resource_service_v1(
    v_owner,v_dining,'venue_water_station','Water','station',
    'active',false,'shared',null,null,'America/Chicago',
    jsonb_build_object(
      'source','farm_atlas_venue_station_model',
      'physicalLocation','Dining Room',
      'historicalComponents',jsonb_build_array('Water dispenser','Clear cups'),
      'farmAtlasSourceCommit','086bfc5acda1782ac4e206697bdd09fdcc39d25a',
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Attached exterior guest spaces of the Event Center.
  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_front_porch','Front Porch','zone',
    'active',true,'shared',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','2350fb17-47cc-4361-b2b9-677316765bda',
      'legacyAtlasObjectMode','venue_space',
      'objectSubtype','venue_exterior_space',
      'guestFacing',true,
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_back_porch','Back Porch','zone',
    'active',true,'shared',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','39608528-cb99-482e-9faa-e846d69a64b1',
      'legacyAtlasObjectMode','maintenance',
      'objectSubtype','venue_exterior_space',
      'surfaceMaterial','cedar siding and porch surfaces',
      'guestFacing',true,
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  perform reality.upsert_resource_service_v1(
    v_owner,v_event_center,'venue_concrete_entrance_porch','Concrete Entrance Porch','zone',
    'active',true,'shared',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','bb9676b8-4075-4499-a043-63b8fa4216a0',
      'legacyAtlasObjectMode','maintenance',
      'objectSubtype','venue_exterior_space',
      'surfaceMaterial','concrete',
      'guestFacing',true,
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Separate structure on the site.
  perform reality.upsert_resource_service_v1(
    v_owner,v_site,'detached_garage_trading_post','Detached Garage / The Trading Post','building',
    'active',true,'exclusive',null,null,'America/Chicago',
    jsonb_build_object(
      'legacyAtlasTable','atlas.growing_objects',
      'legacyAtlasObjectId','ed1be3b0-ef28-4a5e-a42d-35f5d0637e9c',
      'legacyAtlasObjectMode','venue_structure',
      'currentUse','detached_garage',
      'futureUse','trading_post',
      'guestFacing',true,
      'cutover','elm_venue_resource_hierarchy_reconciliation_v2'
    )
  );

  -- Owner explicitly removed these from the active spatial/resource model.
  update atlas.growing_objects
  set guest_visible=false,
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'registry_hidden',true,
        'cutoverDisposition','excluded_by_owner',
        'excludedFromUniversalResourceKernel',true,
        'excludedAt',now(),
        'exclusionBasis','owner_instruction_20260925'
      ),
      updated_at=now()
  where farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
    and stable_key in ('lounge_floor','venue_library_addition_exterior');

  -- Carry physical identity clarification into legacy room metadata without creating aliases as new objects.
  update atlas.growing_objects
  set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'physical_name','Living Room',
        'aliases',jsonb_build_array('Living Room','Meeting Room'),
        'identity_clarified_at',now(),
        'identity_clarified_source','owner_instruction_20260925'
      ),
      updated_at=now()
  where farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
    and stable_key='venue_conference_room';
end $$;
