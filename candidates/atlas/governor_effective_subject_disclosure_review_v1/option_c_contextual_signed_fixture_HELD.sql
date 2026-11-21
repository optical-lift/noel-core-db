-- DISPOSABLE PRODUCTION-SCHEMA CLONE ONLY; apply after the pinned C1 and
-- reciprocal native-Ledger fixtures. Never a live migration or Person grant.
-- Owner already governs organization-primary Ledger A; Worker governs
-- operating Ledger B. This adds owner as a SECOND governor of B.
INSERT INTO atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis
) VALUES (
  'e5200000-0000-4000-8000-000000000603',
  'e5200000-0000-4000-8000-000000000111',
  'e5200000-0000-4000-8000-000000000402',
  'root_governing','active','option_c_signed_clone_second_governor'
);
-- No-seat canonical Person can be inspected as a *current B participant*
-- only by the real governor; no linked Principal is invented.
INSERT INTO ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis)
VALUES (
  'e5200000-0000-4000-8000-000000000506',
  'e5200000-0000-4000-8000-000000000402',
  'e5200000-0000-4000-8000-000000000104',
  'active','{"cloneFixture":true,"purpose":"unresolved_no_principal"}'
);

-- P1A spatial/field source fixtures are seeded only by the loopback signed test.
