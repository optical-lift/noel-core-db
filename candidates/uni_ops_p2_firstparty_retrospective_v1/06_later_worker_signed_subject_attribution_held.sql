-- UNI-OPS-01 P2: truthful later worker Subject attribution for manual logs.
-- HELD, not a migration, transport, accepted Actual, Result or Work.
-- IMPORTANT: live atlas.record_worker_activity_log_v1 stores evidence_only
-- worker_manual_log with NO field_log_objects linkage. Such a log does NOT
-- already contain a verified original Subject. Never infer it from text.
-- One reporter can subsequently identify one exact native growing object,
-- with genuine current authorization to disclose its identity. The later
-- attribution has its OWN real server timestamp and is unverified testimony,
-- not a contemporaneous field-log observation or physical condition.
CREATE TABLE atlas.uni_ops_p2_later_worker_subject_attributions_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 report_id uuid NOT NULL UNIQUE
   REFERENCES atlas.uni_ops_p2_firstparty_activity_reports_v1(id)
   ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL UNIQUE,
 reporter_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 reporter_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 attributed_growing_object_id uuid NOT NULL
   REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT,
 source_log_snapshot_md5 text NOT NULL
   CHECK (source_log_snapshot_md5 ~ '^[0-9a-f]{32}$'),
 attribution_reason text NOT NULL
   CHECK (pg_catalog.char_length(attribution_reason) BETWEEN 12 AND 2000),
 recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 attribution_kind text NOT NULL DEFAULT 'subsequent_worker_subject_claim'
   CHECK (attribution_kind='subsequent_worker_subject_claim'),
 claim_is_contemporaneous_observation boolean NOT NULL DEFAULT false
   CHECK (claim_is_contemporaneous_observation=false),
 condition_was_verified boolean NOT NULL DEFAULT false
   CHECK (condition_was_verified=false)
);
ALTER TABLE atlas.uni_ops_p2_later_worker_subject_attributions_v1
 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_p2_later_worker_subject_attributions_v1
 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_p2_later_worker_subject_attributions_v1
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER uni_ops_p2_later_subject_attribution_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_p2_later_worker_subject_attributions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_p2_prevent_report_rewrite_v1();

