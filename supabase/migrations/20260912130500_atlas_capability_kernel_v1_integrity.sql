-- Atlas Capability Kernel v1 integrity hardening
-- Keep target bindings relational and unambiguous under PostgreSQL NULL uniqueness semantics.

begin;

create unique index capability_knowledge_bindings_capability_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, capability_id, binding_role)
  where capability_id is not null and variant_id is null and deployment_id is null;

create unique index capability_knowledge_bindings_variant_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, variant_id, binding_role)
  where capability_id is null and variant_id is not null and deployment_id is null;

create unique index capability_knowledge_bindings_deployment_unique_idx
  on atlas.capability_knowledge_bindings (knowledge_id, deployment_id, binding_role)
  where capability_id is null and variant_id is null and deployment_id is not null;

create unique index capability_requirements_capability_stable_key_unique_idx
  on atlas.capability_requirements (capability_id, stable_key)
  where capability_id is not null and variant_id is null and deployment_id is null;

create unique index capability_requirements_variant_stable_key_unique_idx
  on atlas.capability_requirements (variant_id, stable_key)
  where capability_id is null and variant_id is not null and deployment_id is null;

create unique index capability_requirements_deployment_stable_key_unique_idx
  on atlas.capability_requirements (deployment_id, stable_key)
  where capability_id is null and variant_id is null and deployment_id is not null;

-- V1 attributes are single-valued per governed definition and target.
-- A future multi-value contract must be admitted explicitly rather than relying on duplicate rows.
create unique index capability_attribute_values_capability_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, capability_id)
  where capability_id is not null and variant_id is null and deployment_id is null;

create unique index capability_attribute_values_variant_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, variant_id)
  where capability_id is null and variant_id is not null and deployment_id is null;

create unique index capability_attribute_values_deployment_unique_idx
  on atlas.capability_attribute_values (attribute_definition_id, deployment_id)
  where capability_id is null and variant_id is null and deployment_id is not null;

commit;
