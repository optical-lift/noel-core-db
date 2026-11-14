-- HELD M3.15A — source-issued specific learner invitation + learner consent.
-- One original Person Course, one accepted Ledger, one open Offering.
-- NO learner enrollment, class operation, learner materials, Work or roster.
-- Clone-only candidate. Old atlas.teaching_enrollments remains fully
-- mutation-blocked for shared Offerings: canonical learner consent alone
-- cannot satisfy its old Atlas People/Principal foreign keys.
-- No production migration or actual data.
DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regclass('atlas.teaching_course_offering_open_issuances') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 OR to_regprocedure('atlas.shared_course_open_source_current_v1(uuid)') IS NULL
 OR to_regprocedure('atlas.guard_shared_course_enrollment_pending_v1()') IS NULL
 THEN RAISE EXCEPTION 'separate signed learner invitation prerequisites missing'
  USING ERRCODE='42501';
 END IF;
END $guard$;

-- Reuse the current source-governed open Offering predicate. A learner
-- invitation is consent solicitation, NOT an Enrollment or class seat.
-- Separate and revocable author disclosure permission: one author has explicitly permitted
-- disclosure of the Course title/schedule for inviting a learner to THIS
-- Offering. No author permission means no named learner offer or title read.
CREATE TABLE atlas.shared_course_learner_invitation_author_decisions(
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('allow_learner_invitation','withhold_learner_invitation')),
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(offering_id,request_id)
);
CREATE INDEX shared_learner_invitation_author_latest_v1
 ON atlas.shared_course_learner_invitation_author_decisions(offering_id,event_seq DESC);
ALTER TABLE atlas.shared_course_learner_invitation_author_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_invitation_author_decisions FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.shared_course_learner_invitation_author_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;

CREATE TABLE atlas.shared_course_learner_invitation_offers(
 offer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 proposal_id uuid NOT NULL REFERENCES atlas.teaching_course_operating_standings(id) ON DELETE RESTRICT,
 course_version_id uuid NOT NULL REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 offered_to_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 offered_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 offer_request_id uuid NOT NULL,
 offered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(offering_id,offer_request_id),
 UNIQUE(offering_id,offered_to_person_entity_id)
);
CREATE INDEX shared_learner_offers_by_target_v1
 ON atlas.shared_course_learner_invitation_offers(offered_to_person_entity_id,offer_id);
ALTER TABLE atlas.shared_course_learner_invitation_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_invitation_offers FROM PUBLIC,anon,authenticated;

