-- HELD M3.17A — private author-to-learner Course study, no institution.
-- SOURCE CANDIDATE ONLY: network-isolated fictional PG17 / approved protected
-- clone. NEVER run on live Supabase, nor treat its availability as release.
-- One existing Person-origin Course; NO replacement Course, Ledger, Offering,
-- institutional Enrollment, Unit disclosure, classroom, homework, or Work.
-- Accepted offer is the Course-specific participation source, NOT a general
-- Reality Person-person relationship or automatic manuscript entitlement.
DO $private_study_gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regclass('atlas.teaching_courses') IS NULL
 OR NOT EXISTS(SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name='teaching_courses'
     AND column_name='created_by_person_entity_id')
 THEN
  RAISE EXCEPTION 'held Person-first Course clone prerequisites required'
    USING ERRCODE='42501';
 END IF;
END $private_study_gate$;

-- Source owns one exact invitation to one existing canonical Person.
-- Request receipts and actor/source identity are immutable; one current
-- invitation per Course/learner pair until a later governed renewal rule.
CREATE TABLE atlas.teaching_course_private_study_invitations (
 invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 invited_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 invited_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz,
 UNIQUE(course_id,learner_person_entity_id),
 UNIQUE(invited_by_person_entity_id,request_id),
 CHECK(learner_person_entity_id<>invited_by_person_entity_id),
 CHECK(expires_at IS NULL OR expires_at>invited_at)
);
CREATE TABLE atlas.teaching_course_private_study_responses (
 response_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE
  REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('accept','decline')),
 responded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 responded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(responded_by_person_entity_id,request_id)
);
CREATE TABLE atlas.teaching_course_private_study_terminations (
 termination_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE
  REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 terminated_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 termination_kind text NOT NULL CHECK(termination_kind IN ('author_withdrew','learner_withdrew')),
 terminated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(terminated_by_person_entity_id,request_id)
);
ALTER TABLE atlas.teaching_course_private_study_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_study_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_study_terminations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_invitations FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_private_study_responses FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_private_study_terminations FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_private_study_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $$
BEGIN
 RAISE EXCEPTION 'private Course study receipts are immutable'
  USING ERRCODE='55000';
END $$;
CREATE TRIGGER private_study_invitation_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_invitations
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_study_response_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_responses
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_study_termination_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_terminations
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_private_study_original_mutation_v1()
 FROM PUBLIC,anon,authenticated;

-- Internal predicate: an independently accepted, nonterminated relationship.
-- This is a necessary input to later exact sealed Unit disclosure, not
-- sufficient permission to read any instruction. No public EXECUTE grant.
CREATE FUNCTION atlas.private_course_study_current_v1(
 p_course_id uuid,p_learner_person_entity_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $$
 SELECT p_course_id IS NOT NULL AND p_learner_person_entity_id IS NOT NULL
 AND EXISTS(
  SELECT 1 FROM atlas.teaching_course_private_study_invitations i
  JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
  JOIN reality.entities learner ON learner.id=i.learner_person_entity_id
    AND learner.entity_kind='person' AND learner.identity_state='canonical'
  JOIN reality.entities author ON author.id=i.invited_by_person_entity_id
    AND author.entity_kind='person' AND author.identity_state='canonical'
  JOIN atlas.teaching_course_private_study_responses r
    ON r.invitation_id=i.invitation_id AND r.decision='accept'
    AND r.responded_by_person_entity_id=i.learner_person_entity_id
  WHERE i.course_id=p_course_id
    AND i.learner_person_entity_id=p_learner_person_entity_id
    AND i.invited_by_person_entity_id=c.created_by_person_entity_id
    AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
      WHERE t.invitation_id=i.invitation_id)
 )
