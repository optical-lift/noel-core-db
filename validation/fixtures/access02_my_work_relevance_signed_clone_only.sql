-- ACCESS-02. DML-only synthetic localhost clone; NEVER production.
-- Appended after the trusted universal original-Work fixture. These Work
-- originals are already fictional, source-backed and native-Ledger relevant.
SELECT 1 / CASE WHEN
 (SELECT count(*) FROM atlas.work_items
  WHERE id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
               'e5200000-0000-4000-8000-000000000902'::uuid)
    AND work_state='open')=2
 AND (SELECT count(*) FROM ledger.seats
  WHERE ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
    AND person_entity_id='e5200000-0000-4000-8000-000000000102'::uuid
    AND seat_state='active' AND ended_at IS NULL)=1
 AND (SELECT count(*) FROM atlas.company_work_native_ledger_relevance
  WHERE ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
    AND work_item_id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
                         'e5200000-0000-4000-8000-000000000902'::uuid)
    AND attribution_state='active' AND evidence_kind='owner_attested')=2
 AND (SELECT count(*) FROM atlas.work_allocations
  WHERE work_item_id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
                         'e5200000-0000-4000-8000-000000000902'::uuid))=0
 THEN 1 ELSE 0 END AS access02_fixture_prerequisites;

UPDATE atlas.work_items
SET instructions=CASE id
  WHEN 'e5200000-0000-4000-8000-000000000901'::uuid
  THEN 'Synthetic instructions for Work 901 - Ledger A only.'
  ELSE 'Synthetic instructions for Work 902 - Ledger A only.'
END
WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
  AND id IN ('e5200000-0000-4000-8000-000000000901'::uuid,
             'e5200000-0000-4000-8000-000000000902'::uuid);

-- The fictional governor's active institution membership is needed for
-- the real owner-issued Work offer RPC. No allocation is manufactured here.
INSERT INTO atlas.organization_memberships
 (id,organization_id,user_id,person_id,role,active,permissions)
VALUES
 ('e5200000-0000-4000-8000-000000000850',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000001',
  'e5200000-0000-4000-8000-000000000101',
  'owner',true,'{}'::jsonb);

SELECT 1 / CASE WHEN
 (SELECT count(*) FROM atlas.organization_memberships
  WHERE id='e5200000-0000-4000-8000-000000000850'::uuid
    AND organization_id='e5200000-0000-4000-8000-000000000801'::uuid
    AND person_id='e5200000-0000-4000-8000-000000000101'::uuid
    AND user_id='e5200000-0000-4000-8000-000000000001'::uuid
    AND role='owner' AND active)=1
 AND (SELECT count(*) FROM atlas.work_allocations WHERE work_item_id IN
   ('e5200000-0000-4000-8000-000000000901'::uuid,
    'e5200000-0000-4000-8000-000000000902'::uuid))=0
 THEN 1 ELSE 0 END AS access02_fixture_postconditions;
