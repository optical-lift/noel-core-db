-- Atlas Capability Kernel v1
-- Durable reusable organizational capability truth.
-- Canonical DB authority: optical-lift/noel-core-db.

begin;

create table atlas.capabilities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  stable_key text not null,
  display_name text not null,
  capability_kind text null,
  purpose_summary text null,
  lifecycle_state text not null default 'draft'
    check (lifecycle_state in ('draft','active','retired')),
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  established_at timestamptz null,
  retired_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint capabilities_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capabilities_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint capabilities_retired_accounting check (
    (lifecycle_state = 'retired' and retired_at is not null)
    or (lifecycle_state <> 'retired' and retired_at is null)
  ),
  unique (organization_id, stable_key)
);

comment on table atlas.capabilities is
  'Durable organization-owned reusable ability. A Capability is not an occurrence, task, person, asset, location, or result.';

create index capabilities_org_lifecycle_idx
  on atlas.capabilities (organization_id, lifecycle_state);

create table atlas.capability_variants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  capability_id uuid not null references atlas.capabilities(id),
  stable_key text not null,
  display_name text not null,
  lifecycle_state text not null default 'draft'
    check (lifecycle_state in ('draft','active','retired')),
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz null,
  constraint capability_variants_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capability_variants_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint capability_variants_retired_accounting check (
    (lifecycle_state = 'retired' and retired_at is not null)
    or (lifecycle_state <> 'retired' and retired_at is null)
  ),
  unique (capability_id, stable_key)
);

comment on table atlas.capability_variants is
  'Governed reusable alternate form of a Capability. One-off execution drift does not become a Variant automatically.';

create index capability_variants_capability_idx
  on atlas.capability_variants (capability_id, lifecycle_state);

create table atlas.capability_deployments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  capability_id uuid not null references atlas.capabilities(id),
  variant_id uuid null references atlas.capability_variants(id),
  organization_unit_id uuid null references atlas.organization_units(id),
  stable_key text not null,
  display_name text not null,
  lifecycle_state text not null default 'draft'
    check (lifecycle_state in ('draft','active','retired')),
  configuration jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz null,
  constraint capability_deployments_configuration_object check (jsonb_typeof(configuration) = 'object'),
  constraint capability_deployments_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capability_deployments_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint capability_deployments_retired_accounting check (
    (lifecycle_state = 'retired' and retired_at is not null)
    or (lifecycle_state <> 'retired' and retired_at is null)
  ),
  unique (capability_id, stable_key)
);

comment on table atlas.capability_deployments is
  'Durable embodiment of a Capability in an organization unit or other durable local operating context. Transient execution locations do not automatically become Deployments.';

create index capability_deployments_capability_idx
  on atlas.capability_deployments (capability_id, lifecycle_state);
create index capability_deployments_unit_idx
  on atlas.capability_deployments (organization_unit_id)
  where organization_unit_id is not null;

create table atlas.capability_attribute_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  stable_key text not null,
  display_name text not null,
  value_type text not null
    check (value_type in ('boolean','integer','decimal','text','enum','duration_minutes')),
  allowed_values jsonb not null default '[]'::jsonb,
  unit text null,
  searchable boolean not null default true,
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint capability_attribute_definitions_allowed_values_array check (jsonb_typeof(allowed_values) = 'array'),
  constraint capability_attribute_definitions_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint capability_attribute_definitions_enum_values check (
    value_type <> 'enum' or jsonb_array_length(allowed_values) > 0
  ),
  unique (organization_id, stable_key)
);

comment on table atlas.capability_attribute_definitions is
  'Organization-scoped governed typed descriptors for Capability discovery/suitability. Operational blockers belong in explicit requirements, not only attributes.';

