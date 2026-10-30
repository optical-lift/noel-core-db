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
INSERT INTO atlas.work_allocations
 (id,organization_id,work_item_id,assignee_canonical_person_id,assigned_by_membership_id,
  allocation_role,state,establishment_basis_kind,establishment_basis)
VALUES
 ('e5200000-0000-4000-8000-000000000983'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000902'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'e5200000-0000-4000-8000-000000000981'::uuid,
  'responsible','active','ledger_connection_direct_assignment',
  '{"nativeLedgerId":"e5200000-0000-4000-8000-000000000401","cloneFixture":true}'::jsonb);
