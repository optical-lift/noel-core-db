-- Data-only fixture for Atlas Teaching Course Detail Read v1.
-- Production-schema validation restores schema but not production data.

insert into auth.users(id) values
  ('d2100000-0000-4000-8000-000000000001'::uuid),
  ('f2100000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('d2100000-0000-4000-8000-000000000011'::uuid,'Teaching Detail Fixture Root','active','{"validation_fixture":true}'::jsonb),
  ('f2100000-0000-4000-8000-000000000011'::uuid,'Teaching Detail Fixture Learner','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('d2100000-0000-4000-8000-000000000021'::uuid,'d2100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','d2100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('f2100000-0000-4000-8000-000000000021'::uuid,'f2100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','f2100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values (
  'd2100000-0000-4000-8000-000000000031'::uuid,
  'd2100000-0000-4000-8000-000000000001'::uuid,
  null,
  'teaching_detail_fixture_root',
  'Teaching Detail Fixture Root',
  'America/Chicago',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'd2100000-0000-4000-8000-000000000011'::uuid
);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values (
  'd2200000-0000-4000-8000-000000000001'::uuid,
  'teachingdetailfixtureledger0001',
  'Teaching Detail Fixture Ledger',
  null,
  'governed_reality',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.capability_definitions(capability_key,capability_version,status,eligible_subject_kinds)
values ('teaching',1,'active',array['ledger','organization_ledger_entry']::text[]);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'd2300000-0000-4000-8000-000000000001'::uuid,
  'd2100000-0000-4000-8000-000000000031'::uuid,
  'd2200000-0000-4000-8000-000000000001'::uuid,
  'root_governing',
  'active',
  'teaching_course_detail_validation',
  '{"validation_fixture":true}'::jsonb
);