create table atlas.capability_attribute_values (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  attribute_definition_id uuid not null references atlas.capability_attribute_definitions(id),
  capability_id uuid null references atlas.capabilities(id),
  variant_id uuid null references atlas.capability_variants(id),
  deployment_id uuid null references atlas.capability_deployments(id),
  value jsonb not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint capability_attribute_values_exactly_one_target check (
    ((capability_id is not null)::integer + (variant_id is not null)::integer + (deployment_id is not null)::integer) = 1
  ),
  constraint capability_attribute_values_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capability_attribute_values_metadata_object check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.capability_attribute_values is
  'Typed attribute values bound to exactly one Capability, Variant, or Deployment. V1 values are single-valued per governed definition and target.';

create index capability_attribute_values_definition_idx
  on atlas.capability_attribute_values (attribute_definition_id);
create index capability_attribute_values_capability_idx
  on atlas.capability_attribute_values (capability_id)
  where capability_id is not null;
create index capability_attribute_values_variant_idx
  on atlas.capability_attribute_values (variant_id)
  where variant_id is not null;
create index capability_attribute_values_deployment_idx
  on atlas.capability_attribute_values (deployment_id)
  where deployment_id is not null;

create unique index capability_attribute_values_capability_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, capability_id)
  where capability_id is not null and variant_id is null and deployment_id is null;
create unique index capability_attribute_values_variant_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, variant_id)
  where capability_id is null and variant_id is not null and deployment_id is null;
create unique index capability_attribute_values_deployment_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, deployment_id)
  where capability_id is null and variant_id is null and deployment_id is not null;

create table atlas.capability_requirements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  capability_id uuid null references atlas.capabilities(id),
  variant_id uuid null references atlas.capability_variants(id),
  deployment_id uuid null references atlas.capability_deployments(id),
  requirement_kind text not null
    check (requirement_kind in (
      'staffing','skill_or_certification','equipment','material','inventory',
      'location','environment','time_or_season','audience','authorization',
      'dependency','safety_control','financial_or_resource_approval','source_data'
    )),
  stable_key text not null,
  summary text not null,
  resolver_kind text not null default 'manual_or_external'
    check (resolver_kind in ('manual_or_external','organization_unit','company_operating_knowledge','capability_dependency')),
  resolver_config jsonb not null default '{}'::jsonb,
  severity text not null default 'required'
    check (severity in ('advisory','required','blocking','safety_critical')),
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','retired')),
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint capability_requirements_exactly_one_target check (
    ((capability_id is not null)::integer + (variant_id is not null)::integer + (deployment_id is not null)::integer) = 1
  ),
  constraint capability_requirements_resolver_config_object check (jsonb_typeof(resolver_config) = 'object'),
  constraint capability_requirements_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capability_requirements_metadata_object check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.capability_requirements is
  'Conditions that must be satisfied for valid Capability execution. Requirement satisfaction is derived from owning authorities; this table does not persist a mutable readiness boolean.';

create index capability_requirements_capability_idx
  on atlas.capability_requirements (capability_id, lifecycle_state)
  where capability_id is not null;
create index capability_requirements_variant_idx
  on atlas.capability_requirements (variant_id, lifecycle_state)
  where variant_id is not null;
create index capability_requirements_deployment_idx
  on atlas.capability_requirements (deployment_id, lifecycle_state)
  where deployment_id is not null;

create unique index capability_requirements_capability_stable_key_unique_idx
  on atlas.capability_requirements (capability_id, stable_key)
  where capability_id is not null and variant_id is null and deployment_id is null;
create unique index capability_requirements_variant_stable_key_unique_idx
  on atlas.capability_requirements (variant_id, stable_key)
  where capability_id is null and variant_id is not null and deployment_id is null;
create unique index capability_requirements_deployment_stable_key_unique_idx
  on atlas.capability_requirements (deployment_id, stable_key)
  where capability_id is null and variant_id is null and deployment_id is not null;

create table atlas.capability_knowledge_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  knowledge_id uuid not null references atlas.company_operating_knowledge(id),
  capability_id uuid null references atlas.capabilities(id),
  variant_id uuid null references atlas.capability_variants(id),
  deployment_id uuid null references atlas.capability_deployments(id),
  binding_role text not null
    check (binding_role in ('governs','supports','qualifies','safety','completion','local_override')),
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint capability_knowledge_bindings_exactly_one_target check (
    ((capability_id is not null)::integer + (variant_id is not null)::integer + (deployment_id is not null)::integer) = 1
  ),
  constraint capability_knowledge_bindings_metadata_object check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.capability_knowledge_bindings is
  'Explicit binding from Capability truth to Company Operating Knowledge. Knowledge remains authoritative in atlas.company_operating_knowledge.';

