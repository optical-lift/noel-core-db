-- Atlas Household Care Policy v1
-- Five-zone protected-attention rhythm resolved against functional household spaces; never task generation by itself.

begin;

create or replace function atlas.ensure_household_care_policy_v1(
  p_household_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_timezone text;
  v_local_week_start timestamp without time zone;
  v_zone_number integer;
  v_zone_stable_key text;
  v_zone_name text;
  v_zone_tags text[];
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_rhythm_count integer := 0;
begin
  select h.timezone
    into v_timezone
  from atlas.households h
  where h.id = p_household_id
    and h.status = 'active';

  if v_timezone is null then
    raise exception 'Active household not found.' using errcode = 'P0002';
  end if;

  v_local_week_start := date_trunc('week', p_as_of at time zone v_timezone);

  for v_zone_number in 1..5 loop
    v_zone_stable_key := case v_zone_number
      when 1 then 'zone_1_entry_arrival_dining'
      when 2 then 'zone_2_kitchen_pantry_food'
      when 3 then 'zone_3_main_bath_secondary'
      when 4 then 'zone_4_primary_bedroom'
      when 5 then 'zone_5_living_family'
    end;
    v_zone_name := case v_zone_number
      when 1 then 'Entry / porch / arrival / dining'
      when 2 then 'Kitchen / pantry / food storage'
      when 3 then 'Main bathroom + rotating secondary room'
      when 4 then 'Primary bedroom / closet / attached bath'
      when 5 then 'Living / family room'
    end;
    v_zone_tags := case v_zone_number
      when 1 then array['arrival','transition','dining']::text[]
      when 2 then array['food','kitchen','pantry']::text[]
      when 3 then array['hygiene','secondary_room']::text[]
      when 4 then array['primary_sleeping','dressing']::text[]
      when 5 then array['primary_gathering']::text[]
    end;

    insert into atlas.household_zones (
      household_id,
      zone_number,
      stable_key,
      name,
      active,
      metadata
    )
    values (
      p_household_id,
      v_zone_number,
      v_zone_stable_key,
      v_zone_name,
      true,
      jsonb_build_object(
        'policyKey', 'atlas_household_five_zone_attention',
        'policyVersion', 1,
        'functionalTags', to_jsonb(v_zone_tags),
        'releaseKind', 'protected_attention',
        'executionGenerated', false
      )
    )
    on conflict (household_id, zone_number)
    do update set
      metadata = coalesce(atlas.household_zones.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'policyKey', 'atlas_household_five_zone_attention',
          'policyVersion', 1,
          'functionalTags', to_jsonb(v_zone_tags),
          'releaseKind', 'protected_attention',
          'executionGenerated', false
        ),
      updated_at = now();

    v_window_start := (v_local_week_start + ((v_zone_number - 1) * interval '1 week')) at time zone v_timezone;
    v_window_end := (v_local_week_start + (v_zone_number * interval '1 week')) at time zone v_timezone;

    insert into atlas.household_rhythms (
      household_id,
      stable_key,
      area,
      title,
      cadence_rule,
      next_window_start,
      next_window_end,
      expected_minutes,
      protection_level,
      floor_class,
      interruptibility,
      principal_required,
      consequence,
      reason_for_floor,
      active,
      metadata,
      blocks_capacity
    )
    values (
      p_household_id,
      'atlas_household_zone_attention_' || v_zone_number::text,
      'household_care',
      'Household care — Zone ' || v_zone_number::text,
      'every_5_weeks',
      v_window_start,
      v_window_end,
      15,
      'protected',
      3,
      'interruptible',
      true,
      'Household care loses shape when protected attention is repeatedly displaced.',
      'Protected household rhythm: five-zone attention rotation.',
      true,
      jsonb_build_object(
        'policyKey', 'atlas_household_five_zone_attention',
        'policyVersion', 1,
        'zoneNumber', v_zone_number,
        'releaseKind', 'protected_attention',
        'executionGenerated', false
      ),
      true
    )
    on conflict (household_id, stable_key) do nothing;

    if found then
      v_rhythm_count := v_rhythm_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'householdId', p_household_id,
    'policyKey', 'atlas_household_five_zone_attention',
    'zonesEnsured', 5,
    'rhythmsCreated', v_rhythm_count
  );
end;
$$;

revoke all on function atlas.ensure_household_care_policy_v1(uuid,timestamptz) from public, anon, authenticated;
grant execute on function atlas.ensure_household_care_policy_v1(uuid,timestamptz) to service_role;

create or replace function atlas.household_care_policy_after_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  perform atlas.ensure_household_care_policy_v1(new.id, now());
  return new;
end;
$$;

revoke all on function atlas.household_care_policy_after_insert_v1() from public, anon, authenticated;

