-- ACCESS-02. DML-only synthetic localhost clone; NEVER production.
-- Appended after the trusted universal original-Work fixture. These Work
-- originals are already fictional, source-backed and native-Ledger relevant.
DO $access02_fixture_prerequisites$
BEGIN
  IF (SELECT count(*) FROM atlas.work_items WHERE id IN
      ('e5200000-0000-4000-8000-000000000901'::uuid,
       'e5200000-0000-4000-8000-000000000902'::uuid)
      AND work_state='open') <> 2
    OR (SELECT count(*) FROM ledger.seats WHERE ledger_id=
      'e5200000-0000-4000-8000-000000000401'::uuid AND person_entity_id=
      'e5200000-0000-4000-8000-000000000102'::uuid AND seat_state='active'
      AND ended_at IS NULL) <> 1
    OR (SELECT count(*) FROM atlas.company_work_native_ledger_relevance
      WHERE ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
      AND work_item_id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
                           'e5200000-0000-4000-8000-000000000902'::uuid)
      AND attribution_state='active' AND evidence_kind='owner_attested') <> 2
  THEN
    RAISE EXCEPTION 'ACCESS-02 exact fictional native original Work fixture missing';
  END IF;
  IF EXISTS (SELECT 1 FROM atlas.work_allocations WHERE work_item_id IN
      ('e5200000-0000-4000-8000-000000000901'::uuid,
       'e5200000-0000-4000-8000-000000000902'::uuid)) THEN
    RAISE EXCEPTION 'ACCESS-02 refuses preassigned fictional Work';
  END IF;
END;
$access02_fixture_prerequisites$;

UPDATE atlas.work_items
SET instructions=CASE id
  WHEN 'e5200000-0000-4000-8000-000000000901'::uuid
  THEN 'Synthetic instructions for Work 901; Ledger A only.'
  ELSE 'Synthetic instructions for Work 902; Ledger A only.'
END
WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
  AND id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
             'e5200000-0000-4000-8000-000000000902'::uuid);

INSERT INTO atlas.work_allocations
  (id,organization_id,work_item_id,assignee_canonical_person_id,
   allocation_role,state,assignee_membership_id,establishment_basis_kind,
   establishment_basis,metadata)
VALUES
('e5200000-0000-4000-8000-000000000951',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000901',
 'e5200000-0000-4000-8000-000000000102',
 'responsible','active',NULL,'ledger_connection_direct_assignment',
 '{"nativeLedgerId":"e5200000-0000-4000-8000-000000000401","cloneOnly":true}'::jsonb,
 '{"source":"access02_signed_clone_only"}'::jsonb),
('e5200000-0000-4000-8000-000000000952',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000902',
 'e5200000-0000-4000-8000-000000000102',
 'responsible','active',NULL,'ledger_connection_direct_assignment',
 '{"nativeLedgerId":"e5200000-0000-4000-8000-000000000401","cloneOnly":true}'::jsonb,
 '{"source":"access02_signed_clone_only"}'::jsonb);

DO $access02_fixture_postconditions$
BEGIN
 IF (SELECT count(*) FROM atlas.work_allocations WHERE
     id IN ('e5200000-0000-4000-8000-000000000951'::uuid,
            'e5200000-0000-4000-8000-000000000952'::uuid)
     AND state='active' AND assignee_canonical_person_id=
     'e5200000-0000-4000-8000-000000000102'::uuid
     AND establishment_basis->>'nativeLedgerId'=
     'e5200000-0000-4000-8000-000000000401') <> 2 THEN
   RAISE EXCEPTION 'ACCESS-02 fictional two-original Work allocation fixture invalid';
 END IF;
END;
$access02_fixture_postconditions$;
