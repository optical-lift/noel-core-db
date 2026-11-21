-- ONE-TRANSACTION ROLLBACK ONLY: original connected Person's evidence
-- reporter MUST delegate terminal state to the ONE universal lifecycle.
-- Requires files 04,06 and 10 installed in same ROLLBACK transaction.
-- The tests emulate auth.uid in SQL. They are NOT GoTrue-signed tests.
DO $worker_reporter$
DECLARE
 v_work uuid;
 v_person uuid;
 v_uid uuid;
 v_key text;
 v_payload jsonb:=jsonb_build_object('note','Rollback-only evidence, not real field completion',
   'sourceSurface','one_work_lifecycle_test');
 v_first jsonb;
 v_replay jsonb;
 v_wrong_actor_rejected boolean:=false;
 v_collision_rejected boolean:=false;
 v_other_uid uuid;
BEGIN
 SELECT w.id,a.assignee_canonical_person_id,p.user_id
 INTO v_work,v_person,v_uid
 FROM atlas.work_items w
 JOIN atlas.work_allocations a ON a.work_item_id=w.id
 JOIN atlas.principals p ON p.person_id=a.assignee_canonical_person_id
   AND p.status='active' AND p.user_id IS NOT NULL
 WHERE w.work_state='open'
   AND w.organization_id IS NOT NULL AND w.household_id IS NULL
   AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
   AND a.state='active' AND a.allocation_role='responsible'
   AND a.establishment_basis_kind='ledger_connection_direct_assignment'
   AND a.establishment_basis->>'nativeLedgerId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM atlas.work_execution_results r
     WHERE r.work_item_id=w.id)
 ORDER BY CASE WHEN w.title='String EB' THEN 0 ELSE 1 END,
     w.created_at DESC,w.id LIMIT 1;
 IF v_work IS NULL THEN
  RAISE EXCEPTION 'No permitted open original Work fixture; use isolated signed seed';
 END IF;
 v_key:='universal-original-report-rollback:'||gen_random_uuid()::text;

 -- A signed Person other than the allocated one may not use this writer
 -- to create an accepted result or terminal lifecycle event.
 SELECT p.user_id INTO v_other_uid FROM atlas.principals p
 WHERE p.status='active' AND p.user_id IS NOT NULL
   AND p.user_id<>v_uid
 ORDER BY p.created_at,p.id LIMIT 1;
 IF v_other_uid IS NULL THEN RAISE EXCEPTION 'No independent Person for negative test'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_other_uid::text,true);
 BEGIN
   PERFORM atlas.report_connected_person_company_work_internal_v1(
     v_work,'completed',v_key,v_payload,'own_work',NULL,NULL);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_wrong_actor_rejected:=true; END;
 IF NOT v_wrong_actor_rejected THEN
   RAISE EXCEPTION 'Unallocated Person could complete protected original Work';
 END IF;

 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 IF atlas.current_person_id_v1() IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'Signed identity test fixture does not map to allocated Person';
 END IF;
 v_first:=atlas.report_connected_person_company_work_internal_v1(
   v_work,'completed',v_key,v_payload,'own_work',NULL,NULL);
 v_replay:=atlas.report_connected_person_company_work_internal_v1(
   v_work,'completed',v_key,v_payload,'own_work',NULL,NULL);
 IF v_first->>'contractVersion'<>'universal_work_lifecycle_transition_v1'
   OR v_first->>'ok'<>'true' OR v_first->>'idempotent'<>'false'
   OR v_replay->>'ok'<>'true' OR v_replay->>'idempotent'<>'true'
   OR v_replay->>'eventId' IS DISTINCT FROM v_first->>'eventId'
   OR v_replay->>'recordedAt' IS DISTINCT FROM v_first->>'recordedAt'
   OR v_first->>'reporterPersonId' IS DISTINCT FROM v_person::text
   OR v_first->>'responsiblePersonId' IS DISTINCT FROM v_person::text
   OR v_first->>'performanceIsWitnessedClaim'<>'false'
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work AND e.event_kind='work_transition_applied')<>1
   OR (SELECT count(*) FROM atlas.work_execution_results r
     WHERE r.work_item_id=v_work)<>1
   OR (SELECT count(*) FROM atlas.work_result_acceptances acc
     WHERE acc.work_item_id=v_work AND acc.decision='accepted')<>1
   OR NOT (SELECT x.state_matches FROM atlas.work_lifecycle_shadow_reconciliation_v1 x
      WHERE x.work_item_id=v_work)
 THEN RAISE EXCEPTION 'Existing original reporter did not produce one universal Done receipt';
 END IF;
 BEGIN
   PERFORM atlas.report_connected_person_company_work_internal_v1(
     v_work,'completed',v_key,v_payload||'{"note":"changed payload"}'::jsonb,
     'own_work',NULL,NULL);
 EXCEPTION WHEN SQLSTATE '23505' THEN v_collision_rejected:=true; END;
 IF NOT v_collision_rejected THEN
   RAISE EXCEPTION 'Same action identity reused with different Result payload';
 END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=v_work AND e.event_kind='work_transition_applied')<>1
 THEN RAISE EXCEPTION 'Collision inserted a competing Done'; END IF;
END;
$worker_reporter$;

SELECT 'ONE_ORIGINAL_WRITER_ONE_DONE_EVENT_AND_RECEIPT_ROLLBACK_PASS' AS verdict;
-- Must ROLLBACK immediately after this file. No task was physically completed.
