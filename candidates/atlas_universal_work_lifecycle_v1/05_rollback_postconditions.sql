-- Run only after 04_shadow_release_candidate.sql within the SAME
-- transaction, replacing its terminal COMMIT with this file and ROLLBACK.
DO $parity$
DECLARE
 v_total integer;
 v_mismatch integer;
 v_old_results integer;
 v_shadow_results integer;
 v_old_acceptances integer;
 v_shadow_acceptances integer;
 v_old_allocations integer;
 v_shadow_allocation_snapshots integer;
 v_old_plan_events integer;
 v_shadow_plan_events integer;
 v_unproven integer;
 v_lifecycle_rows integer;
 v_private boolean;
 v_failed boolean;
 v_event_id uuid;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE NOT state_matches)
 INTO v_total,v_mismatch
 FROM atlas.work_lifecycle_shadow_reconciliation_v1;
 IF v_total<>(SELECT count(*) FROM atlas.work_items) OR v_mismatch<>0
 THEN RAISE EXCEPTION 'Shadow/live state mismatch: % of %',v_mismatch,v_total; END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_shadow_reconciliation_v1
   WHERE baseline_count<>1 OR original_result_count<>shadow_result_links
   OR original_accepted_result_count<>shadow_acceptance_links)
 THEN RAISE EXCEPTION 'Historical source refs missing, invented, or duplicated'; END IF;
 SELECT count(*) INTO v_old_results FROM atlas.work_execution_results;
 SELECT count(*) INTO v_shadow_results FROM atlas.work_lifecycle_events_v1
   WHERE event_kind='result_reported';
 SELECT count(*) INTO v_old_acceptances FROM atlas.work_result_acceptances;
 SELECT count(*) INTO v_shadow_acceptances FROM atlas.work_lifecycle_events_v1
   WHERE event_kind='result_accepted';
 SELECT count(*) INTO v_old_allocations FROM atlas.work_allocations;
 SELECT count(*) INTO v_shadow_allocation_snapshots
   FROM atlas.work_lifecycle_events_v1
   WHERE event_kind='responsibility_observed'
     AND provenance_kind='historical_snapshot';
 SELECT count(*) INTO v_old_plan_events FROM atlas.work_execution_plan_events;
 SELECT count(*) INTO v_shadow_plan_events FROM atlas.work_lifecycle_events_v1
   WHERE event_kind='plan_event_observed';
 IF v_old_results<>v_shadow_results
   OR v_old_acceptances<>v_shadow_acceptances
   OR v_old_allocations<>v_shadow_allocation_snapshots
   OR v_old_plan_events<>v_shadow_plan_events
 THEN RAISE EXCEPTION 'Original result/acceptance/assignment/plan custody mismatch'; END IF;
 SELECT count(*) INTO v_unproven
 FROM atlas.work_lifecycle_shadow_reconciliation_v1
 WHERE live_state='completed' AND original_accepted_result_count=0;
 -- An unproven recorded completion remains observable, never re-attested.
 IF v_unproven<>(
   SELECT count(*) FROM atlas.work_items w
   WHERE w.work_state='completed' AND NOT EXISTS(
     SELECT 1 FROM atlas.work_result_acceptances a
     WHERE a.work_item_id=w.id AND a.decision='accepted'))
 THEN RAISE EXCEPTION 'Historical unproven completion inventory was changed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1
  WHERE event_kind='historical_state_snapshot'
    AND (actor_user_id IS NOT NULL
      OR actor_attribution<>'unattributed' OR occurred_at IS NOT NULL
      OR provenance_kind<>'historical_snapshot'))
 THEN RAISE EXCEPTION 'Historical snapshot falsely attributes signed real-world action'; END IF;
 IF has_table_privilege('anon','atlas.work_lifecycle_events_v1','SELECT')
   OR has_table_privilege('authenticated','atlas.work_lifecycle_events_v1','SELECT')
   OR has_table_privilege('service_role','atlas.work_lifecycle_events_v1','INSERT')
   OR has_function_privilege('authenticated',
      'atlas.append_work_lifecycle_observation_internal_v1(uuid,text,text,uuid,text,text,uuid,text,text,timestamptz,text,jsonb)',
      'EXECUTE')
   OR has_function_privilege('authenticated',
      'atlas.seed_work_lifecycle_shadow_baseline_internal_v1()','EXECUTE')
   OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas' AND c.relname='work_lifecycle_events_v1'
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity))
 THEN RAISE EXCEPTION 'Shadow stream is exposed or lacks private custody'; END IF;

 SELECT id INTO v_event_id FROM atlas.work_lifecycle_events_v1
 ORDER BY recorded_at,id LIMIT 1;
 v_failed:=false;
 BEGIN
   UPDATE atlas.work_lifecycle_events_v1
   SET evidence_refs='{}'::jsonb WHERE id=v_event_id;
 EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Lifecycle event update was not rejected'; END IF;
 v_failed:=false;
 BEGIN
   DELETE FROM atlas.work_lifecycle_events_v1 WHERE id=v_event_id;
 EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Lifecycle event delete was not rejected'; END IF;
