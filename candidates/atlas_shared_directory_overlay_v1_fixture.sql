-- DML-only fixture for Atlas Shared Directory / Ledger Overlay v1.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values(
  'f0000000-0000-4000-8000-000000000101'::uuid,
  'validation-shared-directory-org-v1',
  'Validation Shared Directory Organization',
  'active',
  'new',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.local_contexts(id,stable_key,organization_id,name,status,metadata)
values(
  'f0000000-0000-4000-8000-000000000102'::uuid,
  'validation-shared-directory-context-v1',
  'f0000000-0000-4000-8000-000000000101'::uuid,
  'Validation Shared Directory Context',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.entities(
  id,stable_key,entity_type,name,description,website_url,phone,email,
  address_line1,city,state,postal_code,status,verification_state,metadata,local_context_id
) values (
  'f0000000-0000-4000-8000-000000000103'::uuid,
  'validation-shared-directory-entity-v1',
  'organization',
  'Validation Shared Directory Buyer',
  'Clone-only canonical entity for Shared Directory validation.',
  'https://example.invalid/shared-directory-validation',
  '+15555550101',
  'shared-directory-validation@example.invalid',
  '101 Validation Way',
  'Springfield',
  'MO',
  '65806',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f0000000-0000-4000-8000-000000000102'::uuid
);
