-- Run only with 04,06,10,12 in one ROLLBACK-only transaction.
-- This reuses original self-adopted evidence and *temporarily* reopens its
-- Work/allocation inside the transaction to test the existing source writer.
-- No real Done, new Work, or physical source result persists.
DO $self_source_cutover$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_old atlas.work_execution_results%ROWTYPE;
 v_alloc atlas.work_allocations%ROWTYPE;
 v_member atlas.organization_memberships%ROWTYPE;
 v_old_receipt jsonb;
 v_first jsonb;
 v_replay jsonb;
 v_key text:='self-original-cutover-rollback:'||gen_random_uuid();
 v_note jsonb:=jsonb_build_object('note',
   'Rollback-only self-responsible Work evidence, not a real-world Done');
 v_results_before bigint;
 v_accepted_before bigint;
 v_wrong_rejected boolean:=false;
 v_collision_rejected boolean:=false;
 v_other_uid uuid;
BEGIN
 SELECT w.* INTO v_work FROM atlas.work_items w
 JOIN atlas.work_allocations a ON a.work_item_id=w.id
 JOIN atlas.organization_memberships m ON m.id=a.assignee_membership_id
 JOIN atlas.work_execution_results r
  ON r.work_item_id=w.id AND r.responsible_allocation_id=a.id
 JOIN atlas.work_result_acceptances acc
  ON acc.execution_result_id=r.id AND acc.decision='accepted'
 WHERE w.work_state='completed'
   AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
   AND a.establishment_basis_kind='self_adoption'
   AND a.allocation_role='responsible' AND a.state='completed'
   AND m.active AND m.user_id=r.reported_by_user_id
   AND r.result_kind='completed'
   AND acc.acceptance_kind='self_responsible_person_attestation'
 ORDER BY r.reported_at DESC,w.id LIMIT 1;
 IF v_work.id IS NULL THEN
  RAISE EXCEPTION 'No self-adopted accepted historical Work to test safely'; END IF;
 SELECT r.* INTO v_old FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances acc ON acc.execution_result_id=r.id
 WHERE r.work_item_id=v_work.id AND acc.decision='accepted'
  AND acc.acceptance_kind='self_responsible_person_attestation'
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 SELECT * INTO v_alloc FROM atlas.work_allocations
 WHERE id=v_old.responsible_allocation_id;
 SELECT * INTO v_member FROM atlas.organization_memberships
 WHERE id=v_alloc.assignee_membership_id;
 IF v_member.id IS NULL OR NOT v_member.active
   OR v_member.user_id IS DISTINCT FROM v_old.reported_by_user_id
 THEN RAISE EXCEPTION 'Original source actor no longer present'; END IF;

 SELECT count(*) INTO v_results_before FROM atlas.work_execution_results r
 WHERE r.work_item_id=v_work.id;
 SELECT count(*) INTO v_accepted_before FROM atlas.work_result_acceptances acc
 WHERE acc.work_item_id=v_work.id AND acc.decision='accepted';
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_old.reported_by_user_id::text,true);
 -- Same original historical result is NOT a new Done and needs no new event.
 v_old_receipt:=atlas.report_self_responsible_company_work_self_api_v1(
   v_work.id,'completed',v_old.idempotency_key,v_old.payload);
 IF v_old_receipt->>'contractVersion'<>'universal_work_lifecycle_transition_v1'
   OR v_old_receipt->>'historicalRecordedCompletion'<>'true'
   OR v_old_receipt->>'newTransitionApplied'<>'false'
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work.id
       AND e.event_kind='work_transition_applied')<>0 THEN
  RAISE EXCEPTION 'Original historical self-adoption replay fabricated a Done'; END IF;
 -- The following state changes are confined to ROLLBACK.
 UPDATE atlas.work_items SET work_state='open',
   completed_at=NULL,updated_at=clock_timestamp()
 WHERE id=v_work.id AND work_state='completed';
 UPDATE atlas.work_allocations SET state='active',
   completed_at=NULL,updated_at=clock_timestamp()
 WHERE id=v_alloc.id AND state='completed';
 IF NOT FOUND THEN RAISE EXCEPTION 'No reversible original allocation for fixture'; END IF;

 SELECT p.user_id INTO v_other_uid FROM atlas.principals p
 WHERE p.status='active' AND p.user_id IS NOT NULL
  AND p.user_id IS DISTINCT FROM v_old.reported_by_user_id
 ORDER BY p.created_at,p.id LIMIT 1;
 IF v_other_uid IS NULL THEN RAISE EXCEPTION 'No unrelated Person test fixture'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_other_uid::text,true);
 BEGIN
   PERFORM atlas.report_self_responsible_company_work_self_api_v1(
      v_work.id,'completed',v_key,v_note);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_wrong_rejected:=true; END;
 IF NOT v_wrong_rejected THEN
   RAISE EXCEPTION 'Unallocated Person completed another Person self-adopted Work';
 END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_old.reported_by_user_id::text,true);

 v_first:=atlas.report_self_responsible_company_work_self_api_v1(
      v_work.id,'completed',v_key,v_note);
 v_replay:=atlas.report_self_responsible_company_work_self_api_v1(
      v_work.id,'completed',v_key,v_note);
 IF v_first->>'ok'<>'true'
   OR v_first->>'contractVersion'<>'universal_work_lifecycle_transition_v1'
   OR v_first->>'idempotent'<>'false'
   OR v_replay->>'idempotent'<>'true'
   OR v_first->>'eventId' IS DISTINCT FROM v_replay->>'eventId'
   OR v_first->>'recordedAt' IS DISTINCT FROM v_replay->>'recordedAt'
   OR v_first->>'reporterPersonId' IS DISTINCT FROM v_member.person_id::text
   OR v_first->>'responsiblePersonId' IS DISTINCT FROM v_member.person_id::text
   OR v_first->>'performanceIsWitnessedClaim'<>'false'
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work.id AND e.event_kind='work_transition_applied')<>1
   OR (SELECT count(*) FROM atlas.work_execution_results r
     WHERE r.work_item_id=v_work.id)<>v_results_before+1
   OR (SELECT count(*) FROM atlas.work_result_acceptances acc
     WHERE acc.work_item_id=v_work.id AND acc.decision='accepted')<>v_accepted_before+1
   OR (SELECT state_matches FROM atlas.work_lifecycle_shadow_reconciliation_v1
       WHERE work_item_id=v_work.id) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Self-adopted original result writer did not yield one Done'; END IF;
 BEGIN
  PERFORM atlas.report_self_responsible_company_work_self_api_v1(
    v_work.id,'completed',v_key,v_note||'{"note":"altered evidence"}'::jsonb);
 EXCEPTION WHEN SQLSTATE '23505' THEN v_collision_rejected:=true; END;
 IF NOT v_collision_rejected THEN
  RAISE EXCEPTION 'Self-adopted action accepted contradictory evidence on replay'; END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=v_work.id AND e.event_kind='work_transition_applied')<>1
 THEN RAISE EXCEPTION 'Self-adopted replay generated a second Done'; END IF;
END;
$self_source_cutover$;
SELECT 'SELF_ADOPTED_ORIGINAL_WRITER_ONE_DONE_AND_HISTORICAL_REPLAY_ROLLBACK_PASS' AS verdict;
-- MUST ROLLBACK the encompassing transaction.
