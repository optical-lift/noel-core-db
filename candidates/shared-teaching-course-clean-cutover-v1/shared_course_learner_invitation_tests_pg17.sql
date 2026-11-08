-- M3.15A: held fictional, separately signed CANONICAL Reality learner offers.
-- Executed inside the teacher source's already-open fictional Course Offering.
-- Every test is rolled back. No Enrollment row, Class or curriculum access.
DO $learner_surface_acl$
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.shared_course_learner_invitation_offers','SELECT')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_learner_invitation_responses','INSERT')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_learner_invitation_author_decisions','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_offer_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_offer_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_offer_read_self_api_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'learner source confidentiality or signed API contract failed';
 END IF;
 IF (SELECT count(*) FROM pg_trigger
     WHERE tgname IN ('shared_learner_author_decision_immutable',
       'shared_learner_offer_immutable','shared_learner_response_immutable',
       'shared_learner_withdrawal_immutable') AND NOT tgisinternal)<>4
 THEN RAISE EXCEPTION 'learner receipts not immutable'; END IF;
END $learner_surface_acl$;

SAVEPOINT fictional_learner_consent;
-- These are independently signed test People, NOT Atlas People/Principals.
INSERT INTO auth.users(id) VALUES
 ('d6666666-6666-4666-8666-666666666661'),
 ('d6666666-6666-4666-8666-666666666662');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('56666666-6666-4666-8666-666666666661',
  'd6666666-6666-4666-8666-666666666661',NULL),
 ('56666666-6666-4666-8666-666666666662',
  'd6666666-6666-4666-8666-666666666662',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('f6666666-6666-4666-8666-666666666661','person','fictional-learner-one'),
 ('f6666666-6666-4666-8666-666666666662','person','fictional-learner-two');
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('d6666666-6666-4666-8666-666666666661',
  'f6666666-6666-4666-8666-666666666661','active'),
 ('d6666666-6666-4666-8666-666666666662',
  'f6666666-6666-4666-8666-666666666662','active');

-- Being a root governor is not sufficient to invite without independent
-- current Course-author authorization for this exact Offering.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_no_unapproved_learner_offer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'f6666666-6666-4666-8666-666666666661',
   'e6666666-6666-4666-8666-666666666661');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor invited learner without author authorization'; END IF;
END $governor_no_unapproved_learner_offer$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_learner_scope$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_learner_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'e6666666-6666-4666-8666-666666666662','allow_learner_invitation');
 b:=public.shared_teaching_learner_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'e6666666-6666-4666-8666-666666666662','allow_learner_invitation');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
  OR a->>'canEnroll'<>'false' THEN
  RAISE EXCEPTION 'author invitation scope was not original and idempotent';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_learner_invitation_decide_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'e6666666-6666-4666-8666-666666666662','withhold_learner_invitation');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author could change already recorded decision'; END IF;
END $author_learner_scope$;
-- The author has no governing power to make another Person's invitation.
DO $author_cannot_invite_learner$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'f6666666-6666-4666-8666-666666666661',
   'e6666666-6666-4666-8666-666666666663');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Course author impersonated learner-inviting governor'; END IF;
END $author_cannot_invite_learner$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_learner_invitations$
DECLARE a jsonb;b jsonb;c jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_learner_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'f6666666-6666-4666-8666-666666666661',
  'e6666666-6666-4666-8666-666666666663');
 b:=public.shared_teaching_learner_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'f6666666-6666-4666-8666-666666666661',
  'e6666666-6666-4666-8666-666666666663');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'offerId'<>b->>'offerId' OR a->>'canEnroll'<>'false'
 OR a->>'canReadCurriculum'<>'false' OR a->>'canParticipate'<>'false'
 OR a->>'enrollmentState'<>'not_enrolled'
 OR a ? 'courseTitle' OR a ? 'roster' OR a ? 'curriculum' THEN
  RAISE EXCEPTION 'learner offer claimed enrollment or leaked private details';
 END IF;
 PERFORM set_config('app.fictional_learner_accept_offer_id',a->>'offerId',true);
 BEGIN
  PERFORM public.shared_teaching_learner_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'f6666666-6666-4666-8666-666666666661',
   'e6666666-6666-4666-8666-666666666664');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'second invitation to same learner minted'; END IF;
 c:=public.shared_teaching_learner_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'f6666666-6666-4666-8666-666666666662',
  'e6666666-6666-4666-8666-666666666665');
 PERFORM set_config('app.fictional_learner_decline_offer_id',c->>'offerId',true);
END $governor_learner_invitations$;
RESET ROLE;

