-- Gate 3C Event shared checklist boundaries. Run only AFTER 04,06,10,12,14
-- in the same ROLLBACK transaction. No production Event is marked Done.
DO $event_shared_negative$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_accept atlas.work_result_acceptances%ROWTYPE;
 v_actor uuid;
 v_actor_uid uuid;
 v_prior_events bigint;
 v_prior_results bigint;
 v_prior_acceptances bigint;
 v_prior_state text;
 v_denied_wrong boolean:=false;
 v_denied_unverified boolean:=false;
 v_denied_unsigned boolean:=false;
 v_other_uid uuid;
BEGIN
 IF has_function_privilege('anon',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
   OR has_function_privilege('authenticated',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Universal terminal authority was exposed for Event'; END IF;
 SELECT w.* INTO v_work
 FROM atlas.work_items w
 JOIN atlas.work_execution_results r ON r.work_item_id=w.id
 JOIN atlas.work_result_acceptances acc ON acc.execution_result_id=r.id
 WHERE w.work_state='completed'
   AND w.source_object_type='ledger_occurrence_shared_work'
   AND r.result_contract_key='ledger_occurrence_shared_confirmation_v1'
   AND r.responsible_allocation_id IS NULL
   AND acc.decision='accepted'
   AND acc.acceptance_kind='shared_checklist_state_confirmation'
 ORDER BY r.reported_at DESC,w.id LIMIT 1;
 IF v_work.id IS NULL THEN RAISE EXCEPTION 'No original Event checklist history'; END IF;
 SELECT r.* INTO v_result FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances acc ON acc.execution_result_id=r.id
 WHERE r.work_item_id=v_work.id AND acc.decision='accepted'
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 SELECT * INTO v_accept FROM atlas.work_result_acceptances a
 WHERE a.execution_result_id=v_result.id AND a.decision='accepted';
 v_actor:=atlas.rhythm_safe_uuid_v1(v_result.payload->>'markedByPersonId');
 v_actor_uid:=v_result.reported_by_user_id;
 IF v_actor IS NULL OR v_actor_uid IS NULL OR
    v_result.payload->>'personalPerformanceNotClaimed' IS DISTINCT FROM 'true' OR
    v_result.payload->'performedByPersonId' IS DISTINCT FROM 'null'::jsonb OR
    v_result.metadata->>'actorPersonId' IS DISTINCT FROM v_actor::text OR
    v_accept.evidence->>'markedByPersonId' IS DISTINCT FROM v_actor::text OR
    v_accept.evidence->>'physicalPerformerAsserted' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'Original Event result actually asserted personal performance'; END IF;

 SELECT count(*) INTO v_prior_events FROM atlas.work_lifecycle_events_v1 e
 WHERE e.work_item_id=v_work.id AND e.event_kind='work_transition_applied';
 SELECT count(*) INTO v_prior_results FROM atlas.work_execution_results r
 WHERE r.work_item_id=v_work.id;
 SELECT count(*) INTO v_prior_acceptances FROM atlas.work_result_acceptances a
 WHERE a.work_item_id=v_work.id;
 v_prior_state:=v_work.work_state;

 SELECT p.user_id INTO v_other_uid FROM atlas.principals p
 WHERE p.status='active' AND p.user_id IS NOT NULL
   AND p.user_id IS DISTINCT FROM v_actor_uid
 ORDER BY p.created_at,p.id LIMIT 1;
 IF v_other_uid IS NULL THEN RAISE EXCEPTION 'No unrelated Event Person'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_other_uid::text,true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied_wrong:=true; END;
 IF NOT v_denied_wrong THEN RAISE EXCEPTION 'Another Person reused Event Result'; END IF;

 -- This emulates only the claim, never a GoTrue session: existing Event
 -- source must fail closed rather than allowing fabricated connection.
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_actor_uid::text,true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied_unverified:=true; END;
 IF NOT v_denied_unverified THEN
   RAISE EXCEPTION 'Synthetic Event credential bypassed reality access'; END IF;

 PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'complete',v_result.id,v_result.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied_unsigned:=true; END;
 IF NOT v_denied_unsigned THEN RAISE EXCEPTION 'Unsigned Event transition'; END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=v_work.id AND e.event_kind='work_transition_applied')
     <>v_prior_events
 OR (SELECT count(*) FROM atlas.work_execution_results r
   WHERE r.work_item_id=v_work.id)<>v_prior_results
 OR (SELECT count(*) FROM atlas.work_result_acceptances a
   WHERE a.work_item_id=v_work.id)<>v_prior_acceptances
 OR (SELECT work_state FROM atlas.work_items WHERE id=v_work.id)
   IS DISTINCT FROM v_prior_state
 THEN RAISE EXCEPTION 'Denied Event altered original Work or historical evidence'; END IF;
END;
$event_shared_negative$;
SELECT 'EVENT_PERSON_DISCARDED_PERFORMER_CLAIM_AND_DENIED_FORGED_ACCESS_PASS' AS verdict;
-- A positive signed Event action must be exercised with a GENUINE
-- signed Atlas Person session, current Ledger and Event identity grant.
-- It is not valid to waive or fake that acceptance test.
