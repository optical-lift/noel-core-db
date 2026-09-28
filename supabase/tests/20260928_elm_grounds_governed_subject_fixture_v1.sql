-- Rollback-only concrete fixture for the Elm Grounds source path.
--
-- Immediate post-write reads use clock_timestamp() for recorded_as_of because
-- recorded_at is admission time, while now() is frozen at transaction start.
-- Historical observed_as_of remains explicit so later evidence does not rewrite
-- earlier observed reality.

begin;

do $$
declare
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  v_elm_entity_id uuid;
  v_observer_entity_id uuid;
  v_site_resource_id uuid;
  v_grounds_resource_id uuid;
  v_elm_org_id uuid;
  v_ground_readiness_id uuid;
  v_elm_scope_id uuid;
  v_stale_at timestamptz := date_trunc('second', now() - interval '1 day');
  v_fresh_at timestamptz := date_trunc('second', now() - interval '5 minutes');
  v_app_from timestamptz := date_trunc('second', now() - interval '30 days');
  v_stale_receipt jsonb;
  v_fresh_receipt jsonb;
  v_latest jsonb;
  v_historical jsonb;
  v_app_receipt jsonb;
  v_app_resolution jsonb;
  v_tasks_before bigint;
  v_tasks_after bigint;
  v_has_tasks boolean := to_regclass('atlas.tasks') is not null;
