-- HELD M3.16A: a separate author choice exposes ONE SEALED Unit
-- to ONE already accepted, still-currently appointed teacher Person.
-- The shared Course, accepted Offering, curriculum snapshot and exact offer
-- already exist. No whole manuscript, other Unit, learner, Work or Class.
-- Fictional isolated PG17 source ONLY; never execute against production.
DO $required$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.shared_course_open_source_current_v1(uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regclass('atlas.shared_course_teacher_appointment_offers') IS NULL
 OR to_regclass('atlas.shared_course_teacher_appointment_responses') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 THEN RAISE EXCEPTION 'accepted original Course teacher and sealed Version required'
  USING ERRCODE='42501'; END IF;
END $required$;

-- Own original author may revoke independently; newest event decides.
-- No client table rights or student/school/teacher roster discovery.
CREATE TABLE atlas.shared_course_teacher_unit_disclosure_decisions (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 teacher_offer_id uuid NOT NULL
  REFERENCES atlas.shared_course_teacher_appointment_offers(offer_id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL
  REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN
  ('allow_teacher_sealed_unit','withhold_teacher_sealed_unit')),
 decided_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(teacher_offer_id,request_id)
);
CREATE INDEX shared_teacher_unit_disclosure_latest_v1
 ON atlas.shared_course_teacher_unit_disclosure_decisions
 (teacher_offer_id,unit_id,event_seq DESC);
ALTER TABLE atlas.shared_course_teacher_unit_disclosure_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_teacher_unit_disclosure_decisions FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.shared_course_teacher_unit_disclosure_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER shared_teacher_unit_disclosure_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_teacher_unit_disclosure_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_teacher_receipt_mutation_v1();

CREATE FUNCTION public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
 p_teacher_offer_id uuid,p_unit_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $author_grant$
DECLARE
 v_offer atlas.shared_course_teacher_appointment_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_prior atlas.shared_course_teacher_unit_disclosure_decisions%ROWTYPE;
 v_seq bigint;
BEGIN
 IF p_teacher_offer_id IS NULL OR p_unit_id IS NULL OR p_request_id IS NULL
 OR p_decision NOT IN ('allow_teacher_sealed_unit','withhold_teacher_sealed_unit')
 THEN RAISE EXCEPTION 'exact teacher invitation, sealed Unit, and author choice required'
  USING ERRCODE='22023'; END IF;
 SELECT * INTO v_offer FROM atlas.shared_course_teacher_appointment_offers
 WHERE offer_id=p_teacher_offer_id;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'known teacher appointment required' USING ERRCODE='42501'; END IF;
 -- The same immutable proposal lock serializes source permission updates,
 -- revocations, teacher acceptance and governor withdrawal.
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR UPDATE;
 PERFORM atlas.require_private_course_author_self_v1(
  v_standing.course_id,p_decision='allow_teacher_sealed_unit');
 v_person:=atlas.current_person_for_private_course_v1();
 IF v_standing.id IS NULL OR v_standing.course_id IS DISTINCT FROM
   (SELECT o.course_id FROM atlas.teaching_course_offerings o
    WHERE o.id=v_offer.offering_id)
 OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
   WHERE o.id=v_offer.offering_id AND o.operating_proposal_id=v_standing.id
   AND o.course_version_id=v_offer.course_version_id)
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u
   WHERE u.unit_id=p_unit_id AND u.course_id=v_standing.course_id)
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_version_curriculum_snapshots s
   CROSS JOIN LATERAL jsonb_array_elements(s.curriculum_payload->'units') j(unit)
   WHERE s.course_id=v_standing.course_id
    AND s.course_version_id=v_offer.course_version_id
    AND j.unit->>'unitId'=p_unit_id::text)
 THEN RAISE EXCEPTION 'unit is not in exact original sealed Course Version'
  USING ERRCODE='42501'; END IF;
 IF p_decision='allow_teacher_sealed_unit' AND (
   NOT atlas.shared_course_open_source_current_v1(v_offer.offering_id)
   OR (SELECT d.decision FROM atlas.shared_course_teacher_invitation_author_decisions d
       WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_teacher_invitation'
   OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_teacher_appointment_responses r
      WHERE r.offer_id=p_teacher_offer_id AND r.decision='accept'
      AND r.responded_by_person_entity_id=v_offer.offered_to_person_entity_id)
   OR EXISTS(SELECT 1 FROM atlas.shared_course_teacher_appointment_withdrawals w
      WHERE w.offer_id=p_teacher_offer_id))
 THEN RAISE EXCEPTION 'separately accepted current appointment required for a Unit grant'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM atlas.shared_course_teacher_unit_disclosure_decisions
 WHERE teacher_offer_id=p_teacher_offer_id AND request_id=p_request_id;
 IF v_prior.event_seq IS NOT NULL THEN
  IF v_prior.unit_id IS DISTINCT FROM p_unit_id
  OR v_prior.decision IS DISTINCT FROM p_decision
  OR v_prior.decided_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'changed immutable teacher Unit disclosure choice'
    USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_teacher_unit_disclosure_author_v1',
   'teacherOfferId',p_teacher_offer_id,'unitId',p_unit_id,
   'decision',p_decision,'alreadyExists',true,
   'canReadCurriculum',false,'canTeach',false,'canReadOthers',false);
 END IF;
 INSERT INTO atlas.shared_course_teacher_unit_disclosure_decisions(
  teacher_offer_id,unit_id,request_id,decision,decided_by_person_entity_id)
 VALUES(p_teacher_offer_id,p_unit_id,p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_seq;
 RETURN jsonb_build_object(
  'contractVersion','shared_teacher_unit_disclosure_author_v1',
  'teacherOfferId',p_teacher_offer_id,'unitId',p_unit_id,
  'decision',p_decision,'alreadyExists',false,'eventSequence',v_seq,
  'canReadCurriculum',false,'canTeach',false,'canReadOthers',false);
END $author_grant$;

-- Signed named teacher ONLY. Read is current and narrow, does NOT make an
-- institution/teacher a co-author or copy the private whole manuscript.
CREATE FUNCTION public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
 p_teacher_offer_id uuid,p_unit_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $unit_read$
DECLARE
 v_person uuid;
 v_offer atlas.shared_course_teacher_appointment_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_unit jsonb;
BEGIN
 IF p_teacher_offer_id IS NULL OR p_unit_id IS NULL THEN
  RAISE EXCEPTION 'exact accepted teacher invitation and one Unit required'
   USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_offer FROM atlas.shared_course_teacher_appointment_offers
 WHERE offer_id=p_teacher_offer_id AND offered_to_person_entity_id=v_person;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'your specific appointed teacher offer is required'
   USING ERRCODE='42501'; END IF;
 -- An author withdrawal or governor withdrawal must acquire this same
 -- proposal lock. Previously read bytes cannot be reclaimed; all FUTURE
 -- reads re-evaluate current permissions, no caching entitlement granted.
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR SHARE;
 IF v_standing.id IS NULL
 OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR v_standing.course_id IS DISTINCT FROM
   (SELECT o.course_id FROM atlas.teaching_course_offerings o
    WHERE o.id=v_offer.offering_id)
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
   WHERE o.id=v_offer.offering_id AND o.operating_proposal_id=v_offer.proposal_id
   AND o.course_version_id=v_offer.course_version_id
   AND o.ledger_id=v_offer.ledger_id)
 OR NOT atlas.shared_course_open_source_current_v1(v_offer.offering_id)
 OR (SELECT d.decision FROM atlas.shared_course_teacher_invitation_author_decisions d
    WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_teacher_invitation'
 OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_teacher_appointment_responses r
   WHERE r.offer_id=p_teacher_offer_id AND r.decision='accept'
    AND r.responded_by_person_entity_id=v_person)
 OR EXISTS(SELECT 1 FROM atlas.shared_course_teacher_appointment_withdrawals w
   WHERE w.offer_id=p_teacher_offer_id)
 OR (SELECT d.decision FROM atlas.shared_course_teacher_unit_disclosure_decisions d
   WHERE d.teacher_offer_id=p_teacher_offer_id AND d.unit_id=p_unit_id
   ORDER BY d.event_seq DESC LIMIT 1)
   IS DISTINCT FROM 'allow_teacher_sealed_unit'
 THEN RAISE EXCEPTION 'a current author-issued sealed Unit read is required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_snapshot FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_id=v_standing.course_id
   AND s.course_version_id=v_offer.course_version_id
   AND s.sealed_by_person_entity_id=(
    SELECT c.created_by_person_entity_id FROM atlas.teaching_courses c
    WHERE c.id=v_standing.course_id);
 IF v_snapshot.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'immutable author-sealed original Version required'
   USING ERRCODE='42501'; END IF;
 SELECT j.unit INTO v_unit
 FROM jsonb_array_elements(v_snapshot.curriculum_payload->'units') j(unit)
 WHERE j.unit->>'unitId'=p_unit_id::text;
 IF v_unit IS NULL THEN
  RAISE EXCEPTION 'exact authorized sealed Unit does not exist'
   USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_teacher_sealed_unit_read_v1',
  'teacherOfferId',p_teacher_offer_id,'offeringId',v_offer.offering_id,
  'courseVersionId',v_offer.course_version_id,'snapshotId',v_snapshot.snapshot_id,
  'unitId',p_unit_id,
  'unit',jsonb_build_object(
    'unitId',p_unit_id,'kind',v_unit->'kind','title',v_unit->'title',
    'position',v_unit->'position',
    'revisionId',v_unit->'revisionId',
    'revisionNumber',v_unit->'revisionNumber','text',v_unit->'text'),
  'scope','one_author_approved_sealed_unit_to_appointed_teacher_only',
  'canTeach',false,'canReadOtherUnits',false,'canReadManuscript',false,
  'canShareWithLearners',false,'canAssignWork',false,'canEnroll',false);
END $unit_read$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_teacher_sealed_unit_read_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_teacher_sealed_unit_read_self_api_v1(uuid,uuid)
 TO authenticated;
-- Sealed Unit material read is a new narrow source right, not a new Course,
-- a student curriculum disclosure, a class, general teaching or Work.
