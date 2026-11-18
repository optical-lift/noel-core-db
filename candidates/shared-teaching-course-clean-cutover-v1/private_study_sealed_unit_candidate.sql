-- HELD M3.17B: independently authorized exact SEALED Unit edition to a
-- direct private-study learner of the SAME original Person-created Course.
-- This is a candidate for synthetic PG17 / owner-approved protected clone,
-- NEVER a production migration or permission release.
-- It depends on M3.17A current private study and M3.11 snapshot source.
-- No institutional Offering/Enrollment, no general manuscript/other Units,
-- no Notebook, submissions, Work, attendance, grading or Class operation.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.private_course_study_current_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_invitations') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_responses') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_terminations') IS NULL
 THEN RAISE EXCEPTION 'held original Course/private study/seal source required'
  USING ERRCODE='42501'; END IF;
END $gate$;

-- Later decisions on this SAME (invitation,Unit) are append-only: keep E1
-- after choosing E2, and WITHHOLD without mutating or erasing old receipts.
CREATE TABLE atlas.teaching_course_private_study_unit_decisions(
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 invitation_id uuid NOT NULL REFERENCES
  atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('allow','withhold')),
 course_version_id uuid REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
 snapshot_id uuid REFERENCES atlas.teaching_course_version_curriculum_snapshots(snapshot_id)
  ON DELETE RESTRICT,
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(decided_by_person_entity_id,request_id),
 UNIQUE(invitation_id,request_id),
 CHECK((decision='allow' AND course_version_id IS NOT NULL AND snapshot_id IS NOT NULL)
    OR (decision='withhold' AND course_version_id IS NULL AND snapshot_id IS NULL))
);
CREATE INDEX private_study_unit_latest_v1
 ON atlas.teaching_course_private_study_unit_decisions(invitation_id,unit_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_private_study_unit_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_unit_decisions
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.teaching_course_private_study_unit_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER private_study_unit_decision_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_unit_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Source-author decision is precisely tied to THIS invited learner and
-- ONE Unit in THIS SAME Course. A Version alone does not expose its text.
CREATE FUNCTION public.shared_teaching_private_study_unit_decide_self_api_v1(
 p_invitation_id uuid,p_unit_id uuid,p_request_id uuid,
 p_decision text,p_course_version_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $decide$
DECLARE
 v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_old atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_event bigint;v_snapshot_id uuid;
BEGIN
 IF p_invitation_id IS NULL OR p_unit_id IS NULL OR p_request_id IS NULL
 OR p_decision NOT IN ('allow','withhold')
 OR (p_decision='allow' AND p_course_version_id IS NULL)
 OR (p_decision='withhold' AND p_course_version_id IS NOT NULL)
 THEN RAISE EXCEPTION 'exact private Unit edition decision required'
  USING ERRCODE='22023'; END IF;
 -- Acquire Course lock first, consistent with author invitation/withdrawal.
 SELECT * INTO v_inv FROM atlas.teaching_course_private_study_invitations
 WHERE invitation_id=p_invitation_id;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'known private study original required' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(v_inv.course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF v_inv.invited_by_person_entity_id IS DISTINCT FROM v_person OR
 NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u
   WHERE u.unit_id=p_unit_id AND u.course_id=v_inv.course_id) THEN
  RAISE EXCEPTION 'exact authored study Unit required' USING ERRCODE='42501';
 END IF;
 -- Idempotent retries must remain valid, not rewrite original decision.
 SELECT * INTO v_old FROM atlas.teaching_course_private_study_unit_decisions
 WHERE decided_by_person_entity_id=v_person AND request_id=p_request_id;
 IF v_old.event_seq IS NOT NULL THEN
  IF v_old.invitation_id IS DISTINCT FROM p_invitation_id
  OR v_old.unit_id IS DISTINCT FROM p_unit_id
  OR v_old.decision IS DISTINCT FROM p_decision
  OR v_old.course_version_id IS DISTINCT FROM p_course_version_id THEN
   RAISE EXCEPTION 'changed private Unit decision replay' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_study_unit_decision_v1',
   'invitationId',p_invitation_id,'unitId',p_unit_id,'decision',p_decision,
   'alreadyExists',true,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF p_decision='allow' THEN
  IF NOT atlas.private_course_study_current_v1(
    v_inv.course_id,v_inv.learner_person_entity_id) THEN
   RAISE EXCEPTION 'signed accepted private study required'
    USING ERRCODE='42501'; END IF;
  SELECT * INTO v_snapshot FROM atlas.teaching_course_version_curriculum_snapshots s
   WHERE s.course_id=v_inv.course_id
     AND s.course_version_id=p_course_version_id
     AND s.sealed_by_person_entity_id=v_person;
  IF v_snapshot.snapshot_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(
     v_snapshot.curriculum_payload->'units') q(unit)
    WHERE q.unit->>'unitId'=p_unit_id::text
      AND q.unit->>'revisionId' IS NOT NULL
      AND q.unit->>'text' IS NOT NULL
  ) THEN
   RAISE EXCEPTION 'original complete author-sealed Unit edition required'
    USING ERRCODE='42501';
  END IF;
  v_snapshot_id:=v_snapshot.snapshot_id;
 END IF;
 INSERT INTO atlas.teaching_course_private_study_unit_decisions(
  invitation_id,unit_id,request_id,decision,course_version_id,
  snapshot_id,decided_by_person_entity_id)
 VALUES(p_invitation_id,p_unit_id,p_request_id,p_decision,p_course_version_id,
  v_snapshot_id,v_person)
 RETURNING event_seq INTO v_event;
 RETURN jsonb_build_object('contractVersion','private_study_unit_decision_v1',
  'invitationId',p_invitation_id,'unitId',p_unit_id,'decision',p_decision,
  'eventSequence',v_event,'alreadyExists',false,
  'canReadMaterial',false,'canSubmitWork',false);
END $decide$;

-- Signed invitee reads exactly ONE author-released Unit, from the exact
-- immutable sealed Version selected for THIS Person + Unit. Inviting or
-- accepting alone NEVER provides a title or manuscript read here.
CREATE FUNCTION public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
 p_invitation_id uuid,p_unit_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $read_one$
DECLARE
 v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_decision atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
 v_snap atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_unit jsonb;
BEGIN
 IF p_invitation_id IS NULL OR p_unit_id IS NULL THEN
  RAISE EXCEPTION 'exact private study Unit required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id
  AND i.learner_person_entity_id=v_person;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'current own private study required' USING ERRCODE='42501';
 END IF;
 -- Course lock serializes with author issue and retirement, then invitation
 -- lock serializes with withdrawal; readers never depend on browser-role tags.
 PERFORM 1 FROM atlas.teaching_courses c
  WHERE c.id=v_inv.course_id AND c.status='active'
    AND c.created_by_person_entity_id=v_inv.invited_by_person_entity_id
  FOR SHARE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'current exact Course required' USING ERRCODE='42501';
 END IF;
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
  WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person
  FOR SHARE;
 IF v_inv.invitation_id IS NULL OR NOT atlas.private_course_study_current_v1(
  v_inv.course_id,v_person) THEN
  RAISE EXCEPTION 'current signed accepted study required' USING ERRCODE='42501';
 END IF;
 SELECT d.* INTO v_decision FROM atlas.teaching_course_private_study_unit_decisions d
 WHERE d.invitation_id=v_inv.invitation_id AND d.unit_id=p_unit_id
 ORDER BY d.event_seq DESC LIMIT 1;
 IF v_decision.event_seq IS NULL OR v_decision.decision<>'allow' THEN
  RAISE EXCEPTION 'exact author-released Unit unavailable' USING ERRCODE='42501';
 END IF;
 SELECT s.* INTO v_snap FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.snapshot_id=v_decision.snapshot_id AND s.course_id=v_inv.course_id
  AND s.course_version_id=v_decision.course_version_id
  AND s.sealed_by_person_entity_id=v_inv.invited_by_person_entity_id;
 IF v_snap.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'original immutable Unit edition unavailable' USING ERRCODE='42501';
 END IF;
 SELECT q.unit INTO v_unit FROM jsonb_array_elements(
  v_snap.curriculum_payload->'units') q(unit)
 WHERE q.unit->>'unitId'=p_unit_id::text;
 IF v_unit IS NULL THEN
  RAISE EXCEPTION 'exact sealed Unit unavailable' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('contractVersion','private_study_sealed_unit_read_v1',
  'invitationId',v_inv.invitation_id,
  'courseId',v_inv.course_id,'courseVersionId',v_snap.course_version_id,
  'unitId',p_unit_id,'snapshotId',v_snap.snapshot_id,
  'unit',jsonb_build_object(
    'unitId',p_unit_id,'kind',v_unit->'kind','title',v_unit->'title',
    'position',v_unit->'position',
    'revisionId',v_unit->'revisionId',
    'revisionNumber',v_unit->'revisionNumber','text',v_unit->'text'),
  'canReadOtherUnits',false,'canReadManuscript',false,
  'canReadCurriculum',false,'canSubmitWork',false,'canTeach',false);
END $read_one$;
REVOKE ALL ON FUNCTION
 public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid),
 public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid),
 public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)
 TO authenticated;
-- Complete a separately governed student source (notes, submissions,
-- feedback and encounter history) BEFORE claiming functional classroom.
