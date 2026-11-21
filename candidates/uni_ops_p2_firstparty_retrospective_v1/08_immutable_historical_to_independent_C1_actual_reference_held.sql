-- UNI-OPS-01 P2: immutable CORRELATION of an old worker testimony to
-- an entirely separate already-accepted PRESENT care Result on a LATER
-- independently accepted original Work. HELD source, not a migration.
-- It does NOT accept a Result, create Done, establish original Work,
-- backdate a report or declare historical activity proved physical.
-- The original source of physical Result/Done remains the current C1
-- record_continuing_care_actual_self_api_v1 and its one acceptance.
CREATE TABLE atlas.uni_ops_p2_independent_current_actual_links_v1(
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 report_id uuid NOT NULL UNIQUE
   REFERENCES atlas.uni_ops_p2_firstparty_activity_reports_v1(id)
   ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id)
   ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL UNIQUE,
 current_original_work_id uuid NOT NULL REFERENCES atlas.work_items(id)
   ON DELETE RESTRICT,
 accepted_current_result_id uuid NOT NULL UNIQUE
   REFERENCES atlas.work_execution_results(id) ON DELETE RESTRICT,
 physical_care_observation_id uuid NOT NULL UNIQUE
   REFERENCES atlas.care_observation_events(id) ON DELETE RESTRICT,
 worker_person_id uuid NOT NULL REFERENCES reality.entities(id)
   ON DELETE RESTRICT,
 worker_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 historical_log_recorded_at timestamptz NOT NULL,
 historical_report_received_at timestamptz NOT NULL,
 historical_governor_reviewed_at timestamptz NOT NULL,
 independent_offer_at timestamptz NOT NULL,
 independent_worker_accepted_at timestamptz NOT NULL,
 independent_original_established_at timestamptz NOT NULL,
 independent_physical_observed_at timestamptz NOT NULL,
 independent_actual_reported_at timestamptz NOT NULL,
 independent_actual_accepted_at timestamptz NOT NULL,
 linked_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 historical_activity_is_this_accepted_actual boolean NOT NULL DEFAULT false
   CHECK(historical_activity_is_this_accepted_actual=false),
 historical_assignment_backdated boolean NOT NULL DEFAULT false
   CHECK(historical_assignment_backdated=false),
 new_work_created_by_link boolean NOT NULL DEFAULT false
   CHECK(new_work_created_by_link=false),
 CHECK(
    historical_report_received_at<=historical_governor_reviewed_at
    AND historical_governor_reviewed_at<independent_offer_at
    AND independent_offer_at<=independent_worker_accepted_at
    AND independent_worker_accepted_at<=independent_original_established_at
    AND independent_original_established_at<independent_physical_observed_at
    AND independent_original_established_at<independent_actual_reported_at
    -- C1 source stamps reported_at with clock_timestamp(), while the
    -- accepted_at default uses now() (transaction start). The temporal
    -- SQL defaults may put accepted_at numerically BEFORE reported_at.
    -- The exact Result FK/acceptance row proves authority, not an
    -- invented chronological order between differing PG clock functions.
    )
);
ALTER TABLE atlas.uni_ops_p2_independent_current_actual_links_v1
 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_p2_independent_current_actual_links_v1
 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_p2_independent_current_actual_links_v1
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER uni_ops_p2_independent_current_actual_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_p2_independent_current_actual_links_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1();

