-- Titus B2B: one learner-authored, exact-response disclosure DECISION.
-- SOURCE-ONLY CANDIDATE. Not a grant, RPC, migration, or consent already given.
-- No historical learner-response authorship/immutability is yet proven.
-- A decision here can be evidence of a signed actor's declaration only;
-- it does NOT allow reviewer access or satisfy the closed B2B issuance gate.
BEGIN;

CREATE TABLE titus.formation_review_disclosure_decisions_v1 (
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  formation_response_id uuid NOT NULL
    REFERENCES titus.formation_responses(formation_response_id) ON DELETE RESTRICT,
  learner_person_entity_id uuid NOT NULL
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  reviewer_person_entity_id uuid NOT NULL
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  decision_kind text NOT NULL
    CHECK (decision_kind IN ('consent','withdraw')),
  prior_decision_id uuid
    REFERENCES titus.formation_review_disclosure_decisions_v1(decision_id) ON DELETE RESTRICT,
  sequence_no integer NOT NULL CHECK (sequence_no >= 1),
  issuer_auth_user_id uuid NOT NULL,
  issuer_auth_session_id uuid NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz,
  CHECK (learner_person_entity_id <> reviewer_person_entity_id),
  CHECK ((decision_kind='consent' AND expires_at IS NOT NULL) OR
         (decision_kind='withdraw' AND expires_at IS NULL)),
  UNIQUE (learner_person_entity_id,request_id),
  UNIQUE (formation_response_id,reviewer_person_entity_id,sequence_no)
);
COMMENT ON TABLE titus.formation_review_disclosure_decisions_v1 IS
 'Candidate signed-learner decision history for one response and one reviewer. '
 'Not reader authorization. Prior response authorship and immutable version '
 'still require independent provenance. No automatic linkage to B2B source refs.';

ALTER TABLE titus.formation_review_disclosure_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.formation_review_disclosure_decisions_v1 FROM PUBLIC;
DO $roles$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
   EXECUTE 'REVOKE ALL ON titus.formation_review_disclosure_decisions_v1 FROM anon';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
   EXECUTE 'REVOKE ALL ON titus.formation_review_disclosure_decisions_v1 FROM authenticated';
 END IF;
END;
$roles$;

-- Defence in depth for direct privileged inserts: the actor must be
-- the currently resolved signed Person. UPDATE/DELETE are always denied.
-- The response-row lock also serializes two decisions for one response.
CREATE OR REPLACE FUNCTION titus.formation_review_disclosure_decision_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO pg_catalog
AS $guard$
DECLARE
 v_response titus.formation_responses%ROWTYPE;
 v_unit titus.formation_units%ROWTYPE;
 v_previous titus.formation_review_disclosure_decisions_v1%ROWTYPE;
 v_session uuid;
