-- ATLAS E05 — SYNTHETIC NONFARM CLONE FIXTURE ONLY.
-- NEVER apply to Production. No migration/GRANT/RLS/real Person/real Work.
-- Source graph through the principal_ledger_authorities row is the frozen
-- pre-farm C1 identity/Organization/Ledger setup in
-- candidates/atlas/atlas_universal_original_work_integrated_v1/fixture.sql
-- (source blob e877d93323ddc67d8778be8bea1dfa34319cc85c).
-- E05 adds only one nonfarm original Work and a lawful test-only
-- worker-attestation Result policy; the auth passwords are installed
-- separately from job environment by the bounded fixture preparer.
-- Execute in one transaction on a fresh, job-temporary atlas_e05_* database.

-- Synthetic original Work and Household fixture for disposable clone only.
-- Clone-only synthetic credentials, native Ledger and operating unit for C1 authorization verification.
-- DML-only disposable fixture; no real email, live user, seat, or Work is changed.
insert into auth.users(id,aud,role,created_at,updated_at) values
('e5200000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000004','authenticated','authenticated',now(),now());

insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('e5200000-0000-4000-8000-000000000011','e5200000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000012','e5200000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000013','e5200000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000014','e5200000-0000-4000-8000-000000000004',now(),now(),now()+interval '1 day');

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values
('e5200000-0000-4000-8000-000000000101','c1-validation-owner','person','Validation Owner','canonical'),
('e5200000-0000-4000-8000-000000000102','c1-validation-worker','person','Validation Worker','canonical'),
('e5200000-0000-4000-8000-000000000103','c1-validation-outsider','person','Validation Other-Ledger Member','canonical'),
('e5200000-0000-4000-8000-000000000104','c1-validation-no-seat','person','Validation No-Seat Person','canonical'),
('e5200000-0000-4000-8000-000000000201','c1-validation-business','business','Validation Business','canonical');

insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values
('e5200000-0000-4000-8000-000000000001','e5200000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000002','e5200000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000003','e5200000-0000-4000-8000-000000000103','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000004','e5200000-0000-4000-8000-000000000104','active','{"cloneFixture":true}');

insert into atlas.people(id,display_name,status) values
('e5200000-0000-4000-8000-000000000101','Validation Owner','active'),
('e5200000-0000-4000-8000-000000000102','Validation Worker','active'),
('e5200000-0000-4000-8000-000000000103','Validation Other-Ledger Member','active'),
('e5200000-0000-4000-8000-000000000104','Validation No-Seat Person','active');

-- Align the legacy Atlas credential link with each synthetic reality binding.
-- Without it the principal compatibility trigger creates a second Person.
insert into atlas.person_auth_credentials(
  person_id,credential_kind,auth_user_id,status,provenance
) values
('e5200000-0000-4000-8000-000000000101','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000001','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000102','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000002','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000103','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000003','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000104','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000004','active','{"cloneFixture":true}');

insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values
('e5200000-0000-4000-8000-000000000111','e5200000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000101','c1-validation-owner-principal','Validation Owner','active');

insert into ledger.onboarding_cases(
  id,subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
  desired_ledger_name,onboarding_state,onboarding_basis
) values
('e5200000-0000-4000-8000-000000000301','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000101','e5200000-0000-4000-8000-000000000101',
 'Validation Ledger A','ready_to_activate','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000302','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000101','e5200000-0000-4000-8000-000000000101',
 'Validation Ledger B','ready_to_activate','{"cloneFixture":true}');

insert into ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state) values
('e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000301','c1-validation-ledger-a','Validation Ledger A','active'),
('e5200000-0000-4000-8000-000000000402','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000302','c1-validation-ledger-b','Validation Ledger B','active');

insert into ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis) values
('e5200000-0000-4000-8000-000000000501','e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000502','e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000503','e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000103','active','{"cloneFixture":true}');

-- Exact synthetic Atlas institution and operating unit for this Ledger.
insert into atlas.organizations(id,stable_key,name,onboarding_state)
values ('e5200000-0000-4000-8000-000000000801','c1-validation-organization',
        'Clone Operating Organization','ready');
