-- Noel/Titus classroom Build 1E: SOURCE CANDIDATE ONLY — NOT A MIGRATION.
-- Must be evaluated after PR #2469's signed-participation candidate and
-- Titus PR #35's exact append-only classroom event carrier.
-- No real actor, issuer, writer, approved Formation edition or live grant.
-- The immutable classroom and assignment authenticity gates remain FALSE.
BEGIN;

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
COMMIT;
