-- ONE ROLLBACK TRANSACTION, after 04+06+10+12. Use a new synthetic
-- Work and validated original self-adoption source membership. NEVER
-- reopen/redo a historical completion or manufacture a real-world Actual.
-- Real signed GoTrue worker session testing remains a separate release gate.
DO $self_source_cutover$
DECLARE
 v_template atlas.work_allocations%ROWTYPE;
 v_historical atlas.work_execution_results%ROWTYPE;
 v_member atlas.organization_memberships%ROWTYPE;
 v_work uuid;
 v_original_allocation uuid;
 v_key text:='self-original-cutover-rollback:'||gen_random_uuid();
 v_note jsonb:=jsonb_build_object('note',
   'TEST ONLY: no actual work performed, all source changes rolled back');
 v_old_receipt jsonb;
 v_first jsonb;
 v_replay jsonb;
 v_other_uid uuid;
 v_wrong_rejected boolean:=false;
 v_collision_rejected boolean:=false;
BEGIN
 SELECT a.* INTO v_template
 FROM atlas.work_allocations a
 JOIN atlas.organization_memberships m ON m.id=a.assignee_membership_id
    AND m.active AND m.user_id IS NOT NULL
 JOIN atlas.work_items w ON w.id=a.work_item_id
    AND w.work_state='completed'
 WHERE a.establishment_basis_kind='self_adoption'
   AND a.state='completed'
   AND a.assignee_membership_id=a.assigned_by_membership_id
   AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
 ORDER BY a.created_at DESC LIMIT 1;
 IF v_template.id IS NULL THEN
   RAISE EXCEPTION 'No original self-adoption authority/provenance fixture'; END IF;
 SELECT * INTO v_member FROM atlas.organization_memberships
 WHERE id=v_template.assignee_membership_id AND active;
 SELECT r.* INTO v_historical
 FROM atlas.work_execution_results r
 JOIN atlas.work_result_acceptances accepted
  ON accepted.execution_result_id=r.id
  AND accepted.decision='accepted'
  AND accepted.acceptance_kind='self_responsible_person_attestation'
 WHERE r.work_item_id=v_template.work_item_id
   AND r.responsible_allocation_id=v_template.id
   AND r.reported_by_user_id=v_member.user_id
   AND r.result_kind='completed'
 ORDER BY r.reported_at DESC,r.id LIMIT 1;
 IF v_member.id IS NULL OR v_member.user_id IS NULL OR v_member.person_id IS NULL
   OR v_historical.id IS NULL THEN
   RAISE EXCEPTION 'Missing intact original self-adopted signed source Result'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_member.user_id::text,true);
 -- Historical replay does not claim that an old completion is a newly
 -- signed lifecycle action, and leaves the original Work completed.
 v_old_receipt:=atlas.report_self_responsible_company_work_self_api_v1(
   v_template.work_item_id,'completed',
   v_historical.idempotency_key,v_historical.payload);
 IF v_old_receipt->>'contractVersion'<>'universal_work_lifecycle_transition_v1'
   OR v_old_receipt->>'historicalRecordedCompletion'<>'true'
   OR v_old_receipt->>'newTransitionApplied'<>'false'
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
       WHERE e.work_item_id=v_template.work_item_id
         AND e.event_kind='work_transition_applied')<>0
 THEN RAISE EXCEPTION 'Old completed self-adopted Work was falsely re-attested'; END IF;

 -- New original synthetic Work and a truthful exact self-adoption record.
 -- Both exist only within this ROLLBACK transaction and use a real,
 -- current source membership (never an invented worker or employee seat).
 INSERT INTO atlas.work_items(
   organization_id,title,instructions,work_state,result_contract_key,metadata)
 VALUES(v_template.organization_id,
   '[ROLLBACK TEST] Original Self-Responsible Work lifecycle',
   'No actual task, completion or obligation. Test-only original.',
   'open','ordinary_company_work_worker_attestation_v1',
   '{"rollbackOnly":true,"neverRelease":true}'::jsonb)
 RETURNING id INTO v_work;
 INSERT INTO atlas.work_allocations(
   organization_id,work_item_id,assignee_membership_id,
   assigned_by_membership_id,allocation_role,state,
   establishment_basis_kind,establishment_basis)
 VALUES(v_template.organization_id,v_work,v_member.id,v_member.id,
   'responsible','active','self_adoption',
   jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','self_adoption',
      'sourceKind','owner_self_adoption_existing_company_work',
      'sourceId',v_work,'workItemId',v_work,'selfPersonId',v_member.person_id,
      'organizationId',v_template.organization_id,
      'nativeLedgerId',v_template.establishment_basis->>'nativeLedgerId',
      'actorMembershipId',v_member.id,
      'assigneeMembershipId',v_member.id,
      'testOnly',true))
 RETURNING id INTO v_original_allocation;

 SELECT p.user_id INTO v_other_uid FROM atlas.principals p
 WHERE p.status='active' AND p.user_id IS NOT NULL
   AND p.user_id IS DISTINCT FROM v_member.user_id
 ORDER BY p.created_at,p.id LIMIT 1;
 IF v_other_uid IS NULL THEN RAISE EXCEPTION 'No unrelated Person fixture'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_other_uid::text,true);
 BEGIN
   PERFORM atlas.report_self_responsible_company_work_self_api_v1(
     v_work,'completed',v_key,v_note);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_wrong_rejected:=true; END;
 IF NOT v_wrong_rejected THEN
   RAISE EXCEPTION 'Wrong Person completed protected self-responsible Work'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_member.user_id::text,true);

 v_first:=atlas.report_self_responsible_company_work_self_api_v1(
    v_work,'completed',v_key,v_note);
 v_replay:=atlas.report_self_responsible_company_work_self_api_v1(
    v_work,'completed',v_key,v_note);
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
     WHERE e.work_item_id=v_work AND e.event_kind='work_transition_applied')<>1
   OR (SELECT count(*) FROM atlas.work_execution_results r
     WHERE r.work_item_id=v_work)<>1
   OR (SELECT count(*) FROM atlas.work_result_acceptances a
     WHERE a.work_item_id=v_work AND a.decision='accepted')<>1
   OR (SELECT state_matches FROM atlas.work_lifecycle_shadow_reconciliation_v1
     WHERE work_item_id=v_work) IS DISTINCT FROM true
   OR (SELECT work_state FROM atlas.work_items WHERE id=v_work)<>'completed'
   OR (SELECT state FROM atlas.work_allocations WHERE id=v_original_allocation)
     <>'completed'
 THEN RAISE EXCEPTION 'Self-adopted original result writer did not yield one Done'; END IF;

 BEGIN
  PERFORM atlas.report_self_responsible_company_work_self_api_v1(
    v_work,'completed',v_key,v_note||'{"note":"contradictory evidence"}'::jsonb);
 EXCEPTION WHEN SQLSTATE '23505' THEN v_collision_rejected:=true; END;
 IF NOT v_collision_rejected THEN
   RAISE EXCEPTION 'Same self-adopted action accepted contradictory evidence'; END IF;
 IF (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work AND e.event_kind='work_transition_applied')<>1
 THEN RAISE EXCEPTION 'Contradictory replay generated second Done'; END IF;
END;
$self_source_cutover$;
SELECT 'SELF_ADOPTED_ORIGINAL_WRITER_ONE_DONE_HISTORICAL_REPLAY_PASS' AS verdict;
-- MUST ROLLBACK enclosing transaction.