CREATE FUNCTION atlas.uni_ops_p2_link_separately_accepted_current_actual_held_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_current_result_id uuid,
 p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $link$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_review atlas.uni_ops_p2_governor_activity_review_events_v1%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_obs atlas.care_observation_events%ROWTYPE;
 v_accept atlas.work_result_acceptances%ROWTYPE;
 v_link atlas.uni_ops_p2_independent_current_actual_links_v1%ROWTYPE;
 v_ledger_links integer;
 v_source_log atlas.field_logs%ROWTYPE;
 v_subject_claim atlas.uni_ops_p2_later_worker_subject_attributions_v1%ROWTYPE;
 v_native_subject_links integer;
 v_native_selected integer;
 v_attribution_recorded_at timestamptz;
 v_attribution_basis text;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL
   OR p_report_id IS NULL OR p_ledger_id IS NULL
   OR p_current_result_id IS NULL OR p_action_id IS NULL
 THEN RAISE EXCEPTION
   'Exact current signed independent-Actual provenance required'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_report
 FROM atlas.uni_ops_p2_firstparty_activity_reports_v1
 WHERE id=p_report_id FOR UPDATE;
 IF v_report.id IS NULL
    OR v_report.reporter_user_id IS DISTINCT FROM v_uid
    OR v_report.reporter_person_id IS DISTINCT FROM v_person
    OR EXISTS(
      SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 p1
      WHERE p1.activity_log_id=v_report.activity_log_id)
 THEN RAISE EXCEPTION 'Historical testimony must remain original worker evidence only'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_source_log FROM atlas.field_logs l
 WHERE l.id=v_report.activity_log_id;
 IF v_source_log.id IS NULL
    OR v_source_log.source<>'worker_manual_log'
    OR v_source_log.actor_user_id IS DISTINCT FROM v_uid
    OR v_source_log.retracted_at IS NOT NULL
    OR pg_catalog.md5(v_source_log.id::text||':'||
       v_source_log.summary_sentence||':'||v_source_log.log_date::text||
       ':'||v_source_log.created_at::text)
        IS DISTINCT FROM v_report.source_summary_snapshot_md5
 THEN RAISE EXCEPTION 'Original historical first-party log no longer current'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_review
 FROM atlas.uni_ops_p2_governor_activity_review_events_v1 r
 WHERE r.report_id=v_report.id AND r.ledger_id=p_ledger_id
 ORDER BY r.reviewer_recorded_at DESC,r.id DESC LIMIT 1;
 IF v_review.id IS NULL OR v_review.outcome IS DISTINCT FROM
      'historical_testimony_acknowledged_without_actual'
    OR v_review.matched_original_work_item_id IS NOT NULL
    OR v_review.source_report_snapshot_md5 IS DISTINCT FROM
       v_report.source_summary_snapshot_md5
 THEN RAISE EXCEPTION 'Independent historical-only governor review required'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.id=p_current_result_id
   AND r.organization_id=v_report.organization_id
   AND r.reported_by_user_id=v_uid
   AND r.result_contract_key='continuing_care_actual_v1';
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=v_result.work_item_id AND w.organization_id=v_report.organization_id
   AND w.household_id IS NULL
   AND w.source_object_type='rhythm_state'
   AND w.result_contract_key='continuing_care_actual_v1'
   AND w.metadata->>'sourceContract'='continuing_original_work_v1';
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=v_work.source_object_id
   AND s.farm_id=v_report.farm_id AND s.organization_id=v_report.organization_id
   AND s.subject_kind='growing_object';
 IF v_result.id IS NULL OR v_work.id IS NULL OR v_state.id IS NULL
    OR v_work.created_at<=v_review.reviewer_recorded_at
    OR v_work.created_at<=v_report.report_received_at
    OR v_result.reported_at<=v_work.created_at
    OR v_result.idempotency_key NOT LIKE
       ('continuing-care-actual:'||v_work.id::text||':%')
    OR v_result.idempotency_key=
       ('continuing-care-actual:'||v_work.id::text||':'||
        v_report.activity_log_id::text)
 THEN RAISE EXCEPTION 'Only a separate later original and independently reported Result may link'
   USING ERRCODE='42501'; END IF;

 -- A historical worker log is NOT automatically about the Subject in a
 -- later Result merely because the same Person performed both. Require
 -- exact genuine native Object link, or one separate signed worker later
 -- Object claim with its OWN recorded_at (never free-text interpretation).
 SELECT count(DISTINCT flo.object_id)::integer,
   count(DISTINCT flo.object_id)
       FILTER(WHERE flo.object_id=v_state.subject_id)::integer
 INTO v_native_subject_links,v_native_selected
 FROM atlas.field_log_objects flo
 WHERE flo.field_log_id=v_report.activity_log_id
   AND flo.object_id IS NOT NULL;
 IF v_native_subject_links>1 OR
   (v_native_subject_links=1 AND v_native_selected<>1)
 THEN RAISE EXCEPTION 'Historical Subject has ambiguous or conflicting real source'
   USING ERRCODE='42501'; END IF;
 IF v_native_subject_links=1 THEN
   SELECT min(flo.created_at) INTO v_attribution_recorded_at
   FROM atlas.field_log_objects flo
   WHERE flo.field_log_id=v_report.activity_log_id
     AND flo.object_id=v_state.subject_id AND flo.role='touched';
   IF v_attribution_recorded_at IS NULL THEN
     RAISE EXCEPTION 'Original field-log Subject source invalid'
       USING ERRCODE='42501'; END IF;
   v_attribution_basis:='native_field_log_object_link';
 ELSE
   SELECT * INTO v_subject_claim
   FROM atlas.uni_ops_p2_later_worker_subject_attributions_v1 a
   WHERE a.report_id=v_report.id;
   IF v_subject_claim.id IS NULL
      OR v_subject_claim.organization_id IS DISTINCT FROM
         v_report.organization_id
      OR v_subject_claim.farm_id IS DISTINCT FROM v_report.farm_id
      OR v_subject_claim.ledger_id IS DISTINCT FROM p_ledger_id
      OR v_subject_claim.reporter_user_id IS DISTINCT FROM v_uid
      OR v_subject_claim.reporter_person_id IS DISTINCT FROM v_person
      OR v_subject_claim.attributed_growing_object_id IS DISTINCT FROM
         v_state.subject_id
      OR v_subject_claim.source_log_snapshot_md5 IS DISTINCT FROM
         v_report.source_summary_snapshot_md5
      OR v_subject_claim.claim_is_contemporaneous_observation
           IS DISTINCT FROM false
      OR v_subject_claim.condition_was_verified IS DISTINCT FROM false
   THEN RAISE EXCEPTION 'Separate signed later worker Subject attribution required'
     USING ERRCODE='42501'; END IF;
   v_attribution_recorded_at:=v_subject_claim.recorded_at;
   v_attribution_basis:='later_signed_worker_subject_claim';
 END IF;
 IF v_attribution_recorded_at IS NULL
    OR v_attribution_recorded_at>v_result.reported_at
 THEN RAISE EXCEPTION 'Retrospective Subject identity cannot be claimed after current accepted Result'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_offer FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.organization_id=v_work.organization_id
   AND o.ledger_id=p_ledger_id AND o.farm_id=v_state.farm_id
   AND o.source_candidate_id=v_state.id
   AND o.source_rule_id=v_state.rhythm_rule_id
   AND o.subject_id=v_state.subject_id
   AND o.target_person_id=v_person
   AND o.offer_state='fulfilled'
   AND o.original_work_item_id=v_work.id;
 IF v_offer.id IS NULL OR v_offer.offered_at<=v_review.reviewer_recorded_at
   OR v_offer.responded_at IS NULL
   OR v_offer.responded_at<v_offer.offered_at
   OR v_offer.responded_at>v_work.created_at
 THEN RAISE EXCEPTION 'This physical result lacks independently accepted later U2 original'
   USING ERRCODE='42501'; END IF;

 -- Independently accepted C1 Result, exact original and signed reporter.
 SELECT * INTO v_accept FROM atlas.work_result_acceptances a
 WHERE a.execution_result_id=v_result.id
   AND a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id
   AND a.decision='accepted'
   AND a.acceptance_kind='source_qualified_physical_actual'
   AND a.accepted_by_domain='continuing_care_actual'
 ORDER BY a.accepted_at,a.id LIMIT 1;
 IF v_accept.id IS NULL
 THEN RAISE EXCEPTION 'Only existing accepted native C1 physical Result may link'
   USING ERRCODE='42501'; END IF;

 IF COALESCE(v_result.payload->>'careObservationId','') !~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
 THEN RAISE EXCEPTION 'Native signed physical source observation missing'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_obs FROM atlas.care_observation_events e
 WHERE e.id=(v_result.payload->>'careObservationId')::uuid
   AND e.source_kind='continuing_care_actual_observation'
   AND e.subject_domain='farm' AND e.subject_kind='growing_object'
   AND e.subject_id=v_state.subject_id::text
   AND e.scope_kind='farm' AND e.scope_id=v_report.farm_id
   AND e.observed_by_user_id=v_uid AND e.inferred_from_clock=false
   AND e.metadata->>'workItemId'=v_work.id::text
   AND e.metadata->>'careResultId'=v_result.payload->>'careResultId'
   AND e.condition_state=v_result.payload->>'conditionAfter';
 IF v_obs.id IS NULL OR v_obs.observed_at<=v_work.created_at
    OR v_obs.observed_at<=v_review.reviewer_recorded_at
 THEN RAISE EXCEPTION 'Independent physical C1 observation provenance mismatch'
   USING ERRCODE='42501'; END IF;

 SELECT count(*)::integer INTO v_ledger_links
 FROM atlas.company_work_native_ledger_relevance rel
 WHERE rel.organization_id=v_work.organization_id
   AND rel.ledger_id=p_ledger_id AND rel.work_item_id=v_work.id
   AND rel.attribution_state='active';
 IF v_ledger_links<>1
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f
      JOIN atlas.farm_crop_ledger_custody_v1 c
        ON c.farm_id=f.id AND c.ledger_id=p_ledger_id
       AND c.custody_state='active' AND c.ended_at IS NULL
      JOIN atlas.ledger_organization_participations lop
        ON lop.ledger_id=c.ledger_id
       AND lop.organization_id=f.organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      WHERE f.id=v_report.farm_id
        AND f.organization_id=v_report.organization_id
        AND f.status='active')
    OR NOT atlas.person_has_native_ledger_connection_v1(
         v_work.organization_id,p_ledger_id,v_person)
    OR NOT COALESCE(atlas.has_current_subject_disclosure_v1(
        p_ledger_id,v_person,'spatial','growing_object',
        v_state.subject_id,'identity'),false)
    OR NOT COALESCE(atlas.has_current_subject_disclosure_v1(
        p_ledger_id,v_person,'spatial','growing_object',
        v_state.subject_id,'condition'),false)
    OR NOT EXISTS(
       SELECT 1 FROM atlas.work_allocations a
       WHERE a.id=v_result.responsible_allocation_id
         AND a.work_item_id=v_work.id
         AND a.organization_id=v_work.organization_id
         AND a.assignee_canonical_person_id=v_person
         AND a.allocation_role='responsible'
         AND a.establishment_basis_kind IN (
           'person_connection_receiver_uptake',
           'delegated_under_standing_scope',
           'ledger_connection_direct_assignment',
           'original_subject_direct_assignment_v1')
         AND a.allocated_at>=v_offer.responded_at
         AND a.allocated_at<=v_obs.observed_at)
 THEN RAISE EXCEPTION 'Accepted worker/Subject/native Ledger source no longer qualifies'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_link
 FROM atlas.uni_ops_p2_independent_current_actual_links_v1 l
 WHERE l.report_id=v_report.id FOR UPDATE;
 IF v_link.id IS NOT NULL THEN
   IF v_link.source_action_id IS DISTINCT FROM p_action_id
     OR v_link.ledger_id IS DISTINCT FROM p_ledger_id
     OR v_link.accepted_current_result_id IS DISTINCT FROM v_result.id
     OR v_link.current_original_work_id IS DISTINCT FROM v_work.id
     OR v_link.worker_user_id IS DISTINCT FROM v_uid
   THEN RAISE EXCEPTION 'P2 historical/current Actual association is immutable'
     USING ERRCODE='23505'; END IF;
   RETURN pg_catalog.jsonb_build_object(
     'ok',true,'contractVersion','p2_separate_present_C1_link_v1',
     'linkId',v_link.id,'replay',true,'historicalActualReclassified',false,
     'newWorkCreated',false,'newResultCreated',false,'doneCreated',false);
 END IF;

 INSERT INTO atlas.uni_ops_p2_independent_current_actual_links_v1(
  report_id,organization_id,ledger_id,farm_id,source_action_id,
  current_original_work_id,accepted_current_result_id,
  physical_care_observation_id,worker_person_id,worker_user_id,
  historical_log_recorded_at,historical_report_received_at,
  historical_governor_reviewed_at,independent_offer_at,
  independent_worker_accepted_at,independent_original_established_at,
  independent_physical_observed_at,independent_actual_reported_at,
  independent_actual_accepted_at)
 VALUES(
  v_report.id,v_report.organization_id,p_ledger_id,v_report.farm_id,
  p_action_id,v_work.id,v_result.id,v_obs.id,v_person,v_uid,
  v_report.source_log_recorded_at,v_report.report_received_at,
  v_review.reviewer_recorded_at,v_offer.offered_at,
  v_offer.responded_at,v_work.created_at,v_obs.observed_at,
  v_result.reported_at,v_accept.accepted_at)
 RETURNING * INTO v_link;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','p2_separate_present_C1_link_v1',
  'linkId',v_link.id,'replay',false,
  'historicalReportId',v_report.id,
  'historicalLogRecordedAt',v_report.source_log_recorded_at,
  'historicalReportReceivedAt',v_report.report_received_at,
  'subjectAttributionBasis',v_attribution_basis,
  'subjectAttributionRecordedAt',v_attribution_recorded_at,
  'subjectAttributionIsNotHistoricalPhysicalProof',true,
  'governorHistoricalReviewedAt',v_review.reviewer_recorded_at,
  'independentOriginalWorkItemId',v_work.id,
  'independentOriginalEstablishedAt',v_work.created_at,
  'independentPhysicalObservedAt',v_obs.observed_at,
  'independentPresentAcceptedResultId',v_result.id,
  'presentResultAcceptedAt',v_accept.accepted_at,
  'originalHistoricalWorkerLogIsNotThePresentResult',true,
  'historicalWorkAuthorizedRetroactively',false,
  'noNewOriginalWorkCreated',true,
  'noNewResultOrDoneCreated',true,
  'noSuccessorAuthorized',true);
END;
$link$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_link_separately_accepted_current_actual_held_v1(
  uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
