-- HELD M3.16B: original author releases ONE sealed Course Unit to ONE
-- specifically enrolled learner Person on the SAME original Enrollment row.
-- Enrollment issuance itself is NEVER permission to inspect Course text.
-- No learner roster, private manuscript, other Units, Class or Work.
-- Disposable synthetic PostgreSQL 17 / protected clone only; no live DDL.
DO $source_gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.shared_course_open_source_current_v1(uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regclass('atlas.shared_course_enrollment_issuances') IS NULL
 OR to_regclass('atlas.shared_course_enrollment_withdrawal_issuances') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 OR to_regclass('atlas.teaching_enrollments') IS NULL
 THEN RAISE EXCEPTION 'original issued Enrollment and immutable sealed Course prerequisite missing'
  USING ERRCODE='42501'; END IF;
END $source_gate$;

-- Author grant is explicitly for one known original Enrollment and one
-- Unit of the Offering's own sealed immutable Version. Latest event wins.
-- Retain decision history after enrollment withdrawal or source revocation.
CREATE TABLE atlas.shared_course_learner_unit_disclosure_decisions(
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 enrollment_id uuid NOT NULL REFERENCES atlas.teaching_enrollments(id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN
  ('allow_learner_sealed_unit','withhold_learner_sealed_unit')),
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(enrollment_id,request_id)
);
CREATE INDEX shared_learner_unit_disclosure_latest_v1
 ON atlas.shared_course_learner_unit_disclosure_decisions(enrollment_id,unit_id,event_seq DESC);
ALTER TABLE atlas.shared_course_learner_unit_disclosure_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_unit_disclosure_decisions
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.shared_course_learner_unit_disclosure_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER shared_learner_unit_disclosure_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_unit_disclosure_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_enrollment_receipt_change_v1();

-- This action is original author-only. Neither the governor nor the teacher
-- can choose what a learner receives. Even an active Enrollment must have
-- accepted learner invitation, current separate author Enroll/Invite scopes,
-- and one independently authored allow for the exact sealed Unit.
CREATE FUNCTION public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
 p_enrollment_id uuid,p_unit_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $decide$
DECLARE
 v_enrollment atlas.teaching_enrollments%ROWTYPE;
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_prior atlas.shared_course_learner_unit_disclosure_decisions%ROWTYPE;
 v_seq bigint;
BEGIN
 IF p_enrollment_id IS NULL OR p_unit_id IS NULL OR p_request_id IS NULL
 OR p_decision NOT IN ('allow_learner_sealed_unit','withhold_learner_sealed_unit')
 THEN RAISE EXCEPTION 'exact original Enrollment, sealed Unit and author decision required'
  USING ERRCODE='22023'; END IF;
 SELECT * INTO v_enrollment FROM atlas.teaching_enrollments
 WHERE id=p_enrollment_id;
 IF v_enrollment.id IS NULL OR v_enrollment.person_entity_id IS NULL THEN
  RAISE EXCEPTION 'known canonical original learner Enrollment required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings
 WHERE id=v_enrollment.offering_id;
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offering.operating_proposal_id FOR UPDATE;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'original accepted Course operating standing required'
  USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(
  v_standing.course_id,p_decision='allow_learner_sealed_unit');
 v_person:=atlas.current_person_for_private_course_v1();
 -- Serialize with independently signed learner self-withdrawal. A learner
 -- cannot become newly authorized after withdrawing concurrently.
 SELECT * INTO v_enrollment FROM atlas.teaching_enrollments
 WHERE id=p_enrollment_id FOR SHARE;
 IF v_enrollment.id IS NULL OR v_enrollment.person_entity_id IS NULL
 OR v_enrollment.offering_id IS DISTINCT FROM v_offering.id
 OR v_enrollment.ledger_id IS DISTINCT FROM v_offering.ledger_id
 OR v_standing.course_id IS DISTINCT FROM v_offering.course_id
 OR v_standing.ledger_id IS DISTINCT FROM v_offering.ledger_id
 OR v_standing.id IS DISTINCT FROM v_offering.operating_proposal_id
 OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_enrollment_issuances i
   WHERE i.enrollment_id=v_enrollment.id
    AND i.offering_id=v_enrollment.offering_id
    AND i.ledger_id=v_enrollment.ledger_id
    AND i.person_entity_id=v_enrollment.person_entity_id
    AND i.learner_offer_id=v_enrollment.shared_learner_offer_id)
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u
   WHERE u.unit_id=p_unit_id AND u.course_id=v_standing.course_id)
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_version_curriculum_snapshots s
   CROSS JOIN LATERAL jsonb_array_elements(s.curriculum_payload->'units') j(unit)
   WHERE s.course_id=v_offering.course_id
    AND s.course_version_id=v_offering.course_version_id
    AND j.unit->>'unitId'=p_unit_id::text)
 THEN RAISE EXCEPTION 'Unit is not in the one source-issued Enrollment sealed Version'
  USING ERRCODE='42501'; END IF;
 IF p_decision='allow_learner_sealed_unit' AND (
   v_enrollment.state<>'active' OR v_enrollment.withdrawn_at IS NOT NULL
   OR EXISTS(SELECT 1 FROM atlas.shared_course_enrollment_withdrawal_issuances w
      WHERE w.enrollment_id=p_enrollment_id)
   OR NOT atlas.shared_course_open_source_current_v1(v_offering.id)
   OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
       WHERE d.offering_id=v_offering.id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_learner_invitation'
   OR (SELECT d.decision FROM atlas.shared_course_learner_enrollment_author_decisions d
       WHERE d.offering_id=v_offering.id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_learner_enrollment'
   OR NOT EXISTS(SELECT 1
      FROM atlas.shared_course_learner_invitation_offers offer
      JOIN atlas.shared_course_learner_invitation_responses r
        ON r.offer_id=offer.offer_id AND r.decision='accept'
       AND r.responded_by_person_entity_id=v_enrollment.person_entity_id
      WHERE offer.offer_id=v_enrollment.shared_learner_offer_id
       AND offer.offering_id=v_offering.id
       AND offer.offered_to_person_entity_id=v_enrollment.person_entity_id)
   OR EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
      WHERE w.offer_id=v_enrollment.shared_learner_offer_id))
 THEN RAISE EXCEPTION 'current original Enrollment, consent and author scopes required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM atlas.shared_course_learner_unit_disclosure_decisions
 WHERE enrollment_id=p_enrollment_id AND request_id=p_request_id;
 IF v_prior.event_seq IS NOT NULL THEN
  IF v_prior.unit_id IS DISTINCT FROM p_unit_id
   OR v_prior.decision IS DISTINCT FROM p_decision
   OR v_prior.decided_by_person_entity_id IS DISTINCT FROM v_person
  THEN RAISE EXCEPTION 'immutable learner Unit disclosure request changed'
   USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_learner_unit_disclosure_author_v1',
   'enrollmentId',p_enrollment_id,'unitId',p_unit_id,
   'decision',p_decision,'alreadyExists',true,
   'canReadCurriculum',false,'canParticipate',false,
   'canSubmit',false,'canAssignWork',false,'canTeach',false);
 END IF;
 INSERT INTO atlas.shared_course_learner_unit_disclosure_decisions(
  enrollment_id,unit_id,request_id,decision,decided_by_person_entity_id)
 VALUES(p_enrollment_id,p_unit_id,p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_seq;
 RETURN jsonb_build_object(
  'contractVersion','shared_learner_unit_disclosure_author_v1',
  'enrollmentId',p_enrollment_id,'unitId',p_unit_id,
  'decision',p_decision,'eventSequence',v_seq,'alreadyExists',false,
  'canReadCurriculum',false,'canParticipate',false,
  'canSubmit',false,'canAssignWork',false,'canTeach',false);
END $decide$;

-- A learner can read a separately authorized SINGLE Unit in its original
-- immutable sealed Version, using their current real signed Person identity.
-- A learner cannot read ANY sealed Unit merely from Enrollment or invitation.
CREATE FUNCTION public.shared_teaching_learner_sealed_unit_read_self_api_v1(
 p_enrollment_id uuid,p_unit_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $read_one$
DECLARE
 v_person uuid;
 v_enrollment atlas.teaching_enrollments%ROWTYPE;
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_unit jsonb;
BEGIN
 IF p_enrollment_id IS NULL OR p_unit_id IS NULL THEN
  RAISE EXCEPTION 'own original Enrollment and one sealed Unit required'
   USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_enrollment FROM atlas.teaching_enrollments
 WHERE id=p_enrollment_id AND person_entity_id=v_person;
 IF v_enrollment.id IS NULL THEN
  RAISE EXCEPTION 'only the independently signed enrolled learner may read own material'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings
 WHERE id=v_enrollment.offering_id;
 -- Same proposal lock as source author and institution permission
 -- decisions; same Enrollment lock as independently signed withdrawal.
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offering.operating_proposal_id FOR SHARE;
 SELECT * INTO v_enrollment FROM atlas.teaching_enrollments
 WHERE id=p_enrollment_id AND person_entity_id=v_person FOR SHARE;
 IF v_standing.id IS NULL OR v_enrollment.id IS NULL
 OR v_enrollment.state<>'active' OR v_enrollment.withdrawn_at IS NOT NULL
 OR v_enrollment.ledger_id IS DISTINCT FROM v_offering.ledger_id
 OR v_standing.course_id IS DISTINCT FROM v_offering.course_id
 OR v_standing.ledger_id IS DISTINCT FROM v_offering.ledger_id
 OR v_standing.id IS DISTINCT FROM v_offering.operating_proposal_id
 OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_enrollment_issuances i
   WHERE i.enrollment_id=v_enrollment.id AND i.offering_id=v_offering.id
    AND i.ledger_id=v_enrollment.ledger_id
    AND i.person_entity_id=v_person
    AND i.learner_offer_id=v_enrollment.shared_learner_offer_id)
 OR EXISTS(SELECT 1 FROM atlas.shared_course_enrollment_withdrawal_issuances w
   WHERE w.enrollment_id=v_enrollment.id)
 OR NOT atlas.shared_course_open_source_current_v1(v_offering.id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
    WHERE d.offering_id=v_offering.id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_invitation'
 OR (SELECT d.decision FROM atlas.shared_course_learner_enrollment_author_decisions d
    WHERE d.offering_id=v_offering.id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_enrollment'
 OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_offers o
   JOIN atlas.shared_course_learner_invitation_responses r
    ON r.offer_id=o.offer_id AND r.decision='accept'
     AND r.responded_by_person_entity_id=v_person
   WHERE o.offer_id=v_enrollment.shared_learner_offer_id
    AND o.offering_id=v_offering.id AND o.offered_to_person_entity_id=v_person)
 OR EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
    WHERE w.offer_id=v_enrollment.shared_learner_offer_id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_unit_disclosure_decisions d
    WHERE d.enrollment_id=v_enrollment.id AND d.unit_id=p_unit_id
    ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_sealed_unit'
 THEN RAISE EXCEPTION 'current exact learner Unit disclosure is unavailable'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_snapshot FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_id=v_offering.course_id
  AND s.course_version_id=v_offering.course_version_id
  AND s.sealed_by_person_entity_id=(
   SELECT c.created_by_person_entity_id FROM atlas.teaching_courses c
   WHERE c.id=v_offering.course_id);
 IF v_snapshot.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'immutable author-sealed Version unavailable'
   USING ERRCODE='42501'; END IF;
 SELECT j.unit INTO v_unit
 FROM jsonb_array_elements(v_snapshot.curriculum_payload->'units') j(unit)
 WHERE j.unit->>'unitId'=p_unit_id::text;
 IF v_unit IS NULL THEN
  RAISE EXCEPTION 'specific authorized sealed Unit unavailable'
   USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_learner_sealed_unit_read_v1',
  'enrollmentId',v_enrollment.id,'offeringId',v_offering.id,
  'learnerPersonEntityId',v_person,
  'courseVersionId',v_offering.course_version_id,
  'snapshotId',v_snapshot.snapshot_id,'unitId',p_unit_id,
  'unit',jsonb_build_object(
    'unitId',p_unit_id,'kind',v_unit->'kind','title',v_unit->'title',
    'position',v_unit->'position','revisionId',v_unit->'revisionId',
    'revisionNumber',v_unit->'revisionNumber','text',v_unit->'text'),
  'scope','one_author_approved_sealed_unit_to_enrolled_learner_only',
  'canReadCurriculum',false,'canReadOtherUnits',false,
  'canReadManuscript',false,'canParticipate',false,'canSubmit',false,
  'canAssignWork',false,'canTeach',false,'canEnroll',false);
END $read_one$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_learner_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_learner_sealed_unit_read_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_learner_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_learner_sealed_unit_read_self_api_v1(uuid,uuid)
 TO authenticated;
-- Source access is not permission to participate, submit, grade, assign,
-- teach, or expose this Unit to other People; no generic Course listing.
