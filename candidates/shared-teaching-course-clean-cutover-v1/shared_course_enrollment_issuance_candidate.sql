-- HELD M3.15B: original Enrollment carrier, canonical Person, one signed
-- learner consent + separate author permission + exact current governor issue.
-- Protected PG17 clone source candidate only. No live migration or release.
-- Administrative Enrollment does NOT convey classroom, curriculum or Work.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.guard_shared_course_enrollment_pending_v1()') IS NULL
 OR to_regprocedure('atlas.shared_course_open_source_current_v1(uuid)') IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)') IS NULL
 OR to_regprocedure('public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text)') IS NULL
 OR to_regclass('atlas.teaching_enrollments') IS NULL
 OR to_regclass('atlas.shared_course_learner_invitation_offers') IS NULL
 OR to_regclass('atlas.shared_course_learner_invitation_responses') IS NULL
 OR to_regclass('atlas.shared_course_learner_invitation_withdrawals') IS NULL
 THEN RAISE EXCEPTION 'one original Enrollment and signed learner prerequisites required'
  USING ERRCODE='42501';
 END IF;
END $gate$;

-- Keep the existing original Enrollment table/PK, ledger/offering FK,
-- historic legacy columns/FKs and immutable state. No shadow carrier.
-- The old three actor fields remain bound to atlas.people/principals ONLY
-- for historical old rows, never silently mapped to a Reality Person.
ALTER TABLE atlas.teaching_enrollments
 ALTER COLUMN person_id DROP NOT NULL,
 ALTER COLUMN enrolled_by_person_id DROP NOT NULL,
 ALTER COLUMN enrolled_by_principal_id DROP NOT NULL,
 ADD COLUMN person_entity_id uuid
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN enrolled_by_person_entity_id uuid
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN shared_learner_offer_id uuid
   REFERENCES atlas.shared_course_learner_invitation_offers(offer_id) ON DELETE RESTRICT,
 ADD COLUMN shared_enrollment_request_id uuid,
 ADD CONSTRAINT shared_course_enrollment_provenance_v1 CHECK (
  (person_id IS NOT NULL AND enrolled_by_person_id IS NOT NULL
   AND enrolled_by_principal_id IS NOT NULL AND person_entity_id IS NULL
   AND enrolled_by_person_entity_id IS NULL
   AND shared_learner_offer_id IS NULL AND shared_enrollment_request_id IS NULL)
  OR
  (person_id IS NULL AND enrolled_by_person_id IS NULL
   AND enrolled_by_principal_id IS NULL AND person_entity_id IS NOT NULL
   AND enrolled_by_person_entity_id IS NOT NULL
   AND shared_learner_offer_id IS NOT NULL AND shared_enrollment_request_id IS NOT NULL)
 );
CREATE UNIQUE INDEX shared_course_enrollment_one_original_person_v1
 ON atlas.teaching_enrollments(offering_id,person_entity_id)
 WHERE person_entity_id IS NOT NULL;
CREATE UNIQUE INDEX shared_course_enrollment_one_original_offer_v1
 ON atlas.teaching_enrollments(shared_learner_offer_id)
 WHERE shared_learner_offer_id IS NOT NULL;
ALTER TABLE atlas.teaching_enrollments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_enrollments FROM PUBLIC,anon,authenticated;

-- Sixth original-author decision. The earlier invitation disclosure
-- permission cannot independently authorize Enrollment.
CREATE TABLE atlas.shared_course_learner_enrollment_author_decisions (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN
   ('allow_learner_enrollment','withhold_learner_enrollment')),
 decided_by_person_entity_id uuid NOT NULL
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(offering_id,request_id)
);
CREATE INDEX shared_course_learner_enrollment_author_latest_v1
 ON atlas.shared_course_learner_enrollment_author_decisions(offering_id,event_seq DESC);
ALTER TABLE atlas.shared_course_learner_enrollment_author_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_enrollment_author_decisions FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.shared_course_learner_enrollment_author_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;

