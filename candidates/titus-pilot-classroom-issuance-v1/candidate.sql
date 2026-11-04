-- Noel/Titus Build 1F — source-issued sample classroom participation candidate.
-- NOT applied to production. Stacked after Build 1E source read/append.
-- Root permission comes from Atlas principal-to-Ledger authority, not from
-- a user-supplied role, an offering's creator, a teacher switch or a UUID.
-- Learner enrollment alone does not consent to disclosure of responses.
BEGIN;

-- Source-binding ensures the fixture classroom relates to exactly one actual
-- Atlas Teaching Offering. A principal may not make an arbitrary classroom.
CREATE TABLE titus.classroom_pilot_offering_link_v1 (
  thread_id uuid PRIMARY KEY
    REFERENCES titus.classroom_threads_v1(thread_id) ON DELETE RESTRICT,
  offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id)
    ON DELETE RESTRICT,
  ledger_id uuid NOT NULL,
  issuing_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  issuing_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
    ON DELETE RESTRICT,
  linked_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX classroom_pilot_offering_link_once_v1
  ON titus.classroom_pilot_offering_link_v1(offering_id,thread_id);

-- Each event is a new immutable source original. State cannot be reconstructed
-- from an editable checkbox or membership row alone.
CREATE TABLE titus.classroom_pilot_assignment_events_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES titus.classroom_threads_v1(thread_id)
    ON DELETE RESTRICT,
  participant_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
    ON DELETE RESTRICT,
  actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
    ON DELETE RESTRICT,
  role text NOT NULL CHECK(role IN ('learner','teacher')),
  assignment_receipt_id uuid NOT NULL,
  event_kind text NOT NULL
    CHECK(event_kind IN ('offered','accepted','withdrawn','revoked')),
  named_reviewer_person_entity_id uuid
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT assignment_accept_consent_shape_v1 CHECK(
    (event_kind='accepted' AND
      ((role='learner' AND named_reviewer_person_entity_id IS NOT NULL)
       OR (role='teacher' AND named_reviewer_person_entity_id IS NULL)))
    OR (event_kind<>'accepted' AND named_reviewer_person_entity_id IS NULL)
  ),
  UNIQUE(assignment_receipt_id,event_kind),
  UNIQUE(thread_id,participant_person_entity_id,assignment_receipt_id,event_kind)
);
CREATE INDEX classroom_pilot_assignment_latest_v1
  ON titus.classroom_pilot_assignment_events_v1(
    thread_id,participant_person_entity_id,id DESC);

CREATE FUNCTION titus.classroom_pilot_issuer_event_immutable_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog
AS $guard$
BEGIN
  RAISE EXCEPTION 'classroom assignment originals are append-only';
END;$guard$;
CREATE TRIGGER classroom_pilot_immutable_offering_v1
  BEFORE UPDATE OR DELETE ON titus.classroom_pilot_offering_link_v1
  FOR EACH ROW EXECUTE FUNCTION titus.classroom_pilot_issuer_event_immutable_v1();
CREATE TRIGGER classroom_pilot_immutable_assignment_v1
  BEFORE UPDATE OR DELETE ON titus.classroom_pilot_assignment_events_v1
  FOR EACH ROW EXECUTE FUNCTION titus.classroom_pilot_issuer_event_immutable_v1();

ALTER TABLE titus.classroom_pilot_offering_link_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.classroom_pilot_assignment_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.classroom_pilot_offering_link_v1,
  titus.classroom_pilot_assignment_events_v1 FROM PUBLIC;
REVOKE ALL ON SEQUENCE titus.classroom_pilot_assignment_events_v1_id_seq FROM PUBLIC;
DO $revoke$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  REVOKE ALL ON TABLE titus.classroom_pilot_offering_link_v1,
    titus.classroom_pilot_assignment_events_v1 FROM anon;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  REVOKE ALL ON TABLE titus.classroom_pilot_offering_link_v1,
    titus.classroom_pilot_assignment_events_v1 FROM authenticated;
 END IF;
END;$revoke$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_issuer_event_immutable_v1()
 FROM PUBLIC;

