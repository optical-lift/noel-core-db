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

-- P1A: one fictional original Work / shared-subject source; disclosure remains governor-only.
-- All fixtures remain in ephemeral local validation DB. This explicitly does
-- not create real Work or reveal the Subject to the signed worker.
INSERT INTO atlas.farms(id,stable_key,name,organization_id)
VALUES ('e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-farm','Option C Fictional Farm',
        'e5200000-0000-4000-8000-000000000801');
INSERT INTO atlas.growing_objects(id,farm_id,stable_key,label,object_type)
VALUES ('e5200000-0000-4000-8000-000000000902',
        'e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-bed','Fictional Bed for source review','bed');
-- No Work allocation or growing-object context link may be fabricated here.
-- Existing source requires a governed legacy-task/custody chain for such links.
-- Separate field decisions are seeded only inside disposable signed test.
