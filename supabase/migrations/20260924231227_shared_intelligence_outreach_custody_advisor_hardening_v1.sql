-- Shared Intelligence outreach custody advisor hardening v1.

drop index if exists local_intel.legacy_outreach_targets_archive_v1_person_entity_id_idx1;

create index if not exists legacy_outreach_mapping_org_idx
  on atlas.legacy_local_intel_outreach_target_mappings(organization_id)
  where organization_id is not null;

create index if not exists legacy_outreach_mapping_relationship_org_idx
  on atlas.legacy_local_intel_outreach_target_mappings(organization_id,external_relationship_id)
  where external_relationship_id is not null;

create index if not exists legacy_outreach_mapping_context_org_idx
  on atlas.legacy_local_intel_outreach_target_mappings(organization_id,purpose_context_id)
  where purpose_context_id is not null;

create index if not exists legacy_outreach_mapping_membership_idx
  on atlas.legacy_local_intel_outreach_target_mappings(purpose_context_membership_id)
  where purpose_context_membership_id is not null;

create index if not exists legacy_outreach_mapping_enrichment_idx
  on atlas.legacy_local_intel_outreach_target_mappings(enrichment_target_id)
  where enrichment_target_id is not null;

revoke insert,update,delete
  on table atlas.legacy_local_intel_outreach_target_mappings
  from service_role;

grant select
  on table atlas.legacy_local_intel_outreach_target_mappings
  to service_role;

comment on table atlas.legacy_local_intel_outreach_target_mappings is
  'Immutable one-to-one custody receipt for the retired local_intel.outreach_targets carrier. Runtime roles may read receipts but may not mutate them.';
