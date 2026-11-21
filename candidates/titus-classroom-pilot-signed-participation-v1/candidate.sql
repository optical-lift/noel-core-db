-- Noel-owned Titus classroom pilot signed-participation SOURCE CANDIDATE.
-- 2026-11-04. NOT a migration, not applied to Supabase/Noel/Atlas.
--
-- Prerequisites when eventually reviewed for release:
--   titus.classroom_threads_v1 (the private append-only event root)
--   titus.current_authenticated_person_entity_id_v1() (existing current
--      signed-session / canonical-Person resolver)
--   atlas.existing_person_claim_signed_actor_v1() (nonanonymous, active,
--      confirmed current signed session verifier).
--
-- This candidate authorizes ONLY a fictional sample content thread, not
-- the protected Titus Formation corpus or a public institution.
-- Membership rows are insufficient until SOURCE ISSUANCE verifies true.
BEGIN;

CREATE TABLE titus.classroom_pilot_participation_v1(
  thread_id uuid NOT NULL REFERENCES titus.classroom_threads_v1(thread_id)
    ON DELETE RESTRICT,
  person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
    ON DELETE RESTRICT,
  actor_role text NOT NULL CHECK(actor_role IN ('learner','teacher')),
  assignment_state text NOT NULL DEFAULT 'pending'
    CHECK(assignment_state IN ('pending','active','withdrawn','revoked')),
  assignment_receipt_id uuid NOT NULL,
  issued_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
    ON DELETE RESTRICT,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  effective_at timestamptz NOT NULL,
  expires_at timestamptz,
  withdrawn_at timestamptz,
  PRIMARY KEY(thread_id,person_entity_id),
  UNIQUE(thread_id,actor_role),
  CHECK(expires_at IS NULL OR expires_at>effective_at),
  CHECK((assignment_state='active' AND withdrawn_at IS NULL) OR
    assignment_state<>'active')
);

CREATE TABLE titus.classroom_pilot_parts_v1(
  thread_id uuid NOT NULL REFERENCES titus.classroom_threads_v1(thread_id)
    ON DELETE RESTRICT,
  part_ref text NOT NULL CHECK(
    part_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,119}$'),
  PRIMARY KEY(thread_id,part_ref)
);

ALTER TABLE titus.classroom_pilot_participation_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.classroom_pilot_parts_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.classroom_pilot_participation_v1,
  titus.classroom_pilot_parts_v1 FROM PUBLIC;
DO $grants$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    REVOKE ALL ON TABLE titus.classroom_pilot_participation_v1,
      titus.classroom_pilot_parts_v1 FROM anon;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    REVOKE ALL ON TABLE titus.classroom_pilot_participation_v1,
      titus.classroom_pilot_parts_v1 FROM authenticated;
  END IF;
END;$grants$;

-- Default-deny source authenticity. An assignment written by a privileged
-- actor, even a real governor, is NOT sufficient to confer an instructor or
-- learner right until the owning issuer can prove this exact assignment
-- receipt is presently in force for this Person, role and thread.
CREATE FUNCTION titus.classroom_pilot_assignment_issued_v1(
  p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,
  p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE sql STABLE
  SET search_path=pg_catalog
AS $$SELECT false$$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_assignment_issued_v1(
  uuid,uuid,text,uuid) FROM PUBLIC;

CREATE FUNCTION titus.classroom_pilot_authorize_current_v1(
  p_thread_id uuid,p_operation text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,auth,atlas,titus,reality
AS $authorize$
DECLARE
  v_user uuid;
  v_person uuid;
  v_member titus.classroom_pilot_participation_v1%ROWTYPE;
  v_thread titus.classroom_threads_v1%ROWTYPE;
  v_parts text[];
BEGIN
  IF p_thread_id IS NULL OR p_operation IS NULL OR p_operation NOT IN
    ('read','discussion_post','homework_submission','homework_feedback')
  THEN RETURN NULL; END IF;

  -- Both existing source checks are performed. OAuth claims supplied to an
  -- HTTP JSON body are never an identity or a teacher appointment.
  BEGIN
    v_user:=atlas.existing_person_claim_signed_actor_v1();
    v_person:=titus.current_authenticated_person_entity_id_v1();
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF v_user IS NULL OR v_person IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.id=v_person AND e.entity_kind='person'
      AND e.identity_state='canonical'
  ) THEN RETURN NULL; END IF;

  SELECT * INTO v_thread FROM titus.classroom_threads_v1
  WHERE thread_id=p_thread_id AND source_kind='fixture';
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT * INTO v_member FROM titus.classroom_pilot_participation_v1 m
  WHERE m.thread_id=p_thread_id AND m.person_entity_id=v_person
    AND m.assignment_state='active'
    AND m.effective_at<=now()
    AND (m.expires_at IS NULL OR m.expires_at>now())
    AND m.withdrawn_at IS NULL;
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF (p_operation='homework_submission' AND v_member.actor_role<>'learner')
    OR (p_operation='homework_feedback' AND v_member.actor_role<>'teacher')
  THEN RETURN NULL; END IF;

  -- The deliberately false issuer is separately owned. A valid-looking
  -- UUID or source-inserted membership record cannot silently open access.
  IF NOT titus.classroom_pilot_assignment_issued_v1(
    p_thread_id,v_person,v_member.actor_role,v_member.assignment_receipt_id
  ) THEN RETURN NULL; END IF;

  SELECT array_agg(p.part_ref ORDER BY p.part_ref) INTO v_parts
    FROM titus.classroom_pilot_parts_v1 p
    WHERE p.thread_id=p_thread_id;
  IF v_parts IS NULL OR cardinality(v_parts)>160 OR
     NOT ('class'=ANY(v_parts) AND 'homework'=ANY(v_parts))
  THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'threadId',v_thread.thread_id,
    'courseRef',v_thread.course_ref,
    'unitRef',v_thread.unit_ref,
    'viewerPersonId',v_person,
    'viewerRole',v_member.actor_role,
    'operation',p_operation,
    'allowedParts',to_jsonb(v_parts),
    'sourceReceiptId',v_member.assignment_receipt_id);
END;$authorize$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_authorize_current_v1(
  uuid,text) FROM PUBLIC;

-- Thin published-API transport: this is *not* evidence that any membership
-- is authentically issued. The source-side private authorization rechecks
-- current signed identity and source-issued assignment on every RPC request.
CREATE FUNCTION public.titus_classroom_authorize_self_api_v1(
  p_thread_id uuid,p_operation text
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,titus,public
AS $$
  SELECT titus.classroom_pilot_authorize_current_v1(
    p_thread_id,p_operation);
$$;
REVOKE ALL ON FUNCTION public.titus_classroom_authorize_self_api_v1(
  uuid,text) FROM PUBLIC;
DO $grants$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    GRANT EXECUTE ON FUNCTION public.titus_classroom_authorize_self_api_v1(
      uuid,text) TO authenticated;
  END IF;
END;$grants$;

-- Source real read/append still NOT granted here. Those separate RPCs
-- must recheck signed Person+operation and append atomically under the
-- existing classroom event root guard when their source is ready.
COMMIT;
