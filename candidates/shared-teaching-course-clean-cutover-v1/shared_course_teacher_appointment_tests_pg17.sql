-- HELD M3.14: isolated PG17 actual SQL source issuer + separate signed
-- fictional teacher, author and institution, all rolled back. No learner.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/shared_course_teacher_appointment_candidate.sql
-- M3.15A same-root learner consent source. Issuer stays closed to Enrollment.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/shared_course_learner_invitation_candidate.sql

DO $teacher_surface_acl$
DECLARE n integer;
BEGIN
 IF has_function_privilege('authenticated',
   'atlas.shared_course_open_source_current_v1(uuid)','EXECUTE')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_teacher_appointment_offers','SELECT')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_teacher_appointment_responses','INSERT')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_teacher_invitation_author_decisions','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_teacher_offer_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_teacher_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_teacher_offer_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_teacher_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_teacher_offer_read_self_api_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'teacher invitation source privilege leak or absent RPC'; END IF;
 SELECT count(*) INTO n FROM pg_trigger
 WHERE tgname IN ('shared_teacher_author_decision_immutable',
  'shared_teacher_offer_immutable','shared_teacher_response_immutable',
  'shared_teacher_withdrawal_immutable') AND NOT tgisinternal;
 IF n<>4 THEN RAISE EXCEPTION 'teacher history immutable source guards missing'; END IF;
END $teacher_surface_acl$;

SAVEPOINT shared_teacher_appointment_isolation;
-- Two independently signed, canonical fictional teacher People.
INSERT INTO auth.users(id) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeed');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',NULL),
 ('5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeed',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeed',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('ffffffff-ffff-4fff-8fff-ffffffffffff','person','fictional-invited-teacher'),
 ('ffffffff-ffff-4fff-8fff-fffffffffffe','person','fictional-declining-teacher');
INSERT INTO reality.auth_person_bindings(
 auth_user_id,person_entity_id,binding_state) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'ffffffff-ffff-4fff-8fff-ffffffffffff','active'),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeed',
  'ffffffff-ffff-4fff-8fff-fffffffffffe','active');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $teacher_course_author_proposes$
DECLARE a jsonb;b jsonb;
BEGIN
 a:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  '91234567-1234-4234-8234-123456789012');
 IF a->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'original sealed Course fixture missing';
 END IF;
 b:=public.shared_teaching_course_operating_propose_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '77777777-7777-4777-8777-777777777777',
  'c1234567-1234-4234-8234-123456789012');
 IF b->>'state'<>'proposed' THEN
  RAISE EXCEPTION 'author original Course relationship not proposed';
 END IF;
END $teacher_course_author_proposes$;
RESET ROLE;
-- Controlled fictional fixture handle; never a real API operation.
UPDATE atlas.teaching_course_operating_standings
 SET id='e1234567-1234-4234-8234-123456789012'
 WHERE request_id='c1234567-1234-4234-8234-123456789012';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $teacher_governor_accepts_course$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_operating_accept_self_api_v1(
  'e1234567-1234-4234-8234-123456789012',
  'a7777777-7777-4777-8777-777777777777',
  'f1234567-1234-4234-8234-123456789012');
 IF j->>'state'<>'accepted' THEN
  RAISE EXCEPTION 'independent institution did not accept Course';
 END IF;
END $teacher_governor_accepts_course$;

-- Even accepted institution cannot offer before author scopes permission.
DO $proposal_not_teacher_offer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_self_api_v1(
   '11234567-1234-4234-8234-123456789012',
   'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'b1234567-1234-4234-8234-123456789012');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'nonexistent/unopened Offering allowed a teacher invitation';
 END IF;
END $proposal_not_teacher_offer$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $teacher_author_prior_necessary_grants$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e1234567-1234-4234-8234-123456789012',
  'd1234567-1234-4234-8234-123456789011','allow_title');
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
  'e1234567-1234-4234-8234-123456789012',
  current_setting('app.fictional_published_version_id')::uuid,
  'd1234567-1234-4234-8234-123456789012','allow_draft_offering');
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
  'e1234567-1234-4234-8234-123456789012',
  current_setting('app.fictional_published_version_id')::uuid,
  'd1234567-1234-4234-8234-123456789013','allow_sealed_curriculum');
END $teacher_author_prior_necessary_grants$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $teacher_governor_draft$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_offering_draft_create_self_api_v1(
  'e1234567-1234-4234-8234-123456789012',
  current_setting('app.fictional_published_version_id')::uuid,
  'a1234567-1234-4234-8234-123456789012','cohort',NULL,NULL);
 IF j->>'offeringState'<>'draft' THEN
  RAISE EXCEPTION 'governor did not create exact Course draft';
 END IF;
 PERFORM set_config('app.fictional_teacher_offering_id',j->>'offeringId',true);
END $teacher_governor_draft$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $teacher_author_open_scope$
BEGIN
 PERFORM public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'd1234567-1234-4234-8234-123456789014','allow_open_offering');
