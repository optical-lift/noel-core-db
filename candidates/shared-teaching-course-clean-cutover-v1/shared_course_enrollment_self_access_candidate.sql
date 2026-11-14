-- HELD M3.15C: exact own-person original Enrollment read and self-withdraw.
-- Additive source on the ONE atlas.teaching_enrollments carrier. No new
-- Course, Offering, Enrollment root, classroom, private text or Work.
-- Isolated PG17 source candidate ONLY; never direct apply on live.
DO $m315c_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('atlas.guard_shared_course_enrollment_pending_v1()') IS NULL
 OR to_regclass('atlas.teaching_enrollments') IS NULL
 OR to_regclass('atlas.shared_course_enrollment_issuances') IS NULL
 OR (SELECT count(*) FROM pg_trigger t WHERE t.tgrelid='atlas.teaching_enrollments'::regclass
   AND t.tgname='shared_course_enrollment_pending_v1' AND NOT t.tgisinternal)<>1
 THEN RAISE EXCEPTION 'source-issued original Enrollment and data-plane gate missing'
  USING ERRCODE='42501';
 END IF;
END $m315c_guard$;

-- No direct privilege to guess other Enrollment IDs. Only signed self RPC.
-- Receipt is non-editable, references the one original Enrollment row.
CREATE TABLE atlas.shared_course_enrollment_withdrawal_issuances(
 withdrawal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 enrollment_id uuid NOT NULL UNIQUE
   REFERENCES atlas.teaching_enrollments(id) ON DELETE RESTRICT,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 withdrawn_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 issuer_txid bigint NOT NULL,
 withdrawn_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK (person_entity_id=withdrawn_by_person_entity_id)
);
ALTER TABLE atlas.shared_course_enrollment_withdrawal_issuances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.shared_course_enrollment_withdrawal_issuances
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER shared_enrollment_withdrawal_immutable
 BEFORE UPDATE OR DELETE ON atlas.shared_course_enrollment_withdrawal_issuances
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_enrollment_receipt_change_v1();

-- The M3.15B shared INSERT gate remains intact. For UPDATE the SAME
-- table-level trigger accepts only a current SAME-TRANSACTION withdrawal
-- receipt from this exact original Enrollment and same canonical learner.
-- DELETE, reparenting, direct UPDATE, state reversal and arbitrary GUC fail.

CREATE OR REPLACE FUNCTION atlas.guard_shared_course_enrollment_pending_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $issued_enrollment_guard$
DECLARE
 v_offering_id uuid;
BEGIN
 v_offering_id:=CASE WHEN TG_OP='DELETE' THEN OLD.offering_id ELSE NEW.offering_id END;
 -- Prevent a shared original from being reparented to an old Offering
 -- even if some earlier institutional guard is later retired.
 IF TG_OP='UPDATE'
  AND OLD.offering_id IS DISTINCT FROM NEW.offering_id
  AND EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
   WHERE o.id=OLD.offering_id AND o.operating_proposal_id IS NOT NULL)
 THEN RAISE EXCEPTION 'shared Enrollment cannot be reparented outside its original'
  USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
  WHERE o.id=v_offering_id AND o.operating_proposal_id IS NOT NULL)
 THEN
  IF TG_OP='UPDATE' THEN
    IF OLD.offering_id IS DISTINCT FROM NEW.offering_id
     OR OLD.state<>'active' OR NEW.state<>'withdrawn'
     OR NEW.withdrawn_at IS NULL OR NEW.withdrawal_reason IS DISTINCT FROM OLD.withdrawal_reason
     OR (to_jsonb(NEW) - 'state' - 'withdrawn_at')
         IS DISTINCT FROM (to_jsonb(OLD) - 'state' - 'withdrawn_at')
     OR NOT EXISTS(
       SELECT 1 FROM atlas.shared_course_enrollment_withdrawal_issuances w
       JOIN atlas.shared_course_enrollment_issuances i
         ON i.enrollment_id=w.enrollment_id
       WHERE w.enrollment_id=OLD.id AND w.enrollment_id=NEW.id
        AND w.offering_id=OLD.offering_id
        AND w.person_entity_id=OLD.person_entity_id
        AND w.withdrawn_by_person_entity_id=OLD.person_entity_id
        AND i.person_entity_id=OLD.person_entity_id
        AND w.withdrawn_at=NEW.withdrawn_at
        AND w.issuer_txid=txid_current()
     )
    THEN RAISE EXCEPTION 'shared Enrollment withdrawal requires own exact source receipt'
      USING ERRCODE='42501'; END IF;
  ELSIF TG_OP<>'INSERT'
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


