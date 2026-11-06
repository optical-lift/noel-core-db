-- UNI-OPS-01 P2 source-only bounded GOVERNOR case history, not a
-- worker-visible roster or an Actual/Work reader. No new authorization.
-- Requires first-party report 01 and native governor review 02. HELD.
CREATE FUNCTION atlas.uni_ops_p2_governor_case_history_self_api_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_after_review_event_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $history$
DECLARE
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_root uuid;
 v_curs_at timestamptz;
 v_curs_id uuid;
 v_rows jsonb:='[]'::jsonb;
 v_has_more boolean:=false;
BEGIN
 IF auth.uid() IS NULL OR p_report_id IS NULL OR p_ledger_id IS NULL
 THEN RAISE EXCEPTION 'Exact signed governor case required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_report FROM atlas.uni_ops_p2_firstparty_activity_reports_v1
 WHERE id=p_report_id;
 IF v_report.id IS NULL THEN
  RAISE EXCEPTION 'Retrospective case unavailable' USING ERRCODE='42501';
 END IF;
 v_root:=atlas.company_work_native_ledger_owner_self_v1(
  v_report.organization_id,p_ledger_id);
 IF v_root IS NULL OR v_root IS DISTINCT FROM
    atlas.current_person_id_v1()
    OR NOT EXISTS (
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
    )
 THEN RAISE EXCEPTION 'Current exact governing farm Ledger required'
   USING ERRCODE='42501';
 END IF;
 IF p_after_review_event_id IS NOT NULL THEN
  SELECT e.reviewer_recorded_at,e.id INTO v_curs_at,v_curs_id
  FROM atlas.uni_ops_p2_governor_activity_review_events_v1 e
  WHERE e.id=p_after_review_event_id AND e.report_id=v_report.id;
  IF v_curs_id IS NULL THEN
   RAISE EXCEPTION 'Review history cursor not in authorized case'
      USING ERRCODE='42501';
  END IF;
 END IF;
 WITH ordered AS (
  SELECT e.id,e.outcome,e.reason,e.previous_review_event_id,
         e.reviewer_recorded_at,
         (e.matched_original_work_item_id IS NOT NULL) matched_original_reviewed,
         pg_catalog.row_number() OVER
           (ORDER BY e.reviewer_recorded_at,e.id) AS sequence
  FROM (
   SELECT * FROM atlas.uni_ops_p2_governor_activity_review_events_v1 e
   WHERE e.report_id=v_report.id AND e.ledger_id=p_ledger_id
     AND (v_curs_id IS NULL OR
          (e.reviewer_recorded_at,e.id)>(v_curs_at,v_curs_id))
   ORDER BY e.reviewer_recorded_at,e.id LIMIT 26
  ) e
 )
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'reviewId',id,'outcome',outcome,'reason',reason,
      'previousReviewId',previous_review_event_id,
      'reviewedAt',reviewer_recorded_at,
      'existingOriginalWasConsidered',matched_original_reviewed,
      'noActualOrWorkCreated',true)
      ORDER BY sequence) FILTER(WHERE sequence<=25),'[]'::jsonb),
    coalesce(pg_catalog.bool_or(sequence>25),false)
 INTO v_rows,v_has_more FROM ordered;
 RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_governor_case_history_v1',
   'reportId',v_report.id,'sourceFarmId',v_report.farm_id,
   'sourceLogDate',v_report.source_log_date,
   'sourceLogRecordedAt',v_report.source_log_recorded_at,
   'workerClaimedPerformedAt',v_report.reporter_claimed_performed_at,
   'workerClaimedTimeIsUnverified',true,
   'reportReceivedAt',v_report.report_received_at,
   'sourceLogDateIsNotOccurrenceProof',true,
   'reviews',v_rows,'hasMore',v_has_more,
   'historicalOnly',true,'acceptedActual',false,
   'workIssuedByThisReader',false,'doneCreated',false
 );
END;
$history$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_governor_case_history_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
