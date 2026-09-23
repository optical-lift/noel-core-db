-- Elm operator calendar: resolve remaining named venues and dated events v1
-- Resolve canonical place identity first. Reuse Ellis O. Jackson Park as the
-- Webster County Fairgrounds identity rather than creating a duplicate.

do $$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_local_context constant uuid := 'f12da65e-9daf-46c8-b881-c4304d5d4b20';
  v_community_context uuid;
  v_city_annex uuid;
  v_ra_barr uuid;
  v_fairgrounds constant uuid := '8c1840db-0c42-4a8d-bd7d-b0e1490e3ece';
  v_city_org constant uuid := '6cf6d7f2-e452-4b65-a56d-db1375c8d447';
  v_occ uuid;
  v_binding uuid;
begin
  select id into v_community_context
  from atlas.organization_purpose_contexts
  where organization_id=v_org
    and stable_key='community_calendar'
    and context_state='active';

  if v_community_context is null then
    raise exception 'Elm community_calendar context is missing.' using errcode='P0002';
  end if;

  -- Official City of Marshfield calendar identifies the Oct. 8 Board meeting
  -- venue as the City Annex at 915 S Marshall, distinct from City Hall.
  insert into local_intel.entities(
    stable_key,entity_type,name,address_line1,city,state,postal_code,
    status,verification_state,local_context_id,metadata
  )
  values(
    'marshfield-city-annex',
    'place',
    'City of Marshfield Annex',
    '915 S Marshall',
    'Marshfield',
    'MO',
    '65706',
    'active',
    'official_verified',
    v_local_context,
    jsonb_build_object(
      'category','municipal meeting facility',
      'source_url','https://www.marshfieldmo.gov/Calendar.aspx?EID=1035',
      'verification_basis','official_city_calendar_2026_10_08',
      'parent_entity_id',v_city_org
    )
  )
  on conflict (local_context_id,stable_key) do update
  set name=excluded.name,
      address_line1=excluded.address_line1,
      city=excluded.city,
      state=excluded.state,
      postal_code=excluded.postal_code,
      status=excluded.status,
      verification_state=excluded.verification_state,
      local_context_id=excluded.local_context_id,
      metadata=coalesce(local_intel.entities.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_city_annex;

  -- Marshfield R-I Schools' sports-facilities page gives the stadium GPS
  -- location as 540 North Elm St.
  insert into local_intel.entities(
    stable_key,entity_type,name,address_line1,city,state,postal_code,
    status,verification_state,local_context_id,metadata
  )
  values(
    'ra-barr-stadium-marshfield',
    'place',
    'R.A. Barr Stadium',
    '540 N Elm St',
    'Marshfield',
    'MO',
    '65706',
    'active',
    'official_source_current',
    v_local_context,
    jsonb_build_object(
      'category','school athletic stadium',
      'source_url','https://mhs.mjays.us/athletics-actvities/sports-fields-activity-facilities',
      'verification_basis','official_school_gps_listing',
      'parent_entity_id','22ca7920-8aaa-49d3-96d8-e36268868603'::uuid
    )
  )
  on conflict (local_context_id,stable_key) do update
  set name=excluded.name,
      address_line1=excluded.address_line1,
      city=excluded.city,
      state=excluded.state,
      postal_code=excluded.postal_code,
      status=excluded.status,
      verification_state=excluded.verification_state,
      local_context_id=excluded.local_context_id,
      metadata=coalesce(local_intel.entities.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_ra_barr;

  -- Reuse the already-canonical Ellis O. Jackson Park identity for the
  -- Webster County Fairgrounds name used by event sources.
  if not exists(
    select 1
    from local_intel.entity_aliases a
    where a.entity_id=v_fairgrounds
      and lower(a.alias)=lower('Webster County Fairgrounds')
      and a.is_current
  ) then
    insert into local_intel.entity_aliases(
      entity_id,alias,alias_kind,verification_state,is_current,metadata
    )
    values(
      v_fairgrounds,
      'Webster County Fairgrounds',
      'official_name_variant',
      'official_verified',
      true,
      jsonb_build_object(
        'source_url','https://www.marshfieldmo.gov/308/Ellis-O-Jackson-Park-Webster-Co-Fairgrou',
        'basis','City of Marshfield identifies Ellis O. Jackson Park as Webster County Fairgrounds'
      )
    );
  end if;

  if not exists(
    select 1
    from local_intel.entity_aliases a
    where a.entity_id=v_ra_barr
      and lower(a.alias)=lower('R.A. Barr Football Stadium')
      and a.is_current
  ) then
    insert into local_intel.entity_aliases(
      entity_id,alias,alias_kind,verification_state,is_current,metadata
    )
    values(
      v_ra_barr,
      'R.A. Barr Football Stadium',
      'official_name_variant',
      'official_source_current',
      true,
      jsonb_build_object(
        'source_url','https://mhs.mjays.us/athletics-actvities/sports-fields-activity-facilities'
      )
    );
  end if;

  -- Officially verified Oct. 8 Board of Aldermen meeting.
  insert into local_intel.occurrences(
    stable_key,entity_id,title,occurrence_type,start_at,end_at,
    venue_name,address_line1,city,state,postal_code,status,public_url,
    last_verified_at,metadata
  )
  values(
    'marshfield-board-of-aldermen-2026-10-08',
    v_city_org,
    'Board of Aldermen Meeting',
    'government_meeting',
    '2026-10-08 23:30:00+00'::timestamptz,
    '2026-10-09 01:30:00+00'::timestamptz,
    'City of Marshfield Annex',
    '915 S Marshall',
    'Marshfield','MO','65706',
    'scheduled',
    'https://www.marshfieldmo.gov/Calendar.aspx?EID=1035',
    now(),
    jsonb_build_object(
      'sourceType','official',
      'sourceAuthority','City of Marshfield',
      'sourceUrl','https://www.marshfieldmo.gov/Calendar.aspx?EID=1035',
      'venueEntityId',v_city_annex,
      'operatorCalendarSource','operator_calendar_spec_2026_09_23'
    )
  )
  on conflict (stable_key) do update
  set entity_id=excluded.entity_id,
      title=excluded.title,
      occurrence_type=excluded.occurrence_type,
      start_at=excluded.start_at,
      end_at=excluded.end_at,
      venue_name=excluded.venue_name,
      address_line1=excluded.address_line1,
      city=excluded.city,
      state=excluded.state,
      postal_code=excluded.postal_code,
      status=excluded.status,
      public_url=excluded.public_url,
      last_verified_at=excluded.last_verified_at,
      metadata=coalesce(local_intel.occurrences.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_occ;

  v_binding := (
    atlas.bind_canonical_occurrence_service_v1(
      v_org,v_occ,
      jsonb_build_object('basis','operator_calendar_spec_2026_09_23','verification','official_city_calendar'),
      null
    )->>'bindingId'
  )::uuid;

  perform atlas.add_occurrence_to_purpose_context_service_v1(
    v_org,v_community_context,v_binding,array['calendar_entry'],
    jsonb_build_object('included',true,'routingSource','operator_calendar_spec_2026_09_23'),
    jsonb_build_object('basis','official_city_calendar','canonicalOccurrenceId',v_occ),
    null
  );

  -- Official Missouri Dexter Breeders Fall Classic main show on Oct. 10.
  insert into local_intel.occurrences(
    stable_key,entity_id,title,occurrence_type,start_at,end_at,
    venue_name,address_line1,city,state,postal_code,status,public_url,
    last_verified_at,metadata
  )
  values(
    'missouri-dexter-breeders-fall-classic-show-2026-10-10',
    v_fairgrounds,
    '2026 Missouri Dexter Breeders Fall Classic',
    'livestock_show',
    '2026-10-10 14:00:00+00'::timestamptz,
    null,
    'Webster County Fairgrounds',
    '614 N Marshall St',
    'Marshfield','MO','65706',
    'scheduled',
    'https://www.missouridexter.org/',
    now(),
    jsonb_build_object(
      'sourceType','official',
      'sourceAuthority','Missouri Dexter Breeders Association',
      'sourceUrl','https://www.missouridexter.org/',
      'eventWindow','October 9-10, 2026',
      'mainShowStart','Saturday 9:00 AM',
      'venueEntityId',v_fairgrounds,
      'operatorCalendarSource','operator_calendar_spec_2026_09_23'
    )
  )
  on conflict (stable_key) do update
  set entity_id=excluded.entity_id,
      title=excluded.title,
      occurrence_type=excluded.occurrence_type,
      start_at=excluded.start_at,
      end_at=excluded.end_at,
      venue_name=excluded.venue_name,
      address_line1=excluded.address_line1,
      city=excluded.city,
      state=excluded.state,
      postal_code=excluded.postal_code,
      status=excluded.status,
      public_url=excluded.public_url,
      last_verified_at=excluded.last_verified_at,
      metadata=coalesce(local_intel.occurrences.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_occ;

  v_binding := (
    atlas.bind_canonical_occurrence_service_v1(
      v_org,v_occ,
      jsonb_build_object('basis','operator_calendar_spec_2026_09_23','verification','official_event_site'),
      null
    )->>'bindingId'
  )::uuid;

  perform atlas.add_occurrence_to_purpose_context_service_v1(
    v_org,v_community_context,v_binding,array['calendar_entry'],
    jsonb_build_object('included',true,'routingSource','operator_calendar_spec_2026_09_23'),
    jsonb_build_object('basis','official_event_site','canonicalOccurrenceId',v_occ),
    null
  );

  -- Gobble Wobble: venue identity is now official; 2026 event coordinates
  -- remain operator-supplied and are intentionally marked needs_verification.
  insert into local_intel.occurrences(
    stable_key,entity_id,title,occurrence_type,start_at,end_at,
    venue_name,address_line1,city,state,postal_code,status,metadata
  )
  values(
    'marshfield-gobble-wobble-2026-11-28',
    v_ra_barr,
    'Gobble Wobble',
    'community_run',
    '2026-11-28 13:30:00+00'::timestamptz,
    null,
    'R.A. Barr Stadium',
    '540 N Elm St',
    'Marshfield','MO','65706',
    'needs_verification',
    jsonb_build_object(
      'sourceType','operator_supplied',
      'sourceAuthority','operator_calendar_spec_2026_09_23',
      'venueVerification','official_school_gps_listing',
      'venueSourceUrl','https://mhs.mjays.us/athletics-actvities/sports-fields-activity-facilities',
      'venueEntityId',v_ra_barr,
      'verificationNote','2026 event date/time supplied by operator; independent 2026 event source not yet located.'
    )
  )
  on conflict (stable_key) do update
  set entity_id=excluded.entity_id,
      title=excluded.title,
      occurrence_type=excluded.occurrence_type,
      start_at=excluded.start_at,
      end_at=excluded.end_at,
      venue_name=excluded.venue_name,
      address_line1=excluded.address_line1,
      city=excluded.city,
      state=excluded.state,
      postal_code=excluded.postal_code,
      status=excluded.status,
      metadata=coalesce(local_intel.occurrences.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_occ;

  v_binding := (
    atlas.bind_canonical_occurrence_service_v1(
      v_org,v_occ,
      jsonb_build_object('basis','operator_calendar_spec_2026_09_23','verification','operator_supplied_event_official_venue'),
      null
    )->>'bindingId'
  )::uuid;

  perform atlas.add_occurrence_to_purpose_context_service_v1(
    v_org,v_community_context,v_binding,array['calendar_entry'],
    jsonb_build_object(
      'included',true,
      'routingSource','operator_calendar_spec_2026_09_23',
      'verificationState','event_needs_verification'
    ),
    jsonb_build_object('basis','operator_supplied_event_official_venue','canonicalOccurrenceId',v_occ),
    null
  );
end
$$;