-- Own bounded original receipt only. No roster, title, summary, curriculum,
-- exercise, other Person metadata, or class seat. Read persists after a
-- Course permit is withdrawn because the learner owns this historical fact.
CREATE FUNCTION public.shared_teaching_learner_enrollment_read_self_api_v1(
 p_enrollment_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $self_read$
DECLARE
 v_person uuid;
 v_original atlas.teaching_enrollments%ROWTYPE;
BEGIN
 IF p_enrollment_id IS NULL THEN
  RAISE EXCEPTION 'known original Enrollment ID required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT e.* INTO v_original
 FROM atlas.teaching_enrollments e
 JOIN atlas.shared_course_enrollment_issuances i
  ON i.enrollment_id=e.id AND i.offering_id=e.offering_id
   AND i.person_entity_id=e.person_entity_id
 WHERE e.id=p_enrollment_id AND e.person_entity_id=v_person;
 IF v_original.id IS NULL THEN
  RAISE EXCEPTION 'private current Person Enrollment not found' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
   'contractVersion','shared_learner_enrollment_read_v1',
   'enrollmentId',v_original.id,'offeringId',v_original.offering_id,
   'learnerPersonEntityId',v_original.person_entity_id,
   'enrollmentState',v_original.state,
   'enrolledAt',v_original.enrolled_at,
   'withdrawnAt',v_original.withdrawn_at,
   'canParticipate',false,'canReadCurriculum',false,'canTeach',false);
END $self_read$;

-- An enrolled learner, not the school governor/author, controls withdrawal
-- from their own original Enrollment. No author invitation/title permission
-- is required to EXIT, even after Offering closes or a grant is revoked.
-- Independent request + one immutable receipt, never erase history.
CREATE FUNCTION public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
 p_enrollment_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $self_withdraw$
DECLARE
 v_person uuid;
 v_row atlas.teaching_enrollments%ROWTYPE;
 v_receipt atlas.shared_course_enrollment_withdrawal_issuances%ROWTYPE;
 v_at timestamptz;
BEGIN
 IF p_enrollment_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'known original Enrollment and exact withdrawal request required'
   USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT e.* INTO v_row
 FROM atlas.teaching_enrollments e
 JOIN atlas.shared_course_enrollment_issuances i
  ON i.enrollment_id=e.id AND i.offering_id=e.offering_id
    AND i.person_entity_id=e.person_entity_id
 WHERE e.id=p_enrollment_id AND e.person_entity_id=v_person
 FOR UPDATE OF e;
 IF v_row.id IS NULL THEN
  RAISE EXCEPTION 'cannot withdraw another Person or a legacy Enrollment'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_receipt
 FROM atlas.shared_course_enrollment_withdrawal_issuances
 WHERE enrollment_id=v_row.id;
 IF v_receipt.withdrawal_id IS NOT NULL THEN
  IF v_receipt.request_id IS DISTINCT FROM p_request_id
   OR v_receipt.withdrawn_by_person_entity_id IS DISTINCT FROM v_person
   OR v_receipt.withdrawn_at IS DISTINCT FROM v_row.withdrawn_at
   OR v_row.state<>'withdrawn'
  THEN RAISE EXCEPTION 'cannot replace a terminal Enrollment withdrawal request'
   USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_learner_enrollment_withdraw_v1',
   'enrollmentId',v_row.id,'offeringId',v_row.offering_id,
   'learnerPersonEntityId',v_person,'enrollmentState','withdrawn',
   'withdrawnAt',v_row.withdrawn_at,'alreadyExists',true,
   'canParticipate',false,'canReadCurriculum',false,'canTeach',false);
 END IF;
 IF v_row.state IS DISTINCT FROM 'active' OR v_row.withdrawn_at IS NOT NULL THEN
  RAISE EXCEPTION 'only an active original Enrollment can be self-withdrawn'
   USING ERRCODE='23514';
 END IF;
 v_at:=clock_timestamp();
 INSERT INTO atlas.shared_course_enrollment_withdrawal_issuances(
  enrollment_id,offering_id,person_entity_id,
  withdrawn_by_person_entity_id,request_id,issuer_txid,withdrawn_at)
 VALUES(v_row.id,v_row.offering_id,v_person,v_person,p_request_id,txid_current(),v_at);
 UPDATE atlas.teaching_enrollments
 SET state='withdrawn',withdrawn_at=v_at
 WHERE id=v_row.id AND state='active';
 IF NOT FOUND THEN
  RAISE EXCEPTION 'original Enrollment changed before authorized withdrawal'
   USING ERRCODE='23514';
 END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_learner_enrollment_withdraw_v1',
  'enrollmentId',v_row.id,'offeringId',v_row.offering_id,
  'learnerPersonEntityId',v_person,'enrollmentState','withdrawn',
  'withdrawnAt',v_at,'alreadyExists',false,
  'canParticipate',false,'canReadCurriculum',false,'canTeach',false);
END $self_withdraw$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_learner_enrollment_read_self_api_v1(uuid),
 public.shared_teaching_learner_enrollment_withdraw_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_learner_enrollment_read_self_api_v1(uuid),
 public.shared_teaching_learner_enrollment_withdraw_self_api_v1(uuid,uuid)
 TO authenticated;
-- No general Enrollment list or grants to table readers, teacher,
-- former institution root, author, or somebody holding a Course UUID.
