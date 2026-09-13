-- Data-only fixture for Atlas Teaching Academic Kernel v1 candidate.
-- Production-schema validation restores schema but not production data, so this fixture
-- also restores the Gate A Teaching v1 definition that Gate B depends on.

insert into auth.users(id) values
  ('d1100000-0000-4000-8000-000000000001'::uuid),
  ('e1100000-0000-4000-8000-000000000001'::uuid),
  ('f1100000-0000-4000-8000-000000000001'::uuid),
  ('f1200000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('d1100000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Root','active','{"validation_fixture":true}'::jsonb),
  ('e1100000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Org Owner','active','{"validation_fixture":true}'::jsonb),
  ('f1100000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Learner One','active','{"validation_fixture":true}'::jsonb),
  ('f1200000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Learner Two','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('d1100000-0000-4000-8000-000000000021'::uuid,'d1100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','d1100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('e1100000-0000-4000-8000-000000000021'::uuid,'e1100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','e1100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('f1100000-0000-4000-8000-000000000021'::uuid,'f1100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','f1100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('f1200000-0000-4000-8000-000000000021'::uuid,'f1200000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','f1200000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values
  ('d1100000-0000-4000-8000-000000000031'::uuid,'d1100000-0000-4000-8000-000000000001'::uuid,null,'teaching_fixture_principal_root','Teaching Fixture Root','America/Chicago','active','{"validation_fixture":true}'::jsonb,'d1100000-0000-4000-8000-000000000011'::uuid),
  ('e1100000-0000-4000-8000-000000000031'::uuid,'e1100000-0000-4000-8000-000000000001'::uuid,null,'teaching_fixture_principal_owner','Teaching Fixture Org Owner','America/Chicago','active','{"validation_fixture":true}'::jsonb,'e1100000-0000-4000-8000-000000000011'::uuid);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values
  ('d1200000-0000-4000-8000-000000000001'::uuid,'teachingfixtureledgerroot000001','Teaching Fixture Governed Ledger',null,'governed_reality','active','{"validation_fixture":true}'::jsonb),
  ('e1200000-0000-4000-8000-000000000001'::uuid,'teachingfixtureledgerother00001','Teaching Fixture Other Ledger',null,'governed_reality','active','{"validation_fixture":true}'::jsonb);

insert into atlas.capability_definitions(capability_key,capability_version,status,eligible_subject_kinds)
values ('teaching',1,'active',array['ledger']::text[]);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values
  ('d1300000-0000-4000-8000-000000000001'::uuid,'d1100000-0000-4000-8000-000000000031'::uuid,'d1200000-0000-4000-8000-000000000001'::uuid,'root_governing','active','teaching_academic_kernel_validation','{"validation_fixture":true}'::jsonb),
  ('e1300000-0000-4000-8000-000000000001'::uuid,'e1100000-0000-4000-8000-000000000031'::uuid,'e1200000-0000-4000-8000-000000000001'::uuid,'root_governing','active','teaching_academic_kernel_validation','{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values (
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'teaching_fixture_org_owner',
  'Teaching Fixture Organization',
  'active','{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'e1400000-0000-4000-8000-000000000011'::uuid,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'governing',false,'active','{"source":"teaching_academic_kernel_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions,person_id
) values (
  'e1400000-0000-4000-8000-000000000021'::uuid,
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'e1100000-0000-4000-8000-000000000001'::uuid,
  'owner',true,'{}'::jsonb,
  'e1100000-0000-4000-8000-000000000011'::uuid
);