-- Elm Local public calendar read model v1
-- Canonical sources remain atlas.community_events for Elm-owned events
-- and local_intel.occurrences for outside-community events.

update atlas.community_events
set end_local_time = time '11:00:00',
    metadata = metadata || jsonb_build_object('time_source','user_confirmed_public_time_20260829'),
    updated_at = now()
where event_kind='free_community_morning'
  and event_date >= date '2026-08-29'
  and start_local_time = time '09:30:00'
  and end_local_time <> time '11:00:00';

update atlas.community_events
set title = case stable_key
      when 'thursdays_at_elm_2026_09_10_evening' then 'Preserve the Season: Flower Drying Night'
      when 'thursdays_at_elm_2026_09_24_evening' then 'First Fall Table'
      when 'thursdays_at_elm_2026_10_08_evening' then 'Knot + Grow: Macramé Plant Hanger Workshop'
      when 'thursdays_at_elm_2026_10_22_evening' then 'Clay + Color: Handmade Clay Jewelry with Ashley Link'
      else title
    end,
    metadata = metadata || case stable_key
      when 'thursdays_at_elm_2026_09_10_evening' then jsonb_build_object(
        'public_theme','flower drying',
        'baked_good_pairing','Pie from Sweeter Than Honey',
        'program_detail','Guests strip flowers, make drying bundles, and take them home to dry.'
      )
      when 'thursdays_at_elm_2026_09_24_evening' then jsonb_build_object(
        'public_theme','first fall table',
        'baked_good_pairing','Apple crumb cake'
      )
      when 'thursdays_at_elm_2026_10_08_evening' then jsonb_build_object(
        'public_theme','macrame plant hanger',
        'baked_good_pairing','Cinnamon knot rolls',
        'instructor_status','not yet confirmed'
      )
      when 'thursdays_at_elm_2026_10_22_evening' then jsonb_build_object(
        'public_theme','clay jewelry',
        'baked_good_pairing','Brown-butter pumpkin cookies',
        'proposed_instructor','Ashley Link',
        'instructor_status','not yet confirmed'
      )
      else '{}'::jsonb
    end,
    updated_at = now()
where stable_key in (
  'thursdays_at_elm_2026_09_10_evening',
  'thursdays_at_elm_2026_09_24_evening',
  'thursdays_at_elm_2026_10_08_evening',
  'thursdays_at_elm_2026_10_22_evening'
);

update atlas.community_events
set metadata = metadata || jsonb_build_object(
      'season_price', jsonb_build_object(
        'amount',60,
        'currency','USD',
        'unit','family',
        'covers','six-week fall 2026 series'
      ),
      'public_program_dates', jsonb_build_array(
        '2026-09-08','2026-09-15','2026-09-22','2026-09-29','2026-10-06','2026-10-13'
      )
    ),
    updated_at = now()
where event_kind='family_field_club_session'
  and event_date between date '2026-09-08' and date '2026-10-13';

create table public.elm_local_calendar_events_v1 (
  public_id text primary key,
  source_system text not null check (source_system in ('atlas','local_intel')),
  is_elm_owned boolean not null,
  title text not null,
  event_kind text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  time_precision text not null check (time_precision in ('exact','date_only','conditional')),
  host_name text,
  venue_name text,
  city text,
  state text,
  cost jsonb not null default '{}'::jsonb,
  audience jsonb not null default '{}'::jsonb,
  publication_status text not null,
  public_url text,
  details jsonb not null default '{}'::jsonb,
  last_verified_at timestamptz,
  source_updated_at timestamptz not null,
  projected_at timestamptz not null default now()
);

comment on table public.elm_local_calendar_events_v1 is
  'Non-canonical public Elm Local calendar projection. Elm-owned truth comes from atlas.community_events; outside-community truth comes from local_intel.occurrences.';

create index elm_local_calendar_events_v1_starts_at_idx
  on public.elm_local_calendar_events_v1 (starts_at);
create index elm_local_calendar_events_v1_city_state_starts_idx
  on public.elm_local_calendar_events_v1 (city, state, starts_at);

alter table public.elm_local_calendar_events_v1 enable row level security;
revoke all on table public.elm_local_calendar_events_v1 from public, anon, authenticated;
grant select on table public.elm_local_calendar_events_v1 to anon, authenticated;

