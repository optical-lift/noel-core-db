-- DISPOSABLE RIVERSONG PG17 ONLY. Synthetic signed-session GUCs are NOT auth.
-- Actual event core from frozen Titus PR #35 + Noel issuer from PR #2469.
INSERT INTO titus.classroom_pilot_participation_v1(
  thread_id,person_entity_id,actor_role,assignment_state,
  assignment_receipt_id,issued_by_person_entity_id,effective_at
) VALUES
 ('00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000201','learner','active',
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes'),
 ('00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000202','teacher','active',
  '00000000-0000-4000-8000-000000000302',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes'),
 ('00000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000203','learner','active',
  '00000000-0000-4000-8000-000000000303',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes');
INSERT INTO titus.classroom_pilot_parts_v1 VALUES
 ('00000000-0000-4000-8000-000000000100','class'),
 ('00000000-0000-4000-8000-000000000100','homework'),
 ('00000000-0000-4000-8000-000000000100','block:reading-1'),
 ('00000000-0000-4000-8000-000000000102','class'),
 ('00000000-0000-4000-8000-000000000102','homework');

DO $privileges$
BEGIN
 IF has_table_privilege('authenticated','titus.classroom_events_v1','SELECT')
 OR has_table_privilege('authenticated','titus.classroom_pilot_participation_v1','SELECT')
 OR has_table_privilege('anon','titus.classroom_events_v1','SELECT') THEN
   RAISE EXCEPTION 'FAIL: browser direct data access'; END IF;
 IF has_function_privilege('anon',
    'public.titus_classroom_read_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
    'public.titus_classroom_append_self_api_v1(uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anonymous classroom source RPC'; END IF;
 IF NOT has_function_privilege('authenticated',
    'public.titus_classroom_read_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
    'public.titus_classroom_append_self_api_v1(uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: no signed API transport'; END IF;
END;
$privileges$;

SELECT set_config('titus.test_user',
  '00000000-0000-4000-8000-000000000501',false);
SELECT set_config('titus.test_person',
  '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $hard_false$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
    '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN
  denied:=(SQLSTATE='42501');
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'FAIL: unauthorized reader opened with issuer false'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(
    '00000000-0000-4000-8000-000000000100',
    jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000401',
      'expectedVersion',0,'kind','homework_submission','partRef','homework',
      'body','A first original','replyToEventId',NULL));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501');
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'FAIL: unauthorized writer opened with issuer false'; END IF;
END;
$hard_false$;
RESET ROLE;

-- The following is an explicitly UNSAFE test-only issuer override.
-- A real database must never replace the source issuer with this expression.
CREATE OR REPLACE FUNCTION titus.classroom_pilot_assignment_issued_v1(
 p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,
 p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$
 SELECT p_thread_id='00000000-0000-4000-8000-000000000100'::uuid
 AND (
  (p_person_entity_id='00000000-0000-4000-8000-000000000201'::uuid
   AND p_actor_role='learner'
   AND p_assignment_receipt_id='00000000-0000-4000-8000-000000000301'::uuid)
  OR
  (p_person_entity_id='00000000-0000-4000-8000-000000000202'::uuid
   AND p_actor_role='teacher'
   AND p_assignment_receipt_id='00000000-0000-4000-8000-000000000302'::uuid)
 )$$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_assignment_issued_v1(
 uuid,uuid,text,uuid) FROM PUBLIC;

SET ROLE authenticated;
DO $writer_gate$
DECLARE s jsonb;denied boolean:=false;
BEGIN
 s:=public.titus_classroom_read_self_api_v1(
    '00000000-0000-4000-8000-000000000100');
 IF (s->>'version')::integer<>0 OR s->>'homeworkState'<>'not_started'
   OR jsonb_array_length(s->'events')<>0 THEN
    RAISE EXCEPTION 'FAIL: empty classroom source projection wrong'; END IF;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(
    '00000000-0000-4000-8000-000000000100',
    jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000401',
      'expectedVersion',0,'kind','homework_submission','partRef','homework',
      'body','First original','replyToEventId',NULL));
 EXCEPTION WHEN OTHERS THEN
   denied:=position('no authorized classroom writer' in SQLERRM)>0;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: event source gate open'; END IF;
END;$writer_gate$;
RESET ROLE;

-- Second UNSAFE test-only override. It is limited to a scratch PostgreSQL
-- cluster and restored to hard false before end-of-proof.
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT true$$;

SET ROLE authenticated;
DO $complete$
DECLARE
  t uuid:='00000000-0000-4000-8000-000000000100';
  a jsonb;b jsonb;c jsonb;d jsonb;e jsonb;f jsonb;
  answer uuid;feedback uuid;revision uuid;last_review uuid;
  original text:=E'O''Reilly observed the leaning stem.\nCause is not established.';
  cmd jsonb;
  denied boolean;
BEGIN
 PERFORM set_config('titus.test_person',
   '00000000-0000-4000-8000-000000000201',false);

 cmd:=jsonb_build_object(
  'operationId','00000000-0000-4000-8000-000000000401',
  'expectedVersion',0,'kind','homework_submission','partRef','homework',
  'body',original,'replyToEventId',NULL);
 a:=public.titus_classroom_append_self_api_v1(t,cmd);
 answer:=(a->>'eventId')::uuid;
 IF a->>'replay'<>'false' OR (a->'snapshot'->>'version')::integer<>1
 OR a->'snapshot'->>'homeworkState'<>'submitted'
 OR a->'snapshot'->'events'->0->>'body'<>original THEN
   RAISE EXCEPTION 'FAIL: initial original not preserved'; END IF;

 b:=public.titus_classroom_append_self_api_v1(t,cmd);
 IF b->>'replay'<>'true' OR b->>'eventId'<>answer::text
 OR (b->'snapshot'->>'version')::integer<>1 THEN
   RAISE EXCEPTION 'FAIL: idempotent replay duplicate'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(t,
    cmd||jsonb_build_object('body','forged replacement'));
 EXCEPTION WHEN OTHERS THEN
   denied:=position('Classroom operation conflict' in SQLERRM)>0;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: mutated retry accepted'; END IF;

 -- Signed Person is required by the source; a client cannot choose "teacher".
 PERFORM set_config('titus.test_person',
   '00000000-0000-4000-8000-000000000202',false);
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000409',
      'expectedVersion',1,'kind','homework_submission','partRef','homework',
      'body','pretend teacher is learner','replyToEventId',NULL));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501');
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: teacher submitted as learner'; END IF;

 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000410',
      'expectedVersion',0,'kind','discussion_post','partRef','class',
      'body','stale teacher note','replyToEventId',answer));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='40001');
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: stale version accepted'; END IF;

 b:=public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000402',
      'expectedVersion',1,'kind','discussion_post','partRef','class',
      'body','What did you actually observe?','replyToEventId',answer));
 IF (b->'snapshot'->>'version')::integer<>2 THEN
   RAISE EXCEPTION 'FAIL: discussion event not appended'; END IF;

 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000411',
      'expectedVersion',2,'kind','homework_feedback','partRef','homework',
      'body','review another thread','replyToEventId',
      '00000000-0000-4000-8000-000000000499',
      'disposition','reviewed'));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='22023');
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: wrong-parent review accepted'; END IF;

 c:=public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000403',
      'expectedVersion',2,'kind','homework_feedback','partRef','homework',
      'body','Please separate observation from inferred cause.',
      'replyToEventId',answer,'disposition','needs_revision'));
 feedback:=(c->>'eventId')::uuid;
 IF c->'snapshot'->>'homeworkState'<>'needs_revision' THEN
   RAISE EXCEPTION 'FAIL: feedback status not returned'; END IF;

 PERFORM set_config('titus.test_person',
   '00000000-0000-4000-8000-000000000201',false);
 d:=public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000404',
      'expectedVersion',3,'kind','homework_submission','partRef','homework',
      'body','I saw leaning; the light explanation needs another test.',
      'replyToEventId',feedback));
 revision:=(d->>'eventId')::uuid;
 IF d->'snapshot'->'events'->0->>'body'<>original
 OR (d->'snapshot'->>'version')::integer<>4 THEN
   RAISE EXCEPTION 'FAIL: revision overwrote original'; END IF;

 PERFORM set_config('titus.test_person',
   '00000000-0000-4000-8000-000000000202',false);
 e:=public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000405',
      'expectedVersion',4,'kind','homework_feedback','partRef','homework',
      'body','Reviewed, not graded.','replyToEventId',revision,
      'disposition','reviewed'));
 last_review:=(e->>'eventId')::uuid;
 IF e->'snapshot'->>'homeworkState'<>'reviewed' THEN
   RAISE EXCEPTION 'FAIL: final review state not returned'; END IF;

 PERFORM set_config('titus.test_person',
   '00000000-0000-4000-8000-000000000201',false);
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(t,
    jsonb_build_object('operationId',
       '00000000-0000-4000-8000-000000000412',
       'expectedVersion',5,'kind','homework_submission','partRef','homework',
       'body','cannot overwrite reviewed work','replyToEventId',last_review));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501');
 END;
 IF NOT denied THEN
   RAISE EXCEPTION 'FAIL: reviewed homework improperly reopened'; END IF;

 f:=public.titus_classroom_append_self_api_v1(t,
   jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000406',
      'expectedVersion',5,'kind','discussion_post','partRef','block:reading-1',
      'body','Can we test the observation in a new example?',
      'replyToEventId',last_review));
 IF (f->'snapshot'->>'version')::integer<>6
 OR f->'snapshot'->>'homeworkState'<>'reviewed'
 OR jsonb_array_length(f->'snapshot'->'events')<>6 THEN
   RAISE EXCEPTION 'FAIL: conversation after review was not persistent'; END IF;