-- Private original issue. Transaction receipt is created immediately before
-- INSERT into the SINGLE old atlas.teaching_enrollments carrier. Old privileged
-- functions never mint this receipt and cannot pass its trigger gate.
CREATE TABLE atlas.shared_course_enrollment_issuances (
 issuance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 enrollment_id uuid NOT NULL UNIQUE,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 learner_offer_id uuid NOT NULL UNIQUE REFERENCES
   atlas.shared_course_learner_invitation_offers(offer_id) ON DELETE RESTRICT,
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 issued_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 issuer_txid bigint NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(offering_id,request_id)
);
ALTER TABLE atlas.shared_course_enrollment_issuances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_enrollment_issuances FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_shared_enrollment_receipt_change_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'shared Enrollment authorization receipt cannot mutate'
  USING ERRCODE='55000';
END $immutable$;
CREATE TRIGGER shared_enrollment_author_decision_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_enrollment_author_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_enrollment_receipt_change_v1();
CREATE TRIGGER shared_enrollment_issuance_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_enrollment_issuances
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_enrollment_receipt_change_v1();
REVOKE ALL ON FUNCTION atlas.reject_shared_enrollment_receipt_change_v1()
 FROM PUBLIC,anon,authenticated;

-- Replace the M3.13 categorical guard, but ONLY for a new same-transaction,
-- same-original, current source-issued INSERT. Every shared UPDATE/DELETE
-- remains closed. No arbitrary GUC/token can authorize a privileged writer.
CREATE OR REPLACE FUNCTION atlas.guard_shared_course_enrollment_pending_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $issued_enrollment_guard$
DECLARE
 v_offering_id uuid;
