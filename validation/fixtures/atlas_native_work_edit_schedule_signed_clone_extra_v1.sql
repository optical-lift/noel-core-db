-- Additional fictional records for native editing/date/status signed proof.
-- Applied ONLY after the existing C1 synthetic Person/Ledger fixture on local clone.
UPDATE atlas.work_items SET source_object_type='ledger_occurrence_shared_work',
  title='Synthetic event refreshments', instructions='Original synthetic instructions'
WHERE id='e5200000-0000-4000-8000-000000000901'::uuid;
UPDATE atlas.work_items SET source_object_type='ledger_connected_direct_task',
  title='Synthetic worker setup', instructions='Worker-visible synthetic task'
WHERE id='e5200000-0000-4000-8000-000000000902'::uuid;
INSERT INTO atlas.organization_memberships
  (id,organization_id,user_id,person_id,role,active)
VALUES
 ('e5200000-0000-4000-8000-000000000981'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000001'::uuid,
  'e5200000-0000-4000-8000-000000000101'::uuid,'owner',true),
 ('e5200000-0000-4000-8000-000000000982'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000002'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,'member',true);
-- Source-backed offer to the original fictional Work and exact native Ledger.
-- The fixture seeds an offered relationship, then records one accepted uptake.
-- No real Person, consent, membership, or production Work is touched.
INSERT INTO atlas.company_work_initial_responsibility_offers
  (id,organization_id,work_item_id,ledger_id,offered_by_person_id,
   target_person_id,reason,offer_state)
VALUES
 ('e5200000-0000-4000-8000-000000000985'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000902'::uuid,
  'e5200000-0000-4000-8000-000000000401'::uuid,
  'e5200000-0000-4000-8000-000000000101'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'Synthetic offered Work uptake in disposable clone','offered');
INSERT INTO atlas.work_allocations
 (id,organization_id,work_item_id,assignee_canonical_person_id,
  allocation_role,state,establishment_basis_kind,establishment_basis)
VALUES
 ('e5200000-0000-4000-8000-000000000983'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000902'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'responsible','active','person_connection_receiver_uptake',
  '{"contractVersion":"exact_work_responsibility_establishment_v2",
    "basisKind":"person_connection_receiver_uptake",
    "organizationId":"e5200000-0000-4000-8000-000000000801",
    "workItemId":"e5200000-0000-4000-8000-000000000902",
    "targetPersonId":"e5200000-0000-4000-8000-000000000102",
    "nativeLedgerId":"e5200000-0000-4000-8000-000000000401",
    "offerId":"e5200000-0000-4000-8000-000000000985",
    "uptakeKind":"recipient_self_accepted"}'::jsonb);
UPDATE atlas.company_work_initial_responsibility_offers
  SET offer_state='accepted', resolved_at=now(),
      accepted_allocation_id='e5200000-0000-4000-8000-000000000983'::uuid
WHERE id='e5200000-0000-4000-8000-000000000985'::uuid;