$$;
REVOKE ALL ON FUNCTION atlas.private_course_study_current_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- Exact Course author only. Course lock serializes invite minting with
-- author's Course status and same-Course idempotent request checks.
CREATE FUNCTION public.shared_teaching_private_study_invite_self_api_v1(
 p_course_id uuid,p_learner_person_entity_id uuid,
 p_request_id uuid,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $invite$
DECLARE
 v_person uuid;v_existing atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_invitation uuid;
BEGIN
 IF p_course_id IS NULL OR p_learner_person_entity_id IS NULL
 OR p_request_id IS NULL OR
 (p_expires_at IS NOT NULL AND p_expires_at<=clock_timestamp()) THEN
  RAISE EXCEPTION 'valid exact private study invitation required' USING ERRCODE='22023';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_learner_person_entity_id=v_person OR NOT EXISTS (
  SELECT 1 FROM reality.entities e
   WHERE e.id=p_learner_person_entity_id AND e.entity_kind='person'
    AND e.identity_state='canonical'
 ) THEN
  RAISE EXCEPTION 'known distinct canonical learner Person required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_existing FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invited_by_person_entity_id=v_person AND i.request_id=p_request_id;
 IF v_existing.invitation_id IS NOT NULL THEN
  IF v_existing.course_id IS DISTINCT FROM p_course_id
   OR v_existing.learner_person_entity_id IS DISTINCT FROM p_learner_person_entity_id
   OR v_existing.expires_at IS DISTINCT FROM p_expires_at THEN
   RAISE EXCEPTION 'changed immutable private study invitation request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_v1',
   'invitationId',v_existing.invitation_id,'alreadyExists',true,
   'consentAccepted',false,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF EXISTS(
  SELECT 1 FROM atlas.teaching_course_private_study_invitations i
   WHERE i.course_id=p_course_id
     AND i.learner_person_entity_id=p_learner_person_entity_id
 ) THEN
  RAISE EXCEPTION 'this Course/learner already has a study invitation'
   USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.teaching_course_private_study_invitations(
  course_id,learner_person_entity_id,invited_by_person_entity_id,
  request_id,expires_at
 ) VALUES (p_course_id,p_learner_person_entity_id,v_person,p_request_id,p_expires_at)
 RETURNING invitation_id INTO v_invitation;
 RETURN jsonb_build_object('contractVersion','private_course_study_v1',
  'invitationId',v_invitation,'alreadyExists',false,
  'consentAccepted',false,'canReadMaterial',false,'canSubmitWork',false);
END $invite$;

-- Only the invitee can inspect this one invitation. Title is disclosed
-- only in this explicitly targeted consent prompt; NO Unit or author notes.
CREATE FUNCTION public.shared_teaching_private_study_offer_read_self_api_v1(
 p_invitation_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $read_offer$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_title text;v_decision text;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv
 FROM atlas.teaching_course_private_study_invitations i
 JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
  AND c.created_by_person_entity_id=i.invited_by_person_entity_id
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person;
 IF v_inv.invitation_id IS NULL OR
 EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
    WHERE t.invitation_id=v_inv.invitation_id) THEN
  RAISE EXCEPTION 'known current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 SELECT r.decision INTO v_decision
 FROM atlas.teaching_course_private_study_responses r
 WHERE r.invitation_id=v_inv.invitation_id;
 IF v_decision IS NULL AND v_inv.expires_at IS NOT NULL
 AND v_inv.expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'known current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 SELECT c.name INTO v_title FROM atlas.teaching_courses c
 WHERE c.id=v_inv.course_id;
 RETURN jsonb_build_object('contractVersion','private_course_study_offer_v1',
  'invitationId',v_inv.invitation_id,'courseTitle',v_title,
  'state',coalesce(v_decision,'offered'),
  'consentAccepted',coalesce(v_decision='accept',false),
  'canReadMaterial',false,'canSubmitWork',false);
END $read_offer$;

-- Exact learner signed Person; no author/parent/institution can accept
-- on their behalf. One terminal response, append-only and idempotent.
CREATE FUNCTION public.shared_teaching_private_study_respond_self_api_v1(
 p_invitation_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $respond$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_prev atlas.teaching_course_private_study_responses%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL
 OR p_decision IS NULL OR p_decision NOT IN ('accept','decline') THEN
  RAISE EXCEPTION 'exact signed study consent choice required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
   AND c.created_by_person_entity_id=i.invited_by_person_entity_id
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person
 FOR UPDATE OF i;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'known current private study invitation required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prev FROM atlas.teaching_course_private_study_responses r
 WHERE r.invitation_id=v_inv.invitation_id;
 IF v_prev.response_id IS NOT NULL THEN
  IF v_prev.request_id IS DISTINCT FROM p_request_id
  OR v_prev.decision IS DISTINCT FROM p_decision
  OR v_prev.responded_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'private study consent is immutable'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_respond_v1',
   'invitationId',p_invitation_id,'decision',p_decision,
   'alreadyExists',true,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
     WHERE t.invitation_id=v_inv.invitation_id)
 OR (v_inv.expires_at IS NOT NULL AND v_inv.expires_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'current private study invitation required'
  USING ERRCODE='42501'; END IF;
 INSERT INTO atlas.teaching_course_private_study_responses(
  invitation_id,request_id,decision,responded_by_person_entity_id
 ) VALUES(p_invitation_id,p_request_id,p_decision,v_person)
 RETURNING response_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','private_course_study_respond_v1',
  'invitationId',p_invitation_id,'decision',p_decision,
  'alreadyExists',false,'canReadMaterial',false,'canSubmitWork',false);
END $respond$;

-- Withdrawal by the EXACT author or invited learner. A withdrawal is a
-- terminal original; no relationship can be revived by restoring UI state.
CREATE FUNCTION public.shared_teaching_private_study_withdraw_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $withdraw$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_kind text;v_previous atlas.teaching_course_private_study_terminations%ROWTYPE;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact private study withdrawal required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv
 FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id FOR UPDATE;
 IF v_inv.invitation_id IS NULL OR v_person NOT IN(
   v_inv.learner_person_entity_id,v_inv.invited_by_person_entity_id
 ) THEN RAISE EXCEPTION 'known current private study invitation required'
   USING ERRCODE='42501'; END IF;
 IF v_person=v_inv.invited_by_person_entity_id THEN
  PERFORM atlas.require_private_course_author_self_v1(v_inv.course_id,true);
  v_kind:='author_withdrew';
 ELSE
  v_kind:='learner_withdrew';
 END IF;
 SELECT * INTO v_previous FROM atlas.teaching_course_private_study_terminations t
 WHERE t.invitation_id=v_inv.invitation_id;
 IF v_previous.termination_id IS NOT NULL THEN
  IF v_previous.request_id IS DISTINCT FROM p_request_id
  OR v_previous.terminated_by_person_entity_id IS DISTINCT FROM v_person
  OR v_previous.termination_kind IS DISTINCT FROM v_kind THEN
   RAISE EXCEPTION 'private study withdrawal is terminal'
    USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_withdraw_v1',
   'invitationId',p_invitation_id,'alreadyExists',true,
   'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 INSERT INTO atlas.teaching_course_private_study_terminations(
  invitation_id,request_id,terminated_by_person_entity_id,termination_kind
 ) VALUES(p_invitation_id,p_request_id,v_person,v_kind);
 RETURN jsonb_build_object('contractVersion','private_course_study_withdraw_v1',
  'invitationId',p_invitation_id,'alreadyExists',false,
  'canReadMaterial',false,'canSubmitWork',false);
END $withdraw$;

-- Privileged data is never exposed directly. Each public entry point
-- re-resolves a *current signed* Person and enforces the exact actor.
REVOKE ALL ON FUNCTION
 public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz),
 public.shared_teaching_private_study_offer_read_self_api_v1(uuid),
 public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz),
 public.shared_teaching_private_study_offer_read_self_api_v1(uuid),
 public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)
 TO authenticated;
-- No lesson/version disclosure API defined here, NO student enrollment or Work.
