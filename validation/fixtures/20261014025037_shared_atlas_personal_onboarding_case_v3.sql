-- Fixture is limited to the disposable production-schema clone.
-- Synthetic credentials and identities only; never part of a live migration.
INSERT INTO auth.users (
  id,instance_id,aud,role,email,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) VALUES
 ('10000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-clone-a@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-clone-b@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-clone-noaccess@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now());

-- User A exercises the genuine fresh verified invitation enrollment branch.
INSERT INTO atlas.personal_atlas_complimentary_test_invitations(
  email,code_digest,state,expires_at,claimed_by_user_id,claimed_at
) VALUES (
  'atlas-clone-a@example.invalid',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','issued',now()+interval '1 day',
  '10000000-0000-4000-8000-000000000001',now()
);

-- User B exercises the pre-existing legacy Principal, Person and grant branch.
-- The compatibility trigger supplies their actual legacy Person and credential.
INSERT INTO atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
VALUES (
  '10000000-0000-4000-8000-000000000002',
  'clone-preexisting-person-b','Clone Existing User','America/Chicago','active',
  '{"source":"isolated_fixture"}'::jsonb
);
INSERT INTO atlas.personal_atlas_access_grants(
  principal_id,grant_kind,state,basis
) SELECT id,'complimentary_testing','active','{"origin":"isolated_fixture"}'::jsonb
  FROM atlas.principals
  WHERE user_id='10000000-0000-4000-8000-000000000002';
