-- Run only AFTER fixture.sql then candidate.sql in a disposable Postgres.
-- Production gate must remain false. We temporarily override it ONLY in the
-- isolated test database to check data structure and concurrency invariants.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION pg_temp.insert_work_event(
  p_id uuid, p_kind text, p_response uuid, p_previous uuid,
  p_actor uuid, p_disposition text DEFAULT NULL, p_feedback text DEFAULT NULL,
  p_program uuid DEFAULT '00000000-0000-4000-8000-000000000201',
  p_release uuid DEFAULT '00000000-0000-4000-8000-000000000601',
  p_learner uuid DEFAULT '00000000-0000-4000-8000-000000000101',
  p_version uuid DEFAULT '00000000-0000-4000-8000-000000000602'
) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO titus.formation_response_work_events_v1(
    work_event_id,root_formation_response_id,formation_response_id,
    previous_work_event_id,event_kind,program_id,
    curriculum_version_id,teaching_release_ref,
    learner_person_entity_id,actor_person_entity_id,
    feedback_disposition,feedback_text
  ) VALUES(
    p_id,'00000000-0000-4000-8000-000000000501',p_response,
    p_previous,p_kind,p_program,p_version,p_release,p_learner,
    p_actor,p_disposition,p_feedback
  );
END;
$f$;
CREATE OR REPLACE FUNCTION pg_temp.expect_denied(p_sql text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE did_deny boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    did_deny := true;
  END;
  IF NOT did_deny THEN
    RAISE EXCEPTION 'Expected rejection but statement was permitted: %',p_sql;
  END IF;
END;
$f$;

-- The proposal is unusable with real privileges even for a database writer
-- until a separately released source-owned authority decision exists.
SELECT pg_temp.expect_denied($q$
  SELECT pg_temp.insert_work_event(
    '00000000-0000-4000-8000-000000000701','teacher_feedback',
    '00000000-0000-4000-8000-000000000501',NULL,
    '00000000-0000-4000-8000-000000000102',
    'needs_revision','Please explain the warrant')
$q$);

DO $assert$
BEGIN
  IF (SELECT count(*) FROM titus.formation_response_work_events_v1) <> 0 THEN
    RAISE EXCEPTION 'closed gate made a durable record';
  END IF;
  IF (SELECT relrowsecurity FROM pg_class
      WHERE oid='titus.formation_response_work_events_v1'::regclass) IS NOT TRUE
    OR has_table_privilege('anon','titus.formation_response_work_events_v1','SELECT')
    OR has_table_privilege('authenticated','titus.formation_response_work_events_v1','SELECT')
    OR has_table_privilege('authenticated','titus.formation_response_work_events_v1','INSERT')
  THEN RAISE EXCEPTION 'unexpected browser privilege on private event carrier';
  END IF;
END;
$assert$;

-- Disposable PG TEST OVERRIDE ONLY. NEVER COPY THIS INTO A RELEASE CANDIDATE.
CREATE OR REPLACE FUNCTION titus.formation_response_work_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT true;
$$;

-- You cannot start with an orphan revision or use the learner as their own reviewer.
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000502',NULL,
 '00000000-0000-4000-8000-000000000101')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','teacher_feedback',
 '00000000-0000-4000-8000-000000000501',NULL,
 '00000000-0000-4000-8000-000000000101','reviewed','Own review')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','teacher_feedback',
 '00000000-0000-4000-8000-000000000501',NULL,
 '00000000-0000-4000-8000-000000000102','reviewed','Wrong program',
 '00000000-0000-4000-8000-000000000202')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','teacher_feedback',
 '00000000-0000-4000-8000-000000000503',NULL,
 '00000000-0000-4000-8000-000000000102','reviewed','Wrong unit')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','teacher_feedback',
 '00000000-0000-4000-8000-000000000504',NULL,
 '00000000-0000-4000-8000-000000000102','reviewed','Wrong teacher profile')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','teacher_feedback',
 '00000000-0000-4000-8000-000000000501',NULL,
 '00000000-0000-4000-8000-000000000102','reviewed','Wrong learner binding',
 '00000000-0000-4000-8000-000000000201',
 '00000000-0000-4000-8000-000000000601',
 '00000000-0000-4000-8000-000000000104')$q$);

