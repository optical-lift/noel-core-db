-- Align Elm's fall 2026 canonical operational/public rhythms with the owner-confirmed public calendar direction.

-- Thursdays at Elm: the public Community Morning is 9:30–11:00 a.m.
update atlas.community_programs
set cadence = jsonb_set(cadence, '{free_mornings,end_local_time}', '"11:00"'::jsonb, true),
    metadata = metadata || jsonb_build_object('community_morning_time_source','owner_confirmed_public_time_20260829'),
    updated_at = now()
where stable_key = 'thursdays_at_elm';

-- September harvest rhythm was still carrying the older Wednesday/Friday cadence.
-- Retire those two regular templates; keep any separate Saturday clear/cleanup rhythm intact.
update atlas.rhythm_templates
set active = false,
    metadata = metadata || jsonb_build_object('retired_reason','superseded_by_monday_thursday_fall_harvest_20260829'),
    updated_at = now()
where stable_key in ('sep_wed_harvest','sep_fri_harvest')
  and active = true;

-- Install the fall Monday/Thursday harvest rhythm through October.
insert into atlas.rhythm_templates (
  farm_id, stable_key, season_key, season_label, start_date, end_date,
  weekday, sort_order, work_key, display_label, default_zone_keys,
  default_duration_minutes, weather_rule, source_note, active, metadata
)
select
  f.id,
  v.stable_key,
  'fall_2026_public_rhythm',
  'Fall 2026 Elm Public Rhythm',
  date '2026-09-01',
  date '2026-10-31',
  v.weekday,
  10,
  'harvest',
  'Harvest',
  '{}'::text[],
  90,
  'Prefer cool morning conditions; use current harvest-readiness and weather truth.',
  'Owner-confirmed Elm weekly rhythm 2026-08-29: harvest Monday and Thursday mornings.',
  true,
  jsonb_build_object(
    'calendar_source','elm_fall_public_rhythm_2026',
    'public_rhythm',true,
    'time_of_day','morning'
  )
from atlas.farms f
cross join (values
  ('fall_2026_mon_harvest', 1),
  ('fall_2026_thu_harvest', 4)
) as v(stable_key, weekday)
where f.stable_key = 'elm_farm'
on conflict (stable_key) do update set
  farm_id = excluded.farm_id,
  season_key = excluded.season_key,
  season_label = excluded.season_label,
  start_date = excluded.start_date,
  end_date = excluded.end_date,
  weekday = excluded.weekday,
  sort_order = excluded.sort_order,
  work_key = excluded.work_key,
  display_label = excluded.display_label,
  default_duration_minutes = excluded.default_duration_minutes,
  weather_rule = excluded.weather_rule,
  source_note = excluded.source_note,
  active = true,
  metadata = excluded.metadata,
  updated_at = now();

-- Arise is a public community program, not farm work. Add a reusable public movement session kind.
alter table atlas.community_events drop constraint community_events_event_kind_check;
alter table atlas.community_events add constraint community_events_event_kind_check check (
  event_kind = any (array[
    'free_community_morning'::text,
    'ticketed_seasonal_evening'::text,
    'special_fifth_thursday'::text,
    'church_group_visit'::text,
    'family_field_club_session'::text,
    'public_movement_session'::text
  ])
);

insert into atlas.community_programs (
  farm_id, stable_key, title, active, timezone_name, cadence, metadata
)
select
  f.id,
  'elm_arise_outdoor_movement',
  'Arise: Outdoor Movement at Elm',
  true,
  'America/Chicago',
  jsonb_build_object(
    'kind','weekly_multi_day',
    'weekdays',jsonb_build_array('Tuesday','Friday'),
    'start_local_time','06:00',
    'end_local_time','07:00',
    'launch_date','2026-09-01'
  ),
  jsonb_build_object(
    'source','owner_direction_20260829',
    'public_format','outdoor movement',
    'launch_mode','soft_launch',
    'pilates_barre_instructor_status','not yet confirmed'
  )
from atlas.farms f
where f.stable_key = 'elm_farm'
on conflict (farm_id, stable_key) do update set
  title = excluded.title,
  active = true,
  timezone_name = excluded.timezone_name,
  cadence = excluded.cadence,
  metadata = atlas.community_programs.metadata || excluded.metadata,
  updated_at = now();

insert into atlas.community_events (
  farm_id, program_id, stable_key, title, event_kind, event_date,
  start_local_time, end_local_time, timezone_name, status,
  visibility_scope, capacity, metadata
)
select
  p.farm_id,
  p.id,
  'elm_arise_' || to_char(d::date, 'YYYY_MM_DD'),
  'Arise: Outdoor Movement at Elm',
  'public_movement_session',
  d::date,
  time '06:00',
  time '07:00',
  'America/Chicago',
  'planned',
  'farm_shared',
  null,
  jsonb_build_object(
    'public_format','Outdoor movement',
    'program_detail','A simple outdoor morning movement session at Elm.',
    'launch_mode','soft_launch',
    'source','owner_direction_20260829'
  )
from atlas.community_programs p
cross join generate_series(date '2026-09-01', date '2026-10-31', interval '1 day') d
where p.stable_key = 'elm_arise_outdoor_movement'
  and extract(isodow from d) in (2,5)
on conflict (farm_id, stable_key) do update set
  title = excluded.title,
  event_kind = excluded.event_kind,
  event_date = excluded.event_date,
  start_local_time = excluded.start_local_time,
  end_local_time = excluded.end_local_time,
  timezone_name = excluded.timezone_name,
  status = excluded.status,
  visibility_scope = excluded.visibility_scope,
  metadata = atlas.community_events.metadata || excluded.metadata,
  updated_at = now();