insert into atlas.organization_units(id,organization_id,stable_key,name)
values ('e5200000-0000-4000-8000-000000000802','e5200000-0000-4000-8000-000000000801',
        'c1-validation-farm-unit','Clone Farm Unit');
insert into atlas.ledgers(id,stable_key,name,ledger_kind,status,organization_id) values
('e5200000-0000-4000-8000-000000000401','c1-validation-legacy-a','Validation Ledger A','governed_reality','active','e5200000-0000-4000-8000-000000000801');
insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,basis
) values ('e5200000-0000-4000-8000-000000000803','e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000801',
          'governing',true,'{"cloneFixture":true}');

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis
) values
('e5200000-0000-4000-8000-000000000601',
 'e5200000-0000-4000-8000-000000000111',
 'e5200000-0000-4000-8000-000000000401',
 'root_governing','active','clone_validation_fixture');

-- The C1-only sensitive Ledger Action was intentionally omitted: E05 tests
-- original Work authority, not the unrelated Ledger Action privacy surface.

-- Remove the *label* inherited from the C1 Farm test, not the native
-- Organization identity. No atlas.farms row is ever created.
UPDATE atlas.organization_units
SET stable_key='e05-synthetic-archive-unit',
    name='E05 Synthetic Archive Operations'
WHERE id='e5200000-0000-4000-8000-000000000802'::uuid;

UPDATE atlas.organizations
SET stable_key='e05-synthetic-nonfarm-organization',
    name='E05 Synthetic Nonfarm Organization'
WHERE id='e5200000-0000-4000-8000-000000000801'::uuid;

INSERT INTO atlas.work_result_contract_policies
 (contract_key,source_domain,acceptance_mode,active,description)
VALUES
 ('ordinary_company_work_worker_attestation_v1','organization','worker_attestation',true,
  'Fictional nonfarm archive review; signed recipient worker attestation in disposable clone');

INSERT INTO atlas.work_items
 (id,organization_id,title,work_state,result_contract_key,stable_key,metadata)
VALUES
 ('e5200000-0000-4000-8000-000000000901',
  'e5200000-0000-4000-8000-000000000801',
  'E05 SYNTHETIC nonprofit archive review','open',
  'ordinary_company_work_worker_attestation_v1',
  'e05-synthetic-nonfarm-archive-review',
  '{"cloneFixture":true,"e05Nonfarm":true}'::jsonb);

INSERT INTO atlas.company_work_native_ledger_relevance
 (organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
  attestation_source_ref,attestation_reason,established_by_person_id)
VALUES
 ('e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000901',
  'e5200000-0000-4000-8000-000000000401',
  'serves_purpose','owner_attested',
  'clone:e05-exact-original-nonfarm-901',
  'One fictional existing original Work attributed to this native Ledger only.',
  'e5200000-0000-4000-8000-000000000101');

-- Fail closed *before* reporting a valid E05 fixture.
DO $e05$
BEGIN
  IF EXISTS (
    SELECT 1 FROM atlas.farms
    WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
  ) THEN RAISE EXCEPTION 'E05 nonfarm association failed'; END IF;

  IF (SELECT count(*) FROM atlas.work_items
      WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid) != 1
  OR (SELECT count(*) FROM atlas.company_work_native_ledger_relevance
      WHERE work_item_id='e5200000-0000-4000-8000-000000000901'::uuid
        AND ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
        AND attribution_state='active') != 1
  OR (SELECT count(*) FROM atlas.work_allocations
      WHERE work_item_id='e5200000-0000-4000-8000-000000000901'::uuid) != 0
  OR (SELECT count(*) FROM atlas.principal_ledger_authorities
      WHERE ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
        AND authority_kind='root_governing' AND status='active') != 1
  OR (SELECT count(*) FROM ledger.seats
      WHERE id='e5200000-0000-4000-8000-000000000502'::uuid
        AND person_entity_id='e5200000-0000-4000-8000-000000000102'::uuid
        AND seat_state='active') != 1
  THEN RAISE EXCEPTION 'E05 native Source/Work/seat fixture failed'; END IF;
END;
$e05$;
