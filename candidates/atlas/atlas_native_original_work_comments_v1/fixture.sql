-- W07 DISPOSABLE CLONE SUPPLEMENT ONLY.
-- This file must be concatenated AFTER the exact existing C1 original Work
-- fixture, validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql.
-- No real People, existing work, Production rows, or new canonical seats.
-- DML only. No privileged side effects or grants.

-- Current signed Atlas admission requires a native Personal Atlas, not merely
-- a canonical Person binding or a Ledger seat. Four distinct synthetic actors.
INSERT INTO personal.atlases (person_entity_id,atlas_state,native)
SELECT p.id,'active',true
FROM reality.entities p
WHERE p.id IN (
  'e5200000-0000-4000-8000-000000000101'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'e5200000-0000-4000-8000-000000000103'::uuid,
  'e5200000-0000-4000-8000-000000000104'::uuid
)
AND NOT EXISTS (
  SELECT 1 FROM personal.atlases a WHERE a.person_entity_id=p.id
);

-- The synthetic worker's native responsibility needs a matching source
-- offer and complete immutable establishment basis. This is never a real
-- recipient consent receipt, user membership, employee classification or
-- production assignment. The signed W07 test checks current authorization
-- over the fictional already-established Work relation.
INSERT INTO atlas.company_work_initial_responsibility_offers (
  id,organization_id,work_item_id,ledger_id,
  offered_by_person_id,target_person_id,reason,offer_state
) VALUES (
  'e5200000-0000-4000-8000-000000000982',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000902',
  'e5200000-0000-4000-8000-000000000401',
  'e5200000-0000-4000-8000-000000000101',
  'e5200000-0000-4000-8000-000000000102',
  'Disposable original Work comment authorization fixture only',
  'offered'
);

INSERT INTO atlas.work_allocations (
  id,organization_id,work_item_id,allocation_role,state,
  assignee_canonical_person_id,establishment_basis_kind,establishment_basis,
  metadata
) VALUES (
  'e5200000-0000-4000-8000-000000000983',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000902',
  'responsible','active',
  'e5200000-0000-4000-8000-000000000102',
  'person_connection_receiver_uptake',
  '{"contractVersion":"exact_work_responsibility_establishment_v2",'
    '"basisKind":"person_connection_receiver_uptake",'
    '"organizationId":"e5200000-0000-4000-8000-000000000801",'
    '"workItemId":"e5200000-0000-4000-8000-000000000902",'
    '"targetPersonId":"e5200000-0000-4000-8000-000000000102",'
    '"nativeLedgerId":"e5200000-0000-4000-8000-000000000401",'
    '"offerId":"e5200000-0000-4000-8000-000000000982",'
    '"uptakeKind":"recipient_self_accepted"}'::jsonb,
  '{"cloneFixture":"w07_signed_ordinary_comment_v1"}'::jsonb
);
