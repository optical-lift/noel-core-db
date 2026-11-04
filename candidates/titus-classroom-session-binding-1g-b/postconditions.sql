-- Build 1G-B: source-shaped session-table validation on disposable PG17.
-- request.jwt.claims below is a synthetic, UNVERIFIED PostgREST claims GUC.
-- These tests DO NOT assert GoTrue signing or independent human consent.
DO $acl$
BEGIN
 IF has_table_privilege('authenticated','auth.sessions','SELECT')
 OR has_table_privilege('authenticated','reality.auth_person_bindings','SELECT')
 OR has_table_privilege('authenticated',
 'titus.classroom_pilot_assignment_events_v1','SELECT')
 OR has_function_privilege('anon',
 'public.titus_classroom_pilot_accept_self_api_v1(uuid,uuid,uuid,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: session/Person source or participation exposed'; END IF;
 IF titus.classroom_authority_gate_v1() THEN
   RAISE EXCEPTION 'FAIL: source writer already open'; END IF;
END;$acl$;

-- A caller claiming to be a governor but without a matching live session
-- must fail. Even a present session belonging to someone else is not enough.
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000501","session_id":"00000000-0000-4000-8000-000000000759"}',false);
SET ROLE authenticated;
DO $no_session$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000202','teacher');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: unbacked claims obtained governor offer'; END IF;
END;$no_session$;
RESET ROLE;

SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000501","session_id":"00000000-0000-4000-8000-000000000752"}',false);
SET ROLE authenticated;
DO $wrong_owner$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000202','teacher');
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: unrelated session obtained governor right'; END IF;
END;$wrong_owner$;
RESET ROLE;

-- Current, session-backed governor can offer two seats in the exact
-- existing Teaching Offering, not create a free-standing classroom.
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000501","session_id":"00000000-0000-4000-8000-000000000751"}',false);
SET ROLE authenticated;
DO $offers$
DECLARE a jsonb;b jsonb;
BEGIN
 a:=public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000202','teacher');
 b:=public.titus_classroom_pilot_offer_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   '00000000-0000-4000-8000-000000000610',
   '00000000-0000-4000-8000-000000000201','learner');
 IF a->>'state'<>'offered' OR b->>'state'<>'offered' THEN
  RAISE EXCEPTION 'FAIL: session-backed governor offer'; END IF;
 PERFORM set_config('titus.test_teacher_receipt',a->>'assignmentReceiptId',false);
 PERFORM set_config('titus.test_learner_receipt',b->>'assignmentReceiptId',false);
END;$offers$;
RESET ROLE;

-- Outsider's live session cannot claim teacher invitation.
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000504","session_id":"00000000-0000-4000-8000-000000000754"}',false);
SET ROLE authenticated;
DO $outsider$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_teacher_receipt')::uuid,NULL,true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: unrelated Person accepted teacher seat'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: outsider read classroom'; END IF;
END;$outsider$;
RESET ROLE;

-- A valid subject with the *learner's* session_id cannot accept teacher.
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000502","session_id":"00000000-0000-4000-8000-000000000753"}',false);
SET ROLE authenticated;
DO $mismatch$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_teacher_receipt')::uuid,NULL,true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: mismatch session impersonated teacher'; END IF;
END;$mismatch$;
RESET ROLE;

-- Expiration must be checked afresh at the database, not via old Titus
-- authorize receipts or browser state.
UPDATE auth.sessions SET not_after=now()-interval '1 day'
 WHERE id='00000000-0000-4000-8000-000000000752';
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000502","session_id":"00000000-0000-4000-8000-000000000752"}',false);
SET ROLE authenticated;
DO $expired$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_teacher_receipt')::uuid,NULL,true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: expired session accepted teacher'; END IF;
END;$expired$;
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 day'
 WHERE id='00000000-0000-4000-8000-000000000752';

-- The recipient acts in their own current session. Teacher acceptance
-- still cannot disclose a response until the enrolled learner consents.
SET ROLE authenticated;
DO $teacher_accept$
DECLARE s jsonb;
BEGIN
 s:=public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_teacher_receipt')::uuid,NULL,true);
 IF s->>'state'<>'accepted' OR s->>'role'<>'teacher' THEN
  RAISE EXCEPTION 'FAIL: teacher self-accept'; END IF;
END;$teacher_accept$;
DO $teacher_cannot_read$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: no learner consent but teacher read'; END IF;
END;$teacher_cannot_read$;
RESET ROLE;

-- Learner cannot name another teacher, or omit their explicit acceptance.
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000503","session_id":"00000000-0000-4000-8000-000000000753"}',false);
SET ROLE authenticated;
DO $wrong_teacher$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_learner_receipt')::uuid,
   '00000000-0000-4000-8000-000000000203',true);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: unappointed reviewer accepted'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_learner_receipt')::uuid,
   '00000000-0000-4000-8000-000000000202',false);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: false learner consent accepted'; END IF;
END;$wrong_teacher$;
RESET ROLE;

