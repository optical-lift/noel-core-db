create or replace function atlas.household_rhythm_shadow_state_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_observed_at timestamptz := statement_timestamp();
  v_active_count integer := 0;
  v_windowed_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','household_rhythm_shadow_state_self_api_v1',
      'ok',false,
      'state','principal_required',
      'observedAt',v_observed_at,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'currentStateOnly',true,
        'historicalReadClaimed',false,
        'clockArbitrationExposed',false,
        'unrelatedCandidatesExposed',false,
        'authorityMutationAllowed',false
      )
    );
  end if;

  select h.id, h.timezone
  into v_household_id, v_timezone
  from atlas.principals p
  join atlas.households h
    on h.id = p.active_household_id
   and h.principal_id = p.id
   and h.status = 'active'
  where p.id = v_principal_id
    and p.status = 'active'
  limit 1;

  if v_household_id is null then
    return jsonb_build_object(
      'contractVersion','household_rhythm_shadow_state_self_api_v1',
      'ok',false,
      'state','active_household_required',
      'principalId',v_principal_id,
      'observedAt',v_observed_at,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'currentStateOnly',true,
        'historicalReadClaimed',false,
        'clockArbitrationExposed',false,
        'unrelatedCandidatesExposed',false,
        'authorityMutationAllowed',false
      )
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where r.next_window_start is not null
        and r.next_window_end is not null
        and r.next_window_end > r.next_window_start
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rhythmId',r.id,
          'stableKey',r.stable_key,
          'windowStart',r.next_window_start,
          'windowEnd',r.next_window_end,
          'updatedAt',r.updated_at
        )
        order by r.stable_key, r.id
      ),
      '[]'::jsonb
    )
  into v_active_count, v_windowed_count, v_rows
  from atlas.household_rhythms r
  where r.household_id = v_household_id
    and r.active
    and r.principal_required;

  return jsonb_build_object(
    'contractVersion','household_rhythm_shadow_state_self_api_v1',
    'ok',true,
    'state',case
      when v_windowed_count = v_active_count then 'ready'
      else 'incomplete_legacy_window_state'
    end,
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'timezone',v_timezone,
    'observedAt',v_observed_at,
    'serviceDate',(v_observed_at at time zone v_timezone)::date,
    'activePrincipalRhythmCount',v_active_count,
    'windowedRhythmCount',v_windowed_count,
    'rhythms',v_rows,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'currentStateOnly',true,
      'historicalReadClaimed',false,
      'clockArbitrationExposed',false,
      'unrelatedCandidatesExposed',false,
      'authorityMutationAllowed',false
    )
  );
end;
$function$;

revoke all on function atlas.household_rhythm_shadow_state_self_api_v1() from public;
revoke all on function atlas.household_rhythm_shadow_state_self_api_v1() from anon;
revoke all on function atlas.household_rhythm_shadow_state_self_api_v1() from authenticated;

create or replace function public.household_rhythm_shadow_state_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.household_rhythm_shadow_state_self_api_v1();
$function$;

revoke all on function public.household_rhythm_shadow_state_self_api_v1() from public;
revoke all on function public.household_rhythm_shadow_state_self_api_v1() from anon;
revoke all on function public.household_rhythm_shadow_state_self_api_v1() from authenticated;
grant execute on function public.household_rhythm_shadow_state_self_api_v1() to authenticated;
