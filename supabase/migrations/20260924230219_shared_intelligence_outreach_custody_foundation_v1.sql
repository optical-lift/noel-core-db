-- Shared Intelligence outreach custody foundation v1.
-- Separates universal external-world truth from Organization-private concepts.

alter table local_intel.entity_enrichment_targets
  drop constraint if exists entity_enrichment_targets_target_kind_check;

alter table local_intel.entity_enrichment_targets
  add constraint entity_enrichment_targets_target_kind_check
  check (target_kind = any (array[
    'classification'::text,
    'official_site_contact'::text,
    'leadership_people'::text,
    'public_professional_email'::text,
    'employer_resolution'::text,
    'role_detail'::text,
    'exact_address_geocode'::text,
    'relationship_enrichment'::text,
    'hierarchy_resolution'::text,
    'contact_validation'::text,
    'human_use_affordance'::text,
    'availability_refresh'::text,
    'source_acquisition'::text,
    'fact_verification'::text
  ]));

comment on column local_intel.entity_enrichment_targets.target_kind is
  'Universal Shared Intelligence research/enrichment question kind. Organization-specific campaigns, outreach ideas, priorities, and use concepts belong in Atlas Organization purpose/context overlays.';

create table local_intel.legacy_outreach_targets_archive_v1
  (like local_intel.outreach_targets including all);

alter table local_intel.legacy_outreach_targets_archive_v1
  add column archived_at timestamptz not null default now(),
  add column archive_reason text not null default 'mixed_custody_retirement';

insert into local_intel.legacy_outreach_targets_archive_v1(
  id,entity_id,target_kind,rationale,proposed_format,proposed_window,priority,status,
  contact_name,contact_email,contact_phone,source_id,notes,metadata,created_at,updated_at,
  person_entity_id,contact_point_id,archived_at,archive_reason
)
select
  id,entity_id,target_kind,rationale,proposed_format,proposed_window,priority,status,
  contact_name,contact_email,contact_phone,source_id,notes,metadata,created_at,updated_at,
  person_entity_id,contact_point_id,now(),'mixed_custody_retirement'
from local_intel.outreach_targets;

alter table local_intel.legacy_outreach_targets_archive_v1 enable row level security;
revoke all on table local_intel.legacy_outreach_targets_archive_v1 from public,anon,authenticated;
grant select on table local_intel.legacy_outreach_targets_archive_v1 to service_role;

comment on table local_intel.legacy_outreach_targets_archive_v1 is
  'Historical copy of retired mixed-custody outreach-target rows. This table is provenance only, not a live contact, outreach, research, or identity authority.';