END $teacher_author_open_scope$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $teacher_governor_opens_one_offering$
DECLARE j jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  '81234567-1234-4234-8234-123456789012');
 IF j->>'offeringState'<>'open' OR j->>'canAppointTeacher'<>'false' THEN
  RAISE EXCEPTION 'opening unexpectedly appointed teacher';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'b1234567-1234-4234-8234-123456789012');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'opened Offering without distinct author teacher grant gave appointment';
 END IF;
END $teacher_governor_opens_one_offering$;
RESET ROLE;

-- Fifth author permission releases only title/schedule to one teacher invite.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_allows_invitation_scope$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_teacher_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'd1234567-1234-4234-8234-123456789015','allow_teacher_invitation');
 b:=public.shared_teaching_teacher_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'd1234567-1234-4234-8234-123456789015','allow_teacher_invitation');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'canTeach'<>'false' OR a->>'canEnroll'<>'false' THEN
  RAISE EXCEPTION 'exact author permission or idempotent consent failed';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_teacher_invitation_decide_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'd1234567-1234-4234-8234-123456789015','withhold_teacher_invitation');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'changed immutable teacher invitation grant was accepted';
 END IF;
END $author_allows_invitation_scope$;

-- Author may not impersonate governor offering a teacher seat.
DO $author_cannot_offer_as_governor$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'b1234567-1234-4234-8234-123456789012');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Course author impersonated root governor'; END IF;
END $author_cannot_offer_as_governor$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_issues_exact_private_offers$
DECLARE a jsonb;b jsonb;c jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_teacher_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'ffffffff-ffff-4fff-8fff-ffffffffffff',
  'b1234567-1234-4234-8234-123456789012');
 b:=public.shared_teaching_teacher_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'ffffffff-ffff-4fff-8fff-ffffffffffff',
  'b1234567-1234-4234-8234-123456789012');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'offerId'<>b->>'offerId' OR a->>'canTeach'<>'false'
 OR a->>'canReadCurriculum'<>'false' OR a->>'canEnroll'<>'false'
 OR a ? 'courseTitle' OR a ? 'curriculum' THEN
  RAISE EXCEPTION 'specific teacher offer leaked title/curriculum or duplicate';
 END IF;
 PERFORM set_config('app.teacher_accept_offer_id',a->>'offerId',true);
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'b1234567-1234-4234-8234-123456789013');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'second conflicting teacher invitation minted';
 END IF;
 c:=public.shared_teaching_teacher_offer_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'ffffffff-ffff-4fff-8fff-fffffffffffe',
  'b1234567-1234-4234-8234-123456789014');
 PERFORM set_config('app.teacher_decline_offer_id',c->>'offerId',true);
END $governor_issues_exact_private_offers$;
RESET ROLE;

-- Neither author nor governor can read a named teacher's personal invite.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_cannot_see_private_teacher_offer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author inspected teacher personal invitation'; END IF;
END $author_cannot_see_private_teacher_offer$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_cannot_see_private_teacher_offer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor read invitee-only title view'; END IF;
END $governor_cannot_see_private_teacher_offer$;
RESET ROLE;

-- Teacher's own signed session sees only author-permitted Version title and
-- Offered schedule, never sealed text/Units or other teacher identities.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $teacher_reads_consent_and_accepts$
DECLARE j jsonb;a jsonb;b jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 IF j->>'courseTitle'<>'Founding Course definition'
 OR j->>'state'<>'offered'
 OR j->>'appointmentEffective' IS DISTINCT FROM 'false'
 OR j->>'canTeach' IS DISTINCT FROM 'false'
 OR j->>'canReadCurriculum' IS DISTINCT FROM 'false'
 OR j->>'canEnroll'<>'false' OR j ? 'curriculum' OR j ? 'units'
 OR j ? 'otherTeachers' OR j ? 'roster'
 OR j->>'deliveryMode'<>'cohort' THEN
  RAISE EXCEPTION 'teacher private invitation disclosed wrong bounded context';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'teacher read other teacher invitation'; END IF;
 a:=public.shared_teaching_teacher_respond_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   'b1234567-1234-4234-8234-123456789015','accept');
 b:=public.shared_teaching_teacher_respond_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   'b1234567-1234-4234-8234-123456789015','accept');
 IF a->>'decision'<>'accept' OR a->>'alreadyExists'<>'false'
 OR b->>'alreadyExists'<>'true'
 OR a->>'appointmentEffective'<>'true'
 OR a->>'canTeach'<>'false' OR a->>'canReadCurriculum'<>'false'
 OR a->>'canEnroll'<>'false' THEN
  RAISE EXCEPTION 'signed teacher acceptance or idempotent replay failed';
 END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_teacher_respond_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   'b1234567-1234-4234-8234-123456789016','decline');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'accepted teacher appointment was reversed'; END IF;
 j:=public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 IF j->>'state'<>'accept' OR j->>'appointmentEffective'<>'true' THEN
  RAISE EXCEPTION 'teacher acceptance was not recorded as effective';
 END IF;