create policy elm_local_calendar_public_select_v1
  on public.elm_local_calendar_events_v1
  for select
  to anon, authenticated
  using (true);

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
      'sport', new.metadata ->> 'sport',
      'instructor_status', new.metadata ->> 'instructor_status',
      'proposed_instructor', new.metadata ->> 'proposed_instructor'
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

create or replace function local_intel.sync_elm_local_calendar_from_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  v_public_id text;
  v_host_name text;
  v_host_stable_key text;
  v_time_precision text;
begin
  if tg_op = 'DELETE' then
    v_public_id := 'local_' || pg_catalog.md5(old.id::text);
    delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;
    return old;
  end if;

  v_public_id := 'local_' || pg_catalog.md5(new.id::text);
  delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;

  select e.name, e.stable_key
    into v_host_name, v_host_stable_key
  from local_intel.entities e
  where e.id = new.entity_id;

  if new.start_at >= timestamptz '2026-08-29 00:00:00-05'
     and pg_catalog.lower(coalesce(new.city,'')) = 'marshfield'
     and pg_catalog.upper(coalesce(new.state,'')) = 'MO'
     and coalesce(v_host_stable_key,'') <> 'elm-farm'
     and new.status in ('scheduled','announced_save_the_date','conditional') then
    v_time_precision := case
      when new.status = 'conditional'
        or new.metadata ? 'conditional'
        or pg_catalog.lower(new.title) like '%if needed%'
        then 'conditional'
      when new.status = 'announced_save_the_date'
        or pg_catalog.lower(coalesce(new.metadata ->> 'all_day_placeholder','')) in ('true','1','yes')
        or pg_catalog.lower(coalesce(new.metadata ->> 'exact_times_unknown','')) in ('true','1','yes')
        or new.metadata ? 'deadline_local_date'
        or pg_catalog.lower(coalesce(new.metadata ->> 'time_status','')) like '%not exact time%'
        or pg_catalog.lower(coalesce(new.metadata ->> 'time_status','')) like '%date but not exact time%'
        or ((new.start_at at time zone 'America/Chicago')::time = time '00:00:00')
        then 'date_only'
      else 'exact'
    end;

    insert into public.elm_local_calendar_events_v1 (
      public_id, source_system, is_elm_owned, title, event_kind,
      starts_at, ends_at, time_precision, host_name, venue_name,
      city, state, cost, audience, publication_status, public_url,
      details, last_verified_at, source_updated_at, projected_at
    ) values (
      v_public_id,
      'local_intel',
      false,
      new.title,
      new.occurrence_type,
      new.start_at,
      new.end_at,
      v_time_precision,
      v_host_name,
      new.venue_name,
      new.city,
      new.state,
      coalesce(new.price, '{}'::jsonb),
      coalesce(new.audience, '{}'::jsonb),
      new.status,
      new.public_url,
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'deadline_local_date', new.metadata ->> 'deadline_local_date'
      )),
      new.last_verified_at,
      new.updated_at,
      pg_catalog.now()
    );
  end if;

  return new;
end;
$function$;

revoke all on function local_intel.sync_elm_local_calendar_from_atlas_v1() from public, anon, authenticated;
revoke all on function local_intel.sync_elm_local_calendar_from_occurrence_v1() from public, anon, authenticated;

drop trigger if exists sync_elm_local_calendar_from_atlas_v1 on atlas.community_events;
create trigger sync_elm_local_calendar_from_atlas_v1
after insert or update or delete on atlas.community_events
for each row execute function local_intel.sync_elm_local_calendar_from_atlas_v1();

drop trigger if exists sync_elm_local_calendar_from_occurrence_v1 on local_intel.occurrences;
create trigger sync_elm_local_calendar_from_occurrence_v1
after insert or update or delete on local_intel.occurrences
for each row execute function local_intel.sync_elm_local_calendar_from_occurrence_v1();