create table atlas.legacy_local_intel_outreach_target_mappings (
  id uuid primary key default gen_random_uuid(),
  legacy_outreach_target_id uuid not null unique
    references local_intel.legacy_outreach_targets_archive_v1(id) on delete restrict,
  disposition text not null
    check (disposition in ('organization_purpose_context','shared_intelligence_enrichment')),
  organization_id uuid null references atlas.organizations(id) on delete restrict,
  external_relationship_id uuid null,
  purpose_context_id uuid null,
  purpose_context_membership_id uuid null
    references atlas.organization_purpose_context_memberships(id) on delete restrict,
  enrichment_target_id uuid null references local_intel.entity_enrichment_targets(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint legacy_outreach_mapping_relationship_org_fk
    foreign key (organization_id,external_relationship_id)
    references atlas.external_relationships(organization_id,id)
    on delete restrict,
  constraint legacy_outreach_mapping_context_org_fk
    foreign key (organization_id,purpose_context_id)
    references atlas.organization_purpose_contexts(organization_id,id)
    on delete restrict,
  constraint legacy_outreach_mapping_shape_ck check (
    (
      disposition='organization_purpose_context'
      and organization_id is not null
      and external_relationship_id is not null
      and purpose_context_id is not null
      and purpose_context_membership_id is not null
      and enrichment_target_id is null
    )
    or
    (
      disposition='shared_intelligence_enrichment'
      and organization_id is null
      and external_relationship_id is null
      and purpose_context_id is null
      and purpose_context_membership_id is null
      and enrichment_target_id is not null
    )
  )
);

create index legacy_outreach_mapping_disposition_idx
  on atlas.legacy_local_intel_outreach_target_mappings(disposition,created_at);

alter table atlas.legacy_local_intel_outreach_target_mappings enable row level security;
revoke all on table atlas.legacy_local_intel_outreach_target_mappings from public,anon,authenticated;
grant select,insert,update,delete on table atlas.legacy_local_intel_outreach_target_mappings to service_role;

comment on table atlas.legacy_local_intel_outreach_target_mappings is
  'Migration receipt for retiring local_intel.outreach_targets. Every legacy row maps either to an Organization-private purpose concept or to universal Shared Intelligence research.';

create or replace function atlas.record_entity_purpose_concept_service_v1(
  p_organization_id uuid,
  p_entity_id uuid,
  p_context_stable_key text,
  p_context_kind text,
  p_context_title text,
  p_context_description text default null,
  p_concept_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null,
  p_organization_unit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_context jsonb;
  v_attach jsonb;
  v_membership jsonb;
  v_context_id uuid;
  v_relationship_id uuid;
begin
  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Concept payload and provenance must be JSON objects.' using errcode='22023';
  end if;

  v_context := atlas.create_purpose_context_service_v1(
    p_organization_id=>p_organization_id,
    p_stable_key=>p_context_stable_key,
    p_context_kind=>p_context_kind,
    p_title=>p_context_title,
    p_description=>p_context_description,
    p_metadata=>jsonb_build_object(
      'custody','organization_private',
      'identityAuthority','shared_intelligence',
      'conceptCarrier','purpose_context'
    ),
    p_created_by_membership_id=>p_created_by_membership_id
  );

  v_context_id := nullif(v_context->>'contextId','')::uuid;

  v_attach := atlas.attach_shared_directory_entity_service_v1(
    p_organization_id=>p_organization_id,
    p_entity_id=>p_entity_id,
    p_role_key=>'contact',
    p_organization_unit_id=>p_organization_unit_id
  );

  v_relationship_id := nullif(v_attach->>'externalRelationshipId','')::uuid;

  if v_context_id is null or v_relationship_id is null then
    raise exception 'Could not establish Organization-private concept binding.' using errcode='P0001';
  end if;

  v_membership := atlas.add_external_relationship_to_purpose_context_service_v1(
    p_organization_id=>p_organization_id,
    p_context_id=>v_context_id,
    p_external_relationship_id=>v_relationship_id,
    p_role_keys=>coalesce(p_concept_role_keys,'{}'::text[]),
    p_payload=>coalesce(p_payload,'{}'::jsonb),
    p_provenance=>coalesce(p_provenance,'{}'::jsonb)
      || jsonb_build_object(
        'canonicalEntityId',p_entity_id,
        'custody','organization_private_concept'
      ),
    p_created_by_membership_id=>p_created_by_membership_id
  );

  return jsonb_build_object(
    'contractVersion','entity_purpose_concept_v1',
    'organizationId',p_organization_id,
    'canonicalEntityId',p_entity_id,
    'externalRelationshipId',v_relationship_id,
    'contextId',v_context_id,
    'membershipId',nullif(v_membership->>'membershipId','')::uuid,
    'identityDisposition','canonical_shared_identity_with_private_organization_concept'
  );
end
$function$;

create or replace function atlas.record_entity_purpose_concept_self_api_v1(
  p_organization_id uuid,
  p_entity_id uuid,
  p_context_stable_key text,
  p_context_kind text,
  p_context_title text,
  p_context_description text default null,
  p_concept_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_organization_unit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  v_membership_id := atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.record_entity_purpose_concept_service_v1(
    p_organization_id=>p_organization_id,
    p_entity_id=>p_entity_id,
    p_context_stable_key=>p_context_stable_key,
    p_context_kind=>p_context_kind,
    p_context_title=>p_context_title,
    p_context_description=>p_context_description,
    p_concept_role_keys=>p_concept_role_keys,
    p_payload=>p_payload,
    p_provenance=>p_provenance,
    p_created_by_membership_id=>v_membership_id,
    p_organization_unit_id=>p_organization_unit_id
  );
end
$function$;

revoke all on function atlas.record_entity_purpose_concept_service_v1(
  uuid,uuid,text,text,text,text,text[],jsonb,jsonb,uuid,uuid
) from public,anon,authenticated;
grant execute on function atlas.record_entity_purpose_concept_service_v1(
  uuid,uuid,text,text,text,text,text[],jsonb,jsonb,uuid,uuid
) to service_role;

revoke all on function atlas.record_entity_purpose_concept_self_api_v1(
  uuid,uuid,text,text,text,text,text[],jsonb,jsonb,uuid
) from public,anon;
grant execute on function atlas.record_entity_purpose_concept_self_api_v1(
  uuid,uuid,text,text,text,text,text[],jsonb,jsonb,uuid
) to authenticated;

comment on function atlas.record_entity_purpose_concept_service_v1(
  uuid,uuid,text,text,text,text,text[],jsonb,jsonb,uuid,uuid
) is
  'Records one Atlas Organization-private concept/use about one canonical Shared Intelligence entity. Concept payload remains Organization-private and never becomes canonical Shared Intelligence truth.';
