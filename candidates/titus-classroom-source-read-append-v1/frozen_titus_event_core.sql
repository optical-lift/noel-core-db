-- FROZEN, TEST-ONLY COPY of Titus PR #35 classroom event carrier.
-- Source ref: b7fba82b8712a0895167c6d95fd963f0da052dd0; path candidates/titus-classroom-event-core-build1/candidate.sql
-- Do NOT ship this duplicate as a migration. Noel must separately reconcile ownership.
-- TITUS BUILD 1 — UNRELEASED SOURCE CANDIDATE ONLY, 2026-11-03.
-- NOT a migration, not applied to Supabase, no public RPC or privileges.
-- Owner of eventual database change: Noel governed source lane.
-- Course/Unit refs are immutable sample/edition locators, not Person grants.
--
-- The original learner submission, ordinary message, teacher feedback and
-- revised learner original are ALL rows in this one append-only table.
-- No copy of homework text in another "work" table.
BEGIN;

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
COMMIT;
