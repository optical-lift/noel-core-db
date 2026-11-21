-- ONE-TRANSACTION, ROLLBACK-ONLY test, runs AFTER:
--   04_shadow_release_candidate.sql WITHOUT its terminal COMMIT
--   06_single_transition_authority_private.sql
-- No original Result or Acceptance is rewritten. This test momentarily
-- reopens one already-completed fixture *inside the rollback transaction*
-- solely to exercise the same guarded state transition. NEVER COMMIT.
DO $single_transition_test$
DECLARE
 v_w atlas.work_items%ROWTYPE;
 v_r atlas.work_execution_results%ROWTYPE;
 v_a atlas.work_result_acceptances%ROWTYPE;
 v_first jsonb;v_repeat jsonb;
 v_before_results bigint;v_before_acceptances bigint;
 v_missing_ref boolean:=false;
 v_wrong_actor boolean:=false;
 v_collision boolean:=false;
 v_anon boolean:=false;
 v_first_event uuid;
BEGIN
 IF has_function_privilege('anon',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)',
    'EXECUTE')
   OR has_function_privilege('authenticated',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)',
    'EXECUTE')
   OR has_function_privilege('service_role',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)',
    'EXECUTE')
 THEN RAISE EXCEPTION 'Private transition authority was exposed to a client role'; END IF;
 SELECT w.* INTO v_w
 FROM atlas.work_items w
 JOIN atlas.work_execution_results r ON r.work_item_id=w.id
 JOIN atlas.work_result_acceptances accepted
   ON accepted.execution_result_id=r.id AND accepted.decision='accepted'
 JOIN atlas.work_allocations alloc
   ON alloc.id=r.responsible_allocation_id AND alloc.work_item_id=w.id
 WHERE w.work_state='completed' AND w.organization_id IS NOT NULL
   AND w.household_id IS NULL
   AND r.result_kind='completed'
   AND r.result_contract_key='ordinary_company_work_worker_attestation_v1'
   AND alloc.establishment_basis_kind='ledger_connection_direct_assignment'
   AND alloc.assignee_canonical_person_id IS NOT NULL
   AND r.reported_by_user_id IS NOT NULL
 ORDER BY r.reported_at DESC,w.id
 LIMIT 1;
 IF v_w.id IS NULL THEN
   RAISE EXCEPTION 'No source-accepted ordinary Work fixture for this environment'; END IF;
 SELECT r.* INTO v_r FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances a ON a.execution_result_id=r.id
 AND a.decision='accepted'
 WHERE r.work_item_id=v_w.id
   AND r.result_kind='completed'
   AND r.result_contract_key='ordinary_company_work_worker_attestation_v1'
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 SELECT * INTO v_a FROM atlas.work_result_acceptances
 WHERE execution_result_id=v_r.id AND decision='accepted'
 ORDER BY accepted_at DESC,id DESC LIMIT 1;

 SELECT count(*) INTO v_before_results FROM atlas.work_execution_results
 WHERE work_item_id=v_w.id;
 SELECT count(*) INTO v_before_acceptances FROM atlas.work_result_acceptances
 WHERE work_item_id=v_w.id;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_r.reported_by_user_id::text,true);
 -- This is SQL identity emulation, NOT a real GoTrue-signed acceptance test.
 -- Never represent it as such. Genuine browser roles remain future gates.
 IF atlas.current_person_id_v1() IS NULL THEN
   RAISE EXCEPTION 'Existing reporter has no current native Person'; END IF;

 -- Negative: even the correct reporter cannot use a different Result.
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
    v_w.id,'complete',gen_random_uuid(),v_r.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_missing_ref:=true; END;
 IF NOT v_missing_ref THEN RAISE EXCEPTION 'Unaccepted evidence was admitted'; END IF;

 -- Negative: the actor cannot provide a different action identity.
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
    v_w.id,'complete',v_r.id,v_r.idempotency_key||':collision');
 EXCEPTION WHEN SQLSTATE '42501' THEN v_collision:=true; END;
 IF NOT v_collision THEN RAISE EXCEPTION 'Foreign idempotency identity was admitted'; END IF;

 -- No anonymous/non-Person path, even with exact original evidence IDs.
 PERFORM pg_catalog.set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
    v_w.id,'complete',v_r.id,v_r.idempotency_key);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_anon:=true; END;
 IF NOT v_anon THEN RAISE EXCEPTION 'Unsigned transition was admitted'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_r.reported_by_user_id::text,true);

 -- One already completed historical Work is *temporarily* reopened to test
 -- the new transition writer and its projection inside this rollback only.
 UPDATE atlas.work_items
 SET work_state='open',completed_at=NULL,updated_at=clock_timestamp()
 WHERE id=v_w.id AND work_state='completed';
 IF NOT FOUND THEN RAISE EXCEPTION 'Original fixture did not reopen in test'; END IF;
 v_first:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_w.id,'complete',v_r.id,v_r.idempotency_key);
 v_repeat:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_w.id,'complete',v_r.id,v_r.idempotency_key);
 IF v_first->>'ok'<>'true' OR v_repeat->>'ok'<>'true'
   OR v_first->>'contractVersion' IS DISTINCT FROM
      'universal_work_lifecycle_transition_v1'
   OR v_first->>'eventId' IS DISTINCT FROM v_repeat->>'eventId'
   OR v_first->>'recordedAt' IS DISTINCT FROM v_repeat->>'recordedAt'
   OR v_first->>'idempotent'<>'false'
   OR v_repeat->>'idempotent'<>'true'
 THEN RAISE EXCEPTION 'Universal Done receipt is inconsistent on replay'; END IF;
 v_first_event:=(v_first->>'eventId')::uuid;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1
     WHERE work_item_id=v_w.id AND event_kind='work_transition_applied')<>1
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1
     WHERE work_item_id=v_w.id AND event_kind='work_state_observed'
       AND to_state='completed')<>0
   OR NOT (SELECT state_matches FROM atlas.work_lifecycle_shadow_reconciliation_v1
       WHERE work_item_id=v_w.id)
 THEN RAISE EXCEPTION 'One canonical transition did not own the Work state'; END IF;
 IF (SELECT count(*) FROM atlas.work_execution_results WHERE work_item_id=v_w.id)
     <>v_before_results
   OR (SELECT count(*) FROM atlas.work_result_acceptances
       WHERE work_item_id=v_w.id)<>v_before_acceptances
 THEN RAISE EXCEPTION 'Original evidence was changed or duplicated'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
     WHERE e.id=v_first_event
     AND e.actor_user_id=v_r.reported_by_user_id
     AND e.actor_attribution='verified_signed_transition'
     AND e.source_row_id=v_a.id
     AND e.evidence_refs->>'originalResultId'=v_r.id::text)
 THEN RAISE EXCEPTION 'Transition lost source evidence identity'; END IF;
 RAISE NOTICE 'PASS: one accepted original Work, exact replay, private authority and original evidence preserved';
END;
$single_transition_test$;

SELECT jsonb_build_object(
 'verdict','ROLLBACK_ONLY_PRIVATE_TRANSITION_PASS',
 'workCount',(SELECT count(*) FROM atlas.work_items),
 'stateMismatches',(SELECT count(*) FROM atlas.work_lifecycle_shadow_reconciliation_v1
   WHERE NOT state_matches),
 'newTerminalWriterExposed',has_function_privilege('authenticated',
   'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
) AS proof;
-- The encompassing test runner MUST ROLLBACK immediately after this file.
