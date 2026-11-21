-- Titus Build B2 source candidate (2026-11-03).
-- PROPOSED ONLY. Not a canonical Supabase migration; DO NOT deploy/merge.
--
-- All existing learner originals remain in titus.formation_responses.
-- This append-only link stream holds reviewer comments and references to
-- separately saved learner revisions, without duplicating original text.
-- The authority gate is deliberately CLOSED in the candidate. A future,
-- separately reviewed source-owned operation must implement and prove
-- real Person, mandate, teaching-edition, disclosure and current revocation.
--
-- Do not grant authenticated/anon direct access or add a public RPC.
BEGIN;

CREATE OR REPLACE FUNCTION titus.formation_response_work_authority_gate_v1()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
  SELECT false;
$$;
REVOKE ALL ON FUNCTION titus.formation_response_work_authority_gate_v1() FROM PUBLIC;

CREATE TABLE titus.formation_response_work_events_v1 (
  work_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  root_formation_response_id uuid NOT NULL
    REFERENCES titus.formation_responses(formation_response_id) ON DELETE RESTRICT,
  formation_response_id uuid NOT NULL
    REFERENCES titus.formation_responses(formation_response_id) ON DELETE RESTRICT,
  previous_work_event_id uuid
    REFERENCES titus.formation_response_work_events_v1(work_event_id) ON DELETE RESTRICT,
  sequence_no integer NOT NULL CHECK (sequence_no >= 1),
  event_kind text NOT NULL CHECK (event_kind IN ('teacher_feedback','learner_revision')),
  program_id uuid NOT NULL REFERENCES titus.programs(program_id) ON DELETE RESTRICT,
  curriculum_version_id uuid NOT NULL,
  teaching_release_ref uuid NOT NULL,
  learner_person_entity_id uuid NOT NULL
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  actor_person_entity_id uuid NOT NULL
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  feedback_disposition text,
  feedback_text text,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT formation_response_work_events_event_shape CHECK (
    (
      event_kind = 'teacher_feedback'
      AND actor_person_entity_id <> learner_person_entity_id
      AND feedback_disposition IN ('needs_revision','reviewed')
      AND feedback_text IS NOT NULL
      AND length(btrim(feedback_text)) BETWEEN 1 AND 1200
    ) OR (
      event_kind = 'learner_revision'
      AND actor_person_entity_id = learner_person_entity_id
      AND feedback_disposition IS NULL
      AND feedback_text IS NULL
    )
  ),
  UNIQUE(root_formation_response_id,sequence_no)
);

-- An original/revised Formation response may be reviewed at most once in
-- this Work stream and a revision source row may be introduced only once.
CREATE UNIQUE INDEX formation_response_work_review_once_v1
  ON titus.formation_response_work_events_v1(formation_response_id)
  WHERE event_kind = 'teacher_feedback';
CREATE UNIQUE INDEX formation_response_work_revision_once_v1
  ON titus.formation_response_work_events_v1(formation_response_id)
  WHERE event_kind = 'learner_revision';
CREATE INDEX formation_response_work_root_order_v1
  ON titus.formation_response_work_events_v1(root_formation_response_id,sequence_no);

ALTER TABLE titus.formation_response_work_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.formation_response_work_events_v1 FROM PUBLIC;
-- Explicit role-denials matter even when the physical project evolves.
DO $block$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON TABLE titus.formation_response_work_events_v1 FROM anon';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON TABLE titus.formation_response_work_events_v1 FROM authenticated';
  END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION titus.formation_response_work_events_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, titus, reality