BEGIN
 IF TG_OP <> 'INSERT' THEN
  RAISE EXCEPTION 'learner disclosure decisions are append-only';
 END IF;
 IF titus.current_authenticated_person_entity_id_v1()
       IS DISTINCT FROM NEW.learner_person_entity_id
    OR auth.uid() IS DISTINCT FROM NEW.issuer_auth_user_id THEN
  RAISE EXCEPTION 'no current source learner for disclosure decision';
 END IF;
 BEGIN
  v_session := nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN others THEN
  RAISE EXCEPTION 'no verified issuer session';
 END;
 IF v_session IS NULL OR v_session IS DISTINCT FROM NEW.issuer_auth_session_id THEN
  RAISE EXCEPTION 'issuer session does not match the current session';
 END IF;
 SELECT * INTO v_response FROM titus.formation_responses
 WHERE formation_response_id=NEW.formation_response_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'response not available'; END IF;
 SELECT * INTO v_unit FROM titus.formation_units
 WHERE formation_unit_id=v_response.formation_unit_id;
 IF NOT FOUND OR v_unit.teacher_id IS DISTINCT FROM v_response.teacher_id THEN
  RAISE EXCEPTION 'response and source unit mismatch';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM reality.entities e
   WHERE e.id=NEW.reviewer_person_entity_id
     AND e.entity_kind='person' AND e.identity_state='canonical'
 ) THEN RAISE EXCEPTION 'reviewer identity not canonical'; END IF;
 SELECT * INTO v_previous
 FROM titus.formation_review_disclosure_decisions_v1
 WHERE formation_response_id=NEW.formation_response_id
   AND reviewer_person_entity_id=NEW.reviewer_person_entity_id
 ORDER BY sequence_no DESC LIMIT 1;
 IF NOT FOUND THEN
  IF NEW.decision_kind<>'consent' OR NEW.sequence_no<>1
     OR NEW.prior_decision_id IS NOT NULL THEN
   RAISE EXCEPTION 'first disclosure decision must be explicit consent';
  END IF;
 ELSE
  IF NEW.learner_person_entity_id IS DISTINCT FROM v_previous.learner_person_entity_id
    OR NEW.prior_decision_id IS DISTINCT FROM v_previous.decision_id
    OR NEW.sequence_no<>v_previous.sequence_no+1
    OR NEW.decision_kind=v_previous.decision_kind THEN
   RAISE EXCEPTION 'conflicting or stale disclosure predecessor';
  END IF;
 END IF;
 IF NEW.decision_kind='consent' AND
    (v_response.response_status<>'submitted'
     OR v_unit.review_state<>'current'
     OR v_unit.formation_state NOT IN
      ('learner_ready','encountered','teachback_pending',
       'teachback_received','teachback_reviewed',
       'transfer_pending','transfer_reviewed','integrated')
     OR NOT EXISTS (
      SELECT 1 FROM titus.teacher_person_bindings b
      WHERE b.teacher_id=v_response.teacher_id
        AND b.person_entity_id=NEW.learner_person_entity_id
        AND b.binding_state='active' AND b.retired_at IS NULL
     )) THEN
    RAISE EXCEPTION 'source learner or unit not eligible to declare disclosure';
 END IF;
 -- Withdrawal remains possible after the Unit or binding is retired.
 NEW.issued_at := clock_timestamp();
 NEW.expires_at := CASE WHEN NEW.decision_kind='consent'
     THEN NEW.issued_at + interval '30 days' ELSE NULL END;
 RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION titus.formation_review_disclosure_decision_guard_v1() FROM PUBLIC;
CREATE TRIGGER formation_review_disclosure_decision_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON titus.formation_review_disclosure_decisions_v1
FOR EACH ROW EXECUTE FUNCTION titus.formation_review_disclosure_decision_guard_v1();