create trigger households_ensure_care_policy_v1
after insert on atlas.households
for each row execute function atlas.household_care_policy_after_insert_v1();

select atlas.ensure_household_care_policy_v1(h.id, now())
from atlas.households h
where h.status = 'active';

create or replace view atlas.household_space_zone_membership_v1
with (security_invoker = true)
as
select
  s.household_id,
  s.dwelling_id,
  s.id as space_id,
  z.id as zone_id,
  z.zone_number,
  z.stable_key as zone_stable_key,
  z.name as zone_name
from atlas.household_spaces s
join atlas.household_zones z
  on z.household_id = s.household_id
 and z.active
where s.active
  and s.care_relevant
  and s.functional_tags && case z.zone_number
    when 1 then array['arrival','transition','dining']::text[]
    when 2 then array['food','kitchen','pantry']::text[]
    when 3 then array['hygiene','secondary_room']::text[]
    when 4 then array['primary_sleeping','dressing']::text[]
    when 5 then array['primary_gathering']::text[]
    else '{}'::text[]
  end;

grant select on atlas.household_space_zone_membership_v1 to authenticated, service_role;

create or replace view atlas.household_care_space_state_v1
with (security_invoker = true)
as
select
  h.id as household_id,
  d.id as dwelling_id,
  d.name as dwelling_name,
  s.id as space_id,
  s.parent_space_id,
  s.stable_key as space_stable_key,
  s.name as space_name,
  s.space_type,
  s.functional_tags,
  s.floor_level,
  s.care_relevant,
  s.confidence,
  s.confirmed_at,
  m.zone_id,
  m.zone_number,
  m.zone_stable_key,
  m.zone_name,
  (cs.id is not null) as condition_known,
  coalesce(cs.condition_state, 'unknown') as condition_state,
  coalesce(cs.disposition, 'reassess') as disposition,
  cs.last_observed_at,
  cs.last_observation_id,
  cs.care_strategy,
  cs.trend,
  cs.next_reassess_at
from atlas.households h
join atlas.dwellings d
  on d.household_id = h.id
 and d.active
join atlas.household_spaces s
  on s.dwelling_id = d.id
 and s.household_id = h.id
 and s.active
left join atlas.household_space_zone_membership_v1 m
  on m.space_id = s.id
left join atlas.care_current_state cs
  on cs.subject_domain = 'household'
 and cs.subject_kind = 'household_space'
 and cs.subject_id = s.id::text
 and cs.scope_kind = 'household'
 and cs.scope_id = h.id
where h.status = 'active';

grant select on atlas.household_care_space_state_v1 to authenticated, service_role;

create or replace view atlas.household_care_current_attention_v1
with (security_invoker = true)
as
select
  h.id as household_id,
  r.id as rhythm_id,
  r.next_window_start as window_start,
  r.next_window_end as window_end,
  r.expected_minutes,
  z.id as zone_id,
  z.zone_number,
  z.stable_key as zone_stable_key,
  z.name as zone_name,
  s.id as space_id,
  s.name as space_name,
  s.space_type,
  s.floor_level,
  s.functional_tags,
  coalesce(cs.condition_state, 'unknown') as condition_state,
  coalesce(cs.disposition, 'reassess') as disposition,
  (cs.id is not null) as condition_known,
  cs.last_observed_at,
  'protected_attention'::text as release_kind,
  false as releases_executable_work
from atlas.household_rhythms r
join atlas.households h
  on h.id = r.household_id
 and h.status = 'active'
join atlas.household_zones z
  on z.household_id = h.id
 and z.zone_number = case
      when coalesce(r.metadata->>'zoneNumber','') ~ '^[1-5]$'
        then (r.metadata->>'zoneNumber')::integer
      else null
    end
 and z.active
left join atlas.household_spaces s
  on s.household_id = h.id
 and s.active
 and s.care_relevant
 and s.functional_tags && case z.zone_number
    when 1 then array['arrival','transition','dining']::text[]
    when 2 then array['food','kitchen','pantry']::text[]
    when 3 then array['hygiene','secondary_room']::text[]
    when 4 then array['primary_sleeping','dressing']::text[]
    when 5 then array['primary_gathering']::text[]
    else '{}'::text[]
  end
left join atlas.care_current_state cs
  on cs.subject_domain = 'household'
 and cs.subject_kind = 'household_space'
 and cs.subject_id = s.id::text
 and cs.scope_kind = 'household'
 and cs.scope_id = h.id
where r.active
  and r.metadata->>'policyKey' = 'atlas_household_five_zone_attention'
  and r.next_window_start is not null
  and r.next_window_end is not null
  and now() >= r.next_window_start
  and now() < r.next_window_end;

grant select on atlas.household_care_current_attention_v1 to authenticated, service_role;

commit;
