-- Data-only fixture for Atlas Teaching Academic Kernel v1 candidate.
-- Assumes production already contains Gate A capability activation v1.

insert into auth.users(id) values
  ('d1000000-0000-4000-8000-000000000001'::uuid),
  ('e1000000-0000-4000-8000-000000000001'::uuid),
  ('f1000000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('d1000000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Root','active','{"validation_fixture":true}'::jsonb),
  ('e1000000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Learner','active','{"validation_fixture":true}'::jsonb),
  ('f1000000-0000-4000-8000-000000000011'::uuid,'Teaching Fixture Outsider','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('d1000000-0000-4000-8000-000000000021'::uuid,'d1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','d1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('e1000000-0000-4000-8000-000000000021'::uuid,'e1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','e1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('f1000000-0000-4000-8000-000000000021'::uuid,'f1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','f1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values
  ('d1000000-0000-4000-8000-000000000031'::uuid,'d1000000-0000-4000-8000-000000000001'::uuid,null,'teaching_fixture_principal_root','Teaching Fixture Root','America/Chicago','active','{"validation_fixture":true}'::jsonb,'d1000000-0000-4000-8000-000000000011'::uuid);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values
  ('d2000000-0000-4000-8000-000000000001'::uuid,'teachingfixtureledgerroot000001','Teaching Fixture Governed Ledger',null,'governed_reality','active','{"validation_fixture":true}'::jsonb);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'd3000000-0000-4000-8000-000000000001'::uuid,
  'd1000000-0000-4000-8000-000000000031'::uuid,
  'd2000000-0000-4000-8000-000000000001'::uuid,
  'root_governing','active','teaching_academic_kernel_validation','{"validation_fixture":true}'::jsonb
);

-- Gate A capability activation: Teaching v1 active on the same Ledger.
insert into atlas.capability_activations(
  id,ledger_id,capability_key,capability_version,subject_ledger_id,subject_kind,subject_id,subject_key,subject_path,
  state,created_by_person_id,created_by_principal_id,created_at,updated_at,retired_at
) values (
  'd4000000-0000-4000-8000-000000000001'::uuid,
  'd2000000-0000-4000-8000-000000000001'::uuid,
  'teaching',1,
  'd2000000-0000-4000-8000-000000000001'::uuid,
  'ledger','d2000000-0000-4000-8000-000000000001'::uuid,null,null,
  'active','d1000000-0000-4000-8000-000000000011'::uuid,'d1000000-0000-4000-8000-000000000031'::uuid,
  now(),now(),null
);
