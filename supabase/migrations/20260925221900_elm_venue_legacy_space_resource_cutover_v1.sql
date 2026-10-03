
do $$
declare
  v_owner constant uuid := 'de584041-a636-424d-b8f5-2ff90ba3685e'::uuid;
  v_site uuid;
  v_event_center uuid;
  v_rec record;
begin
  select id into v_site
  from reality.resources
  where owner_entity_id=v_owner and stable_key='elm_farm_site';

  if v_site is null then
    raise exception 'Elm Farm Site resource is missing.';
  end if;

  perform reality.upsert_resource_service_v1(
    v_owner,v_site,'event_center','Event Center','building',
    'active',true,'exclusive',null,null,'America/Chicago',
    jsonb_build_object(
      'firstAdopter','Elm Farm Venue Ledger',
      'resourceScope','indoor event center',
      'legacyVenueZoneId','19c7c573-fda5-4624-8d53-c607860959d5',
      'legacyVenueStableKey','venue',
      'farmAtlasSourceCommit','5f0d26a77327899de61ba32d2755bead42d88b7f',
      'farmAtlasSourcePath','supabase/migrations/20260722193000_add_venue_room_objects.sql',
      'cutover','elm_venue_legacy_space_resource_cutover_v1'
    )
  );

  select id into v_event_center
  from reality.resources
  where owner_entity_id=v_owner and stable_key='event_center';

  for v_rec in
    select *
    from (values
      ('venue_lounge','Lounge','room',true,'exclusive','ddc0fb4b-c13d-49aa-a9cc-d3a5bc49d0ff','rental_room',10),
      ('venue_library','Library','room',true,'exclusive','68a637df-3ae0-40a2-9132-2930ae270d9d','rental_room',20),
      ('venue_kitchen','Kitchen','room',true,'exclusive','3997baf0-fe98-4c7f-a37e-164b5086b6ab','rental_room',30),
      ('venue_conference_room','Conference Room','room',true,'exclusive','5556dc37-fa5a-4953-8276-ea212c90a905','rental_room',40),
      ('venue_bathroom','Bathroom','room',true,'exclusive','c1b7f45c-59f5-4bdd-94ef-4631ce8b5d33','rental_room',50),
      ('venue_studio','Studio','room',true,'exclusive','97c145bf-b852-49a3-8e90-33063d8085c5','rental_room',60),
      ('venue_entry','Entry','space',false,'shared','75b42183-e249-43b6-8e0f-0e85b4bb6365','venue_space',5)
    ) as x(stable_key,label,resource_kind,reservable,capacity_mode,legacy_id,legacy_mode,sort_order)
  loop
    perform reality.upsert_resource_service_v1(
      v_owner,
      v_event_center,
      v_rec.stable_key,
      v_rec.label,
      v_rec.resource_kind,
      'active',
      v_rec.reservable,
      v_rec.capacity_mode,
      null,null,
      'America/Chicago',
      jsonb_build_object(
        'legacyAtlasTable','atlas.growing_objects',
        'legacyAtlasObjectId',v_rec.legacy_id,
        'legacyAtlasStableKey',v_rec.stable_key,
        'legacyAtlasObjectMode',v_rec.legacy_mode,
        'legacyAtlasVenueZoneId','19c7c573-fda5-4624-8d53-c607860959d5',
        'legacySortOrder',v_rec.sort_order,
        'guestFacing',true,
        'farmAtlasSourceCommit',case
          when v_rec.stable_key='venue_entry'
            then '4a6d9f8c27d7f7161af3a6c4ddbd6a0ded1ccde3'
          else '5f0d26a77327899de61ba32d2755bead42d88b7f'
        end,
        'farmAtlasSourcePath',case
          when v_rec.stable_key='venue_entry'
            then 'app/owner/task-card-lab/VenueCardSpecimen.tsx'
          else 'supabase/migrations/20260722193000_add_venue_room_objects.sql'
        end,
        'originalRoomModel',case
          when v_rec.legacy_mode='rental_room' then 'canonical_rentable_room'
          else 'venue_space_not_original_rentable_room'
        end,
        'cutover','elm_venue_legacy_space_resource_cutover_v1'
      )
    );
  end loop;
end $$;
