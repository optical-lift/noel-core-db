-- M3.15C: exact own original Enrollment self-read + terminal self-withdraw.
-- Run inside the M3.15B fictional single Enrollment fixture, before rollback.
-- No live data, no new Course, no title/curriculum/classroom exposure.
DO $m315c_acl$
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.shared_course_enrollment_withdrawal_issuances','SELECT')
 OR has_table_privilege('authenticated','atlas.teaching_enrollments','UPDATE')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_enrollment_read_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_enrollment_withdraw_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_enrollment_read_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_enrollment_withdraw_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE
  tgrelid='atlas.shared_course_enrollment_withdrawal_issuances'::regclass
  AND tgname='shared_enrollment_withdrawal_immutable' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'self read/withdraw data-plane ACL is not private and immutable'; END IF;
END $m315c_acl$;

SAVEPOINT m315c_test_one_original;

-- Neither the original author nor the authorized Ledger governor can view
-- the individual learner's private receipt or withdraw on the learner's behalf.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m315c_author_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author read another Person private Enrollment'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   'c7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author withdrew learner Enrollment'; END IF;
END $m315c_author_denied$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m315c_governor_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor read named student private Enrollment'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   'c7666666-6666-4666-8666-666666666662');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor impersonated learner withdrawal'; END IF;
END $m315c_governor_denied$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666662","session_id":"56666666-6666-4666-8666-666666666662"}';
DO $m315c_second_learner_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_read_self_api_v1(
    current_setting('app.fictional_learner_enrollment_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'second learner read someone else Enrollment'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
    current_setting('app.fictional_learner_enrollment_id')::uuid,
    'c7666666-6666-4666-8666-666666666663');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'declining learner withdrew another Enrollment'; END IF;
END $m315c_second_learner_denied$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $m315c_own_bounded_active_read$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_learner_enrollment_read_self_api_v1(
  current_setting('app.fictional_learner_enrollment_id')::uuid);
 IF j->>'contractVersion'<>'shared_learner_enrollment_read_v1'
 OR j->>'enrollmentId'<>current_setting('app.fictional_learner_enrollment_id')
 OR j->>'offeringId'<>current_setting('app.fictional_teacher_offering_id')
 OR j->>'learnerPersonEntityId'<>'f6666666-6666-4666-8666-666666666661'
 OR j->>'enrollmentState'<>'active'
 OR j->>'withdrawnAt' IS NOT NULL
 OR j->>'canParticipate'<>'false' OR j->>'canReadCurriculum'<>'false'
 OR j->>'canTeach'<>'false' OR j ? 'courseTitle' OR j ? 'roster'
 OR j ? 'courseText' OR j ? 'curriculum' OR j ? 'units'
 OR j ? 'otherLearners' OR j ? 'work'
 THEN RAISE EXCEPTION 'learner own Enrollment read leaked rights/others'; END IF;
END $m315c_own_bounded_active_read$;
RESET ROLE;

-- Session ID must be CURRENT. Correct auth user with a forged session
-- cannot read or mutate any Enrollment. A plain user-id is insufficient.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"59999999-9999-4999-8999-999999999999"}';
DO $m315c_expired_session_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_read_self_api_v1(
    current_setting('app.fictional_learner_enrollment_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'session-less learner read original Enrollment'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
    current_setting('app.fictional_learner_enrollment_id')::uuid,
    'c7666666-6666-4666-8666-666666666664');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'session-less learner withdrew original Enrollment'; END IF;
END $m315c_expired_session_denied$;
RESET ROLE;

-- Author rescinds new Enrollment issuance. The learner must nonetheless
-- be able to see their own historic original and exit; no content disclosure.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m315c_author_withholds_future_enrollment$
BEGIN
 PERFORM public.shared_teaching_learner_enrollment_decide_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'c7666666-6666-4666-8666-666666666665','withhold_learner_enrollment');
END $m315c_author_withholds_future_enrollment$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $m315c_learner_exits_withdrawn_scope$
DECLARE a jsonb;b jsonb;j jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_learner_enrollment_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid);
 IF j->>'enrollmentState'<>'active' THEN
  RAISE EXCEPTION 'author revoked permission prevented own history read'; END IF;
 a:=public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   'c7666666-6666-4666-8666-666666666666');
 b:=public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   'c7666666-6666-4666-8666-666666666666');
 IF a->>'contractVersion'<>'shared_learner_enrollment_withdraw_v1'
 OR a->>'enrollmentId'<>current_setting('app.fictional_learner_enrollment_id')
 OR a->>'enrollmentState'<>'withdrawn'
 OR a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'withdrawnAt'<>b->>'withdrawnAt'
 OR a->>'canParticipate'<>'false' OR a->>'canReadCurriculum'<>'false'
 OR a->>'canTeach'<>'false' THEN
  RAISE EXCEPTION 'learner terminal own withdrawal was not immutable/idempotent'; END IF;
 j:=public.shared_teaching_learner_enrollment_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid);
 IF j->>'enrollmentState'<>'withdrawn'
 OR j->>'withdrawnAt' IS NULL OR j->>'withdrawnAt'<>a->>'withdrawnAt' THEN
  RAISE EXCEPTION 'learner lost own permanent withdrawn history'; END IF;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
    current_setting('app.fictional_learner_enrollment_id')::uuid,
    'c7666666-6666-4666-8666-666666666667');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner changed terminal withdrawal receipt'; END IF;
END $m315c_learner_exits_withdrawn_scope$;
RESET ROLE;

DO $m315c_verify_one_original_changed_once$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>1
 OR (SELECT count(*) FROM atlas.shared_course_enrollment_withdrawal_issuances)<>1
 OR NOT EXISTS(
  SELECT 1 FROM atlas.teaching_enrollments e
  JOIN atlas.shared_course_enrollment_withdrawal_issuances w
    ON w.enrollment_id=e.id
  JOIN atlas.shared_course_enrollment_issuances i
    ON i.enrollment_id=e.id
  WHERE e.id=current_setting('app.fictional_learner_enrollment_id')::uuid
   AND e.state='withdrawn' AND e.withdrawn_at=w.withdrawn_at
   AND w.withdrawn_by_person_entity_id=e.person_entity_id
   AND i.person_entity_id=e.person_entity_id
   AND w.issuer_txid=txid_current()
   AND e.person_id IS NULL AND e.enrolled_by_person_id IS NULL
   AND e.enrolled_by_principal_id IS NULL
   AND e.withdrawal_reason IS NULL)
 THEN RAISE EXCEPTION 'terminal withdrawal changed the original Enrollment incorrectly'; END IF;
 BEGIN
  UPDATE atlas.shared_course_enrollment_withdrawal_issuances
   SET issuer_txid=0;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawal receipt could be changed'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.shared_course_enrollment_withdrawal_issuances;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawal receipt could be erased'; END IF;
 denied:=false;
 BEGIN
  UPDATE atlas.teaching_enrollments SET state='active',withdrawn_at=NULL
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'terminal original Enrollment was silently reactivated'; END IF;
 denied:=false;
 BEGIN
  UPDATE atlas.teaching_enrollments SET withdrawal_reason='fabricated'
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn Enrollment was modified outside issued transaction'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.teaching_enrollments
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'original withdrawn Enrollment was deleted'; END IF;
END $m315c_verify_one_original_changed_once$;

ROLLBACK TO SAVEPOINT m315c_test_one_original;
-- M3.15B parent still sees the original ACTIVE Enrollment until own rollback.
