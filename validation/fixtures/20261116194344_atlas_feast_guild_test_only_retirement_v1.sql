-- HELD: source-specific disposable current-schema clone fixture.
-- Fake UUIDs, no real records, no production connection, DML only.
-- Only the existing main protected clone harness may run this on localhost.
INSERT INTO auth.users(id)
VALUES ('a0000000-0000-4000-8000-000000000001'::uuid);

-- The current Atlas Principal compatibility trigger establishes Person custody.
INSERT INTO atlas.principals(
 id,user_id,organization_id,stable_key,name,home_timezone,status,metadata
) VALUES (
 'a1000000-0000-4000-8000-000000000001'::uuid,
 'a0000000-0000-4000-8000-000000000001'::uuid,
 null,
 'feast_test_retirement_clone_principal',
 'Synthetic Test Principal',
 'America/Chicago','active','{"fixture":true}'::jsonb
);

INSERT INTO atlas.organizations(
 id,stable_key,name,status,onboarding_state,created_at,metadata
)
SELECT
 'a2000000-0000-4000-8000-000000000001'::uuid,
 'feast_guild','Feast Guild','active','new',
 timestamptz '2026-09-14 00:42:45+00',
 jsonb_build_object(
  'canonicalInstitution','Feast Guild',
  'established_by_principal_id',p.id::text,
  'established_by_person_id',p.person_id::text,
  'cloneFixture',true
 )
FROM atlas.principals p
WHERE p.id='a1000000-0000-4000-8000-000000000001'::uuid
AND p.person_id IS NOT NULL;

INSERT INTO atlas.organizations(
 id,stable_key,name,status,onboarding_state,created_at,metadata
) VALUES (
 'a2000000-0000-4000-8000-000000000002'::uuid,
 'elm_farm','Elm Farm','active','ready',
 timestamptz '2026-09-14 00:42:45+00',
 '{"fixture":true,"protected":true}'::jsonb
);

INSERT INTO atlas.ledgers(
 id,stable_key,name,organization_id,ledger_kind,status,created_at,metadata
)
SELECT
 'a3000000-0000-4000-8000-000000000001'::uuid,
 'feast_guild','Feast Guild',null,'governed_reality','active',
 timestamptz '2026-09-14 00:42:45+00',
 jsonb_build_object(
   'canonicalEndeavor','Feast Guild',
   'established_by_principal_id',p.id::text,
   'established_by_person_id',p.person_id::text,
   'cloneFixture',true
 )
FROM atlas.principals p
WHERE p.id='a1000000-0000-4000-8000-000000000001'::uuid
AND p.person_id IS NOT NULL;

INSERT INTO atlas.ledgers(
 id,stable_key,name,organization_id,ledger_kind,status,created_at,metadata
) VALUES (
 'a3000000-0000-4000-8000-000000000002'::uuid,
 'elm_farm','Elm Farm',null,'governed_reality','active',
 timestamptz '2026-09-14 00:42:45+00',
 '{"fixture":true,"protected":true}'::jsonb
);

INSERT INTO atlas.ledger_organization_participations(
 id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
 status,basis,metadata
) VALUES
 (
 'a4000000-0000-4000-8000-000000000001'::uuid,
 'a3000000-0000-4000-8000-000000000001'::uuid,
 'a2000000-0000-4000-8000-000000000001'::uuid,
 'governing',true,'active','{"cloneFixture":true}'::jsonb,'{}'::jsonb
 ),(
 'a4000000-0000-4000-8000-000000000002'::uuid,
 'a3000000-0000-4000-8000-000000000002'::uuid,
 'a2000000-0000-4000-8000-000000000002'::uuid,
 'governing',true,'active','{"cloneFixture":true}'::jsonb,'{}'::jsonb
 );

INSERT INTO atlas.principal_ledger_authorities(
 id,principal_id,ledger_id,authority_kind,status,basis,metadata
) VALUES
 (
 'a5000000-0000-4000-8000-000000000001'::uuid,
 'a1000000-0000-4000-8000-000000000001'::uuid,
 'a3000000-0000-4000-8000-000000000001'::uuid,
 'root_governing','active','feast_test_retirement_clone',
 '{}'::jsonb
 ),(
 'a5000000-0000-4000-8000-000000000002'::uuid,
 'a1000000-0000-4000-8000-000000000001'::uuid,
 'a3000000-0000-4000-8000-000000000002'::uuid,
 'root_governing','active','protected_elm_clone',
 '{}'::jsonb
 );
