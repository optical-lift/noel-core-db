-- UNI-OPS-01 P2: first-party retrospective Activity REPORT, not Actual.
-- HELD, SOURCE ONLY, NOT a migration or approved production transport.
-- Source owner: Noel native field_logs / farm_memberships; coordinates with
-- P1's existing assigned-Activity recognition and current real Work kernel.
-- Does not invent a Work, allocation, original date, governor approval,
-- Result, Done, source condition, assignment or first-party observation.
-- Worker claims about actual time are explicitly UNVERIFIED TESTIMONY.

DO $source_prerequisite$
BEGIN
 IF pg_catalog.to_regclass(
   'atlas.assigned_care_activity_recognition_links_v1'
 ) IS NULL THEN
  RAISE EXCEPTION 'P2 requires independently accepted P1 historical/current-Actual collision source';
 END IF;
END;
$source_prerequisite$;

CREATE TABLE atlas.uni_ops_p2_firstparty_activity_reports_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 activity_log_id uuid NOT NULL UNIQUE REFERENCES atlas.field_logs(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL UNIQUE,
 reporter_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 reporter_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 source_log_date date NOT NULL,
 source_log_recorded_at timestamptz NOT NULL,
 -- A reporter's assertion is not a verified actual occurred_at.
 reporter_claimed_performed_at timestamptz,
 claimed_existing_original_work_id uuid REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 reason_for_retrospective text NOT NULL
   CHECK(pg_catalog.char_length(reason_for_retrospective) BETWEEN 12 AND 2000),
 source_summary_snapshot_md5 text NOT NULL
   CHECK(source_summary_snapshot_md5 ~ '^[0-9a-f]{32}$'),
 report_received_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 source_kind text NOT NULL DEFAULT 'worker_manual_log'
   CHECK(source_kind='worker_manual_log'),
 -- Explicitly unresolved until separate source-authorized governor review.
 original_lookup_state text NOT NULL DEFAULT 'not_adjudicated'
   CHECK(original_lookup_state='not_adjudicated'),
 recognition_state text NOT NULL DEFAULT 'raw_testimony_not_accepted_actual'
   CHECK(recognition_state='raw_testimony_not_accepted_actual'),
 CHECK(reporter_claimed_performed_at IS NULL
    OR reporter_claimed_performed_at<=report_received_at),
 UNIQUE(farm_id,activity_log_id)
);
COMMENT ON TABLE atlas.uni_ops_p2_firstparty_activity_reports_v1 IS
 'Immutable worker testimony of potentially unassigned historical activity. Work/assignment/physical Actual and performed timestamp are never inferred from field log. Governor adjudication, original search and later new original are separate authorities.';
ALTER TABLE atlas.uni_ops_p2_firstparty_activity_reports_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_p2_firstparty_activity_reports_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_p2_firstparty_activity_reports_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Retrospective Activity testimony is immutable'
 USING ERRCODE='42501';