CREATE FUNCTION atlas.uni_ops_p2_worker_attest_subject_later_held_v1(
 p_report_id uuid,
 p_ledger_id uuid,
 p_growing_object_id uuid,
 p_reason text,
 p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $worker$
DECLARE
 v_report atlas.uni_ops_p2_firstparty_activity_reports_v1%ROWTYPE;
 v_log atlas.field_logs%ROWTYPE;
 v_claim atlas.uni_ops_p2_later_worker_subject_attributions_v1%ROWTYPE;
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_reason text:=nullif(pg_catalog.btrim(p_reason),'');
 v_snapshot text;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL
   OR p_report_id IS NULL OR p_ledger_id IS NULL
   OR p_growing_object_id IS NULL OR p_action_id IS NULL
   OR v_reason IS NULL
   OR pg_catalog.char_length(v_reason) NOT BETWEEN 12 AND 2000
 THEN RAISE EXCEPTION
  'One current signed worker and exact Subject attribution source required'
  USING ERRCODE='42501'; END IF;

 -- Never let another Person reattribute a worker's first-person testimony.
 SELECT * INTO v_report
 FROM atlas.uni_ops_p2_firstparty_activity_reports_v1
 WHERE id=p_report_id FOR UPDATE;
 IF v_report.id IS NULL
    OR v_report.reporter_user_id IS DISTINCT FROM v_uid
    OR v_report.reporter_person_id IS DISTINCT FROM v_person
 THEN RAISE EXCEPTION 'The reported original Activity does not belong to this worker'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_log FROM atlas.field_logs
 WHERE id=v_report.activity_log_id;
 v_snapshot:=pg_catalog.md5(
   v_log.id::text||':'||v_log.summary_sentence||':'||
   v_log.log_date::text||':'||v_log.created_at::text);
 IF v_log.id IS NULL OR v_log.source<>'worker_manual_log'
    OR v_log.actor_user_id IS DISTINCT FROM v_uid
    OR v_log.retracted_at IS NOT NULL
    OR v_log.farm_id IS DISTINCT FROM v_report.farm_id
    OR v_snapshot IS DISTINCT FROM v_report.source_summary_snapshot_md5
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farm_memberships m
      WHERE m.id=v_log.actor_membership_id
        AND m.user_id=v_uid AND m.farm_id=v_report.farm_id AND m.active)
    OR EXISTS(
      SELECT 1 FROM atlas.assigned_care_activity_recognition_links_v1 p1
      WHERE p1.activity_log_id=v_log.id)
 THEN RAISE EXCEPTION 'First-party report source no longer current or already recognized'
   USING ERRCODE='42501'; END IF;

 -- The claimed object must be a real native subject in this farm, under
 -- the actual current governing farm Ledger. This does NOT certify that
 -- the alleged physical activity happened to that object in the past.
 IF NOT EXISTS(
   SELECT 1 FROM atlas.growing_objects g
   JOIN atlas.farms f ON f.id=g.farm_id
   JOIN atlas.farm_crop_ledger_custody_v1 c
     ON c.farm_id=f.id AND c.ledger_id=p_ledger_id
    AND c.custody_state='active' AND c.ended_at IS NULL
   JOIN atlas.ledger_organization_participations lop
     ON lop.ledger_id=c.ledger_id AND lop.organization_id=f.organization_id
    AND lop.participation_kind='governing'
    AND lop.is_compatibility_primary=true
    AND lop.status='active' AND lop.ended_at IS NULL
   WHERE g.id=p_growing_object_id
     AND g.farm_id=v_report.farm_id
     AND f.organization_id=v_report.organization_id
     AND f.status='active')
 OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
   p_ledger_id,v_person,'spatial','growing_object',
   p_growing_object_id,'identity'),false)
 THEN RAISE EXCEPTION 'No current source-qualified permission to name this Subject'
   USING ERRCODE='42501'; END IF;

 -- Reuse one Activity's stable subject claim, never create a replacement.
 SELECT * INTO v_claim
 FROM atlas.uni_ops_p2_later_worker_subject_attributions_v1 c
 WHERE c.report_id=v_report.id FOR UPDATE;
 IF v_claim.id IS NOT NULL THEN
   IF v_claim.source_action_id IS DISTINCT FROM p_action_id
      OR v_claim.reporter_user_id IS DISTINCT FROM v_uid
      OR v_claim.reporter_person_id IS DISTINCT FROM v_person
      OR v_claim.ledger_id IS DISTINCT FROM p_ledger_id
      OR v_claim.attributed_growing_object_id IS DISTINCT FROM
        p_growing_object_id
      OR v_claim.attribution_reason IS DISTINCT FROM v_reason
      OR v_claim.source_log_snapshot_md5 IS DISTINCT FROM v_snapshot
   THEN RAISE EXCEPTION 'Historical Subject claim cannot be rewritten'
     USING ERRCODE='23505'; END IF;
   RETURN pg_catalog.jsonb_build_object(
     'ok',true,'contractVersion','p2_later_worker_subject_claim_v1',
     'subjectAttributionId',v_claim.id,'replay',true,
     'claimRecordedAt',v_claim.recorded_at,
     'contemporaneousLogSubjectLink',false,
     'physicalSubjectOrConditionVerified',false,
     'newOriginalWorkCreated',false,'actualAccepted',false);
 END IF;

 INSERT INTO atlas.uni_ops_p2_later_worker_subject_attributions_v1(
   report_id,organization_id,ledger_id,farm_id,source_action_id,
   reporter_user_id,reporter_person_id,attributed_growing_object_id,
   source_log_snapshot_md5,attribution_reason)
 VALUES(
   v_report.id,v_report.organization_id,p_ledger_id,v_report.farm_id,
   p_action_id,v_uid,v_person,p_growing_object_id,v_snapshot,v_reason)
 RETURNING * INTO v_claim;
 RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','p2_later_worker_subject_claim_v1',
   'subjectAttributionId',v_claim.id,'replay',false,
   'sourceReportId',v_report.id,
   'sourceLogRecordedAt',v_report.source_log_recorded_at,
   'claimRecordedAt',v_claim.recorded_at,
   'claimMadeAfterLogWasRecorded',true,
   'contemporaneousLogSubjectLink',false,
   'physicalSubjectOrConditionVerified',false,
   'pastWorkAuthorizationEstablished',false,
   'newOriginalWorkCreated',false,'actualAccepted',false,'doneCreated',false
 );
END;
$worker$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p2_worker_attest_subject_later_held_v1(uuid,uuid,uuid,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
