-- M3.15B: protected fictional issuer on SAME historical Enrollment carrier.
-- Called inside M3.15A's currently signed author/governor/two-learner case
-- after a learner independently accepted and BEFORE author later revocation.
-- All accepted rows, provenance and issuance events roll back.
DO $m315b_source_gate$
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_enrollments','INSERT')
 OR has_table_privilege('authenticated','atlas.shared_course_enrollment_issuances','SELECT')
 OR has_table_privilege('authenticated','atlas.shared_course_learner_enrollment_author_decisions','INSERT')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_enrollment_decide_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR (SELECT count(*) FROM pg_trigger WHERE tgname IN
  ('shared_enrollment_author_decision_immutable','shared_enrollment_issuance_immutable')
    AND NOT tgisinternal)<>2
 THEN RAISE EXCEPTION 'Enrollment original-carrier issuance ACL or immutable source missing'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>0 THEN
  RAISE EXCEPTION 'Enrollment source starts with unwanted old enrollment'; END IF;
END $m315b_source_gate$;
SAVEPOINT m315b_one_original_enrollment;

-- A known author invitation and the learner's ACCEPT still cannot enroll.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m315b_no_automatic_enrollment$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'accepted invitation bypassed sixth author scope'; END IF;
END $m315b_no_automatic_enrollment$;
RESET ROLE;

-- Only the original signed Person-author may open an independent Enrollment
-- issuer scope. The author cannot then act as the governor/issuer.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m315b_author_scope$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_learner_enrollment_decide_self_api_v1(
    current_setting('app.fictional_teacher_offering_id')::uuid,
    'b7666666-6666-4666-8666-666666666662','allow_learner_enrollment');
 b:=public.shared_teaching_learner_enrollment_decide_self_api_v1(
    current_setting('app.fictional_teacher_offering_id')::uuid,
    'b7666666-6666-4666-8666-666666666662','allow_learner_enrollment');
 IF a->>'contractVersion'<>'shared_learner_enrollment_author_v1'
 OR a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'canIssueEnrollment'<>'false' OR a->>'canParticipate'<>'false'
 OR a->>'canReadCurriculum'<>'false' THEN
   RAISE EXCEPTION 'author Enrollment scope is not independently bounded';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_decide_self_api_v1(
    current_setting('app.fictional_teacher_offering_id')::uuid,
    'b7666666-6666-4666-8666-666666666662','withhold_learner_enrollment');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'original author could mutate immutable scope'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author impersonated Ledger governor Enrollment issuer'; END IF;
END $m315b_author_scope$;
RESET ROLE;

-- A current separately signed learner may not auto-enroll or self-issue,
-- and a declined invite can never become an Enrollment.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $m315b_learner_cannot_issue$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666663');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner minted own Enrollment without governor'; END IF;
END $m315b_learner_cannot_issue$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m315b_governor_issues_one_original$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_decline_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666664');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor enrolled a learner who declined'; END IF;
 a:=public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 b:=public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 IF a->>'contractVersion'<>'shared_learner_enrollment_issue_v1'
 OR a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'enrollmentId'<>b->>'enrollmentId'
 OR a->>'enrollmentState'<>'active'
 OR a->>'learnerPersonEntityId'<>'f6666666-6666-4666-8666-666666666661'
 OR a->>'canParticipate'<>'false' OR a->>'canReadCurriculum'<>'false'
 OR a->>'canTeach'<>'false' THEN
  RAISE EXCEPTION 'issue receipt was not one original non-class Enrollment'; END IF;
 PERFORM set_config('app.fictional_learner_enrollment_id',a->>'enrollmentId',true);
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666665');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'second new Enrollment for one original invite was minted'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_decline_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege,unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Enrollment issuance request could be reparented'; END IF;
END $m315b_governor_issues_one_original$;
RESET ROLE;