BEGIN
 v_offering_id:=CASE WHEN TG_OP='DELETE' THEN OLD.offering_id ELSE NEW.offering_id END;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
  WHERE o.id=v_offering_id AND o.operating_proposal_id IS NOT NULL)
 THEN
  IF TG_OP<>'INSERT'
   OR NOT EXISTS(
    SELECT 1
    FROM atlas.shared_course_enrollment_issuances i
    JOIN atlas.shared_course_learner_invitation_offers offer
      ON offer.offer_id=i.learner_offer_id AND offer.offering_id=i.offering_id
      AND offer.ledger_id=i.ledger_id
      AND offer.offered_to_person_entity_id=i.person_entity_id
    JOIN atlas.shared_course_learner_invitation_responses response
      ON response.offer_id=offer.offer_id AND response.decision='accept'
      AND response.responded_by_person_entity_id=i.person_entity_id
    WHERE i.enrollment_id=NEW.id AND i.offering_id=NEW.offering_id
      AND i.ledger_id=NEW.ledger_id AND i.person_entity_id=NEW.person_entity_id
      AND i.learner_offer_id=NEW.shared_learner_offer_id
      AND i.request_id=NEW.shared_enrollment_request_id
      AND i.issued_by_person_entity_id=NEW.enrolled_by_person_entity_id
      AND i.issuer_txid=txid_current()
      AND NEW.person_id IS NULL AND NEW.enrolled_by_person_id IS NULL
      AND NEW.enrolled_by_principal_id IS NULL
      AND NEW.state='active' AND NEW.withdrawn_at IS NULL
      AND NOT EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
       WHERE w.offer_id=offer.offer_id)
      AND (SELECT d.decision
       FROM atlas.shared_course_learner_invitation_author_decisions d
       WHERE d.offering_id=offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
       IS NOT DISTINCT FROM 'allow_learner_invitation'
      AND (SELECT d.decision
       FROM atlas.shared_course_learner_enrollment_author_decisions d
       WHERE d.offering_id=offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
       IS NOT DISTINCT FROM 'allow_learner_enrollment'
      AND atlas.shared_course_open_source_current_v1(i.offering_id)
   )
  THEN RAISE EXCEPTION 'shared Enrollment requires exact current source issuance'
   USING ERRCODE='42501';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $issued_enrollment_guard$;

-- Author's independent exact Offering permit; still no principal/learner
-- Enrollment or automatic disclosure. Existing author source checks remain.
CREATE FUNCTION public.shared_teaching_learner_enrollment_decide_self_api_v1(
 p_offering_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $author$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_prior atlas.shared_course_learner_enrollment_author_decisions%ROWTYPE;
 v_seq bigint;
BEGIN
 IF p_offering_id IS NULL OR p_request_id IS NULL OR p_decision IS NULL
 OR p_decision NOT IN ('allow_learner_enrollment','withhold_learner_enrollment')
 THEN RAISE EXCEPTION 'specific original-author Enrollment decision required'
  USING ERRCODE='22023';
 END IF;
 SELECT s.* INTO v_standing FROM atlas.teaching_course_operating_standings s
 JOIN atlas.teaching_course_offerings o
  ON o.operating_proposal_id=s.id AND o.course_id=s.course_id
  AND o.ledger_id=s.ledger_id
 WHERE o.id=p_offering_id FOR UPDATE OF s;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'known same-original Course Offering required'
   USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(
  v_standing.course_id,p_decision='allow_learner_enrollment');
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_decision='allow_learner_enrollment'
 AND (NOT atlas.shared_course_open_source_current_v1(p_offering_id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
     WHERE d.offering_id=p_offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_invitation')
 THEN RAISE EXCEPTION 'current Course author, invitation and opening rights required'
  USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.shared_course_learner_enrollment_author_decisions
 WHERE offering_id=p_offering_id AND request_id=p_request_id;
 IF v_prior.event_seq IS NOT NULL THEN
  IF v_prior.decision IS DISTINCT FROM p_decision
  OR v_prior.decided_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'changed original-author Enrollment decision'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_enrollment_author_v1',
   'offeringId',p_offering_id,'decision',p_decision,'alreadyExists',true,
   'canIssueEnrollment',false,'canParticipate',false,'canReadCurriculum',false);
 END IF;
 INSERT INTO atlas.shared_course_learner_enrollment_author_decisions(
  offering_id,request_id,decision,decided_by_person_entity_id)
 VALUES(p_offering_id,p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_seq;
 RETURN jsonb_build_object('contractVersion','shared_learner_enrollment_author_v1',
  'offeringId',p_offering_id,'decision',p_decision,'alreadyExists',false,
  'eventSequence',v_seq,'canIssueEnrollment',false,
  'canParticipate',false,'canReadCurriculum',false);
END $author$;

-- Only CURRENT independently authenticated native Ledger root governor
-- can issue this original Enrollment, AFTER learner's own accepted response
-- and both separate author grants. Enrollment is not a classroom admission.
CREATE FUNCTION public.shared_teaching_learner_enrollment_issue_self_api_v1(
 p_offer_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $issue$
DECLARE
 v_offer atlas.shared_course_learner_invitation_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_governor uuid;
 v_prior atlas.shared_course_enrollment_issuances%ROWTYPE;
 v_created_id uuid;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact accepted invitation and independent issuance request required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_offer FROM atlas.shared_course_learner_invitation_offers
 WHERE offer_id=p_offer_id;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'known exact learner invitation required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR UPDATE;
 v_governor:=atlas.require_shared_course_native_ledger_governor_self_v1(v_offer.ledger_id);
 IF v_standing.id IS NULL
 OR v_standing.course_id IS DISTINCT FROM
   (SELECT o.course_id FROM atlas.teaching_course_offerings o
    WHERE o.id=v_offer.offering_id)
 OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
    WHERE o.id=v_offer.offering_id AND o.operating_proposal_id=v_offer.proposal_id
     AND o.ledger_id=v_offer.ledger_id AND o.course_version_id=v_offer.course_version_id)
 OR NOT atlas.shared_course_open_source_current_v1(v_offer.offering_id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
     WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_invitation'
 OR (SELECT d.decision FROM atlas.shared_course_learner_enrollment_author_decisions d
     WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_enrollment'
 OR NOT EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_responses r
   WHERE r.offer_id=v_offer.offer_id AND r.decision='accept'
   AND r.responded_by_person_entity_id=v_offer.offered_to_person_entity_id)
 OR EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
   WHERE w.offer_id=v_offer.offer_id)
 OR NOT EXISTS(SELECT 1 FROM reality.entities e
   WHERE e.id=v_offer.offered_to_person_entity_id AND e.entity_kind='person'
    AND e.identity_state='canonical')
 THEN RAISE EXCEPTION 'author, learner consent and current governor Enrollment issuance required'
  USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.shared_course_enrollment_issuances
 WHERE offering_id=v_offer.offering_id AND request_id=p_request_id;
 IF v_prior.issuance_id IS NOT NULL THEN
  IF v_prior.learner_offer_id IS DISTINCT FROM p_offer_id
  OR v_prior.person_entity_id IS DISTINCT FROM v_offer.offered_to_person_entity_id
  OR v_prior.issued_by_person_entity_id IS DISTINCT FROM v_governor
  OR NOT EXISTS(SELECT 1 FROM atlas.teaching_enrollments e
    WHERE e.id=v_prior.enrollment_id AND e.offering_id=v_offer.offering_id
      AND e.person_entity_id=v_offer.offered_to_person_entity_id AND e.state='active')
  THEN RAISE EXCEPTION 'changed immutable Enrollment issuance request'
   USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_enrollment_issue_v1',
   'enrollmentId',v_prior.enrollment_id,'offeringId',v_offer.offering_id,
    'offerId',v_offer.offer_id,
   'learnerPersonEntityId',v_offer.offered_to_person_entity_id,
   'enrollmentState','active','alreadyExists',true,
   'canParticipate',false,'canReadCurriculum',false,'canTeach',false);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.shared_course_enrollment_issuances
   WHERE learner_offer_id=p_offer_id)
 OR EXISTS(SELECT 1 FROM atlas.teaching_enrollments e
   WHERE e.offering_id=v_offer.offering_id
     AND e.person_entity_id=v_offer.offered_to_person_entity_id)
 THEN RAISE EXCEPTION 'one original Enrollment per Person and Offering'
  USING ERRCODE='23505';
 END IF;
 v_created_id:=gen_random_uuid();
 INSERT INTO atlas.shared_course_enrollment_issuances(
  enrollment_id,offering_id,ledger_id,learner_offer_id,person_entity_id,
  issued_by_person_entity_id,request_id,issuer_txid)
 VALUES(v_created_id,v_offer.offering_id,v_offer.ledger_id,p_offer_id,
  v_offer.offered_to_person_entity_id,v_governor,p_request_id,txid_current());
 INSERT INTO atlas.teaching_enrollments(
  id,ledger_id,offering_id,person_entity_id,enrolled_by_person_entity_id,
  shared_learner_offer_id,shared_enrollment_request_id,state)
 VALUES(v_created_id,v_offer.ledger_id,v_offer.offering_id,
  v_offer.offered_to_person_entity_id,v_governor,p_offer_id,p_request_id,'active');
 RETURN jsonb_build_object('contractVersion','shared_learner_enrollment_issue_v1',
  'enrollmentId',v_created_id,'offeringId',v_offer.offering_id,
   'offerId',v_offer.offer_id,
  'learnerPersonEntityId',v_offer.offered_to_person_entity_id,
  'enrollmentState','active','alreadyExists',false,
  'canParticipate',false,'canReadCurriculum',false,'canTeach',false);
END $issue$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_learner_enrollment_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_learner_enrollment_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)
 TO authenticated;
-- Subsequent learner-facing Enrollment read, withdrawal, curriculum disclosure,
-- Work and classroom seat still require their own separate source and tests.
