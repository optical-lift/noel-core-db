-- OWNER #2392 / ROLLBACK ONLY: old self-adoption entrypoint is retired,
-- both for new Done and for replay of an accepted historical Result.
-- Historical source stays untouched and current Need must take NEW native Work.
DO $legacy_writer_denied$
DECLARE
 v_result atlas.work_execution_results%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_uid uuid;
 v_before_events bigint;
 v_before_results bigint;
 v_before_acceptances bigint;
 v_old_denied boolean:=false;
 v_new_denied boolean:=false;
BEGIN
 SELECT r.* INTO v_result
 FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances x ON x.execution_result_id=r.id
 JOIN atlas.work_allocations a ON a.id=r.responsible_allocation_id
 JOIN atlas.work_items w ON w.id=r.work_item_id
 WHERE w.work_state='completed'
   AND r.result_kind='completed'
   AND x.decision='accepted'
   AND x.acceptance_kind='self_responsible_person_attestation'
   AND a.establishment_basis_kind='self_adoption'
   AND r.reported_by_user_id IS NOT NULL
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 IF v_result.id IS NULL THEN
   RAISE EXCEPTION 'No historical self-adopted Result to preserve';
 END IF;
 SELECT * INTO v_work FROM atlas.work_items WHERE id=v_result.work_item_id;
 v_uid:=v_result.reported_by_user_id;
 SELECT count(*) INTO v_before_events FROM atlas.work_lifecycle_events_v1
  WHERE work_item_id=v_work.id;
 SELECT count(*) INTO v_before_results FROM atlas.work_execution_results
  WHERE work_item_id=v_work.id;
 SELECT count(*) INTO v_before_acceptances FROM atlas.work_result_acceptances
  WHERE work_item_id=v_work.id;

 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 BEGIN
   PERFORM atlas.report_self_responsible_company_work_self_api_v1(
     v_work.id,'completed',v_result.idempotency_key,v_result.payload);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_old_denied:=true; END;
 BEGIN
   PERFORM atlas.report_self_responsible_company_work_self_api_v1(
     v_work.id,'partial','legacy-cannot-reopen:'||gen_random_uuid(),
     '{"note":"An old membership does not permit a fresh report."}'::jsonb);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_new_denied:=true; END;
 IF NOT v_old_denied OR NOT v_new_denied THEN
   RAISE EXCEPTION 'Historical self-adoption writer still accepts new authority';
 END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1
       WHERE work_item_id=v_work.id)<>v_before_events
    OR (SELECT count(*) FROM atlas.work_execution_results
       WHERE work_item_id=v_work.id)<>v_before_results
    OR (SELECT count(*) FROM atlas.work_result_acceptances
       WHERE work_item_id=v_work.id)<>v_before_acceptances
    OR (SELECT work_state FROM atlas.work_items WHERE id=v_work.id)<>'completed'
 THEN RAISE EXCEPTION 'Retired writer changed original history'; END IF;
END;
$legacy_writer_denied$;
SELECT 'HISTORICAL_SELF_ADOPTION_WRITER_DENIED_AND_PRESERVED' AS verdict;
