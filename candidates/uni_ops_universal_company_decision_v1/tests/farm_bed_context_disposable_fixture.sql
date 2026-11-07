-- HELD UNI-OPS test only: genuine signed Work->Bed context source prerequisites.
-- NEVER run in production. No real Work, Person, allocation, acceptance,
-- permission or physical Bed data. This fixture adapts *existing fictional
-- C1 original Work* to one native fictional harvest Task and physical Bed.
-- Signed owner must SELF-ADOPT that existing original through the live
-- canonical source function, not through a direct fixture allocation.
\set ON_ERROR_STOP on
DO $source_guard$
BEGIN
  IF current_database() IS DISTINCT FROM 'postgres'
    OR current_setting('uni_ops.disposable_clone',true) IS DISTINCT FROM 'true'
    OR current_setting('server_version_num')::integer/10000 <> 17
    OR (SELECT count(*) FROM auth.users WHERE id IN (
      'e5200000-0000-4000-8000-000000000001'::uuid,
      'e5200000-0000-4000-8000-000000000002'::uuid,
      'e5200000-0000-4000-8000-000000000003'::uuid,
      'e5200000-0000-4000-8000-000000000004'::uuid)) <> 4
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms WHERE
        id='e5200000-0000-4000-8000-000000000b01'::uuid
        AND organization_unit_id='e5200000-0000-4000-8000-000000000802'::uuid)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.work_items w WHERE
        w.id='e5200000-0000-4000-8000-000000000b10'::uuid
        AND w.organization_id='e5200000-0000-4000-8000-000000000801'::uuid
        AND w.stable_key='clone-original-beds-3-and-4'
        AND w.source_object_type='legacy_task_slice'
        AND w.work_state='open')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.tasks t WHERE
        t.id='fa510000-0000-4000-8000-000000000001'::uuid
        AND t.farm_id='e5200000-0000-4000-8000-000000000b01'::uuid)
    OR EXISTS(SELECT 1 FROM atlas.work_allocations WHERE
      work_item_id='e5200000-0000-4000-8000-000000000b10'::uuid)
    OR EXISTS(SELECT 1 FROM atlas.work_item_context_links WHERE
      work_item_id='e5200000-0000-4000-8000-000000000b10'::uuid
      AND subject_kind='growing_object')
    OR EXISTS(SELECT 1 FROM atlas.zones WHERE
      id='fa510000-0000-4000-8000-000000000005'::uuid)
    OR EXISTS(SELECT 1 FROM atlas.organization_memberships WHERE
      id='fa510000-0000-4000-8000-000000000006'::uuid)
  THEN
    RAISE EXCEPTION 'Not the exact test-only genuine Work->Bed source case'
      USING ERRCODE='42501';
  END IF;
END;
$source_guard$;

-- Exact fictional U-Pick Zone and two previously seeded C1 Beds.
INSERT INTO atlas.zones(
  id,farm_id,stable_key,label,zone_type,metadata
) VALUES (
  'fa510000-0000-4000-8000-000000000005',
  'e5200000-0000-4000-8000-000000000b01',
  'held-uniops-synthetic-bed-zone','Fictional Bed 3/4 source Zone',
  'growing_zone','{"cloneFixture":true,"noRealPhysicalState":true}'::jsonb
);
UPDATE atlas.growing_objects
SET zone_id='fa510000-0000-4000-8000-000000000005'::uuid
WHERE id IN (
  'e5200000-0000-4000-8000-000000000b03'::uuid,
  'e5200000-0000-4000-8000-000000000b04'::uuid
) AND farm_id='e5200000-0000-4000-8000-000000000b01'::uuid;

-- Native first-party fictional Task exists from the original Harvest fixture.
UPDATE atlas.tasks
SET zone_id='fa510000-0000-4000-8000-000000000005'::uuid
WHERE id='fa510000-0000-4000-8000-000000000001'::uuid
 AND farm_id='e5200000-0000-4000-8000-000000000b01'::uuid;

-- Adapt an EXISTING original from immutable C1, not issuing an additional
-- Work, auto-successor, appointment or Clock. This fixture only supplies
-- the legacy-task physical source *relation* that the tested native
-- Work->Bed writer will independently recheck.
UPDATE atlas.work_items
SET source_object_type='legacy_task',
    source_object_id='fa510000-0000-4000-8000-000000000001'::uuid,
    organization_unit_id='e5200000-0000-4000-8000-000000000802'::uuid,
    result_contract_key='ordinary_company_work_worker_attestation_v1',
    metadata=metadata || '{"clonePhysicalLegacySource":true}'::jsonb
WHERE id='e5200000-0000-4000-8000-000000000b10'::uuid
 AND organization_id='e5200000-0000-4000-8000-000000000801'::uuid
 AND work_state='open';

-- Current institutional OWNER membership is independently relevant for
-- the first-party signed owner SELF-ADOPTION operation. This row is a
-- synthetic first-encounter identity fixture, not an actual owner grant.
-- It is NOT sufficient alone for native governing Ledger root/GoTrue.
INSERT INTO atlas.organization_memberships(
  id,organization_id,user_id,person_id,role,active,permissions
) VALUES (
  'fa510000-0000-4000-8000-000000000006',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000001',
  'e5200000-0000-4000-8000-000000000101',
  'owner',true,'{"cloneFixture":true,"doesNotConferOtherRights":true}'::jsonb
);

DO $verify_source_fixture$
BEGIN
  IF (SELECT count(*) FROM atlas.growing_objects
      WHERE farm_id='e5200000-0000-4000-8000-000000000b01'::uuid
        AND zone_id='fa510000-0000-4000-8000-000000000005'::uuid
        AND object_type='bed')<>2
     OR (SELECT count(*) FROM atlas.tasks WHERE
        id='fa510000-0000-4000-8000-000000000001'::uuid
        AND zone_id='fa510000-0000-4000-8000-000000000005'::uuid)<>1
     OR (SELECT count(*) FROM atlas.work_items WHERE
        id='e5200000-0000-4000-8000-000000000b10'::uuid
        AND source_object_type='legacy_task'
        AND source_object_id='fa510000-0000-4000-8000-000000000001'::uuid
        AND organization_unit_id='e5200000-0000-4000-8000-000000000802'::uuid)<>1
     OR EXISTS(SELECT 1 FROM atlas.work_allocations WHERE
        work_item_id='e5200000-0000-4000-8000-000000000b10'::uuid)
  THEN RAISE EXCEPTION 'Fictional physical source / existing Work did not match'
    USING ERRCODE='23514'; END IF;
END;
$verify_source_fixture$;