-- Offer actor must be the signed current canonical Person, and that Person
-- must be the currently active root principal for this exact Ledger.
CREATE FUNCTION titus.classroom_pilot_source_governor_v1(
  p_ledger_id uuid
) RETURNS TABLE(person_id uuid,principal_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,atlas,titus,auth
AS $governor$
DECLARE v_actor uuid;v_user uuid;v_principal uuid;
BEGIN
 BEGIN
   v_user:=atlas.existing_person_claim_signed_actor_v1();
   v_actor:=titus.current_authenticated_person_entity_id_v1();
   v_principal:=atlas.current_principal_id_v1();
 EXCEPTION WHEN OTHERS THEN RETURN; END;
 IF v_user IS NULL OR v_actor IS NULL OR v_principal IS NULL THEN RETURN; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.principals p
   WHERE p.id=v_principal AND p.person_id=v_actor AND p.status='active')
   OR NOT atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id)
 THEN RETURN; END IF;
 person_id:=v_actor;principal_id:=v_principal;RETURN NEXT;
END;$governor$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_source_governor_v1(uuid)
 FROM PUBLIC;

-- Only source-original offering + current governing root + explicit teacher
-- acceptance and learner's named-teacher consent constitute current issue.
-- This replaces Build 1C's hard-false *candidate* ONLY; the deployed source
-- remains hard false until an independently approved release.
CREATE OR REPLACE FUNCTION titus.classroom_pilot_assignment_issued_v1(
  p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,
  p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,atlas,titus,reality,auth
AS $issued$
DECLARE v_binding titus.classroom_pilot_offering_link_v1%ROWTYPE;
        v_current titus.classroom_pilot_assignment_events_v1%ROWTYPE;
        v_offer titus.classroom_pilot_assignment_events_v1%ROWTYPE;
        v_teacher uuid;
        v_teacher_accept titus.classroom_pilot_assignment_events_v1%ROWTYPE;
BEGIN
 IF p_thread_id IS NULL OR p_person_entity_id IS NULL OR
    p_assignment_receipt_id IS NULL OR
    p_actor_role NOT IN ('learner','teacher') OR p_actor_role IS NULL
 THEN RETURN false; END IF;

 SELECT * INTO v_binding FROM titus.classroom_pilot_offering_link_v1
 WHERE thread_id=p_thread_id;
 IF v_binding.thread_id IS NULL THEN RETURN false; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.teaching_course_offerings o
   JOIN atlas.teaching_courses c ON c.id=o.course_id
   WHERE o.id=v_binding.offering_id AND o.ledger_id=v_binding.ledger_id
      AND c.ledger_id=o.ledger_id AND c.status='active' AND o.state='open'
      AND atlas.teaching_activation_active_v1(c.ledger_id,c.capability_activation_id))
    OR NOT atlas.principal_has_ledger_authority_v1(
      v_binding.issuing_principal_id,v_binding.ledger_id)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.principals p
      WHERE p.id=v_binding.issuing_principal_id
      AND p.person_id=v_binding.issuing_person_entity_id
      AND p.status='active')
 THEN RETURN false; END IF;
 SELECT * INTO v_current
 FROM titus.classroom_pilot_assignment_events_v1 e
 WHERE e.thread_id=p_thread_id
   AND e.participant_person_entity_id=p_person_entity_id
 ORDER BY e.id DESC LIMIT 1;
 IF v_current.event_kind IS DISTINCT FROM 'accepted'
    OR v_current.assignment_receipt_id IS DISTINCT FROM p_assignment_receipt_id
    OR v_current.role IS DISTINCT FROM p_actor_role
    OR v_current.actor_person_entity_id IS DISTINCT FROM p_person_entity_id
 THEN RETURN false; END IF;
 SELECT * INTO v_offer
 FROM titus.classroom_pilot_assignment_events_v1 e
 WHERE e.thread_id=p_thread_id AND
   e.participant_person_entity_id=p_person_entity_id AND
   e.assignment_receipt_id=p_assignment_receipt_id AND
   e.event_kind='offered' AND e.role=p_actor_role
 LIMIT 1;
 IF v_offer.event_id IS NULL OR v_offer.id>=v_current.id
    OR v_offer.actor_person_entity_id IS DISTINCT FROM
        v_binding.issuing_person_entity_id
 THEN RETURN false; END IF;

 IF p_actor_role='learner' THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.teaching_enrollments e
     WHERE e.offering_id=v_binding.offering_id AND
       e.ledger_id=v_binding.ledger_id AND
       e.person_id=p_person_entity_id AND e.state='active'
       AND e.withdrawn_at IS NULL)
   THEN RETURN false; END IF;
   v_teacher:=v_current.named_reviewer_person_entity_id;
   -- A learner consents only to the specifically named teacher. A new
   -- instructor cannot simply inherit access to historic learner originals.
   SELECT * INTO v_teacher_accept
   FROM titus.classroom_pilot_assignment_events_v1 e
   WHERE e.thread_id=p_thread_id
     AND e.participant_person_entity_id=v_teacher
   ORDER BY e.id DESC LIMIT 1;
   IF v_teacher_accept.event_kind IS DISTINCT FROM 'accepted'
      OR v_teacher_accept.role IS DISTINCT FROM 'teacher'
      OR NOT EXISTS(
        SELECT 1 FROM titus.classroom_pilot_participation_v1 seat
        JOIN titus.classroom_pilot_assignment_events_v1 offer
          ON offer.thread_id=seat.thread_id
         AND offer.participant_person_entity_id=seat.person_entity_id
         AND offer.assignment_receipt_id=seat.assignment_receipt_id
         AND offer.event_kind='offered' AND offer.role='teacher'
        WHERE seat.thread_id=p_thread_id AND seat.actor_role='teacher'
        AND seat.person_entity_id=v_teacher
        AND seat.assignment_receipt_id=v_teacher_accept.assignment_receipt_id
        AND seat.assignment_state='active'
        AND offer.actor_person_entity_id=v_binding.issuing_person_entity_id
        AND offer.id<v_teacher_accept.id)
   THEN RETURN false; END IF;
 ELSE
   -- Teacher may read a room only while a learner currently consents to
   -- this exact teacher. This is a disclosure boundary, not an appointment
   -- or historical author designation.
   IF NOT EXISTS(
     SELECT 1 FROM titus.classroom_pilot_assignment_events_v1 e
       JOIN titus.classroom_pilot_assignment_events_v1 offer
         ON offer.thread_id=e.thread_id
        AND offer.participant_person_entity_id=e.participant_person_entity_id
        AND offer.assignment_receipt_id=e.assignment_receipt_id
        AND offer.event_kind='offered'
     JOIN atlas.teaching_enrollments enrollment
       ON enrollment.person_id=e.participant_person_entity_id
       AND enrollment.offering_id=v_binding.offering_id
       AND enrollment.ledger_id=v_binding.ledger_id
       AND enrollment.state='active' AND enrollment.withdrawn_at IS NULL
     WHERE e.thread_id=p_thread_id
       AND e.event_kind='accepted' AND e.role='learner'
       AND e.named_reviewer_person_entity_id=p_person_entity_id
       AND offer.actor_person_entity_id=v_binding.issuing_person_entity_id
       AND offer.id<e.id
       AND NOT EXISTS(
         SELECT 1 FROM titus.classroom_pilot_assignment_events_v1 newer
         WHERE newer.thread_id=e.thread_id
           AND newer.participant_person_entity_id=e.participant_person_entity_id
           AND newer.id>e.id
       ))
   THEN RETURN false; END IF;
 END IF;
 RETURN true;
