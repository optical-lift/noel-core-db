-- Atlas Person Condition Scope v1
-- Extends the already-generic Care persistence kernel so a signed-in person can
-- own condition observations across life domains without inventing a new
-- health-specific persistence stack. Practitioner sharing is intentionally not
-- introduced here.

begin;

-- Current-state identity must include custody scope. The same domain subject key
-- may lawfully exist in separate households, farms, or person-owned scopes.
alter table atlas.care_current_state
  drop constraint if exists care_current_state_subject_key;

alter table atlas.care_current_state
  add constraint care_current_state_scoped_subject_key
  unique (scope_kind, scope_id, subject_domain, subject_kind, subject_id);

create or replace function atlas.care_apply_observation_current_state_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  insert into atlas.care_current_state (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    condition_state,
    disposition,
    last_observed_at,
    last_observation_id,
    metadata
  )
  values (
    new.subject_domain,
    new.subject_kind,
    new.subject_id,
    new.scope_kind,
    new.scope_id,
    new.condition_state,
    new.disposition,
    new.observed_at,
    new.id,
    jsonb_build_object(
      'lastObservationSourceKind', new.source_kind,
      'inferredFromClock', false
    )
  )
  on conflict (scope_kind, scope_id, subject_domain, subject_kind, subject_id)
  do update set
    condition_state = excluded.condition_state,
    disposition = excluded.disposition,
    last_observed_at = excluded.last_observed_at,
    last_observation_id = excluded.last_observation_id,
    metadata = coalesce(atlas.care_current_state.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now()
  where excluded.last_observed_at >= atlas.care_current_state.last_observed_at;

  return new;
end;
$$;

revoke all on function atlas.care_apply_observation_current_state_v1() from public, anon, authenticated;
grant execute on function atlas.care_apply_observation_current_state_v1() to service_role;

-- Person-owned scope is first-party custody only. It does not grant a
-- practitioner, employer, household member, or other authenticated user access.
drop policy if exists care_observation_events_scope_read on atlas.care_observation_events;
create policy care_observation_events_scope_read
on atlas.care_observation_events
for select
to authenticated
using (
  (
    scope_kind = 'person'
    and scope_id = auth.uid()
  )
  or (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_observation_events.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

drop policy if exists care_current_state_scope_read on atlas.care_current_state;
create policy care_current_state_scope_read
on atlas.care_current_state
for select
to authenticated
using (
  (
    scope_kind = 'person'
    and scope_id = auth.uid()
  )
  or (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_current_state.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

drop policy if exists care_result_events_scope_read on atlas.care_result_events;
create policy care_result_events_scope_read
on atlas.care_result_events
for select
to authenticated
using (
  (
    scope_kind = 'person'
    and scope_id = auth.uid()
  )
  or (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_result_events.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

create or replace function atlas.record_person_condition_observation_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_condition_state text;
  v_disposition text;
  v_source_key text;
  v_storage_key text;
  v_observed_at timestamptz;
  v_observation_id uuid;
  v_existing_scope_kind text;
  v_existing_scope_id uuid;
  v_existing_subject_domain text;
  v_existing_subject_kind text;
  v_existing_subject_id text;
  v_existing_condition_state text;
  v_existing_disposition text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_subject_domain := btrim(coalesce(p_payload->>'subjectDomain', ''));
  v_subject_kind := btrim(coalesce(p_payload->>'subjectKind', ''));
  v_subject_id := btrim(coalesce(p_payload->>'subjectId', ''));
  v_condition_state := btrim(coalesce(p_payload->>'conditionState', ''));

  if v_subject_domain = '' then
    raise exception 'subjectDomain is required.' using errcode = '22023';
  end if;
  if v_subject_kind = '' then
    raise exception 'subjectKind is required.' using errcode = '22023';
  end if;
  if v_subject_id = '' then
    raise exception 'subjectId is required.' using errcode = '22023';
  end if;
  if v_condition_state = '' then
    raise exception 'conditionState is required.' using errcode = '22023';
  end if;

  v_disposition := nullif(btrim(coalesce(p_payload->>'disposition', '')), '');
  if v_disposition is null then
    v_disposition := atlas.care_condition_disposition_v1(v_condition_state);
  end if;

  if v_disposition is null then
    raise exception 'disposition is required when conditionState has no registered default.' using errcode = '22023';
  end if;
  if v_disposition not in ('hold', 'reassess', 'intervene') then
    raise exception 'Unsupported disposition.' using errcode = '22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey', ''));
  if v_source_key = '' then
    raise exception 'sourceKey is required for idempotent condition observations.' using errcode = '22023';
  end if;

  -- care_observation_events.source_key is globally unique, so namespace a
  -- client-supplied idempotency key by the authenticated owner.
  v_storage_key := 'person_condition_observation:' || v_user_id::text || ':' || v_source_key;
  v_observed_at := coalesce(nullif(p_payload->>'observedAt', '')::timestamptz, now());

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
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    'person',
    v_user_id,
    v_observed_at,
    v_condition_state,
    v_disposition,
    v_user_id,
    'person_condition_observation',
    v_storage_key,
    nullif(p_payload->>'note', ''),
    false,
    coalesce(p_payload->'metadata', '{}'::jsonb)
  )
  on conflict (source_key) do nothing
  returning id into v_observation_id;

  if v_observation_id is null then
    select
      o.id,
      o.scope_kind,
      o.scope_id,
      o.subject_domain,
      o.subject_kind,
      o.subject_id,
      o.condition_state,
      o.disposition
    into
      v_observation_id,
      v_existing_scope_kind,
      v_existing_scope_id,
      v_existing_subject_domain,
      v_existing_subject_kind,
      v_existing_subject_id,
      v_existing_condition_state,
      v_existing_disposition
    from atlas.care_observation_events o
    where o.source_key = v_storage_key;

    if v_observation_id is null
       or v_existing_scope_kind is distinct from 'person'
       or v_existing_scope_id is distinct from v_user_id
       or v_existing_subject_domain is distinct from v_subject_domain
       or v_existing_subject_kind is distinct from v_subject_kind
       or v_existing_subject_id is distinct from v_subject_id
       or v_existing_condition_state is distinct from v_condition_state
       or v_existing_disposition is distinct from v_disposition then
      raise exception 'sourceKey retry does not match the existing condition observation.' using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'scopeKind', 'person',
    'scopeId', v_user_id,
    'subjectDomain', v_subject_domain,
    'subjectKind', v_subject_kind,
    'subjectId', v_subject_id,
    'observationId', v_observation_id,
    'conditionState', v_condition_state,
    'disposition', v_disposition,
    'inferredFromClock', false
  );
end;
$$;

revoke all on function atlas.record_person_condition_observation_api_v1(jsonb) from public, anon;
grant execute on function atlas.record_person_condition_observation_api_v1(jsonb) to authenticated, service_role;

comment on function atlas.record_person_condition_observation_api_v1(jsonb) is
  'First-party generic condition observation writer. Domain vocabulary stays domain-owned; Atlas stores only provenance-backed observed state and disposition. This function does not diagnose, schedule, infer from Clock, or grant practitioner access.';

commit;
