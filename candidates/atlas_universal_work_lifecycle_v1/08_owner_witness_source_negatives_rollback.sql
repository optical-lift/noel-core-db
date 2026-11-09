-- Gate 2 witness-mode coverage. Include after the original shadow + single
-- authority candidate in one transaction and ROLLBACK immediately.
-- This source fixture is *historical*, accepted evidence; this test
-- NEVER creates a new claim about Marshall or any person's physical work.
DO $witness_negative$
DECLARE
 v_w atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_a atlas.work_result_acceptances%ROWTYPE;
 v_outsider_rejected boolean:=false;
 v_no_session_rejected boolean:=false;
 v_claim_rejected boolean:=false;
 v_original_state text;
 v_count bigint;
BEGIN
 SELECT w.* INTO v_w FROM atlas.work_items w
 JOIN atlas.work_execution_results r ON r.work_item_id=w.id
 JOIN atlas.work_result_acceptances a
  ON a.execution_result_id=r.id AND a.decision='accepted'
  AND a.acceptance_kind='owner_witnessed_person_result'
 WHERE r.metadata->>'reportMode'='owner_witness'
   AND r.result_kind='completed'
   AND w.work_state='completed'
 ORDER BY r.reported_at DESC,w.id LIMIT 1;
 IF v_w.id IS NULL THEN RAISE EXCEPTION 'No historical owner-witnessed fixture';
 END IF;
 SELECT r.* INTO v_result FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances a ON a.execution_result_id=r.id
 WHERE r.work_item_id=v_w.id AND a.acceptance_kind='owner_witnessed_person_result'
 ORDER BY r.reported_at DESC LIMIT 1;
 SELECT * INTO v_a FROM atlas.work_result_acceptances
 WHERE execution_result_id=v_result.id AND decision='accepted';
 IF v_a.id IS NULL OR v_result.reported_by_user_id IS NULL
   OR v_result.metadata->>'authenticatedReporterPersonId' IS NULL
 THEN RAISE EXCEPTION 'Witness accepted source provenance unavailable'; END IF;
 v_original_state:=v_w.work_state;
 SELECT count(*) INTO v_count FROM atlas.work_lifecycle_events_v1
 WHERE work_item_id=v_w.id AND event_kind='work_transition_applied';

 -- An unrelated worker's signed uid must not masquerade as the owner who
 -- recorded the original witness claim, even when result IDs are known.
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',
   (SELECT pr.user_id::text FROM atlas.principals pr
    WHERE pr.status='active'
      AND pr.user_id IS NOT NULL
      AND pr.user_id IS DISTINCT FROM v_result.reported_by_user_id
    ORDER BY pr.created_at,pr.id LIMIT 1),true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
    v_w.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_outsider_rejected:=true; END;
 IF NOT v_outsider_rejected THEN
   RAISE EXCEPTION 'Unauthorized Person accepted an owner-witnessed result'; END IF;

 -- The exact original reporter's JWT UUID *claim* is NOT a real signed
 -- Atlas session. The root-owner source must reject synthetic credentials.
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',
   v_result.reported_by_user_id::text,true);
 BEGIN
   PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
     v_w.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_claim_rejected:=true; END;
 IF NOT v_claim_rejected THEN
   RAISE EXCEPTION 'A forged owner claim unexpectedly bypassed native Ledger root';
 END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
    v_w.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_no_session_rejected:=true; END;
 IF NOT v_no_session_rejected THEN
   RAISE EXCEPTION 'Unsigned witness transition unexpectedly succeeded'; END IF;

 IF (SELECT work_state FROM atlas.work_items WHERE id=v_w.id)
    IS DISTINCT FROM v_original_state OR
   (SELECT count(*) FROM atlas.work_lifecycle_events_v1
    WHERE work_item_id=v_w.id AND event_kind='work_transition_applied')
    <>v_count
 THEN RAISE EXCEPTION 'Negative witness tests modified Work or its lifecycle'; END IF;
 RAISE NOTICE 'PASS: witness remains distinguishable; unsigned and wrong-actor access denied';
END;
$witness_negative$;

SELECT 'WITNESS_CLAIM_SOURCE_ENFORCEMENT_NEGATIVE_PASS' AS verdict;
-- Positive witness session acceptance MUST be performed through a genuine
-- signed Atlas governor session and a protected test Work. Never impersonate
-- or manufacture a governor or relax the native Ledger function to pass.