create index capability_knowledge_bindings_knowledge_idx
  on atlas.capability_knowledge_bindings (knowledge_id)
  where active;

create unique index capability_knowledge_bindings_capability_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, capability_id, binding_role)
  where capability_id is not null and variant_id is null and deployment_id is null;
create unique index capability_knowledge_bindings_variant_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, variant_id, binding_role)
  where capability_id is null and variant_id is not null and deployment_id is null;
create unique index capability_knowledge_bindings_deployment_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, deployment_id, binding_role)
  where capability_id is null and variant_id is null and deployment_id is not null;

create table atlas.capability_relations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  from_capability_id uuid not null references atlas.capabilities(id),
  to_capability_id uuid not null references atlas.capabilities(id),
  relation_kind text not null
    check (relation_kind in (
      'depends_on','precedes','follows','pairs_with','complements',
      'substitutes_for','conflicts_with','enables'
    )),
  active boolean not null default true,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint capability_relations_distinct_nodes check (from_capability_id <> to_capability_id),
  constraint capability_relations_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint capability_relations_metadata_object check (jsonb_typeof(metadata) = 'object'),
  unique (from_capability_id, to_capability_id, relation_kind)
);

comment on table atlas.capability_relations is
  'Typed reusable relationships among Capabilities. These relations do not themselves create scheduling, assignment, or Work.';

create index capability_relations_from_idx
  on atlas.capability_relations (organization_id, from_capability_id)
  where active;
create index capability_relations_to_idx
  on atlas.capability_relations (organization_id, to_capability_id)
  where active;

create or replace function atlas.guard_capability_scope_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
declare
  v_org uuid;
  v_capability uuid;
begin
  if tg_table_name = 'capability_variants' then
    select organization_id into v_org from atlas.capabilities where id = new.capability_id;
    if v_org is null or v_org <> new.organization_id then
      raise exception 'Capability Variant must belong to the same organization as its Capability';
    end if;
    return new;
  end if;

  if tg_table_name = 'capability_deployments' then
    select organization_id into v_org from atlas.capabilities where id = new.capability_id;
    if v_org is null or v_org <> new.organization_id then
      raise exception 'Capability Deployment must belong to the same organization as its Capability';
    end if;
    if new.variant_id is not null then
      select organization_id, capability_id into v_org, v_capability
      from atlas.capability_variants where id = new.variant_id;
      if v_org is null or v_org <> new.organization_id or v_capability <> new.capability_id then
        raise exception 'Capability Deployment Variant must belong to the same organization and Capability';
      end if;
    end if;
    if new.organization_unit_id is not null and not exists (
      select 1 from atlas.organization_units u
      where u.id = new.organization_unit_id and u.organization_id = new.organization_id
    ) then
      raise exception 'Capability Deployment organization unit must belong to the same organization';
    end if;
    return new;
  end if;

  if tg_table_name = 'capability_attribute_values' then
    if not exists (
      select 1 from atlas.capability_attribute_definitions d
      where d.id = new.attribute_definition_id and d.organization_id = new.organization_id
    ) then
      raise exception 'Capability attribute definition must belong to the same organization';
    end if;
  end if;

  if tg_table_name in ('capability_attribute_values','capability_requirements','capability_knowledge_bindings') then
    if new.capability_id is not null and not exists (
      select 1 from atlas.capabilities c where c.id = new.capability_id and c.organization_id = new.organization_id
    ) then
      raise exception '% Capability target must belong to the same organization', tg_table_name;
    end if;
    if new.variant_id is not null and not exists (
      select 1 from atlas.capability_variants v where v.id = new.variant_id and v.organization_id = new.organization_id
    ) then
      raise exception '% Variant target must belong to the same organization', tg_table_name;
    end if;
    if new.deployment_id is not null and not exists (
      select 1 from atlas.capability_deployments d where d.id = new.deployment_id and d.organization_id = new.organization_id
    ) then
      raise exception '% Deployment target must belong to the same organization', tg_table_name;
    end if;
    if tg_table_name = 'capability_knowledge_bindings' and not exists (
      select 1 from atlas.company_operating_knowledge k where k.id = new.knowledge_id and k.organization_id = new.organization_id
    ) then
      raise exception 'Capability Knowledge binding must remain inside one organization';
    end if;
    return new;
  end if;

  if tg_table_name = 'capability_relations' then
    if not exists (
      select 1 from atlas.capabilities c where c.id = new.from_capability_id and c.organization_id = new.organization_id
    ) or not exists (
      select 1 from atlas.capabilities c where c.id = new.to_capability_id and c.organization_id = new.organization_id
    ) then
      raise exception 'Capability relation endpoints must belong to the same organization';
    end if;
    return new;
  end if;

  return new;