-- Check physical table and immutable exact same-transaction receipt,
-- not just a favorable public API response. No fake legacy Person/Principal.
DO $m315b_original_row_and_guard$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>1
 OR (SELECT count(*) FROM atlas.shared_course_enrollment_issuances)<>1
 OR NOT EXISTS (
  SELECT 1 FROM atlas.teaching_enrollments e
  JOIN atlas.shared_course_enrollment_issuances i ON i.enrollment_id=e.id
  JOIN atlas.shared_course_learner_invitation_offers offer
   ON offer.offer_id=e.shared_learner_offer_id
  WHERE e.id=current_setting('app.fictional_learner_enrollment_id')::uuid
  AND e.offering_id=current_setting('app.fictional_teacher_offering_id')::uuid
  AND e.ledger_id='77777777-7777-4777-8777-777777777777'
  AND e.person_entity_id='f6666666-6666-4666-8666-666666666661'
  AND e.enrolled_by_person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  AND e.person_id IS NULL AND e.enrolled_by_person_id IS NULL
  AND e.enrolled_by_principal_id IS NULL
  AND e.state='active'
  AND e.shared_enrollment_request_id=i.request_id
  AND i.learner_offer_id=offer.offer_id AND i.person_entity_id=e.person_entity_id
  AND i.issuer_txid=txid_current()
 )
 THEN RAISE EXCEPTION 'original Enrollment identity/issuer ledger source is wrong'; END IF;
 -- Faking the source's exact Person and offer in a second direct INSERT
 -- still fails without a newly minted immutable transaction receipt.
 BEGIN
  INSERT INTO atlas.teaching_enrollments(
   ledger_id,offering_id,person_entity_id,enrolled_by_person_entity_id,
   shared_learner_offer_id,shared_enrollment_request_id)
  VALUES('77777777-7777-4777-8777-777777777777',
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'f6666666-6666-4666-8666-666666666661',
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   current_setting('app.fictional_learner_accept_offer_id')::uuid,
   'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'direct forged Enrollment bypassed issue receipt'; END IF;
 denied:=false;
 BEGIN
  UPDATE atlas.teaching_enrollments SET state='withdrawn',withdrawn_at=now()
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'unissued Enrollment withdrawal succeeded'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.teaching_enrollments
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'shared original Enrollment could be deleted'; END IF;
 denied:=false;
 BEGIN
  UPDATE atlas.shared_course_enrollment_issuances SET issuer_txid=0;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Enrollment issue receipt was mutable'; END IF;
END $m315b_original_row_and_guard$;

-- Independent author can withhold Enrollment issuance even after original
-- enrollment exists: history remains, but further/replayed authorization
-- fails until source scope restored. Actual class read remains entirely closed.
SAVEPOINT m315b_author_withholding;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m315b_author_withhold$
BEGIN
 PERFORM public.shared_teaching_learner_enrollment_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'b7666666-6666-4666-8666-666666666666','withhold_learner_enrollment');
END $m315b_author_withhold$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m315b_withheld_prevents_replay$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author scope withdrawal permitted issuance replay'; END IF;
END $m315b_withheld_prevents_replay$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m315b_author_withholding;

-- A withdrawn learner invitation also removes future issuer authority;
-- source history is NOT silently erased/re-written.
SAVEPOINT m315b_withdrawal;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m315b_withdraw_invitation$
DECLARE denied boolean:=false;
BEGIN
 PERFORM public.shared_teaching_learner_withdraw_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid,
  'b7666666-6666-4666-8666-666666666667');
 BEGIN
  PERFORM public.shared_teaching_learner_enrollment_issue_self_api_v1(
    current_setting('app.fictional_learner_accept_offer_id')::uuid,
    'b7666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn learner consent allowed issuance replay'; END IF;
END $m315b_withdraw_invitation$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m315b_withdrawal;

DO $m315b_no_course_or_class_created$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings WHERE operating_proposal_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM atlas.teaching_enrollments)<>1
 OR (SELECT count(*) FROM atlas.shared_course_enrollment_issuances)<>1
 THEN RAISE EXCEPTION 'Enrollment issuance introduced duplicate Course or shadow Enrollment'; END IF;
END $m315b_no_course_or_class_created$;
ROLLBACK TO SAVEPOINT m315b_one_original_enrollment;
-- Existing M3.15A test after this include still sees ZERO Enrollments.
