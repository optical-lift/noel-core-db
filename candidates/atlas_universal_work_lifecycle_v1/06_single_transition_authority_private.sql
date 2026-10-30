-- GATE 2 PREVIEW ONLY. Not an independent Done API. This is the
-- eventual single lifecycle transition authority. No client EXECUTE, no
-- production release, and no old writer delegation until signed acceptance.
-- Admits signed responsible-Person attestation and evidence-grounded
-- governor witness for ordinary Work through THIS SAME authority. Witness
-- is an owner's recorded CLAIM about someone else's performance.
-- Management, farm, household, communications and production remain closed.
-- Event shared-checklist state confirmation is admitted ONLY with existing
-- signed Ledger/Occurrence identity and explicit non-performance evidence.

ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_event_kind_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_event_kind_check CHECK(event_kind IN(
 'historical_state_snapshot','work_established','work_state_observed',
 'result_reported','result_accepted','responsibility_observed',
 'plan_event_observed','work_transition_applied'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_actor_attribution_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_actor_attribution_check CHECK(
 actor_attribution IN ('source_reporter_field','session_claim_only',
 'unattributed','verified_signed_transition'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_provenance_kind_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_provenance_kind_check CHECK(
 provenance_kind IN ('historical_snapshot','observed_original_change',
 'linked_original_evidence','authoritative_transition'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_event_state_shape_v1;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_event_state_shape_v1 CHECK(
 (event_kind IN ('historical_state_snapshot','work_established',
   'work_state_observed','work_transition_applied'))=(to_state IS NOT NULL));
CREATE UNIQUE INDEX work_lifecycle_one_transition_action_v1
 ON atlas.work_lifecycle_events_v1(work_item_id,source_idempotency_key)
 WHERE event_kind='work_transition_applied';

CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(
 p_work_item_id uuid,p_transition_kind text,p_result_id uuid,
 p_idempotency_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transition$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_accept atlas.work_result_acceptances%ROWTYPE;
 v_allocation atlas.work_allocations%ROWTYPE;
 v_event atlas.work_lifecycle_events_v1%ROWTYPE;
 v_actor uuid:=atlas.current_person_id_v1();
 v_uid uuid:=auth.uid();
 v_native_ledger uuid;
 v_report_mode text;
 v_witnessed boolean:=false;
 v_shared_event boolean:=false;
 v_physical_care boolean:=false;
 v_occurrence_id uuid;
 v_claimed_performer uuid;
 v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
 v_completed_at timestamptz;
 v_sequence bigint;
BEGIN
 IF v_uid IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
   OR p_result_id IS NULL OR v_key IS NULL OR length(v_key)>160
   OR p_transition_kind IS NULL
   OR p_transition_kind NOT IN ('complete','cancel') THEN
   RAISE EXCEPTION 'Exact signed original Work transition, evidence and action required'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(
     'atlas.work_lifecycle_events_v1:'||p_work_item_id::text,0));
 -- Serial original Work custody. A source trigger cannot independently
 -- establish a second authoritative event in this transaction.
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL THEN
   RAISE EXCEPTION 'This authority slice requires original Organization Work'
    USING ERRCODE='42501';
 END IF;
 -- The only cancellation admitted in this draft is a *reviewed historical*
 -- self-adopted original.  This is not a general cancel API.  The
 -- p_result_id slot carries the immutable historical review event ONLY for
 -- transition_kind='cancel'; no physical Result or Acceptance is created.
 IF p_transition_kind='cancel' THEN
   DECLARE
     v_review atlas.historical_self_adoption_review_events_v1%ROWTYPE;
     v_link atlas.historical_self_adoption_review_events_v1%ROWTYPE;
     v_impact jsonb;
     v_at timestamptz;
     v_plan atlas.work_execution_plans%ROWTYPE;
   BEGIN
     SELECT * INTO v_review
     FROM atlas.historical_self_adoption_review_events_v1 h
     WHERE h.id=p_result_id AND h.work_item_id=v_work.id
       AND h.organization_id=v_work.organization_id
       AND h.event_kind='governor_reviewed'
       AND h.outcome='obsolete_cancelled';
     IF v_review.id IS NULL THEN
       RAISE EXCEPTION 'Exact obsolete historical review required for retirement'
         USING ERRCODE='42501';
     END IF;
     SELECT * INTO v_link
     FROM atlas.historical_self_adoption_review_events_v1 h
     WHERE h.id=v_review.parent_event_id
       AND h.event_kind='person_confirmed'
       AND h.ledger_id=v_review.ledger_id
       AND h.work_item_id=v_work.id
       AND h.organization_id=v_work.organization_id
       AND h.allocation_id=v_review.allocation_id;
     IF v_link.id IS NULL
       OR NOT EXISTS(
         SELECT 1 FROM atlas.company_work_native_ledger_relevance r
         WHERE r.organization_id=v_work.organization_id
           AND r.ledger_id=v_review.ledger_id
           AND r.work_item_id=v_work.id AND r.attribution_state='active')
       OR atlas.company_work_native_ledger_owner_self_v1(
           v_work.organization_id,v_review.ledger_id) IS DISTINCT FROM v_actor
       OR NOT EXISTS(
         SELECT 1 FROM atlas.work_allocations a
         WHERE a.id=v_review.allocation_id
           AND a.work_item_id=v_work.id
           AND a.organization_id=v_work.organization_id
           AND a.establishment_basis_kind='self_adoption')
     THEN RAISE EXCEPTION 'Present native Ledger governor and reviewed source required'
       USING ERRCODE='42501'; END IF;
     -- Replay retains the exact original review/actor/action and terminal
     -- projection.  A same-key completion or different reviewer conflicts.
     SELECT * INTO v_event
     FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work.id
       AND e.event_kind='work_transition_applied'
       AND e.source_idempotency_key=v_key
     ORDER BY e.sequence_no DESC LIMIT 1;
     IF v_event.id IS NOT NULL THEN
       IF v_event.source_table IS DISTINCT FROM
             'atlas.historical_self_adoption_review_events_v1'
         OR v_event.source_row_id IS DISTINCT FROM v_review.id
         OR v_event.actor_user_id IS DISTINCT FROM v_uid
         OR v_event.from_state IS DISTINCT FROM 'open'
         OR v_event.to_state IS DISTINCT FROM 'cancelled'
         OR v_work.work_state IS DISTINCT FROM 'cancelled'
       THEN RAISE EXCEPTION 'Conflicting historical retirement replay'
          USING ERRCODE='23505'; END IF;
       RETURN jsonb_build_object(
         'ok',true,'contractVersion','universal_work_lifecycle_transition_v1',
         'idempotent',true,'eventId',v_event.id,'workItemId',v_work.id,
         'workState','cancelled','historicalReviewId',v_review.id,
         'originalResultId',null,'acceptedEvidenceId',null,
         'personalPerformanceClaimed',false);
     END IF;
     IF v_work.work_state<>'open'
        OR v_work.completed_at IS NOT NULL
        OR v_work.cancelled_at IS NOT NULL
     THEN RAISE EXCEPTION 'Only an original open historical Work may be retired'
       USING ERRCODE='23514'; END IF;
     -- Use the *installed* retirement dependency snapshot AND the existing
     -- cancellation guard. No bypass for requirements/relations/offers,
     -- worker projections, any prior Result or active time contracts.
     v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
     IF v_impact IS NULL
       OR v_impact->>'workState' IS DISTINCT FROM 'open'
       OR jsonb_array_length(v_impact->'requirements')<>0
       OR jsonb_array_length(v_impact->'relations')<>0
       OR jsonb_array_length(v_impact->'pendingOfferIds')<>0
       OR jsonb_array_length(v_impact->'projectionIds')<>0
       OR jsonb_array_length(v_impact->'executionResultIds')<>0
       OR jsonb_array_length(v_impact->'activeTimeContractIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAdapterIds')<>0
       OR EXISTS(SELECT 1 FROM atlas.work_allocations a
         WHERE a.work_item_id=v_work.id AND a.state='active'
           AND a.id IS DISTINCT FROM v_review.allocation_id)
       OR EXISTS(SELECT 1 FROM atlas.work_execution_plans p
         WHERE p.work_item_id=v_work.id
           AND p.plan_state IN ('active','needs_replan')
           AND p.responsible_allocation_id IS DISTINCT FROM v_review.allocation_id)
     THEN RAISE EXCEPTION 'Historical Work has dependencies needing separate governor reconciliation'
       USING ERRCODE='23514'; END IF;
     v_at:=clock_timestamp();
     -- Existing referenced responsibility and plan history survives; only
     -- the explicitly reviewed active legacy allocation/its plans unwind.
     FOR v_plan IN
       SELECT * FROM atlas.work_execution_plans p
       WHERE p.work_item_id=v_work.id
         AND p.plan_state IN ('active','needs_replan')
         AND p.responsible_allocation_id=v_review.allocation_id
       FOR UPDATE
     LOOP
       UPDATE atlas.work_execution_plans
       SET plan_state='withdrawn',updated_at=v_at,
         plan_reason='Historical obligation retired after native governor review',
         metadata=coalesce(metadata,'{}'::jsonb) ||
           jsonb_build_object('historicalRetirementReviewId',v_review.id,
                              'actorPersonId',v_actor)
       WHERE id=v_plan.id;
       INSERT INTO atlas.work_execution_plan_events(
         organization_id,work_item_id,plan_id,event_kind,
         from_planned_service_date,from_exposure_service_date,
         actor_membership_id,reason,metadata)
       VALUES(v_work.organization_id,v_work.id,v_plan.id,'withdrawn',
         v_plan.planned_service_date,v_plan.exposure_service_date,NULL,
         'Historical obligation retired after native governor review',
         jsonb_build_object('historicalRetirementReviewId',v_review.id,
                            'actorPersonId',v_actor,
                            'modernPerformanceClaimed',false));
     END LOOP;
     UPDATE atlas.work_allocations
       SET state='released',released_at=coalesce(released_at,v_at),
         updated_at=v_at,
         metadata=coalesce(metadata,'{}'::jsonb) ||
           jsonb_build_object('historicalRetirementReviewId',v_review.id,
                              'actorPersonId',v_actor,
                              'newPersonAssignmentCreated',false)
     WHERE id=v_review.allocation_id AND work_item_id=v_work.id
       AND state='active' AND establishment_basis_kind='self_adoption';
     -- Recheck with the same installed dependency helper after the unwind;
     -- the existing Work cancellation trigger independently enforces this.
     v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
     IF jsonb_array_length(v_impact->'requirements')<>0
       OR jsonb_array_length(v_impact->'relations')<>0
       OR jsonb_array_length(v_impact->'pendingOfferIds')<>0
       OR jsonb_array_length(v_impact->'projectionIds')<>0
       OR jsonb_array_length(v_impact->'executionResultIds')<>0
       OR jsonb_array_length(v_impact->'activeTimeContractIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAllocationIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activePlanIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAdapterIds')<>0
     THEN RAISE EXCEPTION 'Original dependencies changed during governed retirement'
       USING ERRCODE='40001'; END IF;
     SELECT coalesce(max(e.sequence_no),0)+1 INTO v_sequence
       FROM atlas.work_lifecycle_events_v1 e WHERE e.work_item_id=v_work.id;
     INSERT INTO atlas.work_lifecycle_events_v1(
       work_item_id,organization_id,household_id,sequence_no,
       event_kind,from_state,to_state,actor_user_id,actor_attribution,
       source_table,source_row_id,source_idempotency_key,provenance_kind,
       occurred_at,evidence_refs)
     VALUES(v_work.id,v_work.organization_id,NULL,v_sequence,
       'work_transition_applied','open','cancelled',v_uid,
       'verified_signed_transition',
       'atlas.historical_self_adoption_review_events_v1',
       v_review.id,v_key,'authoritative_transition',v_at,
       jsonb_build_object(
         'transitionKind','cancel','authorityMode','native_governor_historical_retirement',
         'historicalReviewId',v_review.id,'historicalPersonLinkId',v_link.id,
         'historicalAllocationId',v_review.allocation_id,
         'ledgerId',v_review.ledger_id,'reviewOutcome','obsolete_cancelled',
         'workerPerformanceClaimed',false,'newActualRecorded',false,
         'newResultAccepted',false))
     RETURNING * INTO v_event;
     UPDATE atlas.work_items
       SET work_state='cancelled',cancelled_at=v_at,
         completed_at=NULL,updated_at=v_at
     WHERE id=v_work.id AND work_state='open';
     IF NOT FOUND OR
       (SELECT work_state FROM atlas.work_items WHERE id=v_work.id)
         IS DISTINCT FROM 'cancelled'
     THEN RAISE EXCEPTION 'Original historical Work retirement projection drifted'
       USING ERRCODE='23514'; END IF;
     RETURN jsonb_build_object(
       'ok',true,'contractVersion','universal_work_lifecycle_transition_v1',
       'idempotent',false,'eventId',v_event.id,'workItemId',v_work.id,
       'workState','cancelled','historicalReviewId',v_review.id,
       'originalResultId',null,'acceptedEvidenceId',null,
       'personalPerformanceClaimed',false);
   END;
 END IF;
 v_shared_event:=(v_work.source_object_type='ledger_occurrence_shared_work'
   AND v_work.result_contract_key='ledger_occurrence_shared_confirmation_v1');
 v_physical_care:=(v_work.source_object_type='rhythm_state'
   AND v_work.result_contract_key='continuing_care_actual_v1');
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.id=p_result_id AND r.work_item_id=v_work.id
   AND r.organization_id=v_work.organization_id
   AND r.household_id IS NULL
   AND r.result_kind='completed'
   AND r.result_contract_key IN (
     'ordinary_company_work_worker_attestation_v1',
     'ledger_occurrence_shared_confirmation_v1',
     'continuing_care_actual_v1')
   AND r.reported_by_user_id=v_uid
   AND r.idempotency_key=v_key;
 IF v_result.id IS NULL
   OR v_work.result_contract_key IS DISTINCT FROM v_result.result_contract_key
   OR (v_shared_event IS DISTINCT FROM
       (v_result.result_contract_key='ledger_occurrence_shared_confirmation_v1'))
   OR (v_physical_care IS DISTINCT FROM
       (v_result.result_contract_key='continuing_care_actual_v1'))
 THEN RAISE EXCEPTION 'Original signed Work Result missing or mismatched'
    USING ERRCODE='42501'; END IF;
 SELECT * INTO v_accept FROM atlas.work_result_acceptances a
 WHERE a.execution_result_id=v_result.id AND a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id AND a.household_id IS NULL
   AND a.decision='accepted';
 IF v_accept.id IS NULL THEN
   RAISE EXCEPTION 'Existing accepted source evidence required'
    USING ERRCODE='42501';
 END IF;
 IF v_shared_event THEN
   -- Shared checklist Done asserts a state, not who physically performed it.
   -- Its original result has NO responsible allocation by design.
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
      v_result.metadata->>'ledgerId');
   v_occurrence_id:=atlas.rhythm_safe_uuid_v1(
      v_result.metadata->>'occurrenceId');
   IF v_native_ledger IS NULL OR v_occurrence_id IS NULL
     OR v_work.source_object_id IS DISTINCT FROM v_occurrence_id
     OR v_work.metadata->>'ledgerId' IS DISTINCT FROM v_native_ledger::text
     OR v_work.metadata->>'sourceContract' IS DISTINCT FROM
       'ledger_occurrence_shared_work_v1'
     OR v_result.responsible_allocation_id IS NOT NULL
     OR v_result.metadata->>'source' IS DISTINCT FROM
       'mark_ledger_occurrence_shared_work_done_self_api_v1'
     OR v_result.metadata->>'actorPersonId' IS DISTINCT FROM v_actor::text
     OR v_result.metadata->>'notWorkerResult' IS DISTINCT FROM 'true'
     OR v_result.metadata->>'allocationNotRequired' IS DISTINCT FROM 'true'
     OR v_result.payload->>'stateAssertion' IS DISTINCT FROM
       'ordinary_shared_work_marked_done'
     OR v_result.payload->>'markedByPersonId' IS DISTINCT FROM v_actor::text
     OR v_result.payload->>'personalPerformanceNotClaimed' IS DISTINCT FROM 'true'
     OR v_result.payload->'performedByPersonId' IS DISTINCT FROM 'null'::jsonb
     OR v_accept.acceptance_kind IS DISTINCT FROM
       'shared_checklist_state_confirmation'
     OR v_accept.evidence->>'markedByPersonId' IS DISTINCT FROM v_actor::text
     OR v_accept.evidence->>'sourceActionId' IS DISTINCT FROM
       v_result.payload->>'sourceActionId'
     OR v_accept.evidence->>'physicalPerformerAsserted' IS DISTINCT FROM 'false'
     OR atlas.ledger_occurrence_shared_work_actor_self_v1(
       v_work.organization_id,v_native_ledger,v_occurrence_id)
         IS DISTINCT FROM v_actor
     OR NOT EXISTS (
       SELECT 1 FROM atlas.work_item_context_links ctx
       JOIN atlas.company_work_native_ledger_relevance rel
         ON rel.organization_id=ctx.organization_id
          AND rel.work_item_id=ctx.work_item_id
          AND rel.ledger_id=v_native_ledger
          AND rel.attribution_state='active'
       WHERE ctx.organization_id=v_work.organization_id
         AND ctx.work_item_id=v_work.id
         AND ctx.subject_domain='temporal'
         AND ctx.subject_kind='occurrence'
         AND ctx.subject_id=v_occurrence_id
         AND ctx.relation_kind='for'
     )
   THEN RAISE EXCEPTION 'Exact shared Event evidence or current Person disclosure unavailable'
      USING ERRCODE='42501'; END IF;
   v_claimed_performer:=NULL;
   v_witnessed:=false;
 ELSE

  -- Care can finish original Work only with an exact first-party physical
  -- Actual, observation, accepted result, and qualifying rhythm satisfaction.
  -- A checkbox or elapsed interval never manufactures this evidence.
  IF v_physical_care AND (
    v_accept.acceptance_kind IS DISTINCT FROM 'source_qualified_physical_actual'
    OR v_accept.accepted_by_domain IS DISTINCT FROM 'continuing_care_actual'
    OR v_result.metadata->>'authenticatedReporterPersonId' IS DISTINCT FROM v_actor::text
    OR NOT EXISTS(
      SELECT 1 FROM atlas.rhythm_state s
      JOIN atlas.care_result_events c
        ON c.id=atlas.rhythm_safe_uuid_v1(v_result.payload->>'careResultId')
        AND c.scope_kind='farm' AND c.scope_id=s.farm_id
        AND c.subject_domain='farm' AND c.subject_kind='growing_object'
        AND c.subject_id=s.subject_id::text
      JOIN atlas.care_observation_events o
        ON o.id=atlas.rhythm_safe_uuid_v1(v_result.payload->>'careObservationId')
        AND o.scope_kind=c.scope_kind AND o.scope_id=c.scope_id
        AND o.subject_domain=c.subject_domain AND o.subject_kind=c.subject_kind
        AND o.subject_id=c.subject_id
      JOIN atlas.rhythm_satisfactions sat
        ON sat.rhythm_state_id=s.id AND sat.organization_id=s.organization_id
        AND sat.farm_id=s.farm_id AND sat.source_kind='continuing_care_actual'
        AND sat.source_id=c.id AND sat.satisfaction_kind IN ('full','conditional')
      JOIN atlas.work_item_context_links ctx
        ON ctx.organization_id=v_work.organization_id AND ctx.work_item_id=v_work.id
        AND ctx.subject_domain='spatial' AND ctx.subject_kind='growing_object'
        AND ctx.subject_id=s.subject_id AND ctx.relation_kind='acts_on'
      WHERE s.id=v_work.source_object_id
        AND s.organization_id=v_work.organization_id
        AND s.subject_kind='growing_object'
        AND s.rhythm_key IN ('weed_stewardship','mowing')
        AND v_result.metadata->>'rhythmStateId'=s.id::text
        AND c.source_kind='continuing_care_actual'
        AND c.source_key=v_key AND c.actor_user_id=v_uid
        AND c.metadata->>'workItemId'=v_work.id::text
        AND c.metadata->>'rhythmStateId'=s.id::text
        AND c.metadata->>'physicalActualKind'=v_result.metadata->>'actualKind'
        AND o.source_kind='continuing_care_actual_observation'
        AND o.source_key='continuing-care-observation:'||c.id::text
        AND o.observed_by_user_id=v_uid
        AND o.metadata->>'workItemId'=v_work.id::text
        AND o.metadata->>'careResultId'=c.id::text
        AND c.condition_after=o.condition_state
        AND v_result.payload->>'conditionAfter'=c.condition_after
        AND v_result.payload->>'actualKind'=v_result.metadata->>'actualKind'
        AND v_accept.evidence->>'careResultId'=c.id::text
        AND v_accept.evidence->>'careObservationId'=o.id::text
        AND v_accept.evidence->>'actualKind'=v_result.metadata->>'actualKind'
        AND v_accept.evidence->>'sourceRuleId'=sat.rhythm_rule_id::text
        AND v_accept.evidence->>'actualReporter'=v_actor::text
        AND sat.source_event=v_result.metadata->>'actualKind'
        AND sat.created_by_user_id=v_uid
        AND sat.evidence->>'workItemId'=v_work.id::text
        AND sat.evidence->>'careResultId'=c.id::text
        AND sat.evidence->>'workResultId'=v_result.id::text
    )
  ) THEN
    RAISE EXCEPTION 'Exact qualifying physical Actual and rhythm satisfaction required'
      USING ERRCODE='42501';
  END IF;
 v_report_mode:=coalesce(v_result.metadata->>'reportMode','own_work');
 v_witnessed:=v_report_mode='owner_witness';
 IF (v_witnessed AND (
       v_accept.acceptance_kind IS DISTINCT FROM 'owner_witnessed_person_result'
       OR v_result.metadata->>'performanceIsWitnessedClaim' IS DISTINCT FROM 'true'
       OR v_result.metadata->>'authenticatedReporterPersonId' IS DISTINCT FROM v_actor::text
       OR length(btrim(coalesce(v_result.payload->>'ownerWitnessEvidence',''))) NOT BETWEEN 16 AND 2000
       OR v_accept.evidence->>'ownerWitnessEvidence' IS DISTINCT FROM
         v_result.payload->>'ownerWitnessEvidence'))
   OR (NOT v_witnessed AND (
       v_report_mode<>'own_work'
       OR (v_physical_care AND v_accept.acceptance_kind IS DISTINCT FROM
             'source_qualified_physical_actual')
       OR (NOT v_physical_care AND v_accept.acceptance_kind NOT IN (
         'self_responsible_person_attestation','delegated_worker_attestation'))
       OR (v_result.metadata ? 'authenticatedReporterPersonId'
         AND v_result.metadata->>'authenticatedReporterPersonId'
              IS DISTINCT FROM v_actor::text)))
 THEN RAISE EXCEPTION 'Accepted evidence mode or reporter attribution mismatch'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.id=v_result.responsible_allocation_id
   AND a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id
   AND a.household_id IS NULL
   AND a.allocation_role='responsible'
   AND a.state IN ('active','completed');
 IF v_allocation.id IS NULL THEN
   RAISE EXCEPTION 'Current original responsibility unavailable'
     USING ERRCODE='42501'; END IF;
 v_claimed_performer:=v_allocation.assignee_canonical_person_id;
 IF v_witnessed THEN
   -- Original accountable person is NOT the one clicking Done.
   -- The owner's evidence must point to that SAME responsible Person.
   IF v_claimed_performer IS NULL OR v_claimed_performer=v_actor
     OR v_result.metadata->>'source' IS DISTINCT FROM
       'report_connected_person_company_work_internal_v1'
     OR v_result.metadata->>'canonicalResponsiblePersonId'
       IS DISTINCT FROM v_claimed_performer::text
     OR v_accept.evidence->>'canonicalResponsiblePersonId'
       IS DISTINCT FROM v_claimed_performer::text
     OR v_accept.evidence->>'responsibleAllocationId'
       IS DISTINCT FROM v_allocation.id::text
     OR v_accept.evidence->>'authenticatedReporterPersonId'
       IS DISTINCT FROM v_actor::text
     OR v_allocation.establishment_basis_kind NOT IN(
       'person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
     )
   THEN RAISE EXCEPTION 'Witness claim does not match responsible Person provenance'
       USING ERRCODE='42501'; END IF;
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
     v_allocation.establishment_basis->>'nativeLedgerId');
   IF v_native_ledger IS NULL OR
     atlas.company_work_native_ledger_owner_self_v1(
       v_work.organization_id,v_native_ledger) IS DISTINCT FROM v_actor
   THEN RAISE EXCEPTION 'Present native Ledger root authority required for witness'
       USING ERRCODE='42501'; END IF;
 ELSIF v_allocation.establishment_basis_kind='self_adoption' THEN
   -- Decision #2392: legacy membership remains history, not a signed authority.
   -- Never re-open or auto-convert a historical original Work here.
   RAISE EXCEPTION 'Historical self-adopted responsibility requires native reconciliation'
     USING ERRCODE='42501';
 ELSIF v_allocation.assignee_canonical_person_id IS DISTINCT FROM v_actor THEN
   -- Every accepted new ordinary Done requires the native responsible Person.
   RAISE EXCEPTION 'Current native responsible Person required'
     USING ERRCODE='42501';
 ELSIF v_allocation.establishment_basis_kind IN (
    'person_connection_receiver_uptake','delegated_under_standing_scope',
    'ledger_connection_direct_assignment','original_subject_direct_assignment_v1') THEN
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
     v_allocation.establishment_basis->>'nativeLedgerId');
   IF v_native_ledger IS NULL
     OR NOT atlas.person_original_work_identity_disclosed_self_v1(
       v_work.organization_id,v_native_ledger,v_work.id,v_actor) THEN
     RAISE EXCEPTION 'Original Work is no longer disclosed to the Person'
       USING ERRCODE='42501'; END IF;
 ELSE
   RAISE EXCEPTION 'Responsible source establishment not yet admitted'
     USING ERRCODE='42501';
 END IF;
 END IF;
 SELECT * INTO v_event FROM atlas.work_lifecycle_events_v1 e
 WHERE e.work_item_id=v_work.id
   AND e.event_kind='work_transition_applied'
   AND e.source_idempotency_key=v_key
 ORDER BY e.sequence_no DESC LIMIT 1;
 IF v_event.id IS NOT NULL THEN
   IF v_event.source_row_id IS DISTINCT FROM v_accept.id
     OR v_event.actor_user_id IS DISTINCT FROM v_uid
     OR v_event.from_state IS DISTINCT FROM 'open'
     OR v_event.to_state IS DISTINCT FROM 'completed'
     OR v_work.work_state IS DISTINCT FROM 'completed' THEN
     RAISE EXCEPTION 'Transition action identity conflicts with original evidence'
       USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('ok',true,
     'contractVersion','universal_work_lifecycle_transition_v1',
     'idempotent',true,'eventId',v_event.id,
     'workItemId',v_work.id,'workState','completed',
     'originalResultId',v_result.id,'acceptedEvidenceId',v_accept.id,
     'reporterPersonId',v_actor,'responsiblePersonId',v_claimed_performer,
     'performanceIsWitnessedClaim',v_witnessed,
     'personalPerformanceNotClaimed',v_shared_event,
     'recordedAt',v_event.recorded_at,'effectiveAt',v_event.occurred_at);
 END IF;
 IF v_work.work_state<>'open' OR v_work.completed_at IS NOT NULL THEN
   RAISE EXCEPTION 'Original Work is not currently open; no duplicate Done'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=v_work.id
     AND e.event_kind='work_transition_applied'
     AND e.to_state='completed'
     AND e.from_state='open'
     AND e.source_row_id=v_accept.id)
 THEN RAISE EXCEPTION 'Accepted evidence already drove a lifecycle transition'
   USING ERRCODE='23505'; END IF;
 SELECT coalesce(max(e.sequence_no),0)+1 INTO v_sequence
 FROM atlas.work_lifecycle_events_v1 e WHERE e.work_item_id=v_work.id;
 v_completed_at:=clock_timestamp();
 INSERT INTO atlas.work_lifecycle_events_v1(
   work_item_id,organization_id,household_id,sequence_no,
   event_kind,from_state,to_state,actor_user_id,actor_attribution,
   source_table,source_row_id,source_idempotency_key,provenance_kind,
   occurred_at,evidence_refs)
 VALUES(v_work.id,v_work.organization_id,NULL,v_sequence,
   'work_transition_applied','open','completed',v_uid,
   'verified_signed_transition','atlas.work_result_acceptances',v_accept.id,
   v_key,'authoritative_transition',v_completed_at,
   jsonb_build_object('transitionKind','complete',
     'originalResultId',v_result.id,'acceptanceId',v_accept.id,
     'responsibleAllocationId',v_allocation.id,
     'personalPerformanceNotClaimed',v_shared_event,
     'reporterPersonId',v_actor,
     'responsiblePersonId',v_claimed_performer,
     'performanceIsWitnessedClaim',v_witnessed,
     'authorityMode',case when v_shared_event then 'event_shared_state_confirmation'
          when v_physical_care then 'source_qualified_physical_actual'
         when v_witnessed then 'ledger_governor_witness'
         else 'responsible_person_attestation' end))
 RETURNING * INTO v_event;
 -- Existing mutable state is a backward-compatible *projection* only.
 -- Old trigger chains remain present during the protected transition.
 UPDATE atlas.work_items
 SET work_state='completed',completed_at=v_completed_at,
     updated_at=v_completed_at
 WHERE id=v_work.id AND work_state='open';
 IF NOT FOUND THEN RAISE EXCEPTION 'Original Work projection drifted'
   USING ERRCODE='23514'; END IF;
 IF NOT v_shared_event AND v_allocation.state='active' THEN
   UPDATE atlas.work_allocations
     SET state='completed',completed_at=v_completed_at,updated_at=v_completed_at
   WHERE id=v_allocation.id AND state='active';
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','universal_work_lifecycle_transition_v1',
   'idempotent',false,'eventId',v_event.id,
   'workItemId',v_work.id,'workState','completed',
   'originalResultId',v_result.id,'acceptedEvidenceId',v_accept.id,
   'reporterPersonId',v_actor,'responsiblePersonId',v_claimed_performer,
   'performanceIsWitnessedClaim',v_witnessed,
   'personalPerformanceNotClaimed',v_shared_event,
   'recordedAt',v_event.recorded_at,'effectiveAt',v_event.occurred_at);
END;
$transition$;

REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(
 uuid,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
-- No public wrapper or authenticated EXECUTE. This cannot become an
-- alternate Done button while old completion writers are running.
