-- UNI-OPS-01 P2: later first-Work OFFER observation, not an issuer.
-- HELD, NOT a migration, no accepted Actual or retroactive assignment.
-- A retrospective report may show why present Need is being considered,
-- but NEVER grants the ability to create new Work. Only the independently
-- accepted U1A/U1B/U2A/U2C offered-first future original path may do so.
-- The report and initial governor acknowledgment preceded this offer.
-- This reader cannot call the U2B finalizer or reserve the offered Work.
CREATE FUNCTION atlas.uni_ops_p2_current_future_offer_separation_held_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_source_rhythm_state_id uuid,
 p_independent_accepted_offer_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $future$
DECLARE
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_review atlas.uni_ops_p2_governor_activity_review_events_v1%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_source jsonb;
 v_accepted jsonb;
 v_root uuid;
BEGIN
 IF auth.uid() IS NULL
   OR p_report_id IS NULL OR p_ledger_id IS NULL
   OR p_source_rhythm_state_id IS NULL
   OR p_independent_accepted_offer_id IS NULL
 THEN RAISE EXCEPTION 'Known genuine source and independently accepted offer required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_report FROM atlas.uni_ops_p2_firstparty_activity_reports_v1
 WHERE id=p_report_id;
 IF v_report.id IS NULL THEN
   RAISE EXCEPTION 'No first-party report' USING ERRCODE='42501';
 END IF;

 -- P2 04 rechecks current signed real farm Ledger governor, exact first-
 -- party object link, independent identity+condition disclosures, P1
 -- duplication, and all current original/context Work alternatives.
 v_source:=atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(
   p_report_id,p_ledger_id,p_source_rhythm_state_id);
 IF v_source->>'state' IS DISTINCT FROM
   'no_current_exact_original_identified_not_proof_of_absence'
 THEN RAISE EXCEPTION
   'Existing/ambiguous original must be separately reconciled FIRST'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_review FROM atlas.uni_ops_p2_governor_activity_review_events_v1 e
 WHERE e.report_id=v_report.id AND e.ledger_id=p_ledger_id
 ORDER BY e.reviewer_recorded_at DESC,e.id DESC LIMIT 1;
 IF v_review.id IS NULL
    OR v_review.outcome IS DISTINCT FROM
      'historical_testimony_acknowledged_without_actual'
    OR v_review.matched_original_work_item_id IS NOT NULL
    OR v_review.source_report_snapshot_md5 IS DISTINCT FROM
      v_report.source_summary_snapshot_md5
 THEN RAISE EXCEPTION
    'Current source-governor acknowledgment must be historical testimony only'
    USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_source_rhythm_state_id
   AND s.organization_id=v_report.organization_id
   AND s.farm_id=v_report.farm_id
   AND s.subject_kind='growing_object';
 SELECT * INTO v_offer FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.id=p_independent_accepted_offer_id;
 v_root:=atlas.company_work_native_ledger_owner_self_v1(
    v_report.organization_id,p_ledger_id);

 IF v_state.id IS NULL OR v_offer.id IS NULL
    OR v_root IS NULL
    OR v_offer.organization_id IS DISTINCT FROM v_report.organization_id
    OR v_offer.ledger_id IS DISTINCT FROM p_ledger_id
    OR v_offer.farm_id IS DISTINCT FROM v_report.farm_id
    OR v_offer.source_candidate_id IS DISTINCT FROM v_state.id
    OR v_offer.subject_id IS DISTINCT FROM v_state.subject_id
    OR v_offer.source_rule_id IS DISTINCT FROM v_state.rhythm_rule_id
    OR v_offer.offered_by_person_id IS DISTINCT FROM v_root
    OR v_offer.offer_state IS DISTINCT FROM 'accepted'
    OR v_offer.original_work_item_id IS NOT NULL
    OR v_offer.responded_at IS NULL
    OR v_offer.offered_at <= v_report.report_received_at
    OR v_offer.offered_at <= v_review.reviewer_recorded_at
    OR v_offer.responded_at < v_offer.offered_at
    OR v_offer.first_service_day < (v_offer.offered_at AT TIME ZONE v_offer.timezone_name)::date
 THEN RAISE EXCEPTION
    'Future Work must have a newly offered, separately worker-accepted, current rule and no historical authorization fiction'
    USING ERRCODE='42501';
 END IF;

 -- Calls THE SAME current U2C accepted-first source guard used by the
 -- genuine original writer. Returns no reservation or right to execute.
 v_accepted:=atlas.uni_ops_accepted_first_original_source_receipt_held_v1(
   v_offer.id);
 IF v_accepted->>'state' IS DISTINCT FROM
      'accepted_source_checks_current_for_review_only'
    OR v_accepted->>'sourceOfferId' IS DISTINCT FROM v_offer.id::text
    OR v_accepted->>'sourceSubjectId' IS DISTINCT FROM v_state.subject_id::text
    OR v_accepted->>'recipientAcceptedIndependently' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'Current separate U2 accepted-first Work source required'
    USING ERRCODE='42501';
 END IF;

 RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_future_offer_separation_held_v1',
   'state','past_testimony_and_future_independent_offer_are_separate',
   'historicalReportId',v_report.id,
   'historicalSourceLogRecordedAt',v_report.source_log_recorded_at,
   'historicalReportReceivedAt',v_report.report_received_at,
   'governorTestimonyAcknowledgedAt',v_review.reviewer_recorded_at,
   'independentFutureOfferId',v_offer.id,
   'newOfferEstablishedAt',v_offer.offered_at,
   'independentWorkerAcceptedAt',v_offer.responded_at,
   'futureServiceDay',v_offer.first_service_day,
   'independentCurrentRulebookChecked',true,
   'noCurrentExactOriginalIdentifiedNotProvedAbsent',true,
   'historicalPerformedAtVerified',false,
   'historicalWorkOrAssignmentBackdated',false,
   'physicalActualAccepted',false,
   'originalWorkCreated',false,
   'offerReserved',false,
   'finalizationAuthorizedByThisReader',false,
   'subsequentOriginalRequiresSeparateU2BAction',true,
   'successorFromResultCreated',false
 );
END;
$future$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_current_future_offer_separation_held_v1(uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