END;$issued$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_assignment_issued_v1(
  uuid,uuid,text,uuid) FROM PUBLIC;

-- Principal issues one offer to one known recipient and named role.
-- The source won't create an institutional Offering or Enrollment implicitly.
CREATE FUNCTION titus.classroom_pilot_offer_self_v1(
  p_thread_id uuid,p_offering_id uuid,p_person_id uuid,p_role text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,atlas,reality,auth
AS $offer$
DECLARE v_thread titus.classroom_threads_v1%ROWTYPE;
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_governor record;v_link titus.classroom_pilot_offering_link_v1%ROWTYPE;
 v_person titus.classroom_pilot_participation_v1%ROWTYPE;
 v_receipt uuid;
BEGIN
 IF p_role NOT IN('learner','teacher') OR p_role IS NULL OR
    p_thread_id IS NULL OR p_offering_id IS NULL OR p_person_id IS NULL
 THEN RAISE EXCEPTION 'Invalid classroom offer' USING ERRCODE='22023'; END IF;

 SELECT * INTO v_thread FROM titus.classroom_threads_v1
   WHERE thread_id=p_thread_id AND source_kind='fixture' FOR UPDATE;
 IF v_thread.thread_id IS NULL THEN
   RAISE EXCEPTION 'Sample classroom unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings
 WHERE id=p_offering_id AND state='open';
 IF v_offering.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.teaching_courses c WHERE
   c.id=v_offering.course_id AND c.ledger_id=v_offering.ledger_id
   AND c.status='active' AND atlas.teaching_activation_active_v1(
       c.ledger_id,c.capability_activation_id)) THEN
   RAISE EXCEPTION 'Active Teaching Offering required' USING ERRCODE='42501'; END IF;

 SELECT * INTO v_governor FROM titus.classroom_pilot_source_governor_v1(
   v_offering.ledger_id);
 IF v_governor.person_id IS NULL THEN
   RAISE EXCEPTION 'Current Ledger governor required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM reality.entities e WHERE e.id=p_person_id
     AND e.entity_kind='person' AND e.identity_state='canonical')
 THEN RAISE EXCEPTION 'Canonical Person required' USING ERRCODE='22023'; END IF;
 IF p_role='learner' AND NOT EXISTS(
    SELECT 1 FROM atlas.teaching_enrollments e
    WHERE e.offering_id=p_offering_id AND e.ledger_id=v_offering.ledger_id
      AND e.person_id=p_person_id AND e.state='active'
      AND e.withdrawn_at IS NULL)
 THEN RAISE EXCEPTION 'Active learner enrollment required' USING ERRCODE='42501'; END IF;

 SELECT * INTO v_link FROM titus.classroom_pilot_offering_link_v1
   WHERE thread_id=p_thread_id;
 IF v_link.thread_id IS NULL THEN
   INSERT INTO titus.classroom_pilot_offering_link_v1(
     thread_id,offering_id,ledger_id,issuing_principal_id,
     issuing_person_entity_id)
   VALUES(p_thread_id,p_offering_id,v_offering.ledger_id,
          v_governor.principal_id,v_governor.person_id);
 ELSIF v_link.offering_id IS DISTINCT FROM p_offering_id OR
       v_link.ledger_id IS DISTINCT FROM v_offering.ledger_id OR
       v_link.issuing_principal_id IS DISTINCT FROM v_governor.principal_id
 THEN RAISE EXCEPTION 'Classroom is bound to a different source'
   USING ERRCODE='42501'; END IF;

 -- One fixed learner seat and one teacher seat. Never silently replace an
 -- invited participant or transfer their original response to a new teacher.
 IF EXISTS(
   SELECT 1 FROM titus.classroom_pilot_participation_v1 m
   WHERE m.thread_id=p_thread_id AND
     (m.person_entity_id=p_person_id OR m.actor_role=p_role))
 THEN RAISE EXCEPTION 'Existing classroom seat requires separate source action'
   USING ERRCODE='23505'; END IF;

 v_receipt:=gen_random_uuid();
 INSERT INTO titus.classroom_pilot_participation_v1(
  thread_id,person_entity_id,actor_role,assignment_state,
  assignment_receipt_id,issued_by_person_entity_id,effective_at)
 VALUES(p_thread_id,p_person_id,p_role,'pending',v_receipt,
        v_governor.person_id,clock_timestamp());
 INSERT INTO titus.classroom_pilot_assignment_events_v1(
   thread_id,participant_person_entity_id,actor_person_entity_id,
   role,assignment_receipt_id,event_kind)
 VALUES(p_thread_id,p_person_id,v_governor.person_id,p_role,
        v_receipt,'offered');
 RETURN jsonb_build_object('state','offered',
   'threadId',p_thread_id,'assignmentReceiptId',v_receipt,
   'role',p_role,'participantPersonId',p_person_id);
