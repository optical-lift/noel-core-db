-- UNI-OPS-01 P2 / original FIRST. HELD source-only, NOT a migration.
-- Reviewer supplies an exact first-party field-log linked native Subject.
-- The worker sentence, a guessed Person/Subject and a supplied Work UUID
-- are NEVER source evidence of an actual accepted Result or prior authority.
-- This is a bounded current-state original-custody observation, not a
-- Work finder, issuer, allocation, acceptance or reservation.
-- Existing farm/Company jurisdiction remains unchanged.
CREATE FUNCTION atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_native_rhythm_state_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $preflight$
DECLARE
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_log atlas.field_logs%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_root uuid;
 v_uid uuid:=auth.uid();
 v_object_links integer;
 v_scope_work_count integer:=0;
 v_direct_work_count integer:=0;
 v_ledger_work_count integer:=0;
 v_scope_work_id uuid;
 v_work atlas.work_items%ROWTYPE;
 v_alloc_preexisting boolean:=false;
 v_received_snapshot text;
BEGIN
 IF v_uid IS NULL OR p_report_id IS NULL
    OR p_ledger_id IS NULL OR p_native_rhythm_state_id IS NULL
 THEN RAISE EXCEPTION 'Signed exact original-source reconciliation required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_report FROM atlas.uni_ops_p2_firstparty_activity_reports_v1 r
 WHERE r.id=p_report_id;
 IF v_report.id IS NULL THEN
  RAISE EXCEPTION 'First-party retrospective source unavailable'
   USING ERRCODE='42501';
 END IF;

 -- Reuse the existing independently signed native root and actual farm
 -- Ledger custody, not "owner" metadata or an old service session.
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
 THEN RAISE EXCEPTION 'Current true native farm Ledger governor required'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_log FROM atlas.field_logs l
 WHERE l.id=v_report.activity_log_id;
 v_received_snapshot:=pg_catalog.md5(
   v_log.id::text||':'||v_log.summary_sentence||':'||
   v_log.log_date::text||':'||v_log.created_at::text);
 IF v_log.id IS NULL OR v_log.source<>'worker_manual_log'
    OR v_log.retracted_at IS NOT NULL
    OR v_log.actor_user_id IS DISTINCT FROM v_report.reporter_user_id
    OR v_log.farm_id IS DISTINCT FROM v_report.farm_id
    OR v_received_snapshot IS DISTINCT FROM
       v_report.source_summary_snapshot_md5
    OR EXISTS (
      SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 p1
      WHERE p1.activity_log_id=v_log.id)
 THEN RAISE EXCEPTION 'Retrospective testimony source is not currently usable'
    USING ERRCODE='42501';
 END IF;

 -- Source object must be first-party linked by the actual field_log_objects
 -- provider and belong to the same physical farm. A text mention of a bed,
 -- plant, zone or generic task is NOT a canonical Subject equivalent.
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_native_rhythm_state_id
   AND s.organization_id=v_report.organization_id
   AND s.farm_id=v_report.farm_id
   AND s.subject_kind='growing_object';
 IF v_state.id IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.field_log_objects flo
    JOIN atlas.growing_objects g ON g.id=flo.object_id
    WHERE flo.field_log_id=v_log.id AND flo.object_id=v_state.subject_id
      AND flo.role='touched' AND g.farm_id=v_report.farm_id)
 THEN RAISE EXCEPTION 'Exact firsthand linked growing Subject required'
    USING ERRCODE='42501';
 END IF;

 -- Both identity and condition must independently be disclosed to this
 -- governor before any original Work identity is even considered.
 IF NOT coalesce(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_root,'spatial','growing_object',v_state.subject_id,'identity'),false)
 OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_root,'spatial','growing_object',v_state.subject_id,'condition'),false)
 THEN RAISE EXCEPTION 'Independent current Subject information disclosures required'
    USING ERRCODE='42501';
 END IF;

 SELECT pg_catalog.count(DISTINCT flo.object_id)::integer INTO v_object_links
 FROM atlas.field_log_objects flo
 WHERE flo.field_log_id=v_log.id AND flo.object_id IS NOT NULL;
 IF v_object_links IS DISTINCT FROM 1 THEN
   RETURN pg_catalog.jsonb_build_object(
    'ok',true,'contractVersion','p2_original_source_preflight_held_v1',
    'state','multiple_original_subjects_need_independent_evidence',
    'firstPartySubjectLinkCurrent',true,
    'fieldLogObjectCount',v_object_links,
    'oneOriginalFound',false,'noOriginalExistsProven',false,
    'laterOriginalAuthorized',false,'actualAccepted',false,
    'newWorkCreated',false,'historicalAssignmentEstablished',false);
 END IF;

 -- Source-specific historical search, including completed/cancelled and
 -- all exact native Subject context Work. A "closed" Work is still a real
 -- historical original. A later new Work may not erase its existence.
 SELECT pg_catalog.count(DISTINCT w.id)::integer,pg_catalog.min(w.id)
 INTO v_scope_work_count,v_scope_work_id
 FROM atlas.work_items w
 WHERE w.organization_id=v_report.organization_id AND w.household_id IS NULL
   AND (
     (w.source_object_type='rhythm_state'
       AND w.source_object_id=v_state.id)
     OR EXISTS(
       SELECT 1 FROM atlas.work_item_context_links l
       WHERE l.work_item_id=w.id AND l.organization_id=w.organization_id
         AND l.subject_domain='spatial'
         AND l.subject_kind='growing_object'
         AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on')
   );

 SELECT pg_catalog.count(DISTINCT w.id)::integer
 INTO v_direct_work_count
 FROM atlas.work_items w
 WHERE w.organization_id=v_report.organization_id AND w.household_id IS NULL
   AND w.source_object_type='rhythm_state'
   AND w.source_object_id=v_state.id
   AND w.result_contract_key='continuing_care_actual_v1';

 IF v_scope_work_count<>1 OR v_direct_work_count<>1 THEN
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_original_source_preflight_held_v1',
   'state',CASE
     WHEN v_scope_work_count=0 THEN 'no_current_exact_original_identified_not_proof_of_absence'
     ELSE 'original_source_collision_or_ambiguity_requires_review'
   END,
   'currentRelevantOriginalCount',v_scope_work_count,
   'currentExactRhythmCareOriginalCount',v_direct_work_count,
   'firstPartySubjectLinkCurrent',true,
   'workerActivityIsNotAcceptedActual',true,
   'noOriginalExistsProven',false,
   'laterOriginalAuthorized',false,
   'newWorkCreated',false,'doneCreated',false);
 END IF;

 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=v_scope_work_id AND w.organization_id=v_report.organization_id
   AND w.source_object_type='rhythm_state'
   AND w.source_object_id=v_state.id
   AND w.result_contract_key='continuing_care_actual_v1';
 IF v_work.id IS NULL THEN
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_original_source_preflight_held_v1',
   'state','other_subject_work_not_valid_care_original',
   'noOriginalExistsProven',false,'laterOriginalAuthorized',false,
   'newWorkCreated',false,'actualAccepted',false);
 END IF;

 SELECT pg_catalog.count(*)::integer INTO v_ledger_work_count
 FROM atlas.company_work_native_ledger_relevance r
 WHERE r.organization_id=v_report.organization_id
   AND r.ledger_id=p_ledger_id AND r.work_item_id=v_work.id
   AND r.attribution_state='active';
 IF v_ledger_work_count<>1 THEN
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_original_source_preflight_held_v1',
   'state','existing_original_native_ledger_relevance_unresolved',
   'noOriginalExistsProven',false,'laterOriginalAuthorized',false,
   'newWorkCreated',false,'actualAccepted',false);
 END IF;

 SELECT EXISTS(
  SELECT 1 FROM atlas.work_allocations a
  WHERE a.work_item_id=v_work.id
    AND a.organization_id=v_report.organization_id
    AND a.assignee_canonical_person_id=v_report.reporter_person_id
    AND a.allocation_role='responsible'
    AND a.establishment_basis_kind IN (
      'person_connection_receiver_uptake',
      'delegated_under_standing_scope',
      'ledger_connection_direct_assignment',
      'original_subject_direct_assignment_v1')
    AND a.allocated_at<=v_report.source_log_recorded_at
 ) INTO v_alloc_preexisting;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','p2_original_source_preflight_held_v1',
  'state','one_exact_existing_source_original_for_separate_adjudication',
  'sourceRhythmStateId',v_state.id,
  'sourceSubjectId',v_state.subject_id,
  'matchedWorkItemId',v_work.id,
  'currentExactRhythmCareOriginalCount',v_direct_work_count,
  'existingOriginalEstablishedAt',v_work.created_at,
  'sourceLogRecordedAt',v_report.source_log_recorded_at,
  'originalEstablishedBeforeLogWasRecorded',
    v_work.created_at<=v_report.source_log_recorded_at,
  'reporterHadResponsibleAllocationBeforeLogRecord',v_alloc_preexisting,
  'chronologyIsNotProofOfActualExecution',true,
  'firstPartySubjectLinkCurrent',true,
  'existingOriginalWorkState',v_work.work_state,
  'workerActivityIsNotAcceptedActual',true,
  'noOriginalExistsProven',false,'laterOriginalAuthorized',false,
  'newWorkCreated',false,'actualAccepted',false,'doneCreated',false);
END;
$preflight$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
