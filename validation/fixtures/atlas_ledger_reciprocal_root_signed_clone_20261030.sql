-- DML only. Follows C1 base fixture in an isolated production-schema clone.
-- Owner Principal: Elm root + limited seat on Anna's Ledger.
-- Worker Principal: Anna root + ordinary worker seat on Elm.
INSERT INTO atlas.ledgers(id,stable_key,name,ledger_kind,status,organization_id)
VALUES ('e5200000-0000-4000-8000-000000000402','clone-anna-owned-ledger',
 'Clone Anna-Owned Ledger','governed_reality','active',
 'e5200000-0000-4000-8000-000000000801');
INSERT INTO atlas.ledger_organization_participations(
 id,ledger_id,organization_id,participation_kind,is_compatibility_primary,basis)
VALUES ('e5200000-0000-4000-8000-000000000804',
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000801',
 'governing',false,'{"cloneFixture":true,"purpose":"reciprocal_root"}');
INSERT INTO ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis)
VALUES
('e5200000-0000-4000-8000-000000000504',
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000505',
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000101','active','{"cloneFixture":true}');
-- C1 base seeds the canonical worker Person, Auth binding, legacy credential,
-- and active Elm Ledger seat, but only explicitly seeds the OWNER Principal.
-- Establish the worker's ONE matching Principal for the reciprocal root test.
-- This creates no Person, credential, alternate identity or production record.
INSERT INTO atlas.principals(
 id,user_id,person_id,stable_key,name,status)
SELECT
 'e5200000-0000-4000-8000-000000000112',
 'e5200000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000102',
 'clone-reciprocal-existing-worker-principal','Validation Worker','active'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.principals p
 WHERE p.person_id='e5200000-0000-4000-8000-000000000102'::uuid
);
-- Root authority binds to that same existing canonical Person/Principal.

INSERT INTO atlas.principal_ledger_authorities(id,principal_id,ledger_id,
 authority_kind,status,basis)
SELECT 'e5200000-0000-4000-8000-000000000602',
       p.id,'e5200000-0000-4000-8000-000000000402',
       'root_governing','active','clone_reciprocal_anna_owned'
FROM atlas.principals p
WHERE p.person_id='e5200000-0000-4000-8000-000000000102' AND p.status='active';
-- The existing signed HTTP validator asserts one current Anna Principal and
-- one active root on her Ledger after the DML fixture is admitted.
