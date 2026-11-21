-- OWNER #2392 / ROLLBACK ONLY: historical self-adopted Done is evidence,
-- not a current original-Work transition. Do not reopen historical Work.
-- SQL claim emulation proves a deny path, not actual signed GoTrue identity.
DO $legacy_transition_denied$
DECLARE
 v_result atlas.work_execution_results%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_before_events bigint;
 v_before_results bigint;
 v_before_acceptances bigint;
 v_denied boolean:=false;
BEGIN
 SELECT r.* INTO v_result
 FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances x ON x.execution_result_id=r.id
 JOIN atlas.work_allocations a ON a.id=r.responsible_allocation_id
 JOIN atlas.work_items w ON w.id=r.work_item_id
 WHERE w.work_state='completed'
   AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
   AND r.result_kind='completed' AND x.decision='accepted'
   AND x.acceptance_kind='self_responsible_person_attestation'
   AND a.establishment_basis_kind='self_adoption'
   AND a.assignee_canonical_person_id IS NULL
   AND r.reported_by_user_id IS NOT NULL
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 IF v_result.id IS NULL THEN
   RAISE EXCEPTION 'No historical self-adopted accepted Result to preserve';
 END IF;
 SELECT * INTO v_work FROM atlas.work_items WHERE id=v_result.work_item_id;
 SELECT count(*) INTO v_before_events FROM atlas.work_lifecycle_events_v1
  WHERE work_item_id=v_work.id;
 SELECT count(*) INTO v_before_results FROM atlas.work_execution_results
  WHERE work_item_id=v_work.id;
 SELECT count(*) INTO v_before_acceptances FROM atlas.work_result_acceptances
  WHERE work_item_id=v_work.id;

 PERFORM pg_catalog.set_config('request.jwt.claim.sub',
   v_result.reported_by_user_id::text,true);
 BEGIN
   PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
     v_work.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN
   v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION
   'Legacy membership/accepted old Result enabled a new authoritative Done';
 END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1
       WHERE work_item_id=v_work.id)<>v_before_events
   OR (SELECT count(*) FROM atlas.work_execution_results
       WHERE work_item_id=v_work.id)<>v_before_results
   OR (SELECT count(*) FROM atlas.work_result_acceptances
       WHERE work_item_id=v_work.id)<>v_before_acceptances
   OR (SELECT work_state FROM atlas.work_items WHERE id=v_work.id)<>'completed'
 THEN RAISE EXCEPTION 'Historical original source evidence mutated'; END IF;
END;
$legacy_transition_denied$;
SELECT 'HISTORICAL_SELF_ADOPTION_PRIVATE_DONE_DENIED_AND_PRESERVED' AS verdict;
