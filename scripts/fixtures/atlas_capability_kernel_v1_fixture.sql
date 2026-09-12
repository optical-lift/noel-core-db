-- Atlas Capability Kernel v1 disposable fixture
-- Proves Capability -> Variant -> Deployment -> typed attribute -> Requirement -> COK binding -> relation.
-- This script MUST roll back; it leaves no synthetic Capability truth behind.

begin;

do $$
declare
  v_org uuid;
  v_unit uuid;
  v_capability uuid;
  v_related_capability uuid;
  v_variant uuid;
  v_deployment uuid;
  v_attribute_definition uuid;
  v_knowledge uuid;
  v_count bigint;
begin
  select id into v_org
  from atlas.organizations
  order by id
  limit 1;

  if v_org is null then
    raise exception 'Capability fixture requires at least one organization';
  end if;

  select id into v_unit
  from atlas.organization_units
  where organization_id = v_org
  order by id
  limit 1;

  insert into atlas.capabilities (
    organization_id, stable_key, display_name, capability_kind,
    purpose_summary, lifecycle_state, established_at, provenance, metadata
  ) values (
    v_org,
    'fixture-facilitate-washers',
    'Fixture: Facilitate Washers',
    'activity',
    'Rollback-safe proof of the universal Capability kernel.',
    'active',
    now(),
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  ) returning id into v_capability;

  insert into atlas.capabilities (
    organization_id, stable_key, display_name, capability_kind,
    lifecycle_state, established_at, provenance, metadata
  ) values (
    v_org,
    'fixture-facilitate-related-activity',
    'Fixture: Facilitate Related Activity',
    'activity',
    'active',
    now(),
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  ) returning id into v_related_capability;

  insert into atlas.capability_variants (
    organization_id, capability_id, stable_key, display_name,
    lifecycle_state, provenance, metadata
  ) values (
    v_org,
    v_capability,
    'fixture-standard-rules',
    'Fixture: Standard Rules',
    'active',
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  ) returning id into v_variant;

  insert into atlas.capability_deployments (
    organization_id, capability_id, variant_id, organization_unit_id,
    stable_key, display_name, lifecycle_state,
    configuration, provenance, metadata
  ) values (
    v_org,
    v_capability,
    v_variant,
    v_unit,
    'fixture-washers-local-deployment',
    'Fixture: Washers Local Deployment',
    'active',
    jsonb_build_object('surface', 'outdoor'),
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  ) returning id into v_deployment;

  insert into atlas.capability_attribute_definitions (
    organization_id, stable_key, display_name, value_type,
    allowed_values, lifecycle_state, metadata
  ) values (
    v_org,
    'fixture-day-night-suitability',
    'Fixture: Day/Night Suitability',
    'enum',
    '["day","night","both"]'::jsonb,
    'active',
    jsonb_build_object('fixture', true)
  ) returning id into v_attribute_definition;

  insert into atlas.capability_attribute_values (
    organization_id, attribute_definition_id, deployment_id,
    value, provenance, metadata
  ) values (
    v_org,
    v_attribute_definition,
    v_deployment,
    '"both"'::jsonb,
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  );

  insert into atlas.capability_requirements (
    organization_id, deployment_id, requirement_kind, stable_key,
    summary, resolver_kind, resolver_config, severity,
    lifecycle_state, provenance, metadata
  ) values (
    v_org,
    v_deployment,
    'environment',
    'fixture-dry-play-surface',
    'Playing surface must be acceptably dry before use.',
    'manual_or_external',
    jsonb_build_object('authority_status', 'not_implemented'),
    'blocking',
    'active',
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  );

  insert into atlas.company_operating_knowledge (
    organization_id, organization_unit_id, family_key, stable_key, version,
    knowledge_kind, title, statement, scope_match, effect,
    precedence, status, established_by_label, established_at,
    provenance, metadata
  ) values (
    v_org,
    v_unit,
    'fixture-washers-method',
    'fixture-washers-method-v1',
    1,
    'procedure',
    'Fixture: Washers setup procedure',
    'Place and verify the game equipment before participants begin.',
    '{}'::jsonb,
    jsonb_build_object('fixture_only', true),
    0,
    'established',
    'atlas_capability_kernel_v1 fixture',
    now(),
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  ) returning id into v_knowledge;

  insert into atlas.capability_knowledge_bindings (
    organization_id, knowledge_id, deployment_id, binding_role, metadata
  ) values (
    v_org,
    v_knowledge,
    v_deployment,
    'governs',
    jsonb_build_object('fixture', true)
  );

  insert into atlas.capability_relations (
    organization_id, from_capability_id, to_capability_id,
    relation_kind, provenance, metadata
  ) values (
    v_org,
    v_capability,
    v_related_capability,
    'pairs_with',
    jsonb_build_object('fixture', 'atlas_capability_kernel_v1'),
    jsonb_build_object('fixture', true)
  );

  select count(*) into v_count
  from atlas.capability_knowledge_bindings b
  join atlas.company_operating_knowledge k on k.id = b.knowledge_id
  where b.deployment_id = v_deployment
    and k.status = 'established'
    and b.active;

  if v_count <> 1 then
    raise exception 'Expected exactly one established Company Operating Knowledge binding, got %', v_count;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'atlas'
      and table_name in ('capabilities','capability_variants','capability_deployments','capability_requirements')
      and column_name in ('is_ready','ready','readiness_state')
  ) then
    raise exception 'Capability kernel must not persist readiness as independent mutable truth';
  end if;

  if not exists (
    select 1
    from atlas.capability_requirements r
    where r.deployment_id = v_deployment
      and r.resolver_kind = 'manual_or_external'
      and r.resolver_config->>'authority_status' = 'not_implemented'
  ) then
    raise exception 'Unsupported environmental resolver must remain explicitly unresolved';
  end if;

  if not exists (
    select 1
    from atlas.capability_relations r
    where r.from_capability_id = v_capability
      and r.to_capability_id = v_related_capability
      and r.relation_kind = 'pairs_with'
      and r.active
  ) then
    raise exception 'Capability relation proof failed';
  end if;
end;
$$;

rollback;
