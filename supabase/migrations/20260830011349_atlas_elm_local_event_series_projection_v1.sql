alter table public.elm_local_calendar_events_v1
  add column if not exists series_key text,
  add column if not exists series_title text,
  add column if not exists series_summary text;

create table if not exists local_intel.elm_local_event_series_rules_v1 (
  source_system text not null check (source_system in ('atlas','local_intel')),
  stable_key_regex text not null,
  series_key text not null,
  series_title text not null,
  series_summary text,
  priority integer not null default 100 check (priority > 0),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (source_system, stable_key_regex),
  check (pg_catalog.length(pg_catalog.btrim(series_key)) > 0),
  check (pg_catalog.length(pg_catalog.btrim(series_title)) > 0)
);

alter table local_intel.elm_local_event_series_rules_v1 enable row level security;
revoke all on table local_intel.elm_local_event_series_rules_v1 from public, anon, authenticated;

create or replace function local_intel.elm_local_series_for_event_v1(
  p_source_system text,
  p_source_stable_key text
)
returns table(series_key text, series_title text, series_summary text)
language sql
stable
set search_path to pg_catalog
as $function$
  select r.series_key, r.series_title, r.series_summary
  from local_intel.elm_local_event_series_rules_v1 r
  where r.active
    and r.source_system = p_source_system
    and coalesce(p_source_stable_key,'') ~ r.stable_key_regex
  order by r.priority asc, pg_catalog.length(r.stable_key_regex) desc
  limit 1;
$function$;

revoke all on function local_intel.elm_local_series_for_event_v1(text,text) from public, anon, authenticated;

create or replace function local_intel.apply_elm_local_series_projection_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
begin
  new.series_key := null;
  new.series_title := null;
  new.series_summary := null;

  select s.series_key, s.series_title, s.series_summary
    into new.series_key, new.series_title, new.series_summary
  from local_intel.elm_local_series_for_event_v1(new.source_system,new.source_stable_key) s;

  return new;
end;
$function$;

revoke all on function local_intel.apply_elm_local_series_projection_v1() from public, anon, authenticated;

drop trigger if exists apply_elm_local_series_projection_v1 on public.elm_local_calendar_events_v1;
create trigger apply_elm_local_series_projection_v1
before insert or update of source_system, source_stable_key on public.elm_local_calendar_events_v1
for each row execute function local_intel.apply_elm_local_series_projection_v1();

create or replace function local_intel.sync_elm_local_series_rule_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
begin
  if tg_op in ('UPDATE','DELETE') then
    update public.elm_local_calendar_events_v1 p
    set source_stable_key = p.source_stable_key
    where p.source_system = old.source_system
      and coalesce(p.source_stable_key,'') ~ old.stable_key_regex;
  end if;

  if tg_op in ('INSERT','UPDATE') then
    update public.elm_local_calendar_events_v1 p
    set source_stable_key = p.source_stable_key
    where p.source_system = new.source_system
      and coalesce(p.source_stable_key,'') ~ new.stable_key_regex;
  end if;

  return coalesce(new,old);
end;
$function$;

revoke all on function local_intel.sync_elm_local_series_rule_v1() from public, anon, authenticated;

drop trigger if exists sync_elm_local_series_rule_v1 on local_intel.elm_local_event_series_rules_v1;
create trigger sync_elm_local_series_rule_v1
after insert or update or delete on local_intel.elm_local_event_series_rules_v1
for each row execute function local_intel.sync_elm_local_series_rule_v1();

insert into local_intel.elm_local_event_series_rules_v1(
  source_system, stable_key_regex, series_key, series_title, series_summary, priority
)
values
  ('atlas','^elm_arise_','elm-arise','Arise: Outdoor Movement at Elm','Recurring outdoor morning movement at Elm.',10),
  ('atlas','^elm_family_ultimate_','elm-family-ultimate','Elm Family Ultimate','A recurring family Ultimate Frisbee series at Elm.',10),
  ('atlas','^thursdays_at_elm_.*_morning$','elm-community-flower-mornings','Come Flower Farm With Us','Recurring free community flower-farming mornings at Elm.',20),
  ('local_intel','^library-storytime-','marshfield-preschool-storytime','Preschool Storytime @ Marshfield','Recurring preschool storytime at the Webster County Library in Marshfield.',20),
  ('local_intel','^mct-carrie-performance-','carrie-the-musical-marshfield-2026','Carrie the Musical','The 2026 Marshfield Community Theatre performance run of Carrie the Musical.',20),
  ('local_intel','^msc-monthly-meeting-','marshfield-saddle-club-monthly-meeting','Marshfield Saddle Club Monthly Meeting','Recurring monthly meetings of the Marshfield Saddle Club.',30),
  ('local_intel','^mhs-football-.*-home-2026-','marshfield-blue-jays-football-2026','Marshfield Blue Jays Varsity Football','Marshfield High School varsity football home games for the 2026 season.',30),
  ('local_intel','^417-christmas-market-2026-12-0[45]$','417-christmas-market-2026','417 Christmas Market 2026','The two-day 417 Christmas Market at the Springfield Expo Center.',30)
on conflict (source_system,stable_key_regex) do update set
  series_key=excluded.series_key,
  series_title=excluded.series_title,
  series_summary=excluded.series_summary,
  priority=excluded.priority,
  active=true,
  updated_at=now();

update public.elm_local_calendar_events_v1 p
set source_stable_key = p.source_stable_key;