END;
$immutable$;
CREATE TRIGGER uni_ops_p2_reports_append_only_v1
BEFORE UPDATE OR DELETE ON atlas.uni_ops_p2_firstparty_activity_reports_v1
FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1();
REVOKE ALL ON FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1()
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_p2_submit_unassigned_activity_self_api_v1(
 p_activity_log_id uuid,
 p_source_action_id uuid,
 p_reason_for_retrospective text,
 p_reporter_claimed_performed_at timestamptz DEFAULT NULL,
 p_claimed_existing_original_work_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $report$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_log atlas.field_logs%ROWTYPE;
 v_farm atlas.farms%ROWTYPE;
 v_membership atlas.farm_memberships%ROWTYPE;
 v_existing atlas.work_items%ROWTYPE;
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_reason text:=nullif(pg_catalog.btrim(p_reason_for_retrospective),'');
 v_digest text;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL
    OR p_activity_log_id IS NULL OR p_source_action_id IS NULL
    OR v_reason IS NULL
    OR pg_catalog.char_length(v_reason) NOT BETWEEN 12 AND 2000
    OR (p_reporter_claimed_performed_at IS NOT NULL
        AND p_reporter_claimed_performed_at>pg_catalog.clock_timestamp())
 THEN RAISE EXCEPTION 'Exact current signed worker testimony required'
    USING ERRCODE='42501';
 END IF;

 -- The identical first-party field log is the immutable root of testimony.
 -- P1 uses the same locked source. This is NOT a free text narrative
 -- interpreted as physical Actual, condition or executed Work.
 SELECT * INTO v_log FROM atlas.field_logs l
 WHERE l.id=p_activity_log_id FOR UPDATE;
 IF v_log.id IS NULL OR v_log.source<>'worker_manual_log'
    OR v_log.retracted_at IS NOT NULL
    OR v_log.actor_user_id IS DISTINCT FROM v_uid
    OR nullif(pg_catalog.btrim(v_log.summary_sentence),'') IS NULL
    OR v_log.actor_membership_id IS NULL
 THEN RAISE EXCEPTION 'Exact current first-party activity unavailable'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_membership FROM atlas.farm_memberships m
 WHERE m.id=v_log.actor_membership_id
   AND m.farm_id=v_log.farm_id
   AND m.user_id=v_uid AND m.active;
 SELECT * INTO v_farm FROM atlas.farms f WHERE f.id=v_log.farm_id
   AND f.status='active' AND f.organization_id IS NOT NULL;
 IF v_membership.id IS NULL OR v_farm.id IS NULL
 THEN RAISE EXCEPTION 'Current native farm and worker custody required'
    USING ERRCODE='42501';
 END IF;

 -- An Activity that has ALREADY become an assigned, accepted P1 Actual
 -- must never silently become a second retrospective claim. Do NOT infer
 -- from absence of a P1 link that no original Work ever existed.
 IF EXISTS (
   SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 r
   WHERE r.activity_log_id=v_log.id
 ) THEN
  RAISE EXCEPTION 'This firsthand Activity already has an accepted P1 Result'
   USING ERRCODE='23505';
 END IF;

 IF p_claimed_existing_original_work_id IS NOT NULL THEN
  -- Reporter may identify a concrete original, but no Work/Person authority
  -- is derived from the claim, even if its source and farm happen to match.
  SELECT w.* INTO v_existing
  FROM atlas.work_items w
  JOIN atlas.rhythm_state s
    ON s.id=w.source_object_id AND s.organization_id=w.organization_id
  WHERE w.id=p_claimed_existing_original_work_id
    AND w.organization_id=v_farm.organization_id
    AND w.household_id IS NULL
    AND w.source_object_type='rhythm_state'
    AND w.result_contract_key='continuing_care_actual_v1'
    AND s.farm_id=v_log.farm_id AND s.subject_kind='growing_object';
  IF v_existing.id IS NULL THEN
   RAISE EXCEPTION 'Claimed existing original has no matching native source custody'
    USING ERRCODE='42501';
  END IF;

  -- A known pre-existing, correctly allocated original belongs to P1.
  -- Timestamp order is only a necessary test, not proof of actual occurrence.
  IF v_existing.created_at<=v_log.created_at
   AND EXISTS (
    SELECT 1 FROM atlas.work_allocations a
    WHERE a.work_item_id=v_existing.id
      AND a.organization_id=v_existing.organization_id
      AND a.assignee_canonical_person_id=v_person
      AND a.allocation_role='responsible'
      AND a.allocated_at<=v_log.created_at
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake',
        'delegated_under_standing_scope',
        'ledger_connection_direct_assignment',
        'original_subject_direct_assignment_v1')
   )
  THEN
   RAISE EXCEPTION 'Known preexisting assigned original must be evaluated by P1'
    USING ERRCODE='23514';
  END IF;
 END IF;

 -- We preserve the source log date and creation instant SEPARATELY.
 -- The log_date is NOT precise observed time of activity.
 v_digest:=pg_catalog.md5(
    v_log.id::text||':'||v_log.summary_sentence||':'||
    v_log.log_date::text||':'||v_log.created_at::text
 );
 SELECT * INTO v_report
 FROM atlas.uni_ops_p2_firstparty_activity_reports_v1 r
 WHERE r.activity_log_id=v_log.id FOR UPDATE;
 IF v_report.id IS NOT NULL THEN
  IF v_report.source_action_id IS DISTINCT FROM p_source_action_id
     OR v_report.reporter_user_id IS DISTINCT FROM v_uid
     OR v_report.reporter_person_id IS DISTINCT FROM v_person
     OR v_report.reason_for_retrospective IS DISTINCT FROM v_reason
     OR v_report.reporter_claimed_performed_at IS DISTINCT FROM
       p_reporter_claimed_performed_at
     OR v_report.claimed_existing_original_work_id IS DISTINCT FROM
       p_claimed_existing_original_work_id
     OR v_report.source_summary_snapshot_md5 IS DISTINCT FROM v_digest
  THEN RAISE EXCEPTION 'One original Activity cannot become conflicting historical testimony'
    USING ERRCODE='23505';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_firstparty_testimony_v1',
   'reportId',v_report.id,'replay',true,
   'activityLogId',v_log.id,'sourceLogDate',v_log.log_date,
   'sourceLogRecordedAt',v_log.created_at,
   'reportReceivedAt',v_report.report_received_at,
   'reportedPerformanceTimeIsClaimOnly',true,
   'governorApproved',false,'originalLookupAdjudicated',false,
   'originalWorkCreated',false,'actualAccepted',false,'doneCreated',false,
   'workerAuthorizedInPast',false,'successorCreated',false);
 END IF;

 INSERT INTO atlas.uni_ops_p2_firstparty_activity_reports_v1(
  organization_id,farm_id,activity_log_id,source_action_id,
  reporter_user_id,reporter_person_id,source_log_date,
  source_log_recorded_at,reporter_claimed_performed_at,
  claimed_existing_original_work_id,reason_for_retrospective,
  source_summary_snapshot_md5)
 VALUES(
  v_farm.organization_id,v_farm.id,v_log.id,p_source_action_id,
  v_uid,v_person,v_log.log_date,v_log.created_at,
  p_reporter_claimed_performed_at,p_claimed_existing_original_work_id,
  v_reason,v_digest)
 RETURNING * INTO v_report;
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','p2_firstparty_testimony_v1',
  'reportId',v_report.id,'replay',false,
  'activityLogId',v_log.id,'sourceLogDate',v_log.log_date,
  'sourceLogRecordedAt',v_log.created_at,
  'reportReceivedAt',v_report.report_received_at,
  'reportedPerformanceTimeIsClaimOnly',true,
  'existingOriginalReferenceIsClaimOnly',
      v_report.claimed_existing_original_work_id IS NOT NULL,
  'governorApproved',false,
  'originalLookupAdjudicated',false,
  'originalWorkCreated',false,
  'actualAccepted',false,
  'doneCreated',false,
  'workerAuthorizedInPast',false,
  'successorCreated',false
 );
END;
$report$;
-- This source is private until separate reviewed signed transport is
-- installed. A P2 raw testimony cannot be accepted as a Work Result.
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_submit_unassigned_activity_self_api_v1(
  uuid,uuid,text,timestamptz,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