END;
$parity$;
-- An artificial Work exists only for the life of this rollback test.
-- This tests the ORIGINAL Work writer and its AFTER observer, not a Done API.
DO $forward$
DECLARE v_org uuid;v_work uuid;v_state text;v_count integer;
BEGIN
 SELECT organization_id INTO v_org FROM atlas.work_items
 WHERE organization_id IS NOT NULL ORDER BY created_at,id LIMIT 1;
 INSERT INTO atlas.work_items(
   organization_id,title,instructions,work_state,metadata)
 VALUES(v_org,'[ROLLBACK TEST] Gate 1 shadow source observation',
   'Test-only state observation; never send to a worker.','open',
   jsonb_build_object('testOnly','gate1_shadow_rollback'))
 RETURNING id INTO v_work;
 SELECT count(*) INTO v_count FROM atlas.work_lifecycle_events_v1
 WHERE work_item_id=v_work AND event_kind='work_established'
   AND to_state='open';
 IF v_count<>1 THEN RAISE EXCEPTION 'Original Work insertion did not produce one shadow event'; END IF;
 UPDATE atlas.work_items SET work_state='cancelled',
   cancelled_at=clock_timestamp(),updated_at=clock_timestamp()
 WHERE id=v_work;
 SELECT shadow_state INTO v_state
 FROM atlas.work_lifecycle_shadow_reconciliation_v1 WHERE work_item_id=v_work;
 IF v_state<>'cancelled' OR NOT EXISTS(
   SELECT 1 FROM atlas.work_lifecycle_events_v1
   WHERE work_item_id=v_work AND event_kind='work_state_observed'
     AND from_state='open' AND to_state='cancelled')
 THEN RAISE EXCEPTION 'Original Work state mutation was not shadow-observed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_execution_results WHERE work_item_id=v_work)
   OR EXISTS(SELECT 1 FROM atlas.work_result_acceptances WHERE work_item_id=v_work)
 THEN RAISE EXCEPTION 'Shadow created a competing Result or Acceptance'; END IF;
END;
$forward$;

-- Replay of the baseline does not attribute a new historical snapshot to
-- later Work or manufacture another accepted Result.
SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1() AS replay_receipt;
DO $replay$
BEGIN
 IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_shadow_reconciliation_v1
   WHERE NOT state_matches OR baseline_count>1)
 THEN RAISE EXCEPTION 'Baseline replay introduced duplicate or changed lifecycle'; END IF;
END;
$replay$;
SELECT
 (SELECT count(*) FROM atlas.work_items) AS original_work_count,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1) AS shadow_event_count,
 (SELECT count(*) FROM atlas.work_lifecycle_shadow_reconciliation_v1
   WHERE NOT state_matches) AS mismatched_state_count,
 (SELECT count(*) FROM atlas.work_lifecycle_shadow_reconciliation_v1
   WHERE live_state='completed' AND original_accepted_result_count=0)
     AS historical_unproven_completion_count,
 'ROLLBACK_ONLY_PASS' AS verdict;