-- The exact enrolled learner now makes an affirmative source-state change.
SET ROLE authenticated;
DO $learner_accept$
DECLARE s jsonb;
BEGIN
 s:=public.titus_classroom_pilot_accept_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_learner_receipt')::uuid,
   '00000000-0000-4000-8000-000000000202',true);
 IF s->>'state'<>'accepted' OR s->>'role'<>'learner' THEN
  RAISE EXCEPTION 'FAIL: learner self-accept'; END IF;
END;$learner_accept$;
DO $learner_read$
DECLARE result jsonb;
BEGIN
 result:=public.titus_classroom_authorize_self_api_v1(
  '00000000-0000-4000-8000-000000000100','homework_submission');
 IF result->>'viewerPersonId'<>'00000000-0000-4000-8000-000000000201'
 THEN RAISE EXCEPTION 'FAIL: current Person not learner'; END IF;
END;$learner_read$;
RESET ROLE;

-- Retire a current binding: same signed claims must instantly lose access.
UPDATE reality.auth_person_bindings SET retired_at=clock_timestamp()
 WHERE auth_user_id='00000000-0000-4000-8000-000000000503';
SET ROLE authenticated;
DO $retired_binding$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: retired binding still authorizes'; END IF;
END;$retired_binding$;
RESET ROLE;
UPDATE reality.auth_person_bindings SET retired_at=NULL
 WHERE auth_user_id='00000000-0000-4000-8000-000000000503';

-- Unconfirmed email, anonymous account, and banned user are never a
-- qualifying Atlas signed Person even if sessions and binding remain.
UPDATE auth.users SET email_confirmed_at=NULL
 WHERE id='00000000-0000-4000-8000-000000000503';
SET ROLE authenticated;
DO $unconfirmed$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: unconfirmed user obtained read'; END IF;
END;$unconfirmed$;
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=now(),is_anonymous=true
 WHERE id='00000000-0000-4000-8000-000000000503';
SET ROLE authenticated;
DO $anonymous$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: anonymous user obtained read'; END IF;
END;$anonymous$;
RESET ROLE;
UPDATE auth.users SET is_anonymous=false,banned_until=now()+interval '1 day'
 WHERE id='00000000-0000-4000-8000-000000000503';
SET ROLE authenticated;
DO $banned$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: banned user obtained read'; END IF;
END;$banned$;
RESET ROLE;
UPDATE auth.users SET banned_until=NULL
 WHERE id='00000000-0000-4000-8000-000000000503';

-- Revoke the learner's Auth session row; even previously accepted
-- participation cannot create a right without the live signed session.
DELETE FROM auth.sessions WHERE id='00000000-0000-4000-8000-000000000753';
SET ROLE authenticated;
DO $revoked_session$
DECLARE denied boolean:=false;
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: revoked learner session read'; END IF;
 BEGIN
  PERFORM public.titus_classroom_pilot_withdraw_self_api_v1(
   '00000000-0000-4000-8000-000000000100',
   current_setting('titus.test_learner_receipt')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=(SQLSTATE='42501'); END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: revoked session mutated consent'; END IF;
END;$revoked_session$;
RESET ROLE;
INSERT INTO auth.sessions VALUES(
 '00000000-0000-4000-8000-000000000753',
 '00000000-0000-4000-8000-000000000503',now()+interval '1 day');

-- Revoking the governing root authority must suspend both sides even if
-- both human-like fixture seats were previously accepted.
UPDATE atlas.principal_ledger_authorities SET status='withdrawn'
 WHERE principal_id='00000000-0000-4000-8000-000000000630';
SET ROLE authenticated;
DO $no_governor_authority$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: inactive governor kept classroom authorization'; END IF;
END;$no_governor_authority$;
RESET ROLE;
UPDATE atlas.principal_ledger_authorities SET status='active'
 WHERE principal_id='00000000-0000-4000-8000-000000000630';

-- A fresh valid session can withdraw, closing teacher disclosure too.
SET ROLE authenticated;
DO $withdraw$
DECLARE r jsonb;
BEGIN
 r:=public.titus_classroom_pilot_withdraw_self_api_v1(
 '00000000-0000-4000-8000-000000000100',
 current_setting('titus.test_learner_receipt')::uuid);
 IF r->>'state'<>'withdrawn' THEN
  RAISE EXCEPTION 'FAIL: valid learner cannot withdraw'; END IF;
END;$withdraw$;
RESET ROLE;
SELECT set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-000000000502","session_id":"00000000-0000-4000-8000-000000000752"}',false);
SET ROLE authenticated;
DO $reviewer_revoked$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
  '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: teacher disclosure persisted after withdrawal'; END IF;
END;$reviewer_revoked$;
RESET ROLE;
DO $final$
BEGIN
 IF titus.classroom_authority_gate_v1() THEN
  RAISE EXCEPTION 'FAIL: test opened source writer gate'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM titus.classroom_pilot_assignment_events_v1
  WHERE event_kind='withdrawn' AND actor_person_entity_id=
   '00000000-0000-4000-8000-000000000201')
 THEN RAISE EXCEPTION 'FAIL: withdrawal original not preserved'; END IF;
END;$final$;
