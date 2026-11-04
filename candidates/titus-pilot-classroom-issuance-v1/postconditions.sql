-- Disposable RiverSong PG17 only; tests source real rules with invented identities.
-- All session/GUC stubs are synthetic and MUST NOT become deployed auth.
DO $security$
BEGIN
 IF has_table_privilege('authenticated',
    'titus.classroom_pilot_assignment_events_v1','SELECT')
  OR has_table_privilege('authenticated',
    'titus.classroom_pilot_offering_link_v1','SELECT')
  OR has_table_privilege('anon',
    'titus.classroom_pilot_assignment_events_v1','INSERT')
 THEN RAISE EXCEPTION 'FAIL: raw issuer source exposed'; END IF;
 IF has_function_privilege('anon',
    'public.titus_classroom_pilot_offer_self_api_v1(uuid,uuid,uuid,text)',
    'EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: anonymous classroom offer allowed'; END IF;
 IF NOT has_function_privilege('authenticated',
    'public.titus_classroom_pilot_accept_self_api_v1(uuid,uuid,uuid,boolean)',
    'EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: signed acceptance transport missing'; END IF;
END;$security$;

SELECT set_config('titus.test_user',
  '00000000-0000-4000-8000-000000000501',false);
SELECT set_config('titus.test_person',
  '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $not_governor$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000202','teacher');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: learner offered teacher seat'; END IF;
END;$not_governor$;
RESET ROLE;

-- A signed current root governor explicitly offers two distinct seats.
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000204',false);
SET ROLE authenticated;
DO $offers$
DECLARE teacher_offer jsonb;learner_offer jsonb;
BEGIN
 teacher_offer:=public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000202','teacher');
 learner_offer:=public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000201','learner');
 IF teacher_offer->>'state'<>'offered'
    OR learner_offer->>'state'<>'offered'
 THEN RAISE EXCEPTION 'FAIL: root issue not acknowledged'; END IF;
 PERFORM set_config('titus.test_teacher_receipt',
   teacher_offer->>'assignmentReceiptId',false);
 PERFORM set_config('titus.test_learner_receipt',
   learner_offer->>'assignmentReceiptId',false);
END;$offers$;
RESET ROLE;

-- A person cannot accept the offer belonging to someone else, nor claim
-- to accept when the required explicit statement is false.
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $wrong_recipient$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_classroom_pilot_accept_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  current_setting('titus.test_teacher_receipt')::uuid,
  NULL,true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: wrong Person accepted teacher offer'; END IF;
 denied:=false;
 BEGIN
 PERFORM public.titus_classroom_pilot_accept_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  current_setting('titus.test_learner_receipt')::uuid,
  '00000000-0000-4000-8000-000000000202',false);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: false acceptance passed'; END IF;
 denied:=false;
 BEGIN
 PERFORM public.titus_classroom_pilot_accept_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  current_setting('titus.test_learner_receipt')::uuid,
  '00000000-0000-4000-8000-000000000202',true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: learner consented before teacher accepted'; END IF;
END;$wrong_recipient$;
RESET ROLE;

SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher_accept$
DECLARE s jsonb; denied boolean:=false;
BEGIN
 s:=public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_teacher_receipt')::uuid,
   NULL,true);
 IF s->>'state'<>'accepted' OR s->>'role'<>'teacher' THEN
   RAISE EXCEPTION 'FAIL: teacher self acceptance incorrect'; END IF;
 -- Teacher has been appointed, but has no student disclosure consent yet.
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
   '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN
   RAISE EXCEPTION 'FAIL: teacher read before learner acceptance'; END IF;
END;$teacher_accept$;
RESET ROLE;

-- Learner explicitly accepts that particular teacher, with a live Offering
-- and active Atlas Enrollment. Only NOW does the authorized exchange open.
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $learner_accept$
DECLARE s jsonb; source_receipt jsonb;denied boolean:=false;
BEGIN
 s:=public.titus_classroom_pilot_accept_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  current_setting('titus.test_learner_receipt')::uuid,
  '00000000-0000-4000-8000-000000000202',true);
 IF s->>'state'<>'accepted' THEN
   RAISE EXCEPTION 'FAIL: learner named consent not accepted'; END IF;
 source_receipt:=public.titus_classroom_authorize_self_api_v1(
  '00000000-0000-4000-8000-000000000100','homework_submission');
 IF source_receipt->>'viewerRole'<>'learner'
    OR source_receipt->>'sourceReceiptId' IS DISTINCT FROM
        current_setting('titus.test_learner_receipt')
 THEN RAISE EXCEPTION 'FAIL: learner source grant not issued'; END IF;
 BEGIN
  PERFORM public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_feedback');
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_feedback') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: learner got teacher review right'; END IF;
END;$learner_accept$;
RESET ROLE;

SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher_authority$
DECLARE r jsonb;
BEGIN
 r:=public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_feedback');
 IF r->>'viewerRole'<>'teacher' OR
    r->>'sourceReceiptId' IS DISTINCT FROM
      current_setting('titus.test_teacher_receipt')
 THEN RAISE EXCEPTION 'FAIL: teacher accepted but source did not authorize'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000101','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: unrelated classroom access'; END IF;
END;$teacher_authority$;
RESET ROLE;

-- Source's independent writer custody must still refuse the first original
-- before an explicit scratch-test override.
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $closed_writer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_append_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   jsonb_build_object(
    'operationId','00000000-0000-4000-8000-000000000401',
    'expectedVersion',0,'kind','homework_submission','partRef','homework',
    'body','I observed a leaning leaf.','replyToEventId',NULL));
 EXCEPTION WHEN OTHERS THEN
   denied:=position('no authorized classroom writer' in SQLERRM)>0;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: released writer gate open'; END IF;
END;$closed_writer$;
RESET ROLE;

-- Only the isolated PG17 fixture can enable the independent event writer.
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT true$$;

SET ROLE authenticated;
DO $original$
DECLARE s jsonb;
BEGIN
 s:=public.titus_classroom_append_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  jsonb_build_object(
    'operationId','00000000-0000-4000-8000-000000000401',
    'expectedVersion',0,'kind','homework_submission','partRef','homework',
    'body','I observed a leaning leaf.','replyToEventId',NULL));
 IF s->>'replay'<>'false' OR
    (s->'snapshot'->>'version')::integer<>1 OR
    s->'snapshot'->'events'->0->>'body'<>'I observed a leaning leaf.'
 THEN RAISE EXCEPTION 'FAIL: source-issued learner original'; END IF;
END;$original$;
RESET ROLE;

SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher_reads$
DECLARE s jsonb;
BEGIN
 s:=public.titus_classroom_read_self_api_v1(
  '00000000-0000-4000-8000-000000000100');
 IF (s->>'version')::integer<>1 OR
  s->'events'->0->>'body'<>'I observed a leaning leaf.'
 THEN RAISE EXCEPTION 'FAIL: teacher cannot read consented original'; END IF;
END;$teacher_reads$;
RESET ROLE;

-- Learner can withdraw, instantly closing THEIR access and teacher
-- disclosure without erasing the source original event.
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $withdrawn$
DECLARE r jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_classroom_pilot_withdraw_self_api_v1(
  '00000000-0000-4000-8000-000000000100',
  current_setting('titus.test_learner_receipt')::uuid);
 IF r->>'state'<>'withdrawn' THEN
   RAISE EXCEPTION 'FAIL: learner cannot withdraw'; END IF;
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
   '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: withdrawn learner can still read'; END IF;
END;$withdrawn$;
RESET ROLE;
SELECT set_config('titus.test_person',
 '00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher_closed$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_read_self_api_v1(
   '00000000-0000-4000-8000-000000000100');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN
   RAISE EXCEPTION 'FAIL: teacher retains withdrawn student disclosure'; END IF;
END;$teacher_closed$;
RESET ROLE;

-- The true underlying source original remains immutable after withdrawal.
DO $history$
DECLARE original text;
BEGIN
 SELECT e.body INTO original FROM titus.classroom_events_v1 e
 WHERE e.thread_id='00000000-0000-4000-8000-000000000100'
 AND e.sequence_no=1;
 IF original IS DISTINCT FROM 'I observed a leaning leaf.'
 THEN RAISE EXCEPTION 'FAIL: original lost after withdrawal'; END IF;
 IF EXISTS(SELECT 1 FROM titus.classroom_events_v1 e
  WHERE e.thread_id='00000000-0000-4000-8000-000000000101')
 THEN RAISE EXCEPTION 'FAIL: other classroom received an event'; END IF;
END;$history$;

-- Restore default-closed writer before the isolated test database is removed.
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
DO $final$
BEGIN
 IF titus.classroom_authority_gate_v1() THEN
    RAISE EXCEPTION 'FAIL: event source gate not restored closed'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM titus.classroom_pilot_assignment_events_v1 e
   WHERE e.event_kind='withdrawn') THEN
    RAISE EXCEPTION 'FAIL: source withdrawal not preserved'; END IF;
END;$final$;
