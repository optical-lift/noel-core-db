-- Atlas Household Care API v1
-- Authenticated observation/result recording plus the Principal household Care snapshot.

begin;

create or replace function atlas.principal_record_household_care_observation_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_space_id uuid;
  v_condition text;
  v_disposition text;
  v_source_key text;
  v_storage_key text;
  v_observed_at timestamptz;
  v_observation_id uuid;
  v_existing_subject_id text;
  v_existing_scope_id uuid;
  v_existing_condition text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  v_space_id := nullif(p_payload->>'spaceId','')::uuid;
  if v_space_id is null
     or not exists (
       select 1
       from atlas.household_spaces s
       where s.id = v_space_id
         and s.household_id = v_household_id
         and s.active
     ) then
    raise exception 'Active household space required.' using errcode = '22023';
  end if;

  v_condition := btrim(coalesce(p_payload->>'conditionState',''));
  v_disposition := atlas.care_condition_disposition_v1(v_condition);
  if v_disposition is null then
    raise exception 'Unsupported household care condition.' using errcode = '22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key = '' then
    raise exception 'sourceKey is required for idempotent care observations.' using errcode = '22023';
  end if;
  v_storage_key := 'principal_household_care_observation:' || v_source_key;
  v_observed_at := coalesce((nullif(p_payload->>'observedAt','')::timestamptz), now());

  insert into atlas.care_observation_events (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    observed_at,
    condition_state,
    disposition,
    observed_by_user_id,
    source_kind,
    source_key,
    note,
    inferred_from_clock,
    metadata
  )
  values (
    'household',
    'household_space',
    v_space_id::text,
    'household',
    v_household_id,
    v_observed_at,
    v_condition,
    v_disposition,
    auth.uid(),
    'principal_household_care_observation',
    v_storage_key,
    nullif(p_payload->>'note',''),
    false,
    coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict (source_key) do nothing
  returning id into v_observation_id;

  if v_observation_id is null then
    select o.id, o.subject_id, o.scope_id, o.condition_state
      into v_observation_id, v_existing_subject_id, v_existing_scope_id, v_existing_condition
    from atlas.care_observation_events o
    where o.source_key = v_storage_key;

    if v_existing_subject_id is distinct from v_space_id::text
       or v_existing_scope_id is distinct from v_household_id
       or v_existing_condition is distinct from v_condition then
      raise exception 'sourceKey retry does not match the existing care observation.' using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'householdId', v_household_id,
    'spaceId', v_space_id,
    'observationId', v_observation_id,
    'conditionState', v_condition,
    'disposition', v_disposition,
    'inferredFromClock', false
  );
end;
$$;

revoke all on function atlas.principal_record_household_care_observation_api_v1(jsonb) from public, anon;
grant execute on function atlas.principal_record_household_care_observation_api_v1(jsonb) to authenticated, service_role;

