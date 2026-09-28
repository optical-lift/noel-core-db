-- Rollback-only behavioral proof for governed resource observations and
-- Responsibility→resource applicability.
--
-- Immediate post-write reads use clock_timestamp() for recorded_as_of because
-- record_resource_observation_service_v1 records with clock_timestamp(); PostgreSQL
-- now() is transaction-start time and therefore predates rows recorded later in
-- the same transaction. observed_as_of remains independently controlled.

begin;

do $$
declare
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  v_owner_entity_id uuid;
  v_observer_entity_id uuid;
  v_resource_id uuid;
  v_other_resource_id uuid;
  v_organization_id uuid;
  v_responsibility_id uuid;
  v_scope_id uuid;
  v_observed_at timestamptz := now() - interval '30 minutes';
  v_effective_from timestamptz := now() - interval '1 hour';
  v_receipt jsonb;
  v_replay jsonb;
  v_resolution jsonb;
  v_app_receipt jsonb;
  v_app_replay jsonb;
  v_app_resolution jsonb;
  v_tasks_before bigint;
  v_tasks_after bigint;
  v_has_tasks boolean := to_regclass('atlas.tasks') is not null;
begin
  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('test_owner_' || v_suffix, 'business', 'Observation Test Owner ' || v_suffix)
  returning id into v_owner_entity_id;

  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('test_observer_' || v_suffix, 'person', 'Observation Test Observer ' || v_suffix)
  returning id into v_observer_entity_id;

  insert into reality.resources (
    owner_entity_id, stable_key, label, resource_kind, resource_state, reservable, capacity_mode
  ) values (
    v_owner_entity_id, 'test_ground_' || v_suffix, 'Test Ground ' || v_suffix,
    'zone', 'active', false, 'exclusive'
  ) returning id into v_resource_id;

  insert into reality.resources (
    owner_entity_id, stable_key, label, resource_kind, resource_state, reservable, capacity_mode
  ) values (
    v_owner_entity_id, 'test_other_ground_' || v_suffix, 'Other Test Ground ' || v_suffix,
    'zone', 'active', false, 'exclusive'
  ) returning id into v_other_resource_id;

  insert into atlas.organizations (stable_key, name)
  values ('test_org_' || v_suffix, 'Test Organization ' || v_suffix)
  returning id into v_organization_id;

  insert into atlas.organization_responsibilities (
    organization_id, stable_key, name, responsibility_kind
  ) values (
    v_organization_id, 'test_readiness_' || v_suffix, 'Test Readiness ' || v_suffix, 'stewardship'
  ) returning id into v_responsibility_id;

  insert into atlas.organization_responsibility_scopes (
    organization_id, responsibility_id, scope_kind, scope_id, relation_kind
  ) values (
    v_organization_id, v_responsibility_id, 'organization_unit', 'test-scope-' || v_suffix, 'stewards'
  ) returning id into v_scope_id;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_before;
  end if;

  v_receipt := reality.record_resource_observation_service_v1(
    v_resource_id, 'surface_height_v1', jsonb_build_object('height_inches', 4),
    'test-observer:' || v_suffix, v_observed_at, 'observation:' || v_suffix,
    v_observer_entity_id, jsonb_build_object('test', true)
  );

  if v_receipt->>'state' <> 'admitted' then
    raise exception 'expected admitted observation receipt, got %', v_receipt;
  end if;
  if (v_receipt->>'resourceId')::uuid <> v_resource_id then
    raise exception 'observation receipt lost resource subject identity';
  end if;
  if (v_receipt->>'observedAt')::timestamptz <> v_observed_at then
    raise exception 'observation receipt lost observed_at';
  end if;
  if (v_receipt->>'recordedAt')::timestamptz <= v_observed_at then
    raise exception 'recorded_at must remain distinct from the earlier observed_at fixture';
  end if;

  v_replay := reality.record_resource_observation_service_v1(
    v_resource_id, 'surface_height_v1', jsonb_build_object('height_inches', 4),
    'test-observer:' || v_suffix, v_observed_at, 'observation:' || v_suffix,
    v_observer_entity_id, jsonb_build_object('test', true)
  );

  if v_replay->>'state' <> 'replayed'
     or v_replay->>'observationId' <> v_receipt->>'observationId' then
    raise exception 'observation replay did not return the canonical admitted fact';
  end if;

  begin
    perform reality.record_resource_observation_service_v1(
      v_resource_id, 'surface_height_v1', jsonb_build_object('height_inches', 9),
      'test-observer:' || v_suffix, v_observed_at, 'observation:' || v_suffix,
      v_observer_entity_id, jsonb_build_object('test', true)
    );
    raise exception 'expected observation idempotency conflict';
  exception
    when unique_violation then null;
  end;

  v_resolution := reality.resolve_resource_observation_latest_v1(
    v_resource_id, 'surface_height_v1', now(), clock_timestamp()
  );
  if v_resolution->>'state' <> 'established_latest' then
    raise exception 'expected latest canonical observation, got %', v_resolution;
  end if;
  if (v_resolution->>'resourceId')::uuid <> v_resource_id then
    raise exception 'latest observation crossed resource subject boundaries';
  end if;

  v_resolution := reality.resolve_resource_observation_latest_v1(
    v_other_resource_id, 'surface_height_v1', now(), clock_timestamp()
  );
  if v_resolution->>'state' <> 'indeterminate'
     or v_resolution->>'reason' <> 'no_admitted_observation' then
    raise exception 'different resource must not inherit another subject observation: %', v_resolution;
  end if;

  v_app_receipt := atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_scope_id, v_resource_id, 'acquire_current_resource_observation',
    v_effective_from, null, 'applicability:' || v_suffix, jsonb_build_object('test', true)
  );
  if v_app_receipt->>'state' <> 'admitted' then
    raise exception 'expected admitted applicability receipt, got %', v_app_receipt;
  end if;

  v_app_replay := atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_scope_id, v_resource_id, 'acquire_current_resource_observation',
    v_effective_from, null, 'applicability:' || v_suffix, jsonb_build_object('test', true)
  );
  if v_app_replay->>'state' <> 'replayed'
     or v_app_replay->>'applicabilityId' <> v_app_receipt->>'applicabilityId' then
    raise exception 'applicability replay did not return canonical admitted relation';
  end if;

  begin
    perform atlas.admit_organization_responsibility_resource_applicability_service_v1(
      v_scope_id, v_resource_id, 'acquire_current_resource_observation',
      now() - interval '15 minutes', now() + interval '1 day',
      'applicability-overlap:' || v_suffix, jsonb_build_object('test', true)
    );
    raise exception 'expected applicability overlap rejection';
  exception
    when exclusion_violation then null;
  end;

  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_scope_id, v_resource_id, 'acquire_current_resource_observation', now()
  );
  if v_app_resolution->>'state' <> 'established_current' then
    raise exception 'expected current applicability, got %', v_app_resolution;
  end if;
  if (v_app_resolution#>>'{item,resourceId}')::uuid <> v_resource_id
     or (v_app_resolution#>>'{item,responsibilityScopeId}')::uuid <> v_scope_id then
    raise exception 'current applicability lost exact source identities';
  end if;

  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_scope_id, v_other_resource_id, 'acquire_current_resource_observation', now()
  );
  if v_app_resolution->>'state' <> 'indeterminate'
     or v_app_resolution->>'reason' <> 'applicability_not_recorded' then
    raise exception 'missing applicability must remain indeterminate: %', v_app_resolution;
  end if;

  perform atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_scope_id, v_resource_id, 'historical_resource_observation',
    now() - interval '10 days', now() - interval '5 days',
    'historical-applicability:' || v_suffix, jsonb_build_object('test', true)
  );

  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_scope_id, v_resource_id, 'historical_resource_observation', now()
  );
  if v_app_resolution->>'state' <> 'established_not_current' then
    raise exception 'expected known historical applicability to be not current: %', v_app_resolution;
  end if;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_after;
    if v_tasks_after <> v_tasks_before then
      raise exception 'governed source admission unexpectedly mutated atlas.tasks';
    end if;
  end if;
end;
$$;

rollback;