END;$offer$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_offer_self_v1(
  uuid,uuid,uuid,text) FROM PUBLIC;

-- The invitee's own verified active session must accept. Learner acceptance
-- additionally names the currently accepted teacher who may view responses.
CREATE FUNCTION titus.classroom_pilot_accept_self_v1(
  p_thread_id uuid,p_assignment_receipt_id uuid,
  p_named_reviewer_person_id uuid,p_explicit_acceptance boolean
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,atlas,reality,auth
AS $accept$
DECLARE v_person uuid;v_user uuid;
 v_member titus.classroom_pilot_participation_v1%ROWTYPE;
 v_teacher titus.classroom_pilot_participation_v1%ROWTYPE;
 v_offer titus.classroom_pilot_assignment_events_v1%ROWTYPE;
 v_link titus.classroom_pilot_offering_link_v1%ROWTYPE;
BEGIN
 IF p_explicit_acceptance IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Explicit acceptance required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_member FROM titus.classroom_pilot_participation_v1
   WHERE thread_id=p_thread_id
     AND assignment_receipt_id=p_assignment_receipt_id
   FOR UPDATE;
 IF v_member.person_entity_id IS NULL OR v_member.assignment_state<>'pending'
 THEN RAISE EXCEPTION 'No pending classroom offer' USING ERRCODE='42501'; END IF;
 v_user:=atlas.existing_person_claim_signed_actor_v1();
 v_person:=titus.current_authenticated_person_entity_id_v1();
 IF v_user IS NULL OR v_person IS DISTINCT FROM v_member.person_entity_id
 THEN RAISE EXCEPTION 'Offer belongs to another signed Person'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_offer FROM titus.classroom_pilot_assignment_events_v1
 WHERE thread_id=p_thread_id
   AND assignment_receipt_id=p_assignment_receipt_id
   AND participant_person_entity_id=v_person
   AND event_kind='offered';
 SELECT * INTO v_link FROM titus.classroom_pilot_offering_link_v1
   WHERE thread_id=p_thread_id;
 IF v_offer.event_id IS NULL OR v_link.thread_id IS NULL OR
    v_offer.actor_person_entity_id IS DISTINCT FROM
       v_link.issuing_person_entity_id OR
    NOT atlas.principal_has_ledger_authority_v1(
      v_link.issuing_principal_id,v_link.ledger_id)
 THEN RAISE EXCEPTION 'Offer is not currently source-issued'
   USING ERRCODE='42501'; END IF;

 IF v_member.actor_role='learner' THEN
   SELECT * INTO v_teacher FROM titus.classroom_pilot_participation_v1
   WHERE thread_id=p_thread_id AND actor_role='teacher'
     AND person_entity_id=p_named_reviewer_person_id AND
     assignment_state='active' FOR SHARE;
   IF v_teacher.person_entity_id IS NULL OR NOT EXISTS(
     SELECT 1 FROM titus.classroom_pilot_assignment_events_v1 e
     WHERE e.thread_id=p_thread_id AND
       e.participant_person_entity_id=p_named_reviewer_person_id AND
       e.assignment_receipt_id=v_teacher.assignment_receipt_id AND
       e.event_kind='accepted') THEN
      RAISE EXCEPTION 'Named teacher must accept appointment first'
        USING ERRCODE='42501'; END IF;
   IF NOT EXISTS(
     SELECT 1 FROM atlas.teaching_enrollments e
     WHERE e.offering_id=v_link.offering_id AND
       e.ledger_id=v_link.ledger_id AND e.person_id=v_person
       AND e.state='active' AND e.withdrawn_at IS NULL)
   THEN RAISE EXCEPTION 'Active learner enrollment required'
       USING ERRCODE='42501'; END IF;
 ELSIF p_named_reviewer_person_id IS NOT NULL THEN
    RAISE EXCEPTION 'Teacher acceptance may not designate a reviewer'
      USING ERRCODE='22023';
 END IF;

 UPDATE titus.classroom_pilot_participation_v1
 SET assignment_state='active',effective_at=clock_timestamp(),
     withdrawn_at=NULL WHERE thread_id=p_thread_id
     AND person_entity_id=v_person;
 INSERT INTO titus.classroom_pilot_assignment_events_v1(
   thread_id,participant_person_entity_id,actor_person_entity_id,
   role,assignment_receipt_id,event_kind,named_reviewer_person_entity_id)
 VALUES(p_thread_id,v_person,v_person,v_member.actor_role,
        p_assignment_receipt_id,'accepted',
        CASE WHEN v_member.actor_role='learner' THEN
          p_named_reviewer_person_id ELSE NULL END);
 RETURN jsonb_build_object('state','accepted',
   'threadId',p_thread_id,'assignmentReceiptId',p_assignment_receipt_id,
   'role',v_member.actor_role);
END;$accept$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_accept_self_v1(
 uuid,uuid,uuid,boolean) FROM PUBLIC;

-- A participant can stop access themselves. The original events remain
-- immutable; withdrawal shuts off new reads/writes.
CREATE FUNCTION titus.classroom_pilot_withdraw_self_v1(
  p_thread_id uuid,p_assignment_receipt_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,atlas,auth
AS $withdraw$
DECLARE v_user uuid;v_person uuid;
 v_member titus.classroom_pilot_participation_v1%ROWTYPE;
BEGIN
 v_user:=atlas.existing_person_claim_signed_actor_v1();
 v_person:=titus.current_authenticated_person_entity_id_v1();
 IF v_user IS NULL OR v_person IS NULL THEN
   RAISE EXCEPTION 'Current signed Person required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_member FROM titus.classroom_pilot_participation_v1
 WHERE thread_id=p_thread_id AND assignment_receipt_id=p_assignment_receipt_id
 AND person_entity_id=v_person FOR UPDATE;
 IF v_member.person_entity_id IS NULL OR v_member.assignment_state<>'active'
 THEN RAISE EXCEPTION 'No active classroom participation'
    USING ERRCODE='42501'; END IF;
 UPDATE titus.classroom_pilot_participation_v1 SET
   assignment_state='withdrawn',withdrawn_at=clock_timestamp()
 WHERE thread_id=p_thread_id AND person_entity_id=v_person;
 INSERT INTO titus.classroom_pilot_assignment_events_v1(
   thread_id,participant_person_entity_id,actor_person_entity_id,
   role,assignment_receipt_id,event_kind)
 VALUES(p_thread_id,v_person,v_person,v_member.actor_role,
        p_assignment_receipt_id,'withdrawn');
 RETURN jsonb_build_object('state','withdrawn','threadId',p_thread_id);
END;$withdraw$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_withdraw_self_v1(
  uuid,uuid) FROM PUBLIC;

-- Minimal authenticated narrow self API surfaces; no private table grants.
CREATE FUNCTION public.titus_classroom_pilot_offer_self_api_v1(
  p_thread_id uuid,p_offering_id uuid,p_person_id uuid,p_role text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,public AS $$
 SELECT titus.classroom_pilot_offer_self_v1(
  p_thread_id,p_offering_id,p_person_id,p_role)$$;
CREATE FUNCTION public.titus_classroom_pilot_accept_self_api_v1(
 p_thread_id uuid,p_assignment_receipt_id uuid,
 p_named_reviewer_person_id uuid,p_explicit_acceptance boolean
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,public AS $$
 SELECT titus.classroom_pilot_accept_self_v1(
  p_thread_id,p_assignment_receipt_id,p_named_reviewer_person_id,
  p_explicit_acceptance)$$;
CREATE FUNCTION public.titus_classroom_pilot_withdraw_self_api_v1(
 p_thread_id uuid,p_assignment_receipt_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,public AS $$
 SELECT titus.classroom_pilot_withdraw_self_v1(
  p_thread_id,p_assignment_receipt_id)$$;
REVOKE ALL ON FUNCTION public.titus_classroom_pilot_offer_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.titus_classroom_pilot_accept_self_api_v1(
 uuid,uuid,uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.titus_classroom_pilot_withdraw_self_api_v1(
 uuid,uuid) FROM PUBLIC;
DO $grants$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  GRANT EXECUTE ON FUNCTION public.titus_classroom_pilot_offer_self_api_v1(
     uuid,uuid,uuid,text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.titus_classroom_pilot_accept_self_api_v1(
     uuid,uuid,uuid,boolean) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.titus_classroom_pilot_withdraw_self_api_v1(
     uuid,uuid) TO authenticated;
 END IF;
END;$grants$;
COMMIT;
