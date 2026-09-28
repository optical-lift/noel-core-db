-- Rollback-only proof for correction/supersession semantics across the two
-- governed-subject source membranes introduced in this branch.
--
-- Governing expectations:
--   * a later observation supersedes the present read without deleting the earlier fact;
--   * historical as-of reads still recover the earlier observation;
--   * applicability replacement is expressed through non-overlapping effective intervals;
--   * a later interval does not rewrite the earlier interval;
--   * no Task/Work carrier is created as a side effect.

begin;

do $$
declare
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  v_owner_entity_id uuid;
  v_observer_entity_id uuid;
  v_resource_id uuid;
  v_organization_id uuid;
  v_responsibility_id uuid;
  v_scope_id uuid;
  v_t0 timestamptz := date_trunc('second', now() - interval '2 hours');
  v_t1 timestamptz := date_trunc('second', now() - interval '1 hour');
  v_t2 timestamptz := date_trunc('second', now() + interval '1 hour');
  v_first jsonb;
  v_correction jsonb;
  v_resolution jsonb;
  v_app_first jsonb;
  v_app_second jsonb;
  v_app_resolution jsonb;
  v_tasks_before bigint;
  v_tasks_after bigint;
  v_has_tasks boolean := to_regclass('atlas.tasks') is not null;
