alter table public.elm_local_calendar_events_v1
  add column if not exists source_stable_key text,
  add column if not exists categories text[] not null default '{}'::text[],
  add column if not exists featured_rank integer,
  add column if not exists featured_note text;

create table if not exists local_intel.elm_local_event_curations_v1 (
  source_system text not null check (source_system in ('atlas','local_intel')),
  source_stable_key text not null,
  featured boolean not null default false,
  feature_rank integer,
  feature_note text,
  active_from date,
  active_through date,
  updated_at timestamptz not null default now(),
  primary key (source_system, source_stable_key),
  check ((featured and feature_rank is not null and feature_rank > 0) or (not featured and feature_rank is null))
);

alter table local_intel.elm_local_event_curations_v1 enable row level security;
revoke all on table local_intel.elm_local_event_curations_v1 from public, anon, authenticated;

create or replace function local_intel.elm_local_categories_for_event_v1(
  p_event_kind text,
  p_audience jsonb,
  p_cost jsonb,
  p_details jsonb
)
returns text[]
language plpgsql
immutable
set search_path to pg_catalog
as $function$
declare
  v_kind text := pg_catalog.lower(coalesce(p_event_kind,''));
  v_audience jsonb := coalesce(p_audience,'{}'::jsonb);
  v_cost jsonb := coalesce(p_cost,'{}'::jsonb);
  v_categories text[] := '{}'::text[];
  v_amount numeric;
begin
  if v_kind in ('family_event','family_field_club_session')
     or pg_catalog.lower(coalesce(v_audience->>'family_friendly','')) in ('true','1','yes')
     or pg_catalog.lower(coalesce(v_audience->>'school_families','')) in ('true','1','yes')
     or pg_catalog.lower(coalesce(v_audience->>'audience','')) = 'families'
     or v_audience ? 'ages' then
    v_categories := pg_catalog.array_append(v_categories,'kids-family');
  end if;

  if v_kind = 'free_community_morning'
     or pg_catalog.lower(coalesce(v_cost->>'spectator_admission','')) = 'free' then
    v_categories := pg_catalog.array_append(v_categories,'free');
  elsif (v_cost ? 'amount') then
    begin
      v_amount := (v_cost->>'amount')::numeric;
      if v_amount = 0 then
        v_categories := pg_catalog.array_append(v_categories,'free');
      end if;
    exception when others then
      null;
    end;
  end if;

  if v_kind in ('festival','cultural_festival','arts_crafts_festival','food_festival','expo','swap_meet','market','farmers_market','fair') then
    v_categories := pg_catalog.array_append(v_categories,'markets-festivals');
  end if;

  if v_kind in ('food_festival','food_event','dining_event') then
    v_categories := pg_catalog.array_append(v_categories,'food');
  end if;

  if v_kind in ('concert','live_music','music_event','music_festival') then
    v_categories := pg_catalog.array_append(v_categories,'music');
  end if;

  if v_kind in ('audition','theatre_performance','theater_performance','performance','arts_crafts_festival','art_show') then
    v_categories := pg_catalog.array_append(v_categories,'arts-theater');
  end if;

  if v_kind in ('craft_workshop','workshop','class','ticketed_seasonal_evening') then
    v_categories := pg_catalog.array_append(v_categories,'classes-workshops');
  end if;

  if v_kind in ('public_movement_session','equestrian_event','outdoor_event','hike','nature_program') then
    v_categories := pg_catalog.array_append(v_categories,'outdoors');
  end if;

  if v_kind in ('school_sports','family_field_club_session','equestrian_event','sports_event','tournament','race') then
    v_categories := pg_catalog.array_append(v_categories,'sports');
  end if;

  if v_kind in ('community_event','community_program','club_meeting','benefit_auction','free_community_morning') then
    v_categories := pg_catalog.array_append(v_categories,'community');
  end if;

  return array(
    select distinct x
    from pg_catalog.unnest(v_categories) as x
    order by x
  );
end;
$function$;

revoke all on function local_intel.elm_local_categories_for_event_v1(text,jsonb,jsonb,jsonb) from public,anon,authenticated;

