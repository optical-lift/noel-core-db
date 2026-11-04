-- TITUS CLASSROOM SOURCE ASSEMBLY V1 (2026-11-04): NOEL GOVERNED CANDIDATE ONLY.
-- This is a single transaction-ready DDL packet, NOT a migration and NOT released.
-- Source-owned by noel-core-db; it must receive a governed migration identity,
-- a private-schema clone proof and explicit protected release approval before use.
--
-- Scope: fixture-only sample original; not released Formation or canon research.
-- Existing Auth/Atlas/Reality identities and Atlas Teaching are independently
-- governed; no user, enrollment, capability activation or classroom is seeded.
-- The original event writer remains HARD FALSE; no owner can yet save an event.
-- The narrow public RPCs require the signed authenticated session and source
-- issued assignment; these definitions do NOT themselves create any consent.
-- Do not include test-only auth GUC helpers in production source.
--
-- Provenance of exact ordered source segments (verified at assembly):
-- 1. Core event carrier (Titus draft PR #35): optical-lift/titus:candidates/titus-classroom-event-core-build1/candidate.sql
--    blob 8dc575b53d824a8204f12a1eb6ebaf98b1c1592b
-- 2. Signed membership (Noel PR #2469): optical-lift/noel-core-db:candidates/titus-classroom-pilot-signed-participation-v1/candidate.sql
--    blob 40de318414b4440eb19ae643f0c347691275ee37
-- 3. Read and append (Noel PR #2470): optical-lift/noel-core-db:candidates/titus-classroom-source-read-append-v1/candidate.sql
--    blob cf370c8091e17f08b2653a7ef3f89c8a150eb51f
-- 4. Source issuance and consent (Noel PR #2471): optical-lift/noel-core-db:candidates/titus-pilot-classroom-issuance-v1/candidate.sql
--    blob bd436a4c0f76c11e387c4517088a579d1218a8f3
BEGIN;

-- ==========================================================
-- BEGIN SEGMENT 1: Core event carrier (Titus draft PR #35)
-- ==========================================================
-- TITUS BUILD 1 — UNRELEASED SOURCE CANDIDATE ONLY, 2026-11-03.
-- NOT a migration, not applied to Supabase, no public RPC or privileges.
-- Owner of eventual database change: Noel governed source lane.
-- Course/Unit refs are immutable sample/edition locators, not Person grants.
--
-- The original learner submission, ordinary message, teacher feedback and
-- revised learner original are ALL rows in this one append-only table.
-- No copy of homework text in another "work" table.

CREATE TABLE titus.classroom_threads_v1 (
  thread_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_kind text NOT NULL CHECK (source_kind IN ('fixture','approved_edition')),
  course_ref text NOT NULL CHECK (course_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,119}$'),
  unit_ref text NOT NULL CHECK (unit_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,119}$'),
  teaching_release_ref uuid NULL,
  opened_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT classroom_thread_release_shape_v1 CHECK (
    (source_kind = 'fixture' AND teaching_release_ref IS NULL)
    OR (source_kind = 'approved_edition' AND teaching_release_ref IS NOT NULL)
  ),
  UNIQUE(thread_id,course_ref,unit_ref)
);

CREATE TABLE titus.classroom_events_v1 (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES titus.classroom_threads_v1(thread_id) ON DELETE RESTRICT,
  -- Client retry identifier, not an authority proof. Must be unique per thread.
  operation_id uuid NOT NULL,
  expected_version integer NOT NULL CHECK (expected_version>=0),
  sequence_no integer NOT NULL CHECK (sequence_no>0),
  part_ref text NOT NULL CHECK (part_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,119}$'),
  event_kind text NOT NULL CHECK (event_kind IN (
    'discussion_post','homework_submission','homework_feedback'
  )),
  actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  -- Descriptive kind, resolved from the source in the FUTURE writer. NOT a grant.
  actor_kind text NOT NULL CHECK (actor_kind IN ('learner','teacher')),
  body text NOT NULL CHECK (
    length(btrim(body))>0 AND length(body)<=3000
  ),
  reply_to_event_id uuid NULL REFERENCES titus.classroom_events_v1(event_id) ON DELETE RESTRICT,
  disposition text NULL CHECK (disposition IN ('needs_revision','reviewed')),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT classroom_event_shape_v1 CHECK (
    (event_kind='homework_feedback' AND actor_kind='teacher'
      AND part_ref='homework' AND disposition IS NOT NULL
      AND length(body)<=1200 AND reply_to_event_id IS NOT NULL)
    OR (event_kind='homework_submission' AND actor_kind='learner'
      AND part_ref='homework' AND disposition IS NULL)
    OR (event_kind='discussion_post' AND disposition IS NULL)
  ),
  UNIQUE (thread_id,operation_id),
  UNIQUE (thread_id,sequence_no)
);

CREATE UNIQUE INDEX classroom_review_one_per_original_v1
  ON titus.classroom_events_v1(thread_id,reply_to_event_id)
  WHERE event_kind='homework_feedback';
CREATE INDEX classroom_events_thread_order_v1
  ON titus.classroom_events_v1(thread_id,sequence_no);

ALTER TABLE titus.classroom_threads_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.classroom_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.classroom_threads_v1, titus.classroom_events_v1 FROM PUBLIC;
DO $deny$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    REVOKE ALL ON TABLE titus.classroom_threads_v1, titus.classroom_events_v1 FROM anon;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    REVOKE ALL ON TABLE titus.classroom_threads_v1, titus.classroom_events_v1 FROM authenticated;
  END IF;
END;
$deny$;

-- This gate remains CLOSED. It is not overridden in a release migration.
-- Real Person, entitlement, current reviewer mandate, and content edition
-- must be independently verified in a future source-issued operation.
CREATE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
REVOKE ALL ON FUNCTION titus.classroom_authority_gate_v1() FROM PUBLIC;


CREATE FUNCTION titus.classroom_thread_guard_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog,titus
AS $guard$
BEGIN
  IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'classroom thread identity is immutable'; END IF;
  IF NOT titus.classroom_authority_gate_v1() THEN
    RAISE EXCEPTION 'no authorized classroom thread writer is released';
  END IF;
  NEW.opened_at := clock_timestamp();
  RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION titus.classroom_thread_guard_v1() FROM PUBLIC;
CREATE TRIGGER classroom_thread_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON titus.classroom_threads_v1
FOR EACH ROW EXECUTE FUNCTION titus.classroom_thread_guard_v1();

CREATE FUNCTION titus.classroom_event_append_guard_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog,titus,reality
AS $guard$
DECLARE
  v_thread titus.classroom_threads_v1%ROWTYPE;
  v_last_submit titus.classroom_events_v1%ROWTYPE;
  v_review titus.classroom_events_v1%ROWTYPE;
  v_parent titus.classroom_events_v1%ROWTYPE;
  v_version integer;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'classroom history is append-only';
  END IF;
  IF NOT titus.classroom_authority_gate_v1() THEN
    RAISE EXCEPTION 'no authorized classroom writer is released';
  END IF;
  -- Serialize competing writes to the same thread, before checking version.
  SELECT * INTO v_thread FROM titus.classroom_threads_v1
    WHERE thread_id=NEW.thread_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no such classroom thread'; END IF;
  IF v_thread.source_kind='approved_edition' THEN
    -- Future writer must validate the exact approved content/recipient release;
    -- this candidate never equates a non-null UUID with valid entitlement.
    RAISE EXCEPTION 'no released approved-edition classroom adapter';
  END IF;
  SELECT count(*)::integer INTO v_version FROM titus.classroom_events_v1
    WHERE thread_id=NEW.thread_id;
  IF NEW.expected_version IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION 'stale classroom version';
  END IF;

  IF NEW.reply_to_event_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM titus.classroom_events_v1
      WHERE event_id=NEW.reply_to_event_id AND thread_id=NEW.thread_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'reply parent not in this classroom'; END IF;
  END IF;

  SELECT * INTO v_last_submit FROM titus.classroom_events_v1
    WHERE thread_id=NEW.thread_id AND event_kind='homework_submission'
    ORDER BY sequence_no DESC LIMIT 1;
  IF NEW.event_kind='homework_submission' THEN
    IF FOUND THEN
      SELECT * INTO v_review FROM titus.classroom_events_v1
        WHERE thread_id=NEW.thread_id AND event_kind='homework_feedback'
          AND reply_to_event_id=v_last_submit.event_id;
      IF NOT FOUND OR v_review.disposition<>'needs_revision'
        OR NEW.reply_to_event_id IS DISTINCT FROM v_review.event_id
        OR NEW.actor_person_entity_id IS DISTINCT FROM v_last_submit.actor_person_entity_id THEN
        RAISE EXCEPTION 'revision requires own latest original and revision request';
      END IF;
    ELSIF NEW.reply_to_event_id IS NOT NULL THEN
      RAISE EXCEPTION 'first original must not be a revision';
    END IF;
  ELSIF NEW.event_kind='homework_feedback' THEN
    IF v_last_submit.event_id IS NULL
      OR NEW.reply_to_event_id IS DISTINCT FROM v_last_submit.event_id
      OR NEW.actor_person_entity_id=v_last_submit.actor_person_entity_id
      OR EXISTS (
        SELECT 1 FROM titus.classroom_events_v1 e
          WHERE e.thread_id=NEW.thread_id AND
            e.event_kind='homework_feedback' AND
            e.reply_to_event_id=v_last_submit.event_id
      ) THEN
      RAISE EXCEPTION 'feedback must address the latest unreviewed original by a different Person';
    END IF;
  END IF;

  NEW.sequence_no := v_version+1;
  NEW.recorded_at := clock_timestamp();
  RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION titus.classroom_event_append_guard_v1() FROM PUBLIC;

CREATE TRIGGER classroom_event_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON titus.classroom_events_v1
FOR EACH ROW EXECUTE FUNCTION titus.classroom_event_append_guard_v1();

-- Deliberately no public function, no role grants and no migration history.
-- A future authenticated writer must re-resolve current actor and membership,
-- verify exact Part/Unit/edition, and handle operation_id replay atomically.
-- END SEGMENT 1.

-- ==========================================================
-- BEGIN SEGMENT 2: Signed membership (Noel PR #2469)
-- ==========================================================
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
-- END SEGMENT 2.

-- ==========================================================
-- BEGIN SEGMENT 3: Read and append (Noel PR #2470)
-- ==========================================================
-- Noel/Titus classroom Build 1E: SOURCE CANDIDATE ONLY — NOT A MIGRATION.
-- Must be evaluated after PR #2469's signed-participation candidate and
-- Titus PR #35's exact append-only classroom event carrier.
-- No real actor, issuer, writer, approved Formation edition or live grant.
-- The immutable classroom and assignment authenticity gates remain FALSE.

CREATE FUNCTION titus.classroom_pilot_read_current_v1(p_thread_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,atlas,reality,auth
AS $read$
DECLARE
  v_receipt jsonb;
  v_events jsonb;
  v_count integer;
  v_last uuid;
  v_decision text;
BEGIN
  -- Fresh signed user + canonical Person + source-issued active assignment,
  -- exact classroom and operation, on EVERY read (no trusted client receipt).
  v_receipt:=titus.classroom_pilot_authorize_current_v1(p_thread_id,'read');
  IF v_receipt IS NULL THEN
    RAISE EXCEPTION 'Classroom access denied' USING ERRCODE='42501';
  END IF;

  SELECT count(*)::integer,coalesce(jsonb_agg(jsonb_build_object(
      'id',e.event_id,'operationId',e.operation_id,
      'sequence',e.sequence_no,'kind',e.event_kind,
      'partRef',e.part_ref,'body',e.body,
      'actorId',e.actor_person_entity_id,'actorRole',e.actor_kind,
      'replyToEventId',e.reply_to_event_id,
      'disposition',e.disposition,'recordedAt',e.recorded_at
    ) ORDER BY e.sequence_no),'[]'::jsonb)
    INTO v_count,v_events
  FROM titus.classroom_events_v1 e
  WHERE e.thread_id=p_thread_id;
  IF v_count>1000 THEN
    RAISE EXCEPTION 'Classroom event limit' USING ERRCODE='22023';
  END IF;

  SELECT event_id INTO v_last FROM titus.classroom_events_v1
  WHERE thread_id=p_thread_id AND event_kind='homework_submission'
  ORDER BY sequence_no DESC LIMIT 1;
  IF v_last IS NOT NULL THEN
    SELECT disposition INTO v_decision
    FROM titus.classroom_events_v1
    WHERE thread_id=p_thread_id
      AND event_kind='homework_feedback'
      AND reply_to_event_id=v_last
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'threadId',p_thread_id,
    'version',v_count,
    'homeworkState',CASE
      WHEN v_last IS NULL THEN 'not_started'
      ELSE coalesce(v_decision,'submitted') END,
    'events',v_events);
END;
$read$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_read_current_v1(uuid)
 FROM PUBLIC;

-- ONE transaction for current signed Person, source-issued member,
-- immutable operation-id retry, stale revision conflict, exact part,
-- original-preserving append and canonical post-write snapshot.
CREATE FUNCTION titus.classroom_pilot_append_current_v1(
  p_thread_id uuid,p_command jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,atlas,reality,auth
AS $append$
DECLARE
  v_thread titus.classroom_threads_v1%ROWTYPE;
  v_member titus.classroom_pilot_participation_v1%ROWTYPE;
  v_receipt jsonb;
  v_person uuid;
  v_role text;
  v_operation uuid;
  v_version integer;
  v_count integer;
  v_kind text;
  v_part text;
  v_body text;
  v_parent uuid;
  v_decision text;
  v_prior titus.classroom_events_v1%ROWTYPE;
  v_inserted titus.classroom_events_v1%ROWTYPE;
  v_last titus.classroom_events_v1%ROWTYPE;
  v_review titus.classroom_events_v1%ROWTYPE;
BEGIN
  IF p_thread_id IS NULL OR jsonb_typeof(p_command) IS DISTINCT FROM 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_command) k
       WHERE k NOT IN (
          'operationId','expectedVersion','kind','partRef','body',
          'replyToEventId','disposition'))<>0
     OR NOT (p_command ?& ARRAY[
       'operationId','expectedVersion','kind','partRef','body','replyToEventId'])
  THEN
    RAISE EXCEPTION 'Invalid classroom command' USING ERRCODE='22023';
  END IF;

  v_kind:=p_command->>'kind';
  v_part:=p_command->>'partRef';
  IF v_kind NOT IN ('discussion_post','homework_submission','homework_feedback')
     OR v_kind IS NULL
     OR v_part IS NULL
     OR v_part !~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,119}$'
     OR jsonb_typeof(p_command->'body') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_command->'expectedVersion') IS DISTINCT FROM 'number'
     OR (p_command->>'expectedVersion') !~ '^(0|[1-9][0-9]{0,3})$'
     OR (p_command->>'operationId') IS NULL
     OR (p_command->>'operationId') !~* 
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR ((p_command->>'replyToEventId') IS NOT NULL
       AND (p_command->>'replyToEventId') !~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
  THEN
    RAISE EXCEPTION 'Invalid classroom fields' USING ERRCODE='22023';
  END IF;
  v_operation:=(p_command->>'operationId')::uuid;
  v_version:=(p_command->>'expectedVersion')::integer;
  v_body:=btrim(p_command->>'body');
  v_parent:=(p_command->>'replyToEventId')::uuid;
  v_decision:=p_command->>'disposition';

  IF v_version>1000 OR length(v_body)=0 OR length(v_body)>3000
     OR (v_kind='homework_feedback' AND
         (v_part<>'homework' OR v_parent IS NULL
          OR v_decision NOT IN ('needs_revision','reviewed')
          OR v_decision IS NULL OR length(v_body)>1200))
     OR (v_kind<>'homework_feedback' AND p_command ? 'disposition')
     OR (v_kind='homework_submission' AND v_part<>'homework')
     OR (v_kind='homework_feedback' AND NOT (p_command ? 'disposition'))
  THEN
    RAISE EXCEPTION 'Invalid classroom event' USING ERRCODE='22023';
  END IF;

  -- Serialize concurrent writes on one existing, fixture-only thread.
  SELECT * INTO v_thread
  FROM titus.classroom_threads_v1
  WHERE thread_id=p_thread_id AND source_kind='fixture'
  FOR UPDATE;
  IF v_thread.thread_id IS NULL THEN
    RAISE EXCEPTION 'Classroom unavailable' USING ERRCODE='42501';
  END IF;

  -- Re-resolve current signed Person, active assignment, authentic issuer,
  -- exact classroom and requested operation INSIDE the locked transaction.
  v_receipt:=titus.classroom_pilot_authorize_current_v1(
    p_thread_id,v_kind);
  IF v_receipt IS NULL THEN
    RAISE EXCEPTION 'Classroom access denied' USING ERRCODE='42501';
  END IF;
  v_person:=(v_receipt->>'viewerPersonId')::uuid;
  v_role:=v_receipt->>'viewerRole';

  -- Lock the exact membership before issuing a durable original. A
  -- concurrent withdrawal/update of this Person's assignment must either
  -- precede this lock (and deny the write) or follow the committed write.
  -- This closes the revoke-vs-submit gap left by an unlocked STABLE reader.
  SELECT * INTO v_member FROM titus.classroom_pilot_participation_v1
  WHERE thread_id=p_thread_id AND person_entity_id=v_person FOR SHARE;
  IF v_member.person_entity_id IS NULL
     OR v_member.assignment_state<>'active'
     OR v_member.actor_role IS DISTINCT FROM v_role
     OR v_member.assignment_receipt_id::text IS DISTINCT FROM
          (v_receipt->>'sourceReceiptId')
     OR v_member.effective_at>clock_timestamp()
     OR (v_member.expires_at IS NOT NULL AND
         v_member.expires_at<=clock_timestamp())
     OR v_member.withdrawn_at IS NOT NULL
     OR NOT titus.classroom_pilot_assignment_issued_v1(
       p_thread_id,v_person,v_role,v_member.assignment_receipt_id)
  THEN
    RAISE EXCEPTION 'Classroom assignment changed' USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM titus.classroom_pilot_parts_v1
    WHERE thread_id=p_thread_id AND part_ref=v_part)
  THEN
    RAISE EXCEPTION 'Classroom part unavailable' USING ERRCODE='42501';
  END IF;

  -- A retry must match the SAME original payload and verified actor. This
  -- check precedes expected-version evaluation, as the thread may advance.
  SELECT * INTO v_prior FROM titus.classroom_events_v1
  WHERE thread_id=p_thread_id AND operation_id=v_operation;
  IF v_prior.event_id IS NOT NULL THEN
    IF v_prior.actor_person_entity_id IS DISTINCT FROM v_person OR
       v_prior.actor_kind IS DISTINCT FROM v_role OR
       v_prior.expected_version IS DISTINCT FROM v_version OR
       v_prior.event_kind IS DISTINCT FROM v_kind OR
       v_prior.part_ref IS DISTINCT FROM v_part OR
       v_prior.body IS DISTINCT FROM v_body OR
       v_prior.reply_to_event_id IS DISTINCT FROM v_parent OR
       v_prior.disposition IS DISTINCT FROM v_decision
    THEN
      RAISE EXCEPTION 'Classroom operation conflict' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'eventId',v_prior.event_id,'replay',true,
      'snapshot',titus.classroom_pilot_read_current_v1(p_thread_id));
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM titus.classroom_events_v1 WHERE thread_id=p_thread_id;
  IF v_version<>v_count THEN
    RAISE EXCEPTION 'Classroom version conflict' USING ERRCODE='40001';
  END IF;
  IF v_count>=1000 THEN
    RAISE EXCEPTION 'Classroom event limit' USING ERRCODE='22023';
  END IF;

  IF v_parent IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM titus.classroom_events_v1
    WHERE event_id=v_parent AND thread_id=p_thread_id)
  THEN
    RAISE EXCEPTION 'Classroom parent unavailable' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_last
  FROM titus.classroom_events_v1
  WHERE thread_id=p_thread_id AND event_kind='homework_submission'
  ORDER BY sequence_no DESC LIMIT 1;
  IF v_kind='homework_submission' THEN
    IF v_role<>'learner' THEN
      RAISE EXCEPTION 'Learner submission denied' USING ERRCODE='42501';
    END IF;
    IF v_last.event_id IS NULL THEN
      IF v_parent IS NOT NULL THEN
        RAISE EXCEPTION 'First submission cannot be a revision'
          USING ERRCODE='22023';
      END IF;
    ELSE
      SELECT * INTO v_review
      FROM titus.classroom_events_v1
      WHERE thread_id=p_thread_id AND event_kind='homework_feedback'
        AND reply_to_event_id=v_last.event_id;
      IF v_review.disposition IS DISTINCT FROM 'needs_revision'
         OR v_parent IS DISTINCT FROM v_review.event_id
         OR v_last.actor_person_entity_id IS DISTINCT FROM v_person THEN
        RAISE EXCEPTION 'Revision is not open' USING ERRCODE='42501';
      END IF;
    END IF;
  ELSIF v_kind='homework_feedback' THEN
    IF v_role<>'teacher' OR v_last.event_id IS NULL OR
       v_parent IS DISTINCT FROM v_last.event_id OR
       v_last.actor_person_entity_id=v_person OR
       EXISTS(
         SELECT 1 FROM titus.classroom_events_v1
         WHERE thread_id=p_thread_id
           AND event_kind='homework_feedback'
           AND reply_to_event_id=v_last.event_id)
    THEN
      RAISE EXCEPTION 'Teacher feedback denied' USING ERRCODE='42501';
    END IF;
  END IF;

  -- The original carrier's trigger performs an additional hard-false
  -- source gate, serialization and immutable original/feedback checks.
  -- This function NEVER overrides that gate. Only a disposable test may.
  INSERT INTO titus.classroom_events_v1(
     thread_id,operation_id,expected_version,sequence_no,part_ref,
     event_kind,actor_person_entity_id,actor_kind,body,
     reply_to_event_id,disposition
  ) VALUES(
     p_thread_id,v_operation,v_version,v_count+1,v_part,v_kind,
     v_person,v_role,v_body,v_parent,v_decision
  ) RETURNING * INTO v_inserted;
  RETURN jsonb_build_object(
    'eventId',v_inserted.event_id,'replay',false,
    'snapshot',titus.classroom_pilot_read_current_v1(p_thread_id));
END;
$append$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_append_current_v1(
  uuid,jsonb) FROM PUBLIC;

-- These thin transports are accessible to authenticated signed users
-- ONLY after an actual source deployment. Every call rechecks the source;
-- neither a prior authorize call nor an OAuth token implies permission.
CREATE FUNCTION public.titus_classroom_read_self_api_v1(
  p_thread_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,public
AS $$SELECT titus.classroom_pilot_read_current_v1(p_thread_id)$$;
REVOKE ALL ON FUNCTION public.titus_classroom_read_self_api_v1(uuid)
 FROM PUBLIC;

CREATE FUNCTION public.titus_classroom_append_self_api_v1(
  p_thread_id uuid,p_command jsonb
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,titus,public
AS $$SELECT titus.classroom_pilot_append_current_v1(p_thread_id,p_command)$$;
REVOKE ALL ON FUNCTION public.titus_classroom_append_self_api_v1(
  uuid,jsonb) FROM PUBLIC;

DO $grants$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    GRANT EXECUTE ON FUNCTION public.titus_classroom_read_self_api_v1(uuid)
      TO authenticated;
    GRANT EXECUTE ON FUNCTION public.titus_classroom_append_self_api_v1(
      uuid,jsonb) TO authenticated;
  END IF;
END;$grants$;
-- END SEGMENT 3.

-- ==========================================================
-- BEGIN SEGMENT 4: Source issuance and consent (Noel PR #2471)
-- ==========================================================
-- Noel/Titus Build 1F — source-issued sample classroom participation candidate.
-- NOT applied to production. Stacked after Build 1E source read/append.
-- Root permission comes from Atlas principal-to-Ledger authority, not from
-- a user-supplied role, an offering's creator, a teacher switch or a UUID.
-- Learner enrollment alone does not consent to disclosure of responses.

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
 SET assignment_state='active',effective_at=now(),
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
-- END SEGMENT 4.

COMMIT;
