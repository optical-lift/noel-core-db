-- UNI-OPS-01 P2: separate real native Ledger GOVERNOR review of already
-- recorded first-party retrospective testimony, NOT an accepted Actual.
-- HELD, NOT a migration, not independently authorized to create Work.
-- Distinct signed governor and true farm→Ledger custody are required.
-- Decisions are append-only; later corrections reference current prior.
-- This stage never manufactures historical assignment, Need, Result, Done,
-- previous approval time, Subject equivalence or workday.

DO $review_prereq$
BEGIN
 IF pg_catalog.to_regclass(
   'atlas.uni_ops_p2_firstparty_activity_reports_v1'
 ) IS NULL OR pg_catalog.to_regclass(
   'atlas.farm_crop_ledger_custody_v1'
 ) IS NULL OR pg_catalog.to_regprocedure(
   'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'
 ) IS NULL OR pg_catalog.to_regprocedure(
   'atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)'
 ) IS NULL
 THEN
  RAISE EXCEPTION 'P2 first-party source, true farm Ledger custody and governor/Subject disclosure source required';
 END IF;
END;
$review_prereq$;

CREATE TABLE atlas.uni_ops_p2_governor_activity_review_events_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 report_id uuid NOT NULL
   REFERENCES atlas.uni_ops_p2_firstparty_activity_reports_v1(id)
   ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL UNIQUE,
 previous_review_event_id uuid
   REFERENCES atlas.uni_ops_p2_governor_activity_review_events_v1(id)
   ON DELETE RESTRICT,
 reviewing_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 reviewing_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 outcome text NOT NULL CHECK(outcome IN(
   'needs_more_firstparty_source',
   'historical_testimony_acknowledged_without_actual',
   'existing_original_needs_separate_adjudication',
   'testimony_rejected')),
 matched_original_work_item_id uuid REFERENCES atlas.work_items(id)
   ON DELETE RESTRICT,
 -- Database original establishment timestamp, NEVER backdated performed_at.
 matched_source_rhythm_state_id uuid REFERENCES atlas.rhythm_state(id)
   ON DELETE RESTRICT,
 matched_original_established_at timestamptz,
 matched_original_created_before_log_record boolean,
 matched_original_source_checked_at timestamptz,
 -- Either a native log object-link recorded at its true source time,
 -- or an independently signed later first-person Subject CLAIM. Neither
 -- establishes executed condition, contemporaneous proof or past Work.
 matched_subject_attribution_basis text CHECK(
  matched_subject_attribution_basis IN (
   'native_field_log_object_link','later_signed_worker_subject_claim')),
 matched_subject_attribution_recorded_at timestamptz,
 reason text NOT NULL CHECK(pg_catalog.char_length(reason) BETWEEN 12 AND 2000),
 source_report_snapshot_md5 text NOT NULL
   CHECK(source_report_snapshot_md5 ~ '^[0-9a-f]{32}$'),
 reviewer_recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK(
   (outcome='existing_original_needs_separate_adjudication'
     AND matched_original_work_item_id IS NOT NULL
     AND matched_source_rhythm_state_id IS NOT NULL
     AND matched_original_established_at IS NOT NULL
     AND matched_original_created_before_log_record IS NOT NULL
     AND matched_original_source_checked_at IS NOT NULL
     AND matched_subject_attribution_basis IS NOT NULL
     AND matched_subject_attribution_recorded_at IS NOT NULL)
   OR
   (outcome<>'existing_original_needs_separate_adjudication'
     AND matched_original_work_item_id IS NULL
     AND matched_source_rhythm_state_id IS NULL
     AND matched_original_established_at IS NULL
     AND matched_original_created_before_log_record IS NULL
     AND matched_original_source_checked_at IS NULL
     AND matched_subject_attribution_basis IS NULL
     AND matched_subject_attribution_recorded_at IS NULL))
);
CREATE INDEX uni_ops_p2_review_by_report_v1
 ON atlas.uni_ops_p2_governor_activity_review_events_v1(
  report_id,reviewer_recorded_at DESC,id DESC);
ALTER TABLE atlas.uni_ops_p2_governor_activity_review_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_p2_governor_activity_review_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_p2_governor_activity_review_events_v1
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER uni_ops_p2_governor_review_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_p2_governor_activity_review_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1();

CREATE FUNCTION atlas.uni_ops_p2_governor_review_activity_self_api_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_outcome text,
 p_reason text,
 p_action_id uuid,
 p_expected_previous_review_id uuid DEFAULT NULL,
 p_matched_existing_work_item_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $governor$
DECLARE
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_log atlas.field_logs%ROWTYPE;
 v_root uuid;
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_latest atlas.uni_ops_p2_governor_activity_review_events_v1%ROWTYPE;
 v_review atlas.uni_ops_p2_governor_activity_review_events_v1%ROWTYPE;
 v_existing atlas.work_items%ROWTYPE;
 v_subject atlas.rhythm_state%ROWTYPE;
 v_reason text:=nullif(pg_catalog.btrim(p_reason),'');
 v_source_md5 text;
 v_original_source_recheck jsonb;
