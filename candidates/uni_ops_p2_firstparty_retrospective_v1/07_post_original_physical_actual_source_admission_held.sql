-- UNI-OPS-01 P2 / prospective physical-Actual admission (HELD SOURCE).
-- A worker's old unassigned Activity is historical testimony ONLY.
-- To qualify a later physical Actual, a separate original must be
-- independently offered/accepted/fulfilled FIRST, then this worker must
-- independently observe the Subject AFTER that original existed.
-- This private self-reader does not issue, accept, or complete Work.
-- The existing C1 record_continuing_care_actual_self_api_v1 remains the
-- ONLY source-qualified physical Result/one Done writer after release.
CREATE FUNCTION atlas.uni_ops_p2_later_physical_actual_admission_self_held_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_work_item_id uuid,
 p_physical_observation_id uuid,
 p_proposed_actual_kind text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $admission$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_review atlas.uni_ops_p2_governor_activity_review_events_v1%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_attribution atlas.uni_ops_p2_later_worker_subject_attributions_v1%ROWTYPE;
 v_physical atlas.care_observation_events%ROWTYPE;
 v_kind text:=nullif(pg_catalog.btrim(p_proposed_actual_kind),'');
 v_native_links integer;
 v_native_selected integer;
 v_alloc uuid;
 v_relevant_work_count integer;
 v_basis text;
 v_basis_at timestamptz;
 v_ledger_attribution integer;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL
   OR p_report_id IS NULL OR p_ledger_id IS NULL
   OR p_work_item_id IS NULL OR p_physical_observation_id IS NULL
   OR v_kind IS NULL
 THEN RAISE EXCEPTION 'Current signed worker, actual source and original required'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_report
 FROM atlas.uni_ops_p2_firstparty_activity_reports_v1 r
 WHERE r.id=p_report_id;
 IF v_report.id IS NULL
    OR v_report.reporter_user_id IS DISTINCT FROM v_uid
    OR v_report.reporter_person_id IS DISTINCT FROM v_person
    OR EXISTS (
      SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 a
      WHERE a.activity_log_id=v_report.activity_log_id)
 THEN RAISE EXCEPTION 'First-party historical testimony unavailable or P1-recognized'
   USING ERRCODE='42501'; END IF;

 -- The current governor's LAST review must still acknowledge ONLY
 -- testimony. "historically acknowledged" is not physical Actual or Work.
 SELECT * INTO v_review
 FROM atlas.uni_ops_p2_governor_activity_review_events_v1 r
 WHERE r.report_id=v_report.id AND r.ledger_id=p_ledger_id
 ORDER BY r.reviewer_recorded_at DESC,r.id DESC LIMIT 1;
 IF v_review.id IS NULL
    OR v_review.outcome IS DISTINCT FROM
       'historical_testimony_acknowledged_without_actual'
    OR v_review.matched_original_work_item_id IS NOT NULL
    OR v_review.source_report_snapshot_md5 IS DISTINCT FROM
       v_report.source_summary_snapshot_md5
 THEN RAISE EXCEPTION 'Independent current historical testimony review required'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=p_work_item_id
   AND w.organization_id=v_report.organization_id
   AND w.household_id IS NULL
   AND w.work_state='open'
   AND w.source_object_type='rhythm_state'
   AND w.result_contract_key='continuing_care_actual_v1'
   AND w.metadata->>'sourceContract'='continuing_original_work_v1';
 IF v_work.id IS NULL OR v_work.created_at<=v_review.reviewer_recorded_at
    OR v_work.created_at<=v_report.report_received_at
 THEN RAISE EXCEPTION 'A later independently established current original is required'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=v_work.source_object_id
   AND s.organization_id=v_report.organization_id
   AND s.farm_id=v_report.farm_id
   AND s.subject_kind='growing_object'
   AND s.state<>'paused';
 IF v_state.id IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.growing_objects g
    WHERE g.id=v_state.subject_id AND g.farm_id=v_report.farm_id)
 THEN RAISE EXCEPTION 'Actual physical Subject no longer sourced'
   USING ERRCODE='42501'; END IF;

 -- Current worker must have a real connection and BOTH independent
 -- Subject disclosures. The source review never grants them.
 IF NOT atlas.person_has_native_ledger_connection_v1(
   v_report.organization_id,p_ledger_id,v_person)
    OR NOT COALESCE(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_person,'spatial','growing_object',
      v_state.subject_id,'identity'),false)
    OR NOT COALESCE(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_person,'spatial','growing_object',
      v_state.subject_id,'condition'),false)
 THEN RAISE EXCEPTION 'Current worker connection and both Subject disclosures required'
   USING ERRCODE='42501'; END IF;

 -- Use EXACTLY the true later worker claim OR original native log link.
 -- A text-only claim, guessed plant, many objects or changed log is held.
 IF NOT EXISTS (
   SELECT 1 FROM atlas.field_logs l
   WHERE l.id=v_report.activity_log_id AND l.source='worker_manual_log'
     AND l.retracted_at IS NULL AND l.actor_user_id=v_uid
     AND l.farm_id=v_report.farm_id
     AND pg_catalog.md5(l.id::text||':'||l.summary_sentence||':'||
       l.log_date::text||':'||l.created_at::text)
          =v_report.source_summary_snapshot_md5
 ) THEN RAISE EXCEPTION 'Historical worker log is no longer current'
   USING ERRCODE='42501'; END IF;

 SELECT count(DISTINCT l.object_id)::integer,
   count(DISTINCT l.object_id)
       FILTER(WHERE l.object_id=v_state.subject_id)::integer
 INTO v_native_links,v_native_selected
 FROM atlas.field_log_objects l
 WHERE l.field_log_id=v_report.activity_log_id AND l.object_id IS NOT NULL;
 IF v_native_links>1 OR (v_native_links=1 AND v_native_selected<>1)
 THEN RAISE EXCEPTION 'Historical Activity has ambiguous physical Subject'
   USING ERRCODE='42501'; END IF;
 IF v_native_links=1 THEN
    SELECT min(l.created_at) INTO v_basis_at
    FROM atlas.field_log_objects l
    WHERE l.field_log_id=v_report.activity_log_id
      AND l.object_id=v_state.subject_id AND l.role='touched';
    IF v_basis_at IS NULL THEN
      RAISE EXCEPTION 'Native Subject link lacks original attribution'
        USING ERRCODE='42501'; END IF;
    v_basis:='native_field_log_object_link';
 ELSE
    SELECT * INTO v_attribution
    FROM atlas.uni_ops_p2_later_worker_subject_attributions_v1 a
    WHERE a.report_id=v_report.id;
    IF v_attribution.id IS NULL
       OR v_attribution.organization_id IS DISTINCT FROM v_report.organization_id
       OR v_attribution.ledger_id IS DISTINCT FROM p_ledger_id
       OR v_attribution.farm_id IS DISTINCT FROM v_report.farm_id
       OR v_attribution.reporter_user_id IS DISTINCT FROM v_uid
       OR v_attribution.reporter_person_id IS DISTINCT FROM v_person
       OR v_attribution.attributed_growing_object_id IS DISTINCT FROM
          v_state.subject_id
       OR v_attribution.claim_is_contemporaneous_observation IS DISTINCT FROM false
       OR v_attribution.condition_was_verified IS DISTINCT FROM false
       OR v_attribution.source_log_snapshot_md5 IS DISTINCT FROM
          v_report.source_summary_snapshot_md5
    THEN RAISE EXCEPTION 'Signed later Subject claim is required'
      USING ERRCODE='42501'; END IF;
    v_basis:='later_signed_worker_subject_claim';
    v_basis_at:=v_attribution.recorded_at;
 END IF;

 -- Independent U2 accepted-first offer must already have been FULFILLED to
 -- THIS canonical Work by a genuinely separate U2B original finalizer.
 -- This reader cannot finalize or reserve it.
 SELECT * INTO v_offer
 FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.original_work_item_id=v_work.id
   AND o.organization_id=v_work.organization_id
   AND o.ledger_id=p_ledger_id
   AND o.farm_id=v_state.farm_id
   AND o.source_candidate_id=v_state.id
   AND o.source_rule_id=v_state.rhythm_rule_id
   AND o.subject_id=v_state.subject_id
   AND o.target_person_id=v_person
   AND o.offer_state='fulfilled';
 IF v_offer.id IS NULL
    OR v_offer.offered_at<=v_review.reviewer_recorded_at
    OR v_offer.responded_at IS NULL
    OR v_offer.responded_at<v_offer.offered_at
    OR v_work.created_at<v_offer.responded_at
    OR v_offer.response_action_id IS NULL
    OR v_offer.responding_principal_id IS NULL
 THEN RAISE EXCEPTION 'Work must have been separately offered and worker accepted'
   USING ERRCODE='42501'; END IF;

 SELECT a.id INTO v_alloc FROM atlas.work_allocations a
 WHERE a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id
   AND a.assignee_canonical_person_id=v_person
   AND a.allocation_role='responsible' AND a.state='active'
   AND a.establishment_basis_kind IN (
     'person_connection_receiver_uptake','delegated_under_standing_scope',
     'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
   AND a.allocated_at>=v_offer.responded_at
   AND a.allocated_at<=pg_catalog.clock_timestamp()
 ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
 IF v_alloc IS NULL THEN
  RAISE EXCEPTION 'Current independent responsible original required'
    USING ERRCODE='42501'; END IF;

 SELECT count(*)::integer INTO v_ledger_attribution
 FROM atlas.company_work_native_ledger_relevance rel
 WHERE rel.organization_id=v_work.organization_id
   AND rel.ledger_id=p_ledger_id AND rel.work_item_id=v_work.id
   AND rel.attribution_state='active';
 IF v_ledger_attribution<>1 THEN
  RAISE EXCEPTION 'Real governing Work Ledger required'
    USING ERRCODE='42501'; END IF;

 SELECT count(DISTINCT w.id)::integer INTO v_relevant_work_count
 FROM atlas.work_items w
 WHERE w.organization_id=v_work.organization_id AND w.household_id IS NULL
   AND (
    (w.source_object_type='rhythm_state' AND w.source_object_id=v_state.id)
    OR EXISTS(
      SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
        AND c.subject_domain='spatial' AND c.subject_kind='growing_object'
        AND c.subject_id=v_state.subject_id AND c.relation_kind='acts_on')
   );
 IF v_relevant_work_count<>1 THEN
  RAISE EXCEPTION 'Competing old or current Subject original requires adjudication'
    USING ERRCODE='42501'; END IF;

 -- A REAL fresh signed physical observation is a different source event
 -- from the historical worker Activity. This original and Person must
 -- already exist BEFORE that observation is created. Never retrofit a
 -- past observed_at. The standing observer's own original source policy
 -- controls which physical states are qualified.
 SELECT * INTO v_physical FROM atlas.care_observation_events e
 WHERE e.id=p_physical_observation_id
   AND e.source_kind='standing_care_person_observation'
   AND e.subject_domain='farm' AND e.subject_kind='growing_object'
   AND e.subject_id=v_state.subject_id::text
   AND e.scope_kind='farm' AND e.scope_id=v_state.farm_id
   AND e.observed_by_user_id=v_uid
   AND e.inferred_from_clock=false
   AND e.metadata->>'rhythmStateId'=v_state.id::text
   AND e.metadata->>'ledgerId'=p_ledger_id::text
   AND e.metadata->>'workerPersonId'=v_person::text;
 IF v_physical.id IS NULL
   OR v_physical.created_at<=v_work.created_at
   OR v_physical.observed_at<=v_work.created_at
   OR v_physical.observed_at<=v_review.reviewer_recorded_at
   OR v_physical.observed_at<v_basis_at
   OR v_physical.observed_at>pg_catalog.clock_timestamp()
   OR v_physical.created_at < v_physical.observed_at - INTERVAL '5 minutes'
   OR v_physical.disposition<>'reassess'
 THEN RAISE EXCEPTION 'Independent post-original physically signed observation required'
   USING ERRCODE='42501'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM atlas.care_current_state s
   WHERE s.scope_kind='farm' AND s.scope_id=v_state.farm_id
     AND s.subject_domain='farm' AND s.subject_kind='growing_object'
     AND s.subject_id=v_state.subject_id::text
     AND s.last_observation_id=v_physical.id
     AND s.condition_state=v_physical.condition_state)
 THEN RAISE EXCEPTION 'Post-original physical condition no longer current'
   USING ERRCODE='42501'; END IF;

 -- Source-specific kind/physical condition candidate. The C1 adapter
 -- independently checks the actual domain, rule's qualifying touches and
 -- all other Result/Done guards. No Result is accepted by this test.
 IF NOT (
  (v_state.rhythm_key='mowing' AND (
    (v_kind='mowed_full' AND v_physical.condition_state='resting') OR
    (v_kind='acceptable_no_cut' AND v_physical.condition_state='acceptable') OR
    (v_kind='too_wet' AND v_physical.condition_state='too_wet')
  ))
  OR
  (v_state.rhythm_key='weed_stewardship' AND (
    (v_kind='weeded_full' AND v_physical.condition_state='clear') OR
    (v_kind='weeded_partial' AND
       v_physical.condition_state IN ('row_readable','medium_pressure','heavy')) OR
    (v_kind='inspection_acceptable' AND
       v_physical.condition_state IN ('clear','row_readable'))
  ))
 ) THEN
   RAISE EXCEPTION 'Physical condition and proposed Actual kind do not agree'
   USING ERRCODE='23514';
 END IF;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','p2_prospective_physical_actual_admission_held_v1',
  'state','fresh_source_candidate_for_separate_C1_actual',
  'sourceReportId',v_report.id,
  'historicalReportReceivedAt',v_report.report_received_at,
  'governorHistoricalAcknowledgedAt',v_review.reviewer_recorded_at,
  'subjectAttributionBasis',v_basis,
  'subjectAttributionRecordedAt',v_basis_at,
  'independentOriginalWorkItemId',v_work.id,
  'independentOriginalEstablishedAt',v_work.created_at,
  'independentWorkerAcceptedAt',v_offer.responded_at,
  'physicalObservationId',v_physical.id,
  'physicalObservedAt',v_physical.observed_at,
  'physicalSourceRecordedAt',v_physical.created_at,
  'physicalConditionAfter',v_physical.condition_state,
  'proposedActualKind',v_kind,
  'historicalActivityAcceptedAsActual',false,
  'historicalExecutionTimeVerified',false,
  'historicalWorkAuthorityFabricated',false,
  'C1ResultAcceptancePerformed',false,
  'newWorkCreated',false,'doneCreated',false,
  'noSuccessorAuthorizedFromHistoricalResult',true,
  'requiresSeparateCurrentC1PhysicalActualWriter',true);
END;
$admission$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_later_physical_actual_admission_self_held_v1(
   uuid,uuid,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
