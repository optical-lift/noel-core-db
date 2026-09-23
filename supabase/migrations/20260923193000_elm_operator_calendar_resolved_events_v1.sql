-- Elm operator calendar reconciliation: resolved-venue nonpolitical events v1
-- Establish only events whose host/venue identity is already canonical or Elm-owned.
-- Do not manufacture unresolved City Hall / Fairgrounds / Stadium identities here.

do $$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_farm constant uuid := '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f';
  v_elm constant uuid := 'de584041-a636-424d-b8f5-2ff90ba3685e';
  v_community_context uuid;
  v_education_context uuid;
  v_public_program uuid;
  v_occ uuid;
  v_binding uuid;
  r record;
begin
  select id into v_community_context
  from atlas.organization_purpose_contexts
  where organization_id=v_org
    and stable_key='community_calendar'
    and context_state='active';

  select id into v_education_context
  from atlas.organization_purpose_contexts
  where organization_id=v_org
    and stable_key='educational_events'
    and context_state='active';

  if v_community_context is null or v_education_context is null then
    raise exception 'Required Elm calendar contexts are missing.' using errcode='P0002';
  end if;

  insert into atlas.community_programs(
    farm_id,stable_key,title,active,timezone_name,cadence,metadata
  ) values (
    v_farm,
    'public_events',
    'Elm Public Events',
    true,
    'America/Chicago',
    '{}'::jsonb,
    jsonb_build_object(
      'basis','operator_calendar_spec_2026_09_23',
      'purpose','Elm-owned public events outside a more specific recurring operational program'
    )
  )
  on conflict (farm_id,stable_key) do update
  set title=excluded.title,
      active=true,
      timezone_name=excluded.timezone_name,
      metadata=coalesce(atlas.community_programs.metadata,'{}'::jsonb) || excluded.metadata,
      updated_at=now()
  returning id into v_public_program;

  for r in
    select *
    from (values
      -- stable_key, entity_id, title, type, start_at, end_at, venue, city, state, route_education
      ('elm-first-friday-2026-10-02', v_elm,
       'Elm Farm First Friday', 'community_open_house',
       '2026-10-02 20:00:00+00'::timestamptz, '2026-10-03 01:00:00+00'::timestamptz,
       'Elm Farm','Marshfield','MO',false),

      ('3m-spook-tacular-pop-up-2026-10-03','795330d8-f30d-45be-9b3a-c00ba7d2bf50'::uuid,
       'Spook-tacular Pop-Up','pop_up_market',
       '2026-10-03 15:00:00+00'::timestamptz,'2026-10-03 20:00:00+00'::timestamptz,
       '3M Marketplace','Marshfield','MO',false),

      ('webster-title-night-family-jay-night-2026-10-06','50e922a1-6245-4c46-87a7-183db5cd3602'::uuid,
       'Webster Title Night + Family Jay Night','school_family_event',
       '2026-10-06 22:30:00+00'::timestamptz,'2026-10-07 00:30:00+00'::timestamptz,
       'Daniel Webster Elementary','Marshfield','MO',false),

      ('elm-soap-making-katie-langenberg-2026-10-17',v_elm,
       'Soap Making with Katie Langenberg','workshop',
       '2026-10-17 15:00:00+00'::timestamptz,null::timestamptz,
       'Elm Farm','Marshfield','MO',true),

      ('marshfield-fitness-trunk-or-treat-2026-10-17','32522839-7825-43ae-b9e3-b401b4b5a5b3'::uuid,
       'Trunk or Treat','community_halloween_event',
       '2026-10-17 21:00:00+00'::timestamptz,'2026-10-18 01:00:00+00'::timestamptz,
       'Marshfield Fitness & Tanning','Marshfield','MO',false),

      ('65706-not-so-spooky-mini-sampler-2026-10-24','76235251-108c-4c11-95e3-d2d8676c0868'::uuid,
       '65706 Not-So-Spooky Mini Sampler','community_event',
       '2026-10-24 14:00:00+00'::timestamptz,'2026-10-24 17:00:00+00'::timestamptz,
       'The Wild Honey Boutique','Marshfield','MO',false),

      ('southside-acres-fall-family-photos-2026-10-24','d46bd0b1-460b-49c3-b5e1-66792b5c48ca'::uuid,
       'Fall Family Photos','family_photos',
       '2026-10-24 20:00:00+00'::timestamptz,null::timestamptz,
       'Southside Acres','Marshfield','MO',false),

      ('southside-acres-fall-family-photos-2026-10-25','d46bd0b1-460b-49c3-b5e1-66792b5c48ca'::uuid,
       'Fall Family Photos','family_photos',
       '2026-10-26 00:00:00+00'::timestamptz,null::timestamptz,
       'Southside Acres','Marshfield','MO',false),

      ('elm-trunk-or-treat-bonfire-2026-10-30',v_elm,
       'Trunk or Treat + Bonfire','community_halloween_event',
       '2026-10-30 21:00:00+00'::timestamptz,'2026-10-31 01:00:00+00'::timestamptz,
       'Elm Farm','Marshfield','MO',false),

      ('ellis-jackson-paint-your-own-masterpiece-2026-11-05','8c1840db-0c42-4a8d-bd7d-b0e1490e3ece'::uuid,
       'Paint Your Own Masterpiece','workshop',
       '2026-11-06 00:15:00+00'::timestamptz,'2026-11-06 02:15:00+00'::timestamptz,
       'Ellis O. Jackson Park Safe Room','Marshfield','MO',true),

      ('elm-first-friday-2026-11-06',v_elm,
       'Elm Farm First Friday','community_open_house',
       '2026-11-06 21:00:00+00'::timestamptz,'2026-11-07 02:00:00+00'::timestamptz,
       'Elm Farm','Marshfield','MO',false),

      ('3m-winter-jam-2026-11-07','795330d8-f30d-45be-9b3a-c00ba7d2bf50'::uuid,
       'Winter Jam','pop_up_market',
       '2026-11-07 16:00:00+00'::timestamptz,'2026-11-07 21:00:00+00'::timestamptz,
       '3M Marketplace','Marshfield','MO',false)
    ) as x(stable_key,entity_id,title,occurrence_type,start_at,end_at,venue_name,city,state,route_education)
  loop
    insert into local_intel.occurrences(
      stable_key,entity_id,title,occurrence_type,start_at,end_at,
      venue_name,city,state,status,metadata
    ) values (
      r.stable_key,r.entity_id,r.title,r.occurrence_type,r.start_at,r.end_at,
      r.venue_name,r.city,r.state,'scheduled',
      jsonb_build_object(
        'sourceType','operator_supplied',
        'sourceAuthority','operator_calendar_spec_2026_09_23',
        'calendarSpecification','Elm Oct-Nov 2026'
      )
    )
    on conflict (stable_key) do update
    set entity_id=excluded.entity_id,
        title=excluded.title,
        occurrence_type=excluded.occurrence_type,
        start_at=excluded.start_at,
        end_at=excluded.end_at,
        venue_name=excluded.venue_name,
        city=excluded.city,
        state=excluded.state,
        status=excluded.status,
        metadata=coalesce(local_intel.occurrences.metadata,'{}'::jsonb) || excluded.metadata,
        updated_at=now()
    returning id into v_occ;

    v_binding := (
      atlas.bind_canonical_occurrence_service_v1(
        v_org,
        v_occ,
        jsonb_build_object(
          'basis','operator_calendar_spec_2026_09_23',
          'calendarContext','community_calendar'
        ),
        null
      )->>'bindingId'
    )::uuid;

    perform atlas.add_occurrence_to_purpose_context_service_v1(
      v_org,
      v_community_context,
      v_binding,
      array['calendar_entry'],
      jsonb_build_object(
        'included',true,
        'routingSource','operator_calendar_spec_2026_09_23'
      ),
      jsonb_build_object(
        'basis','operator_calendar_spec_2026_09_23',
        'canonicalOccurrenceId',v_occ
      ),
      null
    );

    if r.route_education then
      perform atlas.add_occurrence_to_purpose_context_service_v1(
        v_org,
        v_education_context,
        v_binding,
        array['educational_event'],
        jsonb_build_object(
          'included',true,
          'routingSource','operator_calendar_spec_2026_09_23',
          'selectionBasis','hands_on_learning_or_workshop'
        ),
        jsonb_build_object(
          'basis','operator_calendar_spec_2026_09_23',
          'canonicalOccurrenceId',v_occ
        ),
        null
      );
    end if;

    -- Elm-owned events with known end times get an operational community_event overlay.
    if r.entity_id=v_elm and r.end_at is not null then
      insert into atlas.community_events(
        farm_id,program_id,stable_key,title,event_kind,event_date,
        start_local_time,end_local_time,timezone_name,status,visibility_scope,
        metadata,occurrence_binding_id
      )
      values(
        v_farm,
        v_public_program,
        replace(r.stable_key,'-','_'),
        r.title,
        r.occurrence_type,
        (r.start_at at time zone 'America/Chicago')::date,
        (r.start_at at time zone 'America/Chicago')::time,
        (r.end_at at time zone 'America/Chicago')::time,
        'America/Chicago',
        'planned',
        'farm_shared',
        jsonb_build_object(
          'source','operator_calendar_spec_2026_09_23',
          'public_format','Elm public event'
        ),
        v_binding
      )
      on conflict (farm_id,stable_key) do update
      set title=excluded.title,
          event_kind=excluded.event_kind,
          event_date=excluded.event_date,
          start_local_time=excluded.start_local_time,
          end_local_time=excluded.end_local_time,
          timezone_name=excluded.timezone_name,
          status=excluded.status,
          visibility_scope=excluded.visibility_scope,
          metadata=coalesce(atlas.community_events.metadata,'{}'::jsonb) || excluded.metadata,
          occurrence_binding_id=excluded.occurrence_binding_id,
          updated_at=now();
    end if;
  end loop;
end
$$;

comment on table atlas.community_programs is
  'Organization operational programs. Stable keys are farm-scoped; public_events is a reusable functional key, while the display title may be Organization-branded.';