insert into public.elm_local_calendar_events_v1 (
  public_id, source_system, is_elm_owned, title, event_kind,
  starts_at, ends_at, time_precision, host_name, venue_name,
  city, state, cost, audience, publication_status, public_url,
  details, last_verified_at, source_updated_at, projected_at
)
select
  'atlas_' || pg_catalog.md5(ce.id::text),
  'atlas',
  true,
  ce.title,
  ce.event_kind,
  (ce.event_date + ce.start_local_time) at time zone ce.timezone_name,
  (ce.event_date + ce.end_local_time) at time zone ce.timezone_name,
  'exact',
  'Elm Farm',
  'Elm Farm',
  'Marshfield',
  'MO',
  case
    when ce.metadata ? 'season_price' then ce.metadata -> 'season_price'
    when ce.metadata ? 'ticket_types' then pg_catalog.jsonb_build_object('ticket_types', ce.metadata -> 'ticket_types')
    else '{}'::jsonb
  end,
  case
    when pg_catalog.lower(coalesce(ce.metadata ->> 'household_program','')) in ('true','1','yes')
      then pg_catalog.jsonb_build_object('audience','families')
    else '{}'::jsonb
  end,
  ce.status,
  null,
  pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'public_format', ce.metadata ->> 'public_format',
    'public_theme', ce.metadata ->> 'public_theme',
    'baked_good_pairing', ce.metadata ->> 'baked_good_pairing',
    'program_detail', ce.metadata ->> 'program_detail',
    'sport', ce.metadata ->> 'sport',
    'instructor_status', ce.metadata ->> 'instructor_status',
    'proposed_instructor', ce.metadata ->> 'proposed_instructor'
  )),
  null,
  ce.updated_at,
  pg_catalog.now()
from atlas.community_events ce
where ce.event_date >= date '2026-08-29'
  and ce.visibility_scope = 'farm_shared'
  and ce.status in ('planned','scheduled')
on conflict (public_id) do update set
  title = excluded.title,
  event_kind = excluded.event_kind,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  time_precision = excluded.time_precision,
  host_name = excluded.host_name,
  venue_name = excluded.venue_name,
  city = excluded.city,
  state = excluded.state,
  cost = excluded.cost,
  audience = excluded.audience,
  publication_status = excluded.publication_status,
  public_url = excluded.public_url,
  details = excluded.details,
  last_verified_at = excluded.last_verified_at,
  source_updated_at = excluded.source_updated_at,
  projected_at = excluded.projected_at;

insert into public.elm_local_calendar_events_v1 (
  public_id, source_system, is_elm_owned, title, event_kind,
  starts_at, ends_at, time_precision, host_name, venue_name,
  city, state, cost, audience, publication_status, public_url,
  details, last_verified_at, source_updated_at, projected_at
)
select
  'local_' || pg_catalog.md5(o.id::text),
  'local_intel',
  false,
  o.title,
  o.occurrence_type,
  o.start_at,
  o.end_at,
  case
    when o.status = 'conditional'
      or o.metadata ? 'conditional'
      or pg_catalog.lower(o.title) like '%if needed%'
      then 'conditional'
    when o.status = 'announced_save_the_date'
      or pg_catalog.lower(coalesce(o.metadata ->> 'all_day_placeholder','')) in ('true','1','yes')
      or pg_catalog.lower(coalesce(o.metadata ->> 'exact_times_unknown','')) in ('true','1','yes')
      or o.metadata ? 'deadline_local_date'
      or pg_catalog.lower(coalesce(o.metadata ->> 'time_status','')) like '%not exact time%'
      or pg_catalog.lower(coalesce(o.metadata ->> 'time_status','')) like '%date but not exact time%'
      or ((o.start_at at time zone 'America/Chicago')::time = time '00:00:00')
      then 'date_only'
    else 'exact'
  end,
  e.name,
  o.venue_name,
  o.city,
  o.state,
  coalesce(o.price, '{}'::jsonb),
  coalesce(o.audience, '{}'::jsonb),
  o.status,
  o.public_url,
  pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'deadline_local_date', o.metadata ->> 'deadline_local_date'
  )),
  o.last_verified_at,
  o.updated_at,
  pg_catalog.now()
from local_intel.occurrences o
join local_intel.entities e on e.id = o.entity_id
where o.start_at >= timestamptz '2026-08-29 00:00:00-05'
  and pg_catalog.lower(coalesce(o.city,'')) = 'marshfield'
  and pg_catalog.upper(coalesce(o.state,'')) = 'MO'
  and e.stable_key <> 'elm-farm'
  and o.status in ('scheduled','announced_save_the_date','conditional')
on conflict (public_id) do update set
  title = excluded.title,
  event_kind = excluded.event_kind,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  time_precision = excluded.time_precision,
  host_name = excluded.host_name,
  venue_name = excluded.venue_name,
  city = excluded.city,
  state = excluded.state,
  cost = excluded.cost,
  audience = excluded.audience,
  publication_status = excluded.publication_status,
  public_url = excluded.public_url,
  details = excluded.details,
  last_verified_at = excluded.last_verified_at,
  source_updated_at = excluded.source_updated_at,
  projected_at = excluded.projected_at;