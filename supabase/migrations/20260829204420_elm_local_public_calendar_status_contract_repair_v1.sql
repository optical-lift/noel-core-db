-- Elm Local public calendar status-contract repair v1
-- atlas.community_events permits planned, scheduled, cancelled, complete.
-- Publish only the two pre-event states: planned and scheduled.

create or replace function local_intel.sync_elm_local_calendar_from_atlas_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  v_public_id text;
  v_cost jsonb;
  v_audience jsonb;
  v_details jsonb;
begin
  if tg_op = 'DELETE' then
    v_public_id := 'atlas_' || pg_catalog.md5(old.id::text);
    delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;
    return old;
  end if;

  v_public_id := 'atlas_' || pg_catalog.md5(new.id::text);
  delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;

  if new.event_date >= date '2026-08-29'
     and new.visibility_scope = 'farm_shared'
     and new.status in ('planned','scheduled') then
    v_cost := case
      when new.metadata ? 'season_price' then new.metadata -> 'season_price'
      when new.metadata ? 'ticket_types' then pg_catalog.jsonb_build_object('ticket_types', new.metadata -> 'ticket_types')
      else '{}'::jsonb
    end;

    v_audience := case
      when pg_catalog.lower(coalesce(new.metadata ->> 'household_program','')) in ('true','1','yes')
        then pg_catalog.jsonb_build_object('audience','families')
      else '{}'::jsonb
    end;

    v_details := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'public_format', new.metadata ->> 'public_format',
      'public_theme', new.metadata ->> 'public_theme',
      'baked_good_pairing', new.metadata ->> 'baked_good_pairing',
      'program_detail', new.metadata ->> 'program_detail',
      'sport', new.metadata ->> 'sport'
    ));

    insert into public.elm_local_calendar_events_v1 (
      public_id, source_system, is_elm_owned, title, event_kind,
      starts_at, ends_at, time_precision, host_name, venue_name,
      city, state, cost, audience, publication_status, public_url,
      details, last_verified_at, source_updated_at, projected_at
    ) values (
      v_public_id,
      'atlas',
      true,
      new.title,
      new.event_kind,
      (new.event_date + new.start_local_time) at time zone new.timezone_name,
      (new.event_date + new.end_local_time) at time zone new.timezone_name,
      'exact',
      'Elm Farm',
      'Elm Farm',
      'Marshfield',
      'MO',
      v_cost,
      v_audience,
      new.status,
      null,
      v_details,
      null,
      new.updated_at,
      pg_catalog.now()
    );
  end if;

  return new;
end;
$function$;

revoke all on function local_intel.sync_elm_local_calendar_from_atlas_v1() from public, anon, authenticated;

update atlas.community_events
set updated_at = updated_at
where event_date >= date '2026-08-29'
  and visibility_scope = 'farm_shared'
  and status in ('planned','scheduled');