end;
$$;

create trigger capability_variants_scope_guard
before insert or update on atlas.capability_variants
for each row execute function atlas.guard_capability_scope_v1();

create trigger capability_deployments_scope_guard
before insert or update on atlas.capability_deployments
for each row execute function atlas.guard_capability_scope_v1();

create trigger capability_attribute_values_scope_guard
before insert or update on atlas.capability_attribute_values
for each row execute function atlas.guard_capability_scope_v1();

create trigger capability_requirements_scope_guard
before insert or update on atlas.capability_requirements
for each row execute function atlas.guard_capability_scope_v1();

create trigger capability_knowledge_bindings_scope_guard
before insert or update on atlas.capability_knowledge_bindings
for each row execute function atlas.guard_capability_scope_v1();

create trigger capability_relations_scope_guard
before insert or update on atlas.capability_relations
for each row execute function atlas.guard_capability_scope_v1();

create or replace function atlas.validate_capability_attribute_value_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
declare
  v_type text;
  v_allowed jsonb;
begin
  select value_type, allowed_values into v_type, v_allowed
  from atlas.capability_attribute_definitions
  where id = new.attribute_definition_id;

  if v_type = 'boolean' and jsonb_typeof(new.value) <> 'boolean' then
    raise exception 'boolean Capability attribute requires JSON boolean';
  elsif v_type = 'integer' and (
    jsonb_typeof(new.value) <> 'number' or (new.value #>> '{}') !~ '^-?[0-9]+$'
  ) then
    raise exception 'integer Capability attribute requires JSON integer';
  elsif v_type = 'decimal' and jsonb_typeof(new.value) <> 'number' then
    raise exception 'decimal Capability attribute requires JSON number';
  elsif v_type = 'text' and jsonb_typeof(new.value) <> 'string' then
    raise exception 'text Capability attribute requires JSON string';
  elsif v_type = 'duration_minutes' and (
    jsonb_typeof(new.value) <> 'number' or (new.value #>> '{}') !~ '^[0-9]+$'
  ) then
    raise exception 'duration_minutes Capability attribute requires non-negative integer minutes';
  elsif v_type = 'enum' and (
    jsonb_typeof(new.value) <> 'string' or not (v_allowed ? (new.value #>> '{}'))
  ) then
    raise exception 'enum Capability attribute value must be one of the governed allowed values';
  end if;

  return new;
end;
$$;

create trigger capability_attribute_value_type_guard
before insert or update on atlas.capability_attribute_values
for each row execute function atlas.validate_capability_attribute_value_v1();

-- Capability remains server-owned until governed user APIs are explicitly admitted.
revoke all on table atlas.capabilities from anon, authenticated;
revoke all on table atlas.capability_variants from anon, authenticated;
revoke all on table atlas.capability_deployments from anon, authenticated;
revoke all on table atlas.capability_attribute_definitions from anon, authenticated;
revoke all on table atlas.capability_attribute_values from anon, authenticated;
revoke all on table atlas.capability_requirements from anon, authenticated;
revoke all on table atlas.capability_knowledge_bindings from anon, authenticated;
revoke all on table atlas.capability_relations from anon, authenticated;

grant select, insert, update, delete on table atlas.capabilities to service_role;
grant select, insert, update, delete on table atlas.capability_variants to service_role;
grant select, insert, update, delete on table atlas.capability_deployments to service_role;
grant select, insert, update, delete on table atlas.capability_attribute_definitions to service_role;
grant select, insert, update, delete on table atlas.capability_attribute_values to service_role;
grant select, insert, update, delete on table atlas.capability_requirements to service_role;
grant select, insert, update, delete on table atlas.capability_knowledge_bindings to service_role;
grant select, insert, update, delete on table atlas.capability_relations to service_role;

commit;