-- Each learner may see only their own offered Course title and time range.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666662","session_id":"56666666-6666-4666-8666-666666666662"}';
DO $second_learner_denies_first_private_offer$
DECLARE denied boolean:=false;j jsonb;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_offer_read_self_api_v1(
   current_setting('app.fictional_learner_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'other learner could read a private invitation'; END IF;
 j:=public.shared_teaching_learner_respond_self_api_v1(
  current_setting('app.fictional_learner_decline_offer_id')::uuid,
  'e6666666-6666-4666-8666-666666666666','decline');
 IF j->>'decision'<>'decline' OR j->>'consentAccepted'<>'false'
 OR j->>'canEnroll'<>'false' THEN
  RAISE EXCEPTION 'own signed learner decline was not honored';
 END IF;
END $second_learner_denies_first_private_offer$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $first_learner_independent_acceptance$
DECLARE j jsonb;a jsonb;b jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_learner_offer_read_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid);
 IF j->>'courseTitle'<>'Founding Course definition'
 OR j->>'state'<>'offered' OR j->>'canParticipate'<>'false'
 OR j->>'canReadCurriculum'<>'false' OR j->>'canEnroll'<>'false'
 OR j->>'enrollmentState'<>'not_enrolled'
 OR j ? 'curriculum' OR j ? 'units' OR j ? 'roster' THEN
  RAISE EXCEPTION 'learner invitation read exceeded approved scope';
 END IF;
 a:=public.shared_teaching_learner_respond_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid,
  'e6666666-6666-4666-8666-666666666667','accept');
 b:=public.shared_teaching_learner_respond_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid,
  'e6666666-6666-4666-8666-666666666667','accept');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'consentAccepted'<>'true' OR a->>'canParticipate'<>'false'
 OR a->>'canReadCurriculum'<>'false' OR a->>'canEnroll'<>'false'
 OR a->>'enrollmentState'<>'not_enrolled' THEN
  RAISE EXCEPTION 'independent learner consent wrongly minted class/enrollment rights';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_learner_respond_self_api_v1(
   current_setting('app.fictional_learner_accept_offer_id')::uuid,
   'e6666666-6666-4666-8666-666666666668','decline');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner response was not terminal'; END IF;
END $first_learner_independent_acceptance$;
RESET ROLE;

-- The consent original must not change Enrollment, Course or teacher status.
DO $learner_consent_no_enrollment$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.shared_course_learner_invitation_offers)<>2
 OR (SELECT count(*) FROM atlas.shared_course_learner_invitation_responses)<>2
 THEN RAISE EXCEPTION 'learner consent incorrectly created an Enrollment'; END IF;
 BEGIN UPDATE atlas.shared_course_learner_invitation_responses SET decision='decline';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner original consent could be rewritten'; END IF;
END $learner_consent_no_enrollment$;

-- Bounded M3.15B Enrollment issuer test, rolled back to no Enrollment.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/shared_course_enrollment_issuance_tests_pg17.sql

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_revokes_learner_disclosure$
BEGIN
 PERFORM public.shared_teaching_learner_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'e6666666-6666-4666-8666-666666666669','withhold_learner_invitation');
END $author_revokes_learner_disclosure$;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $learner_cannot_reuse_withdrawn_permission$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_offer_read_self_api_v1(
   current_setting('app.fictional_learner_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author withdrawal still allowed new learner read'; END IF;
END $learner_cannot_reuse_withdrawn_permission$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_restore_learner_disclosure$
BEGIN
 PERFORM public.shared_teaching_learner_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'e6666666-6666-4666-8666-66666666666a','allow_learner_invitation');
END $author_restore_learner_disclosure$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_revokes_learner_invitation$
DECLARE j jsonb;k jsonb;
BEGIN
 j:=public.shared_teaching_learner_withdraw_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid,
  'e6666666-6666-4666-8666-66666666666b');
 k:=public.shared_teaching_learner_withdraw_self_api_v1(
  current_setting('app.fictional_learner_accept_offer_id')::uuid,
  'e6666666-6666-4666-8666-66666666666b');
 IF j->>'alreadyExists'<>'false' OR k->>'alreadyExists'<>'true'
 OR j->>'consentAccepted'<>'false' THEN
  RAISE EXCEPTION 'governor learner invitation withdrawal not immutable';
 END IF;
END $governor_revokes_learner_invitation$;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $withdrawn_invitation_not_current$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_offer_read_self_api_v1(
   current_setting('app.fictional_learner_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor withdrawn learner consent still active'; END IF;
END $withdrawn_invitation_not_current$;
RESET ROLE;
DO $final_learner_no_enrollment$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>0
 OR (SELECT count(*) FROM atlas.shared_course_learner_invitation_responses WHERE decision='accept')<>1
 OR (SELECT count(*) FROM atlas.shared_course_learner_invitation_withdrawals)<>1
 THEN RAISE EXCEPTION 'historical consent or no-enrollment guarantee failed'; END IF;
END $final_learner_no_enrollment$;
ROLLBACK TO SAVEPOINT fictional_learner_consent;