BEGIN
 IF p_report_id IS NULL OR p_ledger_id IS NULL OR p_action_id IS NULL
   OR v_uid IS NULL OR v_person IS NULL
   OR p_outcome IS NULL OR p_outcome NOT IN (
     'needs_more_firstparty_source',
     'historical_testimony_acknowledged_without_actual',
     'existing_original_needs_separate_adjudication',
     'testimony_rejected')
   OR v_reason IS NULL OR pg_catalog.char_length(v_reason) NOT BETWEEN 12 AND 2000
   OR (p_outcome='existing_original_needs_separate_adjudication'
         AND p_matched_existing_work_item_id IS NULL)
   OR (p_outcome<>'existing_original_needs_separate_adjudication'
         AND p_matched_existing_work_item_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Exact independently signed retrospective governor review required'
   USING ERRCODE='42501';
 END IF;

 -- Serialize decisions on one actual worker report; do not select a roster.
 SELECT * INTO v_report FROM atlas.uni_ops_p2_firstparty_activity_reports_v1 r
 WHERE r.id=p_report_id FOR UPDATE;
 IF v_report.id IS NULL THEN
  RAISE EXCEPTION 'Historical first-party Activity report unavailable'
   USING ERRCODE='42501';
 END IF;
 v_root:=atlas.company_work_native_ledger_owner_self_v1(
   v_report.organization_id,p_ledger_id);
 IF v_root IS NULL OR v_root IS DISTINCT FROM v_person OR NOT EXISTS (
   SELECT 1 FROM atlas.farms f
   JOIN atlas.farm_crop_ledger_custody_v1 c
     ON c.farm_id=f.id AND c.ledger_id=p_ledger_id
    AND c.custody_state='active' AND c.ended_at IS NULL
   JOIN atlas.ledger_organization_participations lop
     ON lop.organization_id=f.organization_id AND lop.ledger_id=c.ledger_id
    AND lop.status='active' AND lop.ended_at IS NULL
    AND lop.participation_kind='governing'
    AND lop.is_compatibility_primary=true
   WHERE f.id=v_report.farm_id
     AND f.organization_id=v_report.organization_id
     AND f.status='active'
 ) THEN
  RAISE EXCEPTION 'Actual current governing Ledger and farm custody required'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_log FROM atlas.field_logs l
 WHERE l.id=v_report.activity_log_id;
 v_source_md5:=pg_catalog.md5(
   v_log.id::text||':'||v_log.summary_sentence||':'||
   v_log.log_date::text||':'||v_log.created_at::text);
 IF v_log.id IS NULL OR v_log.source<>'worker_manual_log'
    OR v_log.retracted_at IS NOT NULL
    OR v_log.actor_user_id IS DISTINCT FROM v_report.reporter_user_id
    OR v_log.farm_id IS DISTINCT FROM v_report.farm_id
    OR v_source_md5 IS DISTINCT FROM v_report.source_summary_snapshot_md5
    OR EXISTS (
      SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 a
      WHERE a.activity_log_id=v_log.id)
 THEN RAISE EXCEPTION 'First-party evidence withdrawn, changed or already accepted through P1'
    USING ERRCODE='42501';
 END IF;

 -- A provided existing original must be genuinely source-matched to the
 -- same native Farm, actual governing Ledger and disclosed Subject. Neither
 -- the worker's original claim nor an ID suffices to establish assignment.
 IF p_matched_existing_work_item_id IS NOT NULL THEN
  SELECT w.* INTO v_existing FROM atlas.work_items w
  JOIN atlas.rhythm_state s
    ON s.id=w.source_object_id AND s.organization_id=w.organization_id
  JOIN atlas.company_work_native_ledger_relevance rel
    ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
   AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
  WHERE w.id=p_matched_existing_work_item_id
    AND w.organization_id=v_report.organization_id
    AND w.household_id IS NULL
    AND w.source_object_type='rhythm_state'
    AND w.result_contract_key='continuing_care_actual_v1'
    AND s.farm_id=v_report.farm_id
    AND s.subject_kind='growing_object';
  IF v_existing.id IS NULL THEN
   RAISE EXCEPTION 'Proposed existing original lacks authorized farm/Ledger source'
     USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_subject FROM atlas.rhythm_state s
  WHERE s.id=v_existing.source_object_id;
  IF NOT coalesce(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_root,'spatial','growing_object',
    v_subject.subject_id,'identity'),false)
   OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_root,'spatial','growing_object',
    v_subject.subject_id,'condition'),false)
  THEN RAISE EXCEPTION 'Independent current Subject identity and condition disclosure required'
     USING ERRCODE='42501';
  END IF;

  -- The governor's nominated Work ID is NEVER itself proof that this
  -- worker's exact firsthand field log implicated its canonical Subject.
  -- Recheck the independently source-owned field_log_objects object link,
  -- the native rhythm State, all relevant original/context alternatives,
  -- current Ledger attribution and two separate disclosures. This receipt
  -- does not accept a physical Actual, infer performed_at, or reserve Work.
  v_original_source_recheck:=
   atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(
    v_report.id,p_ledger_id,v_subject.id);
  IF v_original_source_recheck->>'state' IS DISTINCT FROM
       'one_existing_original_for_attested_subject_requires_adjudication'
     OR v_original_source_recheck->>'matchedWorkItemId'
       IS DISTINCT FROM v_existing.id::text
     OR v_original_source_recheck->>'subjectAttributionCurrent'
       IS DISTINCT FROM 'true'
  THEN
   RAISE EXCEPTION
     'Original Work and firsthand Subject are not uniquely source-reconciled'
     USING ERRCODE='42501';
  END IF;
 END IF;

 SELECT * INTO v_latest

 FROM atlas.uni_ops_p2_governor_activity_review_events_v1 e
 WHERE e.report_id=v_report.id
 ORDER BY e.reviewer_recorded_at DESC,e.id DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO v_review
 FROM atlas.uni_ops_p2_governor_activity_review_events_v1 e
 WHERE e.source_action_id=p_action_id;
 IF v_review.id IS NOT NULL THEN
  IF v_review.report_id IS DISTINCT FROM v_report.id
    OR v_review.ledger_id IS DISTINCT FROM p_ledger_id
    OR v_review.reviewing_person_id IS DISTINCT FROM v_root
    OR v_review.reviewing_user_id IS DISTINCT FROM v_uid
    OR v_review.previous_review_event_id IS DISTINCT FROM
      p_expected_previous_review_id
    OR v_review.outcome IS DISTINCT FROM p_outcome
    OR v_review.reason IS DISTINCT FROM v_reason
    OR v_review.matched_original_work_item_id IS DISTINCT FROM
      p_matched_existing_work_item_id
    OR v_review.matched_original_established_at IS DISTINCT FROM
      v_existing.created_at
    OR v_review.matched_source_rhythm_state_id IS DISTINCT FROM
      v_subject.id
    OR v_review.matched_subject_attribution_basis IS DISTINCT FROM
       v_original_source_recheck->>'subjectAttributionBasis'
    OR v_review.matched_subject_attribution_recorded_at IS DISTINCT FROM
       (v_original_source_recheck->>'subjectAttributionRecordedAt')::timestamptz
  THEN RAISE EXCEPTION 'Immutable retrospective review replay conflicts with source'
   USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'ok',true,'contractVersion','p2_governor_source_review_v1',
   'reviewEventId',v_review.id,'replay',true,
   'outcome',v_review.outcome,'historicalOnly',true,
   'physicalActualAccepted',false,'originalWorkCreated',false,
   'doneCreated',false,'pastAuthorityFabricated',false);
 END IF;
 IF v_latest.id IS DISTINCT FROM p_expected_previous_review_id THEN
  RAISE EXCEPTION 'Reviewer must amend the exact current source review event'
    USING ERRCODE='23505';
 END IF;

 INSERT INTO atlas.uni_ops_p2_governor_activity_review_events_v1(
  report_id,organization_id,ledger_id,farm_id,source_action_id,
  previous_review_event_id,reviewing_person_id,reviewing_user_id,
  outcome,matched_original_work_item_id,
  matched_source_rhythm_state_id,matched_original_established_at,
  matched_original_created_before_log_record,
  matched_original_source_checked_at,
  matched_subject_attribution_basis,
  matched_subject_attribution_recorded_at,
  reason,source_report_snapshot_md5)
 VALUES(
  v_report.id,v_report.organization_id,p_ledger_id,v_report.farm_id,
  p_action_id,p_expected_previous_review_id,v_root,v_uid,
  p_outcome,p_matched_existing_work_item_id,
  v_subject.id,v_existing.created_at,
  CASE WHEN v_existing.id IS NULL THEN NULL
       ELSE v_existing.created_at<=v_report.source_log_recorded_at END,
  CASE WHEN v_existing.id IS NULL THEN NULL
       ELSE pg_catalog.clock_timestamp() END,
  v_original_source_recheck->>'subjectAttributionBasis',
  (v_original_source_recheck->>'subjectAttributionRecordedAt')::timestamptz,
  v_reason,v_report.source_summary_snapshot_md5)
 RETURNING * INTO v_review;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','p2_governor_source_review_v1',
  'reviewEventId',v_review.id,'reportId',v_report.id,'replay',false,
  'outcome',v_review.outcome,
  'existingOriginalIdSelected',
     v_review.matched_original_work_item_id IS NOT NULL,
  'matchedOriginalEstablishedAt',v_review.matched_original_established_at,
  'sourceLogRecordedAt',v_report.source_log_recorded_at,
  'existingOriginalPrecededLogRecord',
    v_review.matched_original_created_before_log_record,
  'sourceReconciledAt',v_review.matched_original_source_checked_at,
  'chronologyIsNotProofOfActualExecution',true,
  'physicalActualAccepted',false,'originalWorkCreated',false,
  'doneCreated',false,'pastAuthorityFabricated',false,
  'futureWorkAuthorized',false,'independentlyAuthorizedIssuerStillRequired',true
 );
END;
$governor$;

REVOKE ALL ON FUNCTION atlas.uni_ops_p2_governor_review_activity_self_api_v1(
 uuid,uuid,text,text,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