create or replace function atlas.principal_record_household_care_result_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_space_id uuid;
  v_result_kind text;
  v_condition_before text;
  v_condition_after text;
  v_disposition text;
  v_source_key text;
  v_storage_key text;
  v_condition_source_key text;
  v_occurred_at timestamptz;
  v_result_id uuid;
  v_observation_id uuid;
  v_minutes integer;
  v_minutes_known boolean;
  v_existing_result_kind text;
  v_existing_condition_after text;
  v_existing_minutes integer;
  v_existing_minutes_known boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  v_space_id := nullif(p_payload->>'spaceId','')::uuid;
  if v_space_id is null
     or not exists (
       select 1
       from atlas.household_spaces s
       where s.id = v_space_id
         and s.household_id = v_household_id
         and s.active
     ) then
    raise exception 'Active household space required.' using errcode = '22023';
  end if;

  v_result_kind := btrim(coalesce(p_payload->>'resultKind',''));
  if v_result_kind not in (
    'recovered',
    'improved_more_remains',
    'condition_differed',
    'blocked',
    'strategy_should_change',
    'plan_changed_not_relevant'
  ) then
    raise exception 'Unsupported care result kind.' using errcode = '22023';
  end if;

  v_condition_after := btrim(coalesce(p_payload->>'conditionAfter',''));
  v_disposition := atlas.care_condition_disposition_v1(v_condition_after);
  if v_disposition is null then
    raise exception 'Unsupported resulting household care condition.' using errcode = '22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key = '' then
    raise exception 'sourceKey is required for idempotent care results.' using errcode = '22023';
  end if;
  v_storage_key := 'principal_household_care_result:' || v_source_key;
  v_occurred_at := coalesce((nullif(p_payload->>'occurredAt','')::timestamptz), now());

  select cs.condition_state
    into v_condition_before
  from atlas.care_current_state cs
  where cs.subject_domain = 'household'
    and cs.subject_kind = 'household_space'
    and cs.subject_id = v_space_id::text
    and cs.scope_kind = 'household'
    and cs.scope_id = v_household_id;

  if nullif(p_payload->>'minutes','') is not null then
    v_minutes := (p_payload->>'minutes')::integer;
    if v_minutes < 0 then
      raise exception 'minutes cannot be negative.' using errcode = '22023';
    end if;
  end if;
  v_minutes_known := coalesce((p_payload->>'minutesKnown')::boolean, v_minutes is not null);

  insert into atlas.care_result_events (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    occurred_at,
    result_kind,
    condition_before,
    condition_after,
    minutes,
    minutes_known,
    actor_user_id,
    source_kind,
    source_key,
    note,
    metadata
  )
  values (
    'household',
    'household_space',
    v_space_id::text,
    'household',
    v_household_id,
    v_occurred_at,
    v_result_kind,
    v_condition_before,
    v_condition_after,
    v_minutes,
    v_minutes_known,
    auth.uid(),
    'principal_household_care_result',
    v_storage_key,
    nullif(p_payload->>'note',''),
    coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict (source_key) do nothing
  returning id into v_result_id;

  if v_result_id is null then
    select r.id, r.result_kind, r.condition_after, r.minutes, r.minutes_known
      into v_result_id, v_existing_result_kind, v_existing_condition_after, v_existing_minutes, v_existing_minutes_known
    from atlas.care_result_events r
    where r.source_key = v_storage_key
      and r.subject_domain = 'household'
      and r.subject_kind = 'household_space'
      and r.subject_id = v_space_id::text
      and r.scope_kind = 'household'
      and r.scope_id = v_household_id;

    if v_result_id is null
       or v_existing_result_kind is distinct from v_result_kind
       or v_existing_condition_after is distinct from v_condition_after
       or v_existing_minutes is distinct from v_minutes
       or v_existing_minutes_known is distinct from v_minutes_known then
      raise exception 'sourceKey retry does not match the existing care result.' using errcode = '23505';
    end if;
  end if;

  v_condition_source_key := 'household_care_result_condition:' || v_result_id::text;

  insert into atlas.care_observation_events (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    observed_at,
    condition_state,
    disposition,
    observed_by_user_id,
    source_kind,
    source_key,
    note,
    inferred_from_clock,
    metadata
  )
  values (
    'household',
    'household_space',
    v_space_id::text,
    'household',
    v_household_id,
    v_occurred_at,
    v_condition_after,
    v_disposition,
    auth.uid(),
    'household_care_result_condition',
    v_condition_source_key,
    nullif(p_payload->>'note',''),
    false,
    coalesce(p_payload->'metadata','{}'::jsonb)
      || jsonb_build_object('careResultId', v_result_id, 'resultKind', v_result_kind)
  )
  on conflict (source_key) do nothing
  returning id into v_observation_id;

  if v_observation_id is null then
    select o.id
      into v_observation_id
    from atlas.care_observation_events o
    where o.source_key = v_condition_source_key
      and o.subject_domain = 'household'
      and o.subject_kind = 'household_space'
      and o.subject_id = v_space_id::text
      and o.scope_kind = 'household'
      and o.scope_id = v_household_id;

    if v_observation_id is null then
      raise exception 'Result condition source key collision.' using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'householdId', v_household_id,
    'spaceId', v_space_id,
    'resultId', v_result_id,
    'observationId', v_observation_id,
    'resultKind', v_result_kind,
    'conditionBefore', v_condition_before,
    'conditionAfter', v_condition_after,
    'disposition', v_disposition
  );
end;
$$;

revoke all on function atlas.principal_record_household_care_result_api_v1(jsonb) from public, anon;
grant execute on function atlas.principal_record_household_care_result_api_v1(jsonb) to authenticated, service_role;

