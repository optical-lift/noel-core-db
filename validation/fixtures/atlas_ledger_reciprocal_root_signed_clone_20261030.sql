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
-- C1 base fixture already creates exactly one Principal for worker.
INSERT INTO atlas.principal_ledger_authorities(id,principal_id,ledger_id,
 authority_kind,status,basis)
SELECT 'e5200000-0000-4000-8000-000000000602',
       p.id,'e5200000-0000-4000-8000-000000000402',
       'root_governing','active','clone_reciprocal_anna_owned'
FROM atlas.principals p
WHERE p.person_id='e5200000-0000-4000-8000-000000000102' AND p.status='active';
DO $ensure$
BEGIN
 IF (SELECT count(*) FROM atlas.principals WHERE person_id=
    'e5200000-0000-4000-8000-000000000102'::uuid AND status='active') <> 1
 THEN RAISE EXCEPTION 'No single existing Anna Principal';END IF;
 IF (SELECT count(*) FROM atlas.principal_ledger_authorities WHERE ledger_id=
    'e5200000-0000-4000-8000-000000000402'::uuid AND authority_kind='root_governing'
    AND status='active') <> 1
 THEN RAISE EXCEPTION 'No unique reciprocal root grant';END IF;
END;
$ensure$;