begin
  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('correction_owner_' || v_suffix, 'business', 'Correction Test Owner ' || v_suffix)
  returning id into v_owner_entity_id;

  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('correction_observer_' || v_suffix, 'person', 'Correction Test Observer ' || v_suffix)
  returning id into v_observer_entity_id;

  insert into reality.resources (
    owner_entity_id,
    stable_key,
    label,
    resource_kind,
    resource_state,
    reservable,
    capacity_mode
  ) values (
    v_owner_entity_id,
    'correction_ground_' || v_suffix,
    'Correction Ground ' || v_suffix,
    'zone',
    'active',
    false,
    'exclusive'
  ) returning id into v_resource_id;

  insert into atlas.organizations (stable_key, name)
  values ('correction_org_' || v_suffix, 'Correction Organization ' || v_suffix)
  returning id into v_organization_id;

  insert into atlas.organization_responsibilities (
    organization_id,
    stable_key,
    name,
    responsibility_kind
  ) values (
    v_organization_id,
    'grounds_readiness_' || v_suffix,
    'Grounds readiness ' || v_suffix,
    'stewardship'
  ) returning id into v_responsibility_id;

  insert into atlas.organization_responsibility_scopes (
    organization_id,
    responsibility_id,
    scope_kind,
    scope_id,
    relation_kind
  ) values (
    v_organization_id,
    v_responsibility_id,
    'organization_unit',
    'elm-' || v_suffix,
    'stewards'
  ) returning id into v_scope_id;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_before;
  end if;

  -- The first observation is real historical evidence. It will later be superseded
  -- for present resolution, not edited or deleted.
  v_first := reality.record_resource_observation_service_v1(
    v_resource_id,
    'surface_height_v1',
    jsonb_build_object('height_inches', 9, 'reading', 'threshold_crossed'),
    'test-observer:' || v_suffix,
    v_t0,
    'correction:first:' || v_suffix,
    v_observer_entity_id,
    jsonb_build_object('test', true, 'sequence', 1)
  );

  if v_first->>'state' <> 'admitted' then
    raise exception 'expected first observation admission, got %', v_first;
  end if;

  -- A later observation is admitted as a distinct canonical fact. This is the
  -- correction/supersession pattern: new source evidence, not mutation of the old fact.
  v_correction := reality.record_resource_observation_service_v1(
    v_resource_id,
    'surface_height_v1',
    jsonb_build_object('height_inches', 4, 'reading', 'standard_satisfied'),
    'test-observer:' || v_suffix,
    v_t1,
    'correction:second:' || v_suffix,
    v_observer_entity_id,
    jsonb_build_object('test', true, 'sequence', 2, 'supersedes_for_current_read', v_first->>'observationId')
  );

  if v_correction->>'state' <> 'admitted' then
    raise exception 'expected later correction observation admission, got %', v_correction;
  end if;
  if v_correction->>'observationId' = v_first->>'observationId' then
    raise exception 'correction must be a distinct source fact, not mutation/reuse of prior observation';
  end if;

  -- Present/current read resolves to the later observation.
  v_resolution := reality.resolve_resource_observation_latest_v1(
    v_resource_id,
    'surface_height_v1',
    v_t2,
    v_t2
  );

  if v_resolution->>'state' <> 'established_latest'
     or v_resolution->>'observationId' <> v_correction->>'observationId'
     or (v_resolution#>>'{observationPayload,height_inches}')::numeric <> 4 then
    raise exception 'current observation did not re-resolve to later source evidence: %', v_resolution;
  end if;

  -- Historical observed-as-of before the later observation still recovers the first
  -- source fact. Current correction must not rewrite history.
  v_resolution := reality.resolve_resource_observation_latest_v1(
    v_resource_id,
    'surface_height_v1',
    v_t0 + interval '1 minute',
    v_t2
  );

  if v_resolution->>'state' <> 'established_latest'
     or v_resolution->>'observationId' <> v_first->>'observationId'
     or (v_resolution#>>'{observationPayload,height_inches}')::numeric <> 9 then
    raise exception 'historical observation was rewritten by later evidence: %', v_resolution;
  end if;

  -- Both facts remain durable in source history.
  if (
    select count(*)
      from reality.resource_observations o
     where o.resource_id = v_resource_id
       and o.observation_type = 'surface_height_v1'
  ) <> 2 then
    raise exception 'expected both historical observation facts to remain durable';
  end if;

  -- Applicability replacement uses adjacent/non-overlapping effective intervals.
  -- First relation is historically valid, then ends at v_t1.
  v_app_first := atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_scope_id,
    v_resource_id,
    'acquire_current_resource_observation',
    v_t0,
    v_t1,
    'correction:app:first:' || v_suffix,
    jsonb_build_object('test', true, 'sequence', 1)
  );

  if v_app_first->>'state' <> 'admitted' then
    raise exception 'expected first applicability admission, got %', v_app_first;
  end if;

  -- Replacement begins exactly when the first relation ends. It is a new durable
  -- relation interval, not an edit of the first row.
  v_app_second := atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_scope_id,
    v_resource_id,
    'acquire_current_resource_observation',
    v_t1,
    null,
    'correction:app:second:' || v_suffix,
    jsonb_build_object('test', true, 'sequence', 2, 'supersedes_for_current_read', v_app_first->>'applicabilityId')
  );

  if v_app_second->>'state' <> 'admitted' then
    raise exception 'expected replacement applicability admission, got %', v_app_second;
  end if;
  if v_app_second->>'applicabilityId' = v_app_first->>'applicabilityId' then
    raise exception 'replacement applicability must remain a distinct durable relation interval';
  end if;

  -- Historical resolution during the first interval must still establish the first row.
  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_scope_id,
    v_resource_id,
    'acquire_current_resource_observation',
    v_t0 + interval '1 minute'
  );

  if v_app_resolution->>'state' <> 'established_current'
     or v_app_resolution#>>'{item,applicabilityId}' <> v_app_first->>'applicabilityId' then
    raise exception 'historical applicability interval was rewritten by replacement: %', v_app_resolution;
  end if;

  -- Resolution after the boundary must establish only the replacement interval.
  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_scope_id,
    v_resource_id,
    'acquire_current_resource_observation',
    v_t1 + interval '1 minute'
  );

  if v_app_resolution->>'state' <> 'established_current'
     or v_app_resolution#>>'{item,applicabilityId}' <> v_app_second->>'applicabilityId' then
    raise exception 'replacement applicability did not become current after boundary: %', v_app_resolution;
  end if;

  if (
    select count(*)
      from atlas.organization_responsibility_resource_applicability a
     where a.responsibility_scope_id = v_scope_id
       and a.resource_id = v_resource_id
       and a.operation_key = 'acquire_current_resource_observation'
  ) <> 2 then
    raise exception 'expected both applicability intervals to remain durable';
  end if;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_after;
    if v_tasks_after <> v_tasks_before then
      raise exception 'correction/supersession proof unexpectedly mutated atlas.tasks';
    end if;
  end if;
end;
$$;

rollback;