-- Only the named learner may record accepted/declined once; immutable event.
CREATE TABLE atlas.shared_course_learner_invitation_responses(
 response_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 offer_id uuid NOT NULL UNIQUE REFERENCES atlas.shared_course_learner_invitation_offers(offer_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 responded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN ('accept','decline')),
 responded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE atlas.shared_course_learner_invitation_responses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_invitation_responses FROM PUBLIC,anon,authenticated;

-- Current governor can withdraw even an already-accepted appointment; a
-- withdrawal never erases the learner's historical consent.
CREATE TABLE atlas.shared_course_learner_invitation_withdrawals(
 offer_id uuid PRIMARY KEY REFERENCES atlas.shared_course_learner_invitation_offers(offer_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 withdrawn_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 withdrawn_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE atlas.shared_course_learner_invitation_withdrawals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_learner_invitation_withdrawals FROM PUBLIC,anon,authenticated;

-- Durable historical receipts cannot be reparented, modified or deleted by
-- any application writer. Deliberately no direct client grants.
CREATE FUNCTION atlas.reject_shared_learner_receipt_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'shared Course learner consent/offer receipts are immutable'
  USING ERRCODE='55000';
END $immutable$;
CREATE TRIGGER shared_learner_author_decision_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_invitation_author_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_learner_receipt_mutation_v1();
CREATE TRIGGER shared_learner_offer_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_invitation_offers
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_learner_receipt_mutation_v1();
CREATE TRIGGER shared_learner_response_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_invitation_responses
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_learner_receipt_mutation_v1();
CREATE TRIGGER shared_learner_withdrawal_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_learner_invitation_withdrawals
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_learner_receipt_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_shared_learner_receipt_mutation_v1()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_learner_invitation_decide_self_api_v1(
 p_offering_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $author$
DECLARE
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_old atlas.shared_course_learner_invitation_author_decisions%ROWTYPE;
 v_event bigint;
BEGIN
 IF p_offering_id IS NULL OR p_request_id IS NULL OR p_decision IS NULL
 OR p_decision NOT IN ('allow_learner_invitation','withhold_learner_invitation') THEN
  RAISE EXCEPTION 'exact author learner-invitation decision required' USING ERRCODE='22023';
 END IF;
 SELECT s.* INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 JOIN atlas.teaching_course_offerings o ON o.operating_proposal_id=s.id
 WHERE o.id=p_offering_id FOR UPDATE OF s;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'exact original Course relationship required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings WHERE id=p_offering_id FOR SHARE;
 PERFORM atlas.require_private_course_author_self_v1(
   v_standing.course_id,p_decision='allow_learner_invitation');
 v_person:=atlas.current_person_for_private_course_v1();
 IF v_offering.course_id IS DISTINCT FROM v_standing.course_id
 OR v_offering.ledger_id IS DISTINCT FROM v_standing.ledger_id
 OR v_standing.proposal_state<>'proposed'
 OR v_standing.operator_acceptance_state<>'accepted'
 OR v_offering.state<>'open' THEN
  RAISE EXCEPTION 'accepted exact open Course Offering required' USING ERRCODE='42501';
 END IF;
 IF p_decision='allow_learner_invitation'
 AND NOT atlas.shared_course_open_source_current_v1(p_offering_id) THEN
  RAISE EXCEPTION 'all original Course author and Teaching conditions required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_old
 FROM atlas.shared_course_learner_invitation_author_decisions
 WHERE offering_id=p_offering_id AND request_id=p_request_id;
 IF v_old.event_seq IS NOT NULL THEN
  IF v_old.decided_by_person_entity_id IS DISTINCT FROM v_person
   OR v_old.decision IS DISTINCT FROM p_decision THEN
   RAISE EXCEPTION 'changed immutable learner invitation decision' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_invitation_author_v1',
   'offeringId',p_offering_id,'decision',p_decision,
   'alreadyExists',true,'canParticipate',false,'canEnroll',false,'enrollmentState','not_enrolled');
 END IF;
 INSERT INTO atlas.shared_course_learner_invitation_author_decisions(
   offering_id,request_id,decision,decided_by_person_entity_id)
 VALUES(p_offering_id,p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_event;
 RETURN jsonb_build_object('contractVersion','shared_learner_invitation_author_v1',
   'offeringId',p_offering_id,'decision',p_decision,
   'eventSequence',v_event,'alreadyExists',false,'canParticipate',false,'canEnroll',false,'enrollmentState','not_enrolled');
END $author$;

-- Governor chooses ONE known canonical Person UUID. No roster/discovery,
-- names, email, teaching permissions or automatic invite acceptance.
CREATE FUNCTION public.shared_teaching_learner_offer_self_api_v1(
 p_offering_id uuid,p_learner_person_entity_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $issuer$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_governor uuid;
 v_old atlas.shared_course_learner_invitation_offers%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_offering_id IS NULL OR p_learner_person_entity_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact Offering, named learner and request required' USING ERRCODE='22023';
 END IF;
 SELECT s.* INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 JOIN atlas.teaching_course_offerings o ON o.operating_proposal_id=s.id
 WHERE o.id=p_offering_id FOR UPDATE OF s;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'authorized original shared Offering required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_offering
 FROM atlas.teaching_course_offerings WHERE id=p_offering_id FOR SHARE;
 v_governor:=atlas.require_shared_course_native_ledger_governor_self_v1(v_standing.ledger_id);
 IF v_offering.ledger_id IS DISTINCT FROM v_standing.ledger_id
 OR v_offering.course_id IS DISTINCT FROM v_standing.course_id
 OR NOT atlas.shared_course_open_source_current_v1(p_offering_id)
 OR (SELECT d.decision
     FROM atlas.shared_course_learner_invitation_author_decisions d
     WHERE d.offering_id=p_offering_id ORDER BY d.event_seq DESC LIMIT 1
    ) IS DISTINCT FROM 'allow_learner_invitation'
 OR NOT EXISTS (SELECT 1 FROM reality.entities e
   WHERE e.id=p_learner_person_entity_id
    AND e.entity_kind='person' AND e.identity_state='canonical') THEN
  RAISE EXCEPTION 'source-authorized learner invitation unavailable'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_old FROM atlas.shared_course_learner_invitation_offers o
 WHERE o.offering_id=p_offering_id AND o.offer_request_id=p_request_id;
 IF v_old.offer_id IS NOT NULL THEN
  IF v_old.offered_by_person_entity_id IS DISTINCT FROM v_governor
   OR v_old.offered_to_person_entity_id IS DISTINCT FROM p_learner_person_entity_id
   OR v_old.proposal_id IS DISTINCT FROM v_standing.id
   OR v_old.course_version_id IS DISTINCT FROM v_offering.course_version_id THEN
   RAISE EXCEPTION 'changed learner invitation request' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_offer_v1',
   'offerId',v_old.offer_id,'offeringId',p_offering_id,
   'alreadyExists',true,'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_offers o
   WHERE o.offering_id=p_offering_id AND o.offered_to_person_entity_id=p_learner_person_entity_id) THEN
  RAISE EXCEPTION 'one immutable learner offer per Person and Offering'
   USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.shared_course_learner_invitation_offers(
   offering_id,proposal_id,course_version_id,ledger_id,offered_to_person_entity_id,
   offered_by_person_entity_id,offer_request_id)
 VALUES (p_offering_id,v_standing.id,v_offering.course_version_id,v_standing.ledger_id,
   p_learner_person_entity_id,v_governor,p_request_id)
 RETURNING offer_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','shared_learner_offer_v1',
   'offerId',v_id,'offeringId',p_offering_id,
   'alreadyExists',false,'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
END $issuer$;

-- Learner may inspect ONLY their known exact invitation. Title comes from
-- the author's immutable Version and is disclosed only while the author's
-- fifth permission remains current. No curriculum, other learners or roster.
CREATE FUNCTION public.shared_teaching_learner_offer_read_self_api_v1(
 p_offer_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $own_offer$
DECLARE
 v_offer atlas.shared_course_learner_invitation_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_decision text;
BEGIN
 IF p_offer_id IS NULL THEN
  RAISE EXCEPTION 'known personal learner invitation required' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_offer FROM atlas.shared_course_learner_invitation_offers
 WHERE offer_id=p_offer_id AND offered_to_person_entity_id=v_person;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'known personal learner invitation required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR SHARE;
 IF v_standing.id IS NULL OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR NOT atlas.shared_course_open_source_current_v1(v_offer.offering_id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
     WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_invitation'
 OR EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
     WHERE w.offer_id=v_offer.offer_id) THEN
  RAISE EXCEPTION 'learner invitation is not currently available'
   USING ERRCODE='42501';
 END IF;
 SELECT r.decision INTO v_decision FROM atlas.shared_course_learner_invitation_responses r
 WHERE r.offer_id=v_offer.offer_id;
 RETURN jsonb_build_object('contractVersion','shared_learner_offer_read_v1',
  'offerId',v_offer.offer_id,'offeringId',v_offer.offering_id,
  'courseVersionId',v_offer.course_version_id,'ledgerId',v_offer.ledger_id,
  'courseTitle',(SELECT v.title FROM atlas.teaching_course_versions v
                 WHERE v.id=v_offer.course_version_id),
  'deliveryMode',(SELECT o.delivery_mode FROM atlas.teaching_course_offerings o
                  WHERE o.id=v_offer.offering_id),
  'startsAt',(SELECT o.starts_at FROM atlas.teaching_course_offerings o
              WHERE o.id=v_offer.offering_id),
  'endsAt',(SELECT o.ends_at FROM atlas.teaching_course_offerings o
            WHERE o.id=v_offer.offering_id),
  'state',coalesce(v_decision,'offered'),
  'consentAccepted',coalesce(v_decision='accept',false),
  'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
END $own_offer$;

-- A signed current actual invitee accepts or declines. No independent
-- institution or author may accept on their behalf. Terminal once decided.
CREATE FUNCTION public.shared_teaching_learner_respond_self_api_v1(
 p_offer_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $learner_response$
DECLARE
 v_offer atlas.shared_course_learner_invitation_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_previous atlas.shared_course_learner_invitation_responses%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL OR p_decision IS NULL
 OR p_decision NOT IN ('accept','decline') THEN
  RAISE EXCEPTION 'explicit learner accept/decline choice required'
   USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT o.* INTO v_offer FROM atlas.shared_course_learner_invitation_offers o
 WHERE o.offer_id=p_offer_id AND o.offered_to_person_entity_id=v_person;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'known personal learner invitation required' USING ERRCODE='42501';
 END IF;
 -- Serialize with current author withdrawal and governor's offer/withdraw.
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR UPDATE;
 IF v_standing.id IS NULL OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR NOT atlas.shared_course_open_source_current_v1(v_offer.offering_id)
 OR (SELECT d.decision FROM atlas.shared_course_learner_invitation_author_decisions d
     WHERE d.offering_id=v_offer.offering_id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_learner_invitation'
 OR EXISTS(SELECT 1 FROM atlas.shared_course_learner_invitation_withdrawals w
     WHERE w.offer_id=v_offer.offer_id) THEN
  RAISE EXCEPTION 'learner invitation is not currently available'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_previous FROM atlas.shared_course_learner_invitation_responses
 WHERE offer_id=v_offer.offer_id;
 IF v_previous.response_id IS NOT NULL THEN
  IF v_previous.request_id IS DISTINCT FROM p_request_id
  OR v_previous.decision IS DISTINCT FROM p_decision
  OR v_previous.responded_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'learner response is terminal and immutable' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_response_v1',
    'offerId',v_offer.offer_id,'decision',p_decision,'alreadyExists',true,
    'consentAccepted',p_decision='accept',
    'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
 END IF;
 INSERT INTO atlas.shared_course_learner_invitation_responses(
   offer_id,request_id,responded_by_person_entity_id,decision)
 VALUES (p_offer_id,p_request_id,v_person,p_decision)
 RETURNING response_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','shared_learner_response_v1',
   'offerId',v_offer.offer_id,'decision',p_decision,'alreadyExists',false,
   'consentAccepted',p_decision='accept',
   'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
END $learner_response$;

CREATE FUNCTION public.shared_teaching_learner_withdraw_self_api_v1(
 p_offer_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $withdraw$
DECLARE
 v_offer atlas.shared_course_learner_invitation_offers%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_governor uuid;
 v_prior atlas.shared_course_learner_invitation_withdrawals%ROWTYPE;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact governor learner withdrawal required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_offer FROM atlas.shared_course_learner_invitation_offers
 WHERE offer_id=p_offer_id;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'known learner offer required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=v_offer.proposal_id FOR UPDATE;
 v_governor:=atlas.require_shared_course_native_ledger_governor_self_v1(v_offer.ledger_id);
 IF v_standing.id IS NULL OR v_standing.ledger_id IS DISTINCT FROM v_offer.ledger_id
 OR v_standing.course_id IS DISTINCT FROM (
     SELECT o.course_id FROM atlas.teaching_course_offerings o WHERE o.id=v_offer.offering_id)
 THEN
  RAISE EXCEPTION 'same Course operating Ledger required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.shared_course_learner_invitation_withdrawals w
 WHERE w.offer_id=p_offer_id;
 IF v_prior.offer_id IS NOT NULL THEN
  IF v_prior.request_id IS DISTINCT FROM p_request_id
   OR v_prior.withdrawn_by_person_entity_id IS DISTINCT FROM v_governor THEN
   RAISE EXCEPTION 'changed immutable learner withdrawal' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_learner_withdraw_v1',
    'offerId',p_offer_id,'alreadyExists',true,'consentAccepted',false,
    'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
 END IF;
 INSERT INTO atlas.shared_course_learner_invitation_withdrawals(
   offer_id,request_id,withdrawn_by_person_entity_id)
 VALUES(p_offer_id,p_request_id,v_governor);
 RETURN jsonb_build_object('contractVersion','shared_learner_withdraw_v1',
   'offerId',p_offer_id,'alreadyExists',false,'consentAccepted',false,
   'canParticipate',false,'canReadCurriculum',false,'canEnroll',false,'enrollmentState','not_enrolled');
END $withdraw$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_learner_invitation_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_offer_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_learner_offer_read_self_api_v1(uuid),
 public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_withdraw_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_learner_invitation_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_offer_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_learner_offer_read_self_api_v1(uuid),
 public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_learner_withdraw_self_api_v1(uuid,uuid)
 TO authenticated;
-- No roster, assignment, original Enrollment row, curriculum read,
-- accepted classroom seat or learner operation is issued by these receipts.
