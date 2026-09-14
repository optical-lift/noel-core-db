-- Data-only fixture for Organization Ledger entry coordinate v1.
-- Run only in a disposable production-schema clone before the candidate migration.

insert into auth.users(id) values
  ('c2100000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('c2100000-0000-4000-8000-000000000011'::uuid,'Organization Ledger Coordinate Fixture Owner','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values (
  'c2100000-0000-4000-8000-000000000021'::uuid,
  'c2100000-0000-4000-8000-000000000011'::uuid,
  'supabase_auth_user',
  'c2100000-0000-4000-8000-000000000001'::uuid,
  'active',now(),'{"validation_fixture":true}'::jsonb
);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values (
  'c2200000-0000-4000-8000-000000000001'::uuid,
  'orgledgercoordinatefixture01',
  'Organization Ledger Coordinate Fixture Ledger',
  null,'governed_reality','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values (
  'c2400000-0000-4000-8000-000000000001'::uuid,
  'organization_ledger_coordinate_fixture_org',
  'Organization Ledger Coordinate Fixture Organization',
  'active','{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'c2400000-0000-4000-8000-000000000011'::uuid,
  'c2200000-0000-4000-8000-000000000001'::uuid,
  'c2400000-0000-4000-8000-000000000001'::uuid,
  'governing',false,'active','{"source":"organization_ledger_coordinate_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,person_id,role,active,permissions
) values (
  'c2400000-0000-4000-8000-000000000021'::uuid,
  'c2400000-0000-4000-8000-000000000001'::uuid,
  'c2100000-0000-4000-8000-000000000001'::uuid,
  'c2100000-0000-4000-8000-000000000011'::uuid,
  'owner',true,'{}'::jsonb
);

insert into atlas.organization_ledger_entries(
  id,organization_id,event_key,source_domain,semantic_type,source_event_key,
  occurred_at,title,detail,truth_status,designation_status,payload,provenance,correlation,ledger_id
) values (
  'c2500000-0000-4000-8000-000000000001'::uuid,
  'c2400000-0000-4000-8000-000000000001'::uuid,
  'coordinate-proof-entry','validation','coordinate_proof','coordinate-proof-source',
  '2026-09-13 20:00:00-05'::timestamptz,
  'Coordinate proof entry','Proves the browser projection receives the exact governing Ledger UUID.',
  'established','designated','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb,'{}'::jsonb,
  'c2200000-0000-4000-8000-000000000001'::uuid
);