create or replace function atlas.principal_household_care_snapshot_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'household',
      jsonb_build_object(
        'id', h.id,
        'name', h.name,
        'timezone', h.timezone
      ),
    'dwellings',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', d.id,
            'stableKey', d.stable_key,
            'name', d.name,
            'dwellingKind', d.dwelling_kind,
            'active', d.active,
            'spaces', coalesce((
              select jsonb_agg(
                jsonb_build_object(
                  'id', s.id,
                  'parentSpaceId', s.parent_space_id,
                  'stableKey', s.stable_key,
                  'name', s.name,
                  'spaceType', s.space_type,
                  'functionalTags', to_jsonb(s.functional_tags),
                  'floorLevel', s.floor_level,
                  'careRelevant', s.care_relevant,
                  'active', s.active,
                  'sourceKind', s.source_kind,
                  'confidence', s.confidence,
                  'confirmedAt', s.confirmed_at,
                  'conditionState', coalesce(cs.condition_state, 'unknown'),
                  'disposition', coalesce(cs.disposition, 'reassess'),
                  'conditionKnown', cs.id is not null,
                  'lastObservedAt', cs.last_observed_at
                )
                order by s.created_at, s.id
              )
              from atlas.household_spaces s
              left join atlas.care_current_state cs
                on cs.subject_domain = 'household'
               and cs.subject_kind = 'household_space'
               and cs.subject_id = s.id::text
               and cs.scope_kind = 'household'
               and cs.scope_id = h.id
              where s.dwelling_id = d.id
                and s.household_id = h.id
            ), '[]'::jsonb)
          )
          order by d.created_at, d.id
        )
        from atlas.dwellings d
        where d.household_id = h.id
      ), '[]'::jsonb),
    'currentAttention',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'rhythmId', a.rhythm_id,
            'windowStart', a.window_start,
            'windowEnd', a.window_end,
            'expectedMinutes', a.expected_minutes,
            'zoneId', a.zone_id,
            'zoneNumber', a.zone_number,
            'zoneStableKey', a.zone_stable_key,
            'zoneName', a.zone_name,
            'spaceId', a.space_id,
            'spaceName', a.space_name,
            'spaceType', a.space_type,
            'floorLevel', a.floor_level,
            'functionalTags', to_jsonb(a.functional_tags),
            'conditionState', a.condition_state,
            'disposition', a.disposition,
            'conditionKnown', a.condition_known,
            'lastObservedAt', a.last_observed_at,
            'releaseKind', a.release_kind,
            'releasesExecutableWork', a.releases_executable_work
          )
          order by a.zone_number, a.space_name nulls first, a.space_id
        )
        from atlas.household_care_current_attention_v1 a
        where a.household_id = h.id
      ), '[]'::jsonb)
  )
  into v_result
  from atlas.households h
  where h.id = v_household_id;

  return v_result;
end;
$$;

revoke all on function atlas.principal_household_care_snapshot_v1() from public, anon;
grant execute on function atlas.principal_household_care_snapshot_v1() to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.principal_upsert_dwelling_api_v1(jsonb)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object('source','atlas_household_care_kernel_v1','purpose','principal household dwelling authoring'),
    now(),
    false
  ),
  (
    'atlas.principal_upsert_household_space_api_v1(jsonb)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object('source','atlas_household_care_kernel_v1','purpose','principal household physical-space authoring'),
    now(),
    false
  ),
  (
    'atlas.principal_record_household_care_observation_api_v1(jsonb)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object('source','atlas_household_care_kernel_v1','purpose','observation-owned household physical condition'),
    now(),
    false
  ),
  (
    'atlas.principal_record_household_care_result_api_v1(jsonb)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object('source','atlas_household_care_kernel_v1','purpose','bounded household care result and resulting condition'),
    now(),
    false
  ),
  (
    'atlas.principal_household_care_snapshot_v1()',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object('source','atlas_household_care_kernel_v1','purpose','principal household care read model'),
    now(),
    false
  )
on conflict (signature)
do update set
  classification = excluded.classification,
  confidence = excluded.confidence,
  review_status = excluded.review_status,
  authenticated_execute_expected = excluded.authenticated_execute_expected,
  security_definer_expected = excluded.security_definer_expected,
  service_execute_expected = excluded.service_execute_expected,
  caller_count = excluded.caller_count,
  policy_reference_count = excluded.policy_reference_count,
  evidence = excluded.evidence,
  reviewed_at = excluded.reviewed_at,
  anonymous_execute_expected = excluded.anonymous_execute_expected;

comment on table atlas.dwellings is
  'Canonical household dwelling containers. A dwelling exists independently of household care zones.';
comment on table atlas.household_spaces is
  'Canonical physical household spaces. Floor topology is descriptive; functional_tags determine care-zone eligibility.';
comment on table atlas.care_observation_events is
  'Domain-neutral physical Care observations. Clocks may request reassessment but inferred_from_clock is permanently false.';
comment on table atlas.care_current_state is
  'Latest observation-derived Care state for a generic Atlas subject tuple.';
comment on table atlas.care_result_events is
  'Domain-neutral bounded Care results. Household result APIs also write a resulting observation so state remains observation-derived.';
comment on view atlas.household_care_current_attention_v1 is
  'Current five-zone household protected-attention window resolved against actual functional household spaces; never releases executable work by itself.';

commit;