END $teacher_reads_consent_and_accepts$;
RESET ROLE;

-- Different teacher sees own offer and can only DECLINE; no one else can
-- later accept their decline or retry with changed identity/request.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeed","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeed"}';
DO $other_teacher_declines$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_teacher_respond_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid,
   'b1234567-1234-4234-8234-123456789017','decline');
 b:=public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid);
 IF a->>'decision'<>'decline' OR a->>'appointmentEffective'<>'false'
 OR b->>'state'<>'decline' OR b->>'appointmentEffective'<>'false' THEN
  RAISE EXCEPTION 'separate teacher decline not terminal';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_teacher_respond_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid,
   'b1234567-1234-4234-8234-123456789018','accept');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'declined teacher still accepted same offer'; END IF;
END $other_teacher_declines$;
RESET ROLE;

DO $no_course_or_learner_side_effects$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings
   WHERE operating_proposal_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM atlas.shared_course_teacher_appointment_offers)<>2
 OR (SELECT count(*) FROM atlas.shared_course_teacher_appointment_responses)<>2
 OR EXISTS(SELECT 1 FROM atlas.teaching_enrollments)
 THEN RAISE EXCEPTION 'teacher appointment introduced Course, Offering or learner'; END IF;
 BEGIN
  UPDATE atlas.shared_course_teacher_appointment_responses SET decision='decline';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'teacher response receipt could mutate'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.shared_course_teacher_appointment_offers;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'immutable teacher offer was deleted'; END IF;
END $no_course_or_learner_side_effects$;

-- Active authorization is dynamic: if the source Teaching entitlement is
-- revoked, the formerly accepted teacher can no longer read an effective
-- appointment even though the historical consent record stays immutable.
SAVEPOINT teacher_teaching_revoked;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $revoked_teacher_source_not_effective$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'ended Teaching grant kept accepted appointment live'; END IF;
END $revoked_teacher_source_not_effective$;
RESET ROLE;
ROLLBACK TO SAVEPOINT teacher_teaching_revoked;

-- Independent author can withdraw permission to invite teachers at ANY
-- time; the signed teacher's acceptance is retained but no longer active.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withholds_teacher_invitation$
BEGIN
 PERFORM public.shared_teaching_teacher_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'd1234567-1234-4234-8234-123456789016','withhold_teacher_invitation');
END $author_withholds_teacher_invitation$;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $no_teacher_access_after_author_revoke$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked author teacher scope remained available'; END IF;
END $no_teacher_access_after_author_revoke$;
RESET ROLE;

-- The same signed author may later reauthorize invitation scope, but the
-- governor can independently withdraw an existing accepted appointment.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_restores_teacher_scope$
BEGIN
 PERFORM public.shared_teaching_teacher_invitation_decide_self_api_v1(
  current_setting('app.fictional_teacher_offering_id')::uuid,
  'd1234567-1234-4234-8234-123456789017','allow_teacher_invitation');
END $author_restores_teacher_scope$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_withdraws_accepted_teacher$
DECLARE j jsonb;k jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_teacher_withdraw_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  'b1234567-1234-4234-8234-123456789019');
 k:=public.shared_teaching_teacher_withdraw_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  'b1234567-1234-4234-8234-123456789019');
 IF j->>'alreadyExists'<>'false' OR k->>'alreadyExists'<>'true'
 OR j->>'appointmentEffective'<>'false' THEN
  RAISE EXCEPTION 'governor immutable appointment withdrawal failed';
 END IF;
 BEGIN PERFORM public.shared_teaching_teacher_withdraw_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  'b1234567-1234-4234-8234-12345678901a');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor changed immutable withdrawal request'; END IF;
END $governor_withdraws_accepted_teacher$;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $withdrawn_teacher_cannot_claim_appointment$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_offer_read_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn teacher appointment still active'; END IF;
END $withdrawn_teacher_cannot_claim_appointment$;
RESET ROLE;

DO $no_unissued_teaching_or_enrollment$
BEGIN
 IF (SELECT count(*) FROM atlas.shared_course_teacher_appointment_responses
   WHERE decision='accept')<>1
 OR (SELECT count(*) FROM atlas.shared_course_teacher_appointment_withdrawals)<>1
 OR (SELECT count(*) FROM atlas.teaching_enrollments)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1 THEN
  RAISE EXCEPTION 'teacher appointment did not preserve one Course and no students';
 END IF;
END $no_unissued_teaching_or_enrollment$;
-- Test a separate learner's current, explicit response on the same open
-- original Offering, before rolling back the fictional teacher fixture.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/shared_course_learner_invitation_tests_pg17.sql
ROLLBACK TO SAVEPOINT shared_teacher_appointment_isolation;
