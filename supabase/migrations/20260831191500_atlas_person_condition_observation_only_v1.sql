-- Atlas Person Condition Observation-Only v1
--
-- A first-party condition observation is evidence. It must be possible to record
-- that evidence without silently manufacturing an operational disposition.
-- Existing domain-owned mappings may still establish hold/reassess/intervene;
-- otherwise the neutral disposition is `observe`.

begin;

alter table atlas.care_observation_events
  drop constraint if exists care_observation_events_disposition_check;

alter table atlas.care_observation_events
  add constraint care_observation_events_disposition_check
  check (disposition in ('observe', 'hold', 'reassess', 'intervene'));

alter table atlas.care_current_state
  drop constraint if exists care_current_state_disposition_check;

alter table atlas.care_current_state
  add constraint care_current_state_disposition_check
  check (disposition in ('observe', 'hold', 'reassess', 'intervene'));

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
    v_disposition := 'observe';
  end if;

  if v_disposition not in ('observe', 'hold', 'reassess', 'intervene') then
    raise exception 'Unsupported disposition.' using errcode = '22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey', ''));
  if v_source_key = '' then
    raise exception 'sourceKey is required for idempotent condition observations.' using errcode = '22023';
  end if;

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

comment on function atlas.record_person_condition_observation_api_v1(jsonb) is
  'First-party generic condition observation writer. Unknown condition vocabulary remains observation-only (`observe`) unless the person supplies a disposition or a domain-owned condition mapping establishes one. This function does not diagnose, schedule, infer causation, infer from Clock, or grant practitioner access.';

-- Same authenticated RPC signature; its custody registration remains valid.
do $$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
    where signature = 'atlas.record_person_condition_observation_api_v1(jsonb)'
  ) then
    raise exception 'Person-condition authenticated RPC custody drifted after observation-only refinement.';
  end if;
end
$$;

commit;
