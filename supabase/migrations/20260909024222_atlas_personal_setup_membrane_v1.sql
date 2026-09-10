create or replace function public.personal_setup_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with principal_ctx as (
    select p.id as principal_id, p.active_household_id
    from atlas.principals p
    where p.user_id = auth.uid()
      and p.status = 'active'
    limit 1
  ), household_ctx as (
    select h.id, h.name, h.timezone
    from atlas.households h
    join principal_ctx p on p.active_household_id = h.id
  )
  select jsonb_build_object(
    'ok', true,
    'contractVersion', 'personal_setup_self_api_v1',
    'household', (
      select jsonb_build_object('id', h.id, 'name', h.name, 'timezone', h.timezone)
      from household_ctx h
    ),
    'rhythms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'stableKey', r.stable_key,
        'area', r.area,
        'title', r.title,
        'cadenceRule', r.cadence_rule,
        'nextWindowStart', r.next_window_start,
        'nextWindowEnd', r.next_window_end,
        'expectedMinutes', r.expected_minutes,
        'active', r.active
      ) order by r.title)
      from atlas.household_rhythms r
      join household_ctx h on h.id = r.household_id
      where r.active
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id,
        'stableKey', e.stable_key,
        'title', e.title,
        'startsAt', e.starts_at,
        'endsAt', e.ends_at,
        'fixed', e.fixed,
        'eventKind', e.event_kind
      ) order by e.starts_at nulls last, e.title)
      from atlas.household_events e
      join household_ctx h on h.id = e.household_id
      where e.ends_at is null or e.ends_at >= now() - interval '1 day'
    ), '[]'::jsonb)
  );
$$;

create or replace function public.principal_upsert_household_rhythm_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.principal_upsert_household_rhythm_api_v1(p_input);
$$;

create or replace function public.principal_upsert_household_event_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.principal_upsert_household_event_api_v1(p_input);
$$;

revoke all on function public.personal_setup_self_api_v1() from public, anon;
revoke all on function public.principal_upsert_household_rhythm_api_v1(jsonb) from public, anon;
revoke all on function public.principal_upsert_household_event_api_v1(jsonb) from public, anon;

grant execute on function public.personal_setup_self_api_v1() to authenticated, service_role;
grant execute on function public.principal_upsert_household_rhythm_api_v1(jsonb) to authenticated, service_role;
grant execute on function public.principal_upsert_household_event_api_v1(jsonb) to authenticated, service_role;