END;$complete$;
RESET ROLE;

-- The source reader sees one canonical history for both current members.
DO $physical$
DECLARE t uuid:='00000000-0000-4000-8000-000000000100';
BEGIN
 IF (SELECT count(*) FROM titus.classroom_events_v1 e
   WHERE e.thread_id=t)<>6 THEN
    RAISE EXCEPTION 'FAIL: 6-event source history missing'; END IF;
 IF (SELECT body FROM titus.classroom_events_v1
   WHERE thread_id=t AND sequence_no=1)
   IS DISTINCT FROM E'O''Reilly observed the leaning stem.\nCause is not established.'
 THEN RAISE EXCEPTION 'FAIL: original was rewritten'; END IF;
 IF (SELECT count(*) FROM titus.classroom_events_v1 e
   WHERE e.thread_id='00000000-0000-4000-8000-000000000101')<>0 THEN
    RAISE EXCEPTION 'FAIL: foreign classroom had events'; END IF;
END;$physical$;

SELECT set_config('titus.test_person',
  '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher_read$
DECLARE s jsonb;
BEGIN
 s:=public.titus_classroom_read_self_api_v1(
   '00000000-0000-4000-8000-000000000100');
 IF s->>'homeworkState'<>'reviewed'
    OR (s->>'version')::integer<>6
    OR s->'events'->0->>'body' IS NULL THEN
    RAISE EXCEPTION 'FAIL: teacher cannot recover canonical history'; END IF;
END;$teacher_read$;
RESET ROLE;

-- Any unrelated Person, wrong class or absent signed session is denied.
SELECT set_config('titus.test_person',
  '00000000-0000-4000-8000-000000000203',false);
SET ROLE authenticated;
DO $outsider$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
    '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: outsider read'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
    '00000000-0000-4000-8000-000000000102');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: approved edition access inferred'; END IF;
