-- Rollback-only fixture for Shared Intelligence universal acquisition.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values
('f2000000-0000-4000-8000-000000000101'::uuid,'validation-universal-acq-org-a','Validation Universal Acquisition A','active','new','{"validationFixture":true}'::jsonb),
('f2000000-0000-4000-8000-000000000102'::uuid,'validation-universal-acq-org-b','Validation Universal Acquisition B','active','new','{"validationFixture":true}'::jsonb);

insert into local_intel.local_contexts(id,stable_key,organization_id,name,status,metadata)
values
('f2000000-0000-4000-8000-000000000111'::uuid,'validation-universal-acq-context-a','f2000000-0000-4000-8000-000000000101'::uuid,'Validation Context A','active','{"validationFixture":true}'::jsonb),
('f2000000-0000-4000-8000-000000000112'::uuid,'validation-universal-acq-context-b','f2000000-0000-4000-8000-000000000102'::uuid,'Validation Context B','active','{"validationFixture":true}'::jsonb);

insert into local_intel.entities(
  id,stable_key,entity_type,name,website_url,status,verification_state,metadata,local_context_id
) values
(
  'f2000000-0000-4000-8000-000000000121'::uuid,
  'validation-universal-acq-business-one',
  'business',
  'Validation One Copy Bank',
  'https://one-copy-bank.example.invalid',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f2000000-0000-4000-8000-000000000111'::uuid
),
(
  'f2000000-0000-4000-8000-000000000122'::uuid,
  'validation-universal-acq-business-two',
  'business',
  'Validation Second Canonical Bank',
  'https://second-canonical-bank.example.invalid',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f2000000-0000-4000-8000-000000000111'::uuid
);

insert into local_intel.sources(
  id,source_url,source_kind,publisher,title,metadata
) values (
  'f2000000-0000-4000-8000-000000000131'::uuid,
  'https://source.example.invalid/universal-acquisition',
  'official_website',
  'Validation Publisher',
  'Validation Universal Acquisition Source',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.search_queries(
  id,local_context_id,query_text,requested_fields,parameters,status,metadata
) values (
  'f2000000-0000-4000-8000-000000000141'::uuid,
  'f2000000-0000-4000-8000-000000000112'::uuid,
  'find email for validation bank',
  array['email']::text[],
  '{"validationFixture":true}'::jsonb,
  'in_process',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.ingestion_sources(
  id,source_id,source_role,status,ingestion_priority,metadata
) values (
  'f2000000-0000-4000-8000-000000000151'::uuid,
  'f2000000-0000-4000-8000-000000000131'::uuid,
  'organization_directory',
  'active',
  50,
  '{"validationFixture":true}'::jsonb
);