-- Internal, source-owned command; remains without browser EXECUTE grants.
-- It records only an actor's explicit intent, not effective reviewer access.
-- The existing signed-current-session resolver is the only actor source.
CREATE OR REPLACE FUNCTION titus.record_formation_review_disclosure_intent_self_v1(
 p_formation_response_id uuid,
 p_reviewer_person_entity_id uuid,
 p_decision_kind text,
 p_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO pg_catalog
AS $command$
DECLARE
 v_actor uuid := titus.current_authenticated_person_entity_id_v1();
 v_auth_user uuid := auth.uid();
 v_session uuid;
 v_response titus.formation_responses%ROWTYPE;
 v_unit titus.formation_units%ROWTYPE;
 v_existing titus.formation_review_disclosure_decisions_v1%ROWTYPE;
 v_previous titus.formation_review_disclosure_decisions_v1%ROWTYPE;
 v_decision_id uuid;
 v_seq integer;
 v_prior_id uuid;
BEGIN
 IF v_actor IS NULL OR v_auth_user IS NULL THEN
   RETURN jsonb_build_object('state','unauthorized');
 END IF;
 BEGIN
  v_session := nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('state','unauthorized');
 END;
 IF v_session IS NULL THEN RETURN jsonb_build_object('state','unauthorized'); END IF;
 IF p_request_id IS NULL OR p_formation_response_id IS NULL OR
    p_reviewer_person_entity_id IS NULL OR
    p_decision_kind IS NULL OR p_decision_kind NOT IN ('consent','withdraw') THEN
  RETURN jsonb_build_object('state','invalid_request');
 END IF;
 IF p_reviewer_person_entity_id=v_actor OR NOT EXISTS (
  SELECT 1 FROM reality.entities e
  WHERE e.id=p_reviewer_person_entity_id AND e.entity_kind='person'
    AND e.identity_state='canonical'
 ) THEN RETURN jsonb_build_object('state','not_available'); END IF;

 -- Root response serializes new decision writes and idempotent retries.
 SELECT * INTO v_response FROM titus.formation_responses
 WHERE formation_response_id=p_formation_response_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('state','not_available'); END IF;
 SELECT * INTO v_existing FROM titus.formation_review_disclosure_decisions_v1
 WHERE learner_person_entity_id=v_actor AND request_id=p_request_id;
 IF FOUND THEN
  IF v_existing.formation_response_id=p_formation_response_id
   AND v_existing.reviewer_person_entity_id=p_reviewer_person_entity_id
   AND v_existing.decision_kind=p_decision_kind THEN
    RETURN jsonb_build_object('state','recorded','decisionId',
      v_existing.decision_id,'replayed',true);
  END IF;
  RETURN jsonb_build_object('state','conflicting_request');
 END IF;

 SELECT * INTO v_previous FROM titus.formation_review_disclosure_decisions_v1
 WHERE formation_response_id=p_formation_response_id
   AND reviewer_person_entity_id=p_reviewer_person_entity_id
 ORDER BY sequence_no DESC LIMIT 1;
 IF FOUND THEN
  IF v_previous.learner_person_entity_id<>v_actor THEN
   RETURN jsonb_build_object('state','not_available');
  END IF;
  IF v_previous.decision_kind=p_decision_kind THEN
   RETURN jsonb_build_object('state','already_in_state');
  END IF;
  v_seq := v_previous.sequence_no+1;
  v_prior_id := v_previous.decision_id;
 ELSE
  IF p_decision_kind='withdraw' THEN
   RETURN jsonb_build_object('state','no_prior_consent');
  END IF;
  v_seq := 1;
  v_prior_id := NULL;
 END IF;
 SELECT * INTO v_unit FROM titus.formation_units
 WHERE formation_unit_id=v_response.formation_unit_id;
 IF NOT FOUND OR v_unit.teacher_id IS DISTINCT FROM v_response.teacher_id THEN
   RETURN jsonb_build_object('state','not_available');
 END IF;
 IF p_decision_kind='consent' AND
    (v_response.response_status<>'submitted'
     OR v_unit.review_state<>'current'
     OR v_unit.formation_state NOT IN
       ('learner_ready','encountered','teachback_pending',
        'teachback_received','teachback_reviewed','transfer_pending',
        'transfer_reviewed','integrated')
     OR NOT EXISTS (
       SELECT 1 FROM titus.teacher_person_bindings b
       WHERE b.teacher_id=v_response.teacher_id
         AND b.person_entity_id=v_actor
         AND b.binding_state='active' AND b.retired_at IS NULL
      )) THEN RETURN jsonb_build_object('state','not_available');
 END IF;

 INSERT INTO titus.formation_review_disclosure_decisions_v1(
   request_id,formation_response_id,learner_person_entity_id,
   reviewer_person_entity_id,decision_kind,prior_decision_id,sequence_no,
   issuer_auth_user_id,issuer_auth_session_id,expires_at
 ) VALUES (
   p_request_id,p_formation_response_id,v_actor,p_reviewer_person_entity_id,
   p_decision_kind,v_prior_id,v_seq,v_auth_user,v_session,
   CASE WHEN p_decision_kind='consent'
     THEN clock_timestamp()+interval '30 days' ELSE NULL END
 ) RETURNING decision_id INTO v_decision_id;
 RETURN jsonb_build_object('state','recorded','decisionId',v_decision_id,
   'replayed',false,'effectiveDisclosure',false);
END;
$command$;
COMMENT ON FUNCTION titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid)
 IS 'Unsigned on the network: internal source-only learner-declared intent; '
    'returns no learner text and opens no reviewer access. '
    'A public/signed access adapter and original authorship proof are not yet released.';
REVOKE ALL ON FUNCTION
 titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid)
 FROM PUBLIC;
DO $roles$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
   EXECUTE 'REVOKE ALL ON FUNCTION titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid) FROM anon';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
   EXECUTE 'REVOKE ALL ON FUNCTION titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid) FROM authenticated';
 END IF;
END;
$roles$;

-- No change to B2B structure, the hard-false issuance gate or B2A writer.
COMMIT;