begin
  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('fixture_elm_farm_' || v_suffix, 'business', 'Elm Farm Fixture ' || v_suffix)
  returning id into v_elm_entity_id;

  insert into reality.entities (stable_key, entity_kind, display_name)
  values ('fixture_elm_observer_' || v_suffix, 'person', 'Elm Grounds Observer Fixture ' || v_suffix)
  returning id into v_observer_entity_id;

  insert into reality.resources (
    owner_entity_id, stable_key, label, resource_kind, resource_state, reservable, capacity_mode
  ) values (
    v_elm_entity_id, 'elm_farm_site_' || v_suffix, 'Elm Farm Site', 'site', 'active', false, 'exclusive'
  ) returning id into v_site_resource_id;

  insert into reality.resources (
    owner_entity_id, parent_resource_id, stable_key, label, resource_kind, resource_state, reservable, capacity_mode
  ) values (
    v_elm_entity_id, v_site_resource_id, 'grounds_' || v_suffix, 'Grounds', 'zone', 'active', false, 'exclusive'
  ) returning id into v_grounds_resource_id;

  insert into atlas.organizations (stable_key, name)
  values ('fixture_elm_' || v_suffix, 'Elm Fixture ' || v_suffix)
  returning id into v_elm_org_id;

  insert into atlas.organization_responsibilities (
    organization_id, stable_key, name, responsibility_kind
  ) values (
    v_elm_org_id, 'grounds_readiness', 'Grounds readiness', 'stewardship'
  ) returning id into v_ground_readiness_id;

  insert into atlas.organization_responsibility_scopes (
    organization_id, responsibility_id, scope_kind, scope_id, relation_kind
  ) values (
    v_elm_org_id, v_ground_readiness_id, 'organization_unit',
    'fixture-elm-operating-business-' || v_suffix, 'stewards'
  ) returning id into v_elm_scope_id;

  if v_elm_scope_id::text = v_grounds_resource_id::text then
    raise exception 'institutional Responsibility scope and physical Grounds subject must remain distinct identities';
  end if;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_before;
  end if;

  v_app_receipt := atlas.admit_organization_responsibility_resource_applicability_service_v1(
    v_elm_scope_id, v_grounds_resource_id, 'acquire_current_grounds_observation',
    v_app_from, null, 'fixture:elm:grounds:applicability:' || v_suffix,
    jsonb_build_object(
      'fixture', 'elm_grounds_v1',
      'institutional_semantic', 'grounds_readiness',
      'physical_subject_semantic', 'Grounds'
    )
  );
  if v_app_receipt->>'state' <> 'admitted' then
    raise exception 'Elm Grounds applicability admission failed: %', v_app_receipt;
  end if;

  v_app_resolution := atlas.resolve_organization_responsibility_resource_applicability_current_v1(
    v_elm_scope_id, v_grounds_resource_id, 'acquire_current_grounds_observation', now()
  );
  if v_app_resolution->>'state' <> 'established_current'
     or (v_app_resolution#>>'{item,resourceId}')::uuid <> v_grounds_resource_id
     or (v_app_resolution#>>'{item,responsibilityScopeId}')::uuid <> v_elm_scope_id
     or v_app_resolution#>>'{item,operationKey}' <> 'acquire_current_grounds_observation' then
    raise exception 'Elm Grounds applicability did not resolve exact governed identities: %', v_app_resolution;
  end if;

  v_stale_receipt := reality.record_resource_observation_service_v1(
    v_grounds_resource_id, 'surface_height_v1',
    jsonb_build_object(
      'height_inches', 8,
      'measurement_method', 'visual_estimate',
      'fixture_semantic', 'stale_before_clarification'
    ),
    'fixture-observer:' || v_suffix, v_stale_at,
    'fixture:elm:grounds:observation:stale:' || v_suffix,
    v_observer_entity_id,
    jsonb_build_object('fixture', 'elm_grounds_v1', 'sequence', 1)
  );
  if v_stale_receipt->>'state' <> 'admitted' then
    raise exception 'Elm stale Grounds observation admission failed: %', v_stale_receipt;
  end if;

  v_latest := reality.resolve_resource_observation_latest_v1(
    v_grounds_resource_id, 'surface_height_v1', now(), clock_timestamp()
  );
  if v_latest->>'state' <> 'established_latest'
     or v_latest->>'observationId' <> v_stale_receipt->>'observationId'
     or (v_latest#>>'{observationPayload,height_inches}')::numeric <> 8 then
    raise exception 'stale source observation was not recoverable before clarification: %', v_latest;
  end if;

  v_fresh_receipt := reality.record_resource_observation_service_v1(
    v_grounds_resource_id, 'surface_height_v1',
    jsonb_build_object(
      'height_inches', 4,
      'measurement_method', 'visual_estimate',
      'fixture_semantic', 'fresh_after_clarification'
    ),
    'fixture-observer:' || v_suffix, v_fresh_at,
    'fixture:elm:grounds:observation:fresh:' || v_suffix,
    v_observer_entity_id,
    jsonb_build_object('fixture', 'elm_grounds_v1', 'sequence', 2)
  );
  if v_fresh_receipt->>'state' <> 'admitted' then
    raise exception 'Elm fresh Grounds observation admission failed: %', v_fresh_receipt;
  end if;

  v_latest := reality.resolve_resource_observation_latest_v1(
    v_grounds_resource_id, 'surface_height_v1', now(), clock_timestamp()
  );
  if v_latest->>'state' <> 'established_latest'
     or v_latest->>'observationId' <> v_fresh_receipt->>'observationId'
     or (v_latest#>>'{observationPayload,height_inches}')::numeric <> 4 then
    raise exception 'fresh Grounds observation did not become latest source answer: %', v_latest;
  end if;

  v_historical := reality.resolve_resource_observation_latest_v1(
    v_grounds_resource_id, 'surface_height_v1',
    v_stale_at + interval '1 minute', clock_timestamp()
  );
  if v_historical->>'state' <> 'established_latest'
     or v_historical->>'observationId' <> v_stale_receipt->>'observationId'
     or (v_historical#>>'{observationPayload,height_inches}')::numeric <> 8 then
    raise exception 'fresh clarification incorrectly rewrote earlier Grounds history: %', v_historical;
  end if;

  if (
    select count(*)
      from reality.resource_observations o
     where o.resource_id = v_grounds_resource_id
       and o.observation_type = 'surface_height_v1'
  ) <> 2 then
    raise exception 'Elm fixture expected both stale and fresh Grounds observations to remain canonical';
  end if;

  if not exists (
    select 1
      from reality.resources g
      join reality.resources s on s.id = g.parent_resource_id
     where g.id = v_grounds_resource_id
       and g.owner_entity_id = v_elm_entity_id
       and g.label = 'Grounds'
       and g.resource_kind = 'zone'
       and s.id = v_site_resource_id
       and s.label = 'Elm Farm Site'
  ) then
    raise exception 'Elm Site → Grounds physical hierarchy was not preserved';
  end if;

  if v_has_tasks then
    execute 'select count(*) from atlas.tasks' into v_tasks_after;
    if v_tasks_after <> v_tasks_before then
      raise exception 'Elm Grounds source fixture unexpectedly manufactured atlas.tasks state';
    end if;
  end if;
end;
$$;

rollback;