AS $guard$
DECLARE
  v_root titus.formation_responses%ROWTYPE;
  v_response titus.formation_responses%ROWTYPE;
  v_unit titus.formation_units%ROWTYPE;
  v_previous titus.formation_response_work_events_v1%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'formation response Work history is append-only';
  END IF;
  -- Permanently unavailable on any live database with this proposal.
  -- The isolated disposable SQL fixture changes this gate ONLY in its own DB.
  IF NOT titus.formation_response_work_authority_gate_v1() THEN
    RAISE EXCEPTION 'no source-authorized Formation review writer exists';
  END IF;

  -- Serializes all events in one existing original response thread. Both
  -- the latest-event comparison and insert happen under one root-row lock.
  SELECT * INTO v_root FROM titus.formation_responses
    WHERE formation_response_id = NEW.root_formation_response_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown original Formation response'; END IF;
  SELECT * INTO v_unit FROM titus.formation_units
    WHERE formation_unit_id = v_root.formation_unit_id;
  IF NOT FOUND OR v_unit.program_id IS DISTINCT FROM NEW.program_id
    OR v_unit.teacher_id IS DISTINCT FROM v_root.teacher_id THEN
    RAISE EXCEPTION 'response, unit and program do not agree';
  END IF;
  -- Existing Formation self-learner identity is the active Person binding
  -- to the historical teacher profile. Teacher profile is NEVER reviewer Person.
  -- This check is NOT sufficient to grant review, source or recipient access.
  IF NOT EXISTS (
    SELECT 1 FROM titus.teacher_person_bindings b
    WHERE b.teacher_id = v_root.teacher_id
      AND b.person_entity_id = NEW.learner_person_entity_id
      AND b.binding_state = 'active'
      AND b.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'no active learner Person binding for this Formation response';
  END IF;

  SELECT * INTO v_response FROM titus.formation_responses
    WHERE formation_response_id = NEW.formation_response_id;
  IF NOT FOUND OR v_response.formation_unit_id IS DISTINCT FROM v_root.formation_unit_id
    OR v_response.teacher_id IS DISTINCT FROM v_root.teacher_id
    OR v_response.formation_question_id IS DISTINCT FROM v_root.formation_question_id THEN
    RAISE EXCEPTION 'response is outside the original Formation unit/question';
  END IF;

  SELECT * INTO v_previous
  FROM titus.formation_response_work_events_v1
  WHERE root_formation_response_id = NEW.root_formation_response_id
  ORDER BY sequence_no DESC LIMIT 1;

  IF NOT FOUND THEN
    IF NEW.event_kind <> 'teacher_feedback'
      OR NEW.previous_work_event_id IS NOT NULL
      OR NEW.formation_response_id <> NEW.root_formation_response_id THEN
      RAISE EXCEPTION 'first Work event must review its existing original response';
    END IF;
    NEW.sequence_no := 1;
  ELSE
    IF NEW.previous_work_event_id IS DISTINCT FROM v_previous.work_event_id
      OR NEW.program_id IS DISTINCT FROM v_previous.program_id
      OR NEW.curriculum_version_id IS DISTINCT FROM v_previous.curriculum_version_id
      OR NEW.teaching_release_ref IS DISTINCT FROM v_previous.teaching_release_ref
      OR NEW.learner_person_entity_id IS DISTINCT FROM v_previous.learner_person_entity_id THEN
      RAISE EXCEPTION 'stale predecessor or changed original Work identity';
    END IF;
    IF v_previous.event_kind = 'teacher_feedback' THEN
      IF v_previous.feedback_disposition <> 'needs_revision'
        OR NEW.event_kind <> 'learner_revision'
        OR NEW.formation_response_id = v_previous.formation_response_id THEN
        RAISE EXCEPTION 'revision requires the latest outstanding revision request';
      END IF;
    ELSIF v_previous.event_kind = 'learner_revision' THEN
      IF NEW.event_kind <> 'teacher_feedback'
        OR NEW.formation_response_id IS DISTINCT FROM v_previous.formation_response_id THEN
        RAISE EXCEPTION 'teacher must review the latest learner revision';
      END IF;
    ELSE
      RAISE EXCEPTION 'unknown preceding event type';
    END IF;
    NEW.sequence_no := v_previous.sequence_no+1;
  END IF;
  -- Clock and sequence are source-controlled, not client-supplied.
  NEW.recorded_at := greatest(
    clock_timestamp(),
    COALESCE(v_previous.recorded_at + interval '1 microsecond', clock_timestamp())
  );
  RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION titus.formation_response_work_events_guard_v1() FROM PUBLIC;

CREATE TRIGGER formation_response_work_events_guard_v1
BEFORE INSERT OR UPDATE OR DELETE
ON titus.formation_response_work_events_v1
FOR EACH ROW EXECUTE FUNCTION titus.formation_response_work_events_guard_v1();

-- No GRANT, no SECURITY DEFINER public API, no new auth/Person/teaching role,
-- no learner original mutation, no data migration, no publication.
COMMIT;