END;$outsider$;
RESET ROLE;

-- An authentic-looking assignment that has been revoked is not a read grant.
UPDATE titus.classroom_pilot_participation_v1
SET assignment_state='revoked',withdrawn_at=now()
WHERE thread_id='00000000-0000-4000-8000-000000000100'
 AND person_entity_id='00000000-0000-4000-8000-000000000202';
SELECT set_config('titus.test_person',
  '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
    '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: revoked participant read'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(
    '00000000-0000-4000-8000-000000000100',
    jsonb_build_object('operationId',
      '00000000-0000-4000-8000-000000000413',
      'expectedVersion',6,'kind','discussion_post','partRef','class',
      'body','revoked teacher must not write','replyToEventId',NULL));
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: revoked participant wrote'; END IF;
END;$revoked$;
RESET ROLE;

-- Even with live-looking participation, source gates return to false.
CREATE OR REPLACE FUNCTION titus.classroom_pilot_assignment_issued_v1(
 p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,
 p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
DO $closed$
BEGIN
 IF titus.classroom_pilot_assignment_issued_v1(
  '00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000201','learner',
  '00000000-0000-4000-8000-000000000301')
 OR titus.classroom_authority_gate_v1() THEN
   RAISE EXCEPTION 'FAIL: test left authority gate open'; END IF;
END;$closed$;
