-- HELD M3.8: first source-authorized institutional Course information operation.
-- Author can explicitly ALLOW or WITHHOLD only the Course title for ONE
-- author-proposed and institution-accepted existing Course/Ledger relation.
-- Every read rechecks live author proposal, accepted governor receipt, actual
-- source-governed root and live Teaching entitlement+activation. No Unit,
-- manuscript, Lesson text, unpublished research, Version or Offering access.
-- Clone-only; not a production migration. No additional Course identity.
DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'clone-only institutional Course title disclosure source'
   USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('public.shared_teaching_course_operating_accept_self_api_v1(uuid,uuid,uuid)')
    IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)')
    IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)')
    IS NULL
 OR to_regprocedure('atlas.teaching_activation_active_v1(uuid,uuid)')
    IS NULL
 OR to_regprocedure('atlas.capability_entitlement_grant_live_v1(uuid,text,integer)')
    IS NULL THEN
  RAISE EXCEPTION 'held author/operator/Teaching authorization prereqs missing'
   USING ERRCODE='23514';
 END IF;
END
$guard$;

-- Never overwrite an author decision. Revocation is a newer, immutable
-- source event. Sequence is the source order, not application timestamps.
CREATE TABLE atlas.teaching_course_operating_title_disclosure_events (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 proposal_id uuid NOT NULL
   REFERENCES atlas.teaching_course_operating_standings(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decided_by_person_entity_id uuid NOT NULL
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN ('allow_title','withhold_title')),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(proposal_id,request_id)
);
CREATE INDEX teaching_course_title_disclosure_position_v1
 ON atlas.teaching_course_operating_title_disclosure_events
 (proposal_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_operating_title_disclosure_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_operating_title_disclosure_events
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE
 atlas.teaching_course_operating_title_disclosure_events_event_seq_seq
 FROM PUBLIC,anon,authenticated;

-- Author's explicit scope decision; no inferred permission from a proposal.
CREATE FUNCTION public.shared_teaching_course_operating_title_decide_self_api_v1(
 p_proposal_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $title_decide$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_previous atlas.teaching_course_operating_title_disclosure_events%ROWTYPE;
 v_event bigint;
BEGIN
 IF p_proposal_id IS NULL OR p_request_id IS NULL OR
 p_decision IS NULL OR p_decision NOT IN ('allow_title','withhold_title') THEN
  RAISE EXCEPTION 'valid exact Course disclosure decision required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 WHERE s.id=p_proposal_id FOR UPDATE;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'Course disclosure decision unavailable'
   USING ERRCODE='42501';
 END IF;
 -- Own original Course is essential; proposal authorship is not inferred
 -- from a submitted UUID or the existence of a Proposal.
 PERFORM atlas.require_private_course_author_self_v1(
   v_standing.course_id,p_decision='allow_title');
 v_person:=atlas.current_person_for_private_course_v1();

 IF p_decision='allow_title' AND v_standing.proposal_state<>'proposed' THEN
  RAISE EXCEPTION 'withdrawn proposal cannot be disclosed'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_previous FROM
  atlas.teaching_course_operating_title_disclosure_events d
 WHERE d.proposal_id=v_standing.id AND d.request_id=p_request_id;
 IF v_previous.event_seq IS NOT NULL THEN
  IF v_previous.decision IS DISTINCT FROM p_decision OR
     v_previous.decided_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'changed Course disclosure request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_title_disclosure_decision_v1',
   'proposalId',v_standing.id,'decision',p_decision,
   'eventSequence',v_previous.event_seq,'alreadyExists',true);
 END IF;

 INSERT INTO atlas.teaching_course_operating_title_disclosure_events(
  proposal_id,request_id,decided_by_person_entity_id,decision)
 VALUES(v_standing.id,p_request_id,v_person,p_decision)
 RETURNING event_seq INTO v_event;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_title_disclosure_decision_v1',
  'proposalId',v_standing.id,'decision',p_decision,
  'eventSequence',v_event,'alreadyExists',false);
END
$title_decide$;

-- First executable institutional operation: read ONLY the explicitly
-- disclosed Course identity/title, never its private manuscript or Units.
-- This is NOT permission to operate the Course curriculum.
CREATE FUNCTION public.shared_teaching_course_operating_title_read_self_api_v1(
 p_proposal_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $title_read$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_title text;
 v_decision text;
BEGIN
 IF p_proposal_id IS NULL THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;

 -- Lock the proposal against simultaneous author withdrawal/consent writes.
 SELECT * INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 WHERE s.id=p_proposal_id FOR SHARE;
 IF v_standing.id IS NULL OR v_standing.proposal_state<>'proposed'
 OR v_standing.operator_acceptance_state<>'accepted'
 OR v_standing.teaching_activation_id IS NULL THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;

 IF NOT EXISTS(
  SELECT 1 FROM atlas.teaching_courses c
   WHERE c.id=v_standing.course_id
   AND c.status='active' AND c.retired_at IS NULL
 ) THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;

 -- Independently recheck current signed governor, current institution,
 -- source-issued Teaching entitlement AND exact original activation.
 PERFORM atlas.require_shared_course_native_ledger_governor_self_v1(v_standing.ledger_id);
 IF NOT atlas.capability_entitlement_grant_live_v1(
   v_standing.ledger_id,'teaching',1)
 OR NOT atlas.teaching_activation_active_v1(
   v_standing.ledger_id,v_standing.teaching_activation_id) THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;

 SELECT d.decision INTO v_decision
 FROM atlas.teaching_course_operating_title_disclosure_events d
 WHERE d.proposal_id=v_standing.id
 ORDER BY d.event_seq DESC LIMIT 1;
 IF v_decision IS DISTINCT FROM 'allow_title' THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;
 SELECT c.name INTO v_title FROM atlas.teaching_courses c
 WHERE c.id=v_standing.course_id
  AND c.status='active' AND c.retired_at IS NULL;
 IF v_title IS NULL THEN
  RAISE EXCEPTION 'Course title not available' USING ERRCODE='42501';
 END IF;

 RETURN jsonb_build_object(
  'contractVersion','shared_course_operating_title_read_v1',
  'courseId',v_standing.course_id,'ledgerId',v_standing.ledger_id,
  'title',v_title,'scope','course_title_only',
  'canReadMaterials',false,'canPublishVersion',false,
  'canCreateOffering',false,'canEnroll',false);
END
$title_read$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_operating_title_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_operating_title_read_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_operating_title_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_operating_title_read_self_api_v1(uuid)
 TO authenticated;

-- No general Course visibility/index, no institution curriculum edit writer,
-- no Version or Offering API, no sharing to other governors by membership.
