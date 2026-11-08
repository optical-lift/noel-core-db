-- HELD M3.7: an institutional governor accepts a specific author proposal,
-- on the SAME canonical Course UUID. This stores mutual intent ONLY.
-- It does NOT create a Course, grant Course author/read rights, or activate
-- Teaching, Versions, Offerings, enrollment, student Work or disclosure.
DO $clone_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'clone-only institutional Course acceptance source'
   USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)')
   IS NULL
 OR to_regprocedure('atlas.teaching_activation_active_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.capability_entitlement_grant_live_v1(uuid,text,integer)')
   IS NULL THEN
  RAISE EXCEPTION 'current governor and Teaching entitlement issuer required'
   USING ERRCODE='23514';
 END IF;
END
$clone_guard$;

-- Separate immutable operator acceptance receipt from mutable author
-- proposal state. An author withdrawal invalidates any past acceptance,
-- while retaining the historical receipt for source adjudication.
ALTER TABLE atlas.teaching_course_operating_standings
 ADD COLUMN operator_acceptance_state text NOT NULL DEFAULT 'pending'
  CHECK (operator_acceptance_state IN ('pending','accepted')),
 ADD COLUMN operator_accepted_by_person_entity_id uuid
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN operator_accept_request_id uuid,
 ADD COLUMN operator_accepted_at timestamptz,
 ADD COLUMN teaching_activation_id uuid
  REFERENCES atlas.capability_activations(id) ON DELETE RESTRICT,
 ADD CONSTRAINT shared_course_operator_receipt_coherence CHECK (
  (operator_acceptance_state='pending' AND
   operator_accepted_by_person_entity_id IS NULL AND
   operator_accept_request_id IS NULL AND
   operator_accepted_at IS NULL AND teaching_activation_id IS NULL)
  OR
  (operator_acceptance_state='accepted' AND
   operator_accepted_by_person_entity_id IS NOT NULL AND
   operator_accept_request_id IS NOT NULL AND
   operator_accepted_at IS NOT NULL AND teaching_activation_id IS NOT NULL)
 );

CREATE FUNCTION public.shared_teaching_course_operating_accept_self_api_v1(
 p_proposal_id uuid,p_activation_id uuid,p_accept_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $accept$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_operator_person uuid;
BEGIN
 IF p_proposal_id IS NULL OR p_activation_id IS NULL
 OR p_accept_request_id IS NULL THEN
  RAISE EXCEPTION 'proposal, activation and idempotent acceptance request required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 WHERE s.id=p_proposal_id FOR UPDATE;
 -- Known-ID lookup does not grant discovery. Missing, withdrawn or
 -- retired Course proposals receive one indistinguishable denial.
 IF v_standing.id IS NULL OR v_standing.proposal_state<>'proposed'
 OR NOT EXISTS (SELECT 1 FROM atlas.teaching_courses c
   WHERE c.id=v_standing.course_id AND c.status='active'
   AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'current operating invitation unavailable'
   USING ERRCODE='42501';
 END IF;

 -- NO seat, title, browser Person, Principal-to-native guess, or job role
 -- substitutes for exact native Ledger identity and verified current root.
 v_operator_person:=
   atlas.require_shared_course_native_ledger_governor_self_v1(v_standing.ledger_id);

 -- Separate current Teaching capability is mandatory, and must be
 -- independently checked again at EACH future institution action.
 IF NOT atlas.capability_entitlement_grant_live_v1(
    v_standing.ledger_id,'teaching',1)
 OR NOT atlas.teaching_activation_active_v1(
    v_standing.ledger_id,p_activation_id) THEN
  RAISE EXCEPTION 'active exact-Ledger Teaching authority required'
   USING ERRCODE='42501';
 END IF;

 IF v_standing.operator_acceptance_state='accepted' THEN
  IF v_standing.operator_accept_request_id IS DISTINCT FROM p_accept_request_id
  OR v_standing.teaching_activation_id IS DISTINCT FROM p_activation_id
  OR v_standing.operator_accepted_by_person_entity_id IS DISTINCT FROM v_operator_person THEN
   RAISE EXCEPTION 'original institutional acceptance request changed'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_operating_acceptance_v1',
   'proposalId',v_standing.id,'state','accepted',
   'alreadyExists',true,'operatingAuthorityGranted',false);
 END IF;

 UPDATE atlas.teaching_course_operating_standings
 SET operator_acceptance_state='accepted',
     operator_accepted_by_person_entity_id=v_operator_person,
     operator_accept_request_id=p_accept_request_id,
     operator_accepted_at=clock_timestamp(),
     teaching_activation_id=p_activation_id
 WHERE id=v_standing.id;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_operating_acceptance_v1',
  'proposalId',v_standing.id,'state','accepted',
  'alreadyExists',false,'operatingAuthorityGranted',false);
END
$accept$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_operating_accept_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_operating_accept_self_api_v1(uuid,uuid,uuid)
 TO authenticated;

-- No institutional read/operate Course API is exposed by acceptance.
-- Source-issued entitlement, proposal state, owner author rights, current
-- governor, and active Teaching source MUST be rechecked at future use.
