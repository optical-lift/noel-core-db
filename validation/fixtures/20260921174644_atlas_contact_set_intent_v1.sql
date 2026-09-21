-- Clone-only pre-migration DML fixture for Atlas Contact-Set Intent v1.
-- The production-shaped clone applies fixtures before the candidate migration,
-- so this file may reference only objects already present in production.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values(
  'f1000000-0000-4000-8000-000000000101'::uuid,
  'validation-contact-set-intent-org-v1',
  'Validation Contact Intent Organization',
  'active',
  'new',
  '{"validationFixture":true}'::jsonb
);