create or replace function local_intel.sync_elm_local_calendar_from_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
declare
  v_public_id text;
  v_host_name text;
  v_host_stable_key text;
  v_time_precision text;
  v_categories text[];
  v_feature_rank integer;
  v_feature_note text;
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
     and local_intel.occurrence_in_elm_local_coverage_v1(new.city,new.state)
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

    v_categories := local_intel.elm_local_categories_for_event_v1(new.occurrence_type,new.audience,new.price,new.metadata);

    select c.feature_rank,c.feature_note
      into v_feature_rank,v_feature_note
    from local_intel.elm_local_event_curations_v1 c
    where c.source_system='local_intel'
      and c.source_stable_key=new.stable_key
      and c.featured=true
      and (c.active_from is null or c.active_from <= (new.start_at at time zone 'America/Chicago')::date)
      and (c.active_through is null or c.active_through >= (new.start_at at time zone 'America/Chicago')::date);

    insert into public.elm_local_calendar_events_v1 (
      public_id, source_system, source_stable_key, is_elm_owned, title, event_kind,
      starts_at, ends_at, time_precision, host_name, venue_name,
      city, state, cost, audience, categories, featured_rank, featured_note,
      publication_status, public_url, details, last_verified_at, source_updated_at, projected_at
    ) values (
      v_public_id,'local_intel',new.stable_key,false,new.title,new.occurrence_type,
      new.start_at,new.end_at,v_time_precision,v_host_name,new.venue_name,
      new.city,new.state,coalesce(new.price,'{}'::jsonb),coalesce(new.audience,'{}'::jsonb),
      coalesce(v_categories,'{}'::text[]),v_feature_rank,v_feature_note,
      new.status,new.public_url,
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'deadline_local_date', new.metadata ->> 'deadline_local_date',
        'publication_note', new.metadata ->> 'publication_note',
        'local_time', new.metadata ->> 'local_time',
        'start_note', new.metadata ->> 'start_note'
      )),
      new.last_verified_at,new.updated_at,pg_catalog.now()
    );
  end if;

  return new;
end;
$function$;

create or replace function local_intel.sync_elm_local_calendar_from_atlas_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
declare
  v_public_id text;
  v_cost jsonb;
  v_audience jsonb;
  v_details jsonb;
  v_categories text[];
  v_feature_rank integer;
  v_feature_note text;
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

    v_categories := local_intel.elm_local_categories_for_event_v1(new.event_kind,v_audience,v_cost,v_details);

    select c.feature_rank,c.feature_note
      into v_feature_rank,v_feature_note
    from local_intel.elm_local_event_curations_v1 c
    where c.source_system='atlas'
      and c.source_stable_key=new.stable_key
      and c.featured=true
      and (c.active_from is null or c.active_from <= new.event_date)
      and (c.active_through is null or c.active_through >= new.event_date);

    insert into public.elm_local_calendar_events_v1 (
      public_id, source_system, source_stable_key, is_elm_owned, title, event_kind,
      starts_at, ends_at, time_precision, host_name, venue_name,
      city, state, cost, audience, categories, featured_rank, featured_note,
      publication_status, public_url, details, last_verified_at, source_updated_at, projected_at
    ) values (
      v_public_id,'atlas',new.stable_key,true,new.title,new.event_kind,
      (new.event_date + new.start_local_time) at time zone new.timezone_name,
      (new.event_date + new.end_local_time) at time zone new.timezone_name,
      'exact','Elm Farm','Elm Farm','Marshfield','MO',
      v_cost,v_audience,coalesce(v_categories,'{}'::text[]),v_feature_rank,v_feature_note,
      new.status,null,v_details,null,new.updated_at,pg_catalog.now()
    );
  end if;

  return new;
end;
$function$;

create or replace function local_intel.sync_elm_local_calendar_from_curation_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
begin
  update public.elm_local_calendar_events_v1 p
  set featured_rank = case when new.featured then new.feature_rank else null end,
      featured_note = case when new.featured then new.feature_note else null end,
      projected_at = pg_catalog.now()
  where p.source_system = new.source_system
    and p.source_stable_key = new.source_stable_key
    and (new.active_from is null or new.active_from <= (p.starts_at at time zone 'America/Chicago')::date)
    and (new.active_through is null or new.active_through >= (p.starts_at at time zone 'America/Chicago')::date);
  return new;
end;
$function$;

revoke all on function local_intel.sync_elm_local_calendar_from_occurrence_v1() from public,anon,authenticated;
revoke all on function local_intel.sync_elm_local_calendar_from_atlas_v1() from public,anon,authenticated;
revoke all on function local_intel.sync_elm_local_calendar_from_curation_v1() from public,anon,authenticated;

drop trigger if exists sync_elm_local_calendar_from_curation_v1 on local_intel.elm_local_event_curations_v1;
create trigger sync_elm_local_calendar_from_curation_v1
after insert or update on local_intel.elm_local_event_curations_v1
for each row execute function local_intel.sync_elm_local_calendar_from_curation_v1();

insert into local_intel.elm_local_event_curations_v1(source_system,source_stable_key,featured,feature_rank,feature_note)
values
  ('local_intel','ozarks-homesteading-expo-2026',true,10,'A major regional weekend event right in Marshfield.'),
  ('local_intel','springfield-japanese-fall-festival-2026',true,20,'A distinctive three-day cultural festival within the Elm Local region.'),
  ('local_intel','springfield-mo-food-truck-festival-2026-09-12',true,30,'A large one-day regional food festival.'),
  ('local_intel','springfield-cider-days-2026',true,40,'A long-running fall arts and street festival.'),
  ('local_intel','fair-grove-heritage-reunion-2026',true,50,'A major nearby heritage festival weekend.')
on conflict (source_system,source_stable_key) do update set
  featured=excluded.featured,
  feature_rank=excluded.feature_rank,
  feature_note=excluded.feature_note,
  updated_at=now();

update local_intel.occurrences set updated_at=updated_at where start_at >= timestamptz '2026-08-29 00:00:00-05';
update atlas.community_events set updated_at=updated_at where event_date >= date '2026-08-29';