-- A proper linked four-stage history begins with an EXISTING learner response.
SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000701','teacher_feedback',
 '00000000-0000-4000-8000-000000000501',NULL,
 '00000000-0000-4000-8000-000000000102',
 'needs_revision','Please separate the evidence from inference');

SELECT pg_temp.expect_denied($q$UPDATE titus.formation_response_work_events_v1
 SET feedback_text='silently changed' WHERE work_event_id='00000000-0000-4000-8000-000000000701'$q$);
SELECT pg_temp.expect_denied($q$DELETE FROM titus.formation_response_work_events_v1
 WHERE work_event_id='00000000-0000-4000-8000-000000000701'$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000502',NULL,
 '00000000-0000-4000-8000-000000000101')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000102')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000503',
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000101')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000501',
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000101')$q$);

SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000702','learner_revision',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000101');
-- A second learner revision cannot skip the review stage.
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','learner_revision',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000101')$q$);
-- Teacher must review latest response and must preserve exact lineage.
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','teacher_feedback',
 '00000000-0000-4000-8000-000000000501',
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000102','reviewed','Old answer')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','teacher_feedback',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000102','reviewed','Stale parent')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','teacher_feedback',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000101','reviewed','Learner pretending to teach')$q$);
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','teacher_feedback',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000102','mastered','Unsupported mastery')$q$);

SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000703','teacher_feedback',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000102',
 'reviewed','Now the claim and warrant are distinguished');

SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','learner_revision',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000703',
 '00000000-0000-4000-8000-000000000101')$q$);

DO $assert$
BEGIN
  IF (SELECT count(*) FROM titus.formation_response_work_events_v1) <> 3
    OR (SELECT min(sequence_no) FROM titus.formation_response_work_events_v1) <> 1
    OR (SELECT max(sequence_no) FROM titus.formation_response_work_events_v1) <> 3
    OR (SELECT count(*) FROM titus.formation_response_work_events_v1
       WHERE event_kind='teacher_feedback') <> 2
    OR (SELECT count(*) FROM titus.formation_response_work_events_v1
       WHERE event_kind='learner_revision') <> 1
  THEN RAISE EXCEPTION 'history sequence incorrect'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM titus.formation_responses r
    WHERE r.formation_response_id='00000000-0000-4000-8000-000000000501'
    AND r.raw_text='Original learner text stays in the existing original record'
  ) OR NOT EXISTS (
    SELECT 1 FROM titus.formation_responses r
    WHERE r.formation_response_id='00000000-0000-4000-8000-000000000502'
    AND r.raw_text='Learner revision is another original response record'
  ) THEN RAISE EXCEPTION 'original or revision text was mutated'; END IF;
  IF (SELECT count(*) FROM titus.formation_response_work_events_v1
      WHERE feedback_disposition IN ('passed','mastered')) <> 0 THEN
    RAISE EXCEPTION 'fictional mastery produced'; END IF;
  IF EXISTS (
    SELECT 1 FROM titus.formation_response_work_events_v1 x
      JOIN titus.formation_response_work_events_v1 y
        ON x.root_formation_response_id=y.root_formation_response_id
       AND x.sequence_no=y.sequence_no+1
    WHERE x.recorded_at <= y.recorded_at
  ) THEN RAISE EXCEPTION 'non-monotonic timestamps'; END IF;
END;
$assert$;

-- The ONLY positive insert used a deliberate isolated-fixture gate override.
-- Restore CLOSED before completion, so the source candidate's default is
-- unambiguously non-operational.
CREATE OR REPLACE FUNCTION titus.formation_response_work_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT false;
$$;
SELECT pg_temp.expect_denied($q$SELECT pg_temp.insert_work_event(
 '00000000-0000-4000-8000-000000000704','learner_revision',
 '00000000-0000-4000-8000-000000000502',
 '00000000-0000-4000-8000-000000000703',
 '00000000-0000-4000-8000-000000000101')$q$);
SELECT 'B2 source-only carrier structural checks PASS; auth/real edition NOT established' AS result;
