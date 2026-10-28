-- Gate 2A self-adoption: the responsible performer is the canonical
-- Person in the actual source membership, not a null connection assignee.
-- Run after 04 and 06 with final ROLLBACK; never commit these test changes.
DO $self_adoption_person$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_alloc atlas.work_allocations%ROWTYPE;
 v_actor uuid;
 v_receipt jsonb;
 v_replay jsonb;
BEGIN
 SELECT w.* INTO v_work
 FROM atlas.work_items w
 JOIN atlas.work_execution_results r ON r.work_item_id=w.id
 JOIN atlas.work_result_acceptances acc ON acc.execution_result_id=r.id
 JOIN atlas.work_allocations a ON a.id=r.responsible_allocation_id
 WHERE w.work_state='completed'
   AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
   AND r.result_kind='completed'
   AND r.result_contract_key=w.result_contract_key
   AND acc.decision='accepted'
   AND acc.acceptance_kind='self_responsible_person_attestation'
   AND a.establishment_basis_kind='self_adoption'
   AND a.assignee_canonical_person_id IS NULL
   AND r.reported_by_user_id IS NOT NULL
   AND EXISTS(SELECT 1 FROM atlas.organization_memberships om
     WHERE om.id=a.assignee_membership_id
       AND om.user_id=r.reported_by_user_id AND om.active)
 ORDER BY r.reported_at DESC,w.id LIMIT 1;
 IF v_work.id IS NULL THEN
   RAISE EXCEPTION 'No current self-adopted source fixture; keep admission closed'; END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.work_item_id=v_work.id AND r.result_kind='completed'
 ORDER BY reported_at DESC,id DESC LIMIT 1;
 SELECT * INTO v_alloc FROM atlas.work_allocations
 WHERE id=v_result.responsible_allocation_id;
 SELECT om.person_id INTO v_actor FROM atlas.organization_memberships om
 WHERE om.id=v_alloc.assignee_membership_id AND om.user_id=v_result.reported_by_user_id
 AND om.active;
 IF v_actor IS NULL THEN RAISE EXCEPTION 'No original self-adopted Person'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',
  v_result.reported_by_user_id::text,true);
 UPDATE atlas.work_items SET work_state='open',completed_at=NULL,
   updated_at=clock_timestamp() WHERE id=v_work.id;
 v_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'complete',v_result.id,v_result.idempotency_key);
 v_replay:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'complete',v_result.id,v_result.idempotency_key);
 IF v_receipt->>'responsiblePersonId' IS DISTINCT FROM v_actor::text
   OR v_receipt->>'reporterPersonId' IS DISTINCT FROM v_actor::text
   OR v_receipt->>'performanceIsWitnessedClaim' IS DISTINCT FROM 'false'
   OR v_receipt->>'eventId' IS DISTINCT FROM v_replay->>'eventId'
   OR (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work.id AND e.event_kind='work_transition_applied')<>1
 THEN RAISE EXCEPTION 'Self-adopted Work performer identity or replay drift'; END IF;
END;
$self_adoption_person$;
SELECT 'SELF_ADOPTION_IDENTITY_AND_SAME_DONE_RECEIPT_PASS' AS verdict;
