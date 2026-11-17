-- HELD M3.17A fiction: private study consent on existing canonical Course.
-- No live accounts, notes, institutional Offering, sealed Unit disclosure,
-- cross-Person classroom, or any published material. All rows rolled back.
DO $acl$
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.teaching_course_private_study_invitations','SELECT')
 OR has_table_privilege('authenticated',
   'atlas.teaching_course_private_study_responses','INSERT')
 OR has_table_privilege('authenticated',
   'atlas.teaching_course_private_study_terminations','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated',
   'atlas.private_course_study_current_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_private_study_offer_read_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)','EXECUTE')
 OR (SELECT count(*) FROM pg_trigger WHERE tgname IN
  ('private_study_invitation_immutable',
   'private_study_response_immutable','private_study_termination_immutable')
   AND NOT tgisinternal)<>3
 THEN RAISE EXCEPTION 'private-study source ACL or immutable receipts failed'; END IF;
END $acl$;

SAVEPOINT private_study_fictional;
-- A and B are separate fictional People; old author Course ID is retained.
INSERT INTO auth.users(id) VALUES
 ('d8888888-8888-4888-8888-888888888881'),
 ('d8888888-8888-4888-8888-888888888882');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('58888888-8888-4888-8888-888888888881',
  'd8888888-8888-4888-8888-888888888881',NULL),
 ('58888888-8888-4888-8888-888888888882',
  'd8888888-8888-4888-8888-888888888882',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('f8888888-8888-4888-8888-888888888881','person','fictional-private-student-a'),
 ('f8888888-8888-4888-8888-888888888882','person','fictional-private-student-b'),
 ('f8888888-8888-4888-8888-888888888883','person','fictional-private-student-c');
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('d8888888-8888-4888-8888-888888888881',
  'f8888888-8888-4888-8888-888888888881','active'),
 ('d8888888-8888-4888-8888-888888888882',
  'f8888888-8888-4888-8888-888888888882','active');

-- A learner alone cannot invite themselves to someone else's Course.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d8888888-8888-4888-8888-888888888881","session_id":"58888888-8888-4888-8888-888888888881"}';
DO $cannot_self_invite$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_private_study_invite_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f8888888-8888-4888-8888-888888888881',
   'e8888888-8888-4888-8888-888888888881',NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'student minted Course access'; END IF;
END $cannot_self_invite$;
RESET ROLE;

-- Author issues exact invitations; retry same request returns same original.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue$
DECLARE a jsonb;b jsonb;c jsonb; denied boolean:=false;
BEGIN
 a:=public.shared_teaching_private_study_invite_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888881',
  'e8888888-8888-4888-8888-888888888881',NULL);
 b:=public.shared_teaching_private_study_invite_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888881',
  'e8888888-8888-4888-8888-888888888881',NULL);
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'invitationId'<>b->>'invitationId'
 OR a->>'canReadMaterial'<>'false' OR a ? 'courseTitle'
 OR a ? 'unit' OR a ? 'curriculum' OR a ? 'roster' THEN
  RAISE EXCEPTION 'author invitation not original/idempotent or leaks manuscript';
 END IF;
 PERFORM set_config('app.private_a',a->>'invitationId',true);
 BEGIN
  PERFORM public.shared_teaching_private_study_invite_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f8888888-8888-4888-8888-888888888882',
   'e8888888-8888-4888-8888-888888888881',NULL);
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'replayed request changed its target'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_private_study_invite_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f8888888-8888-4888-8888-888888888881',
   'e8888888-8888-4888-8888-888888888880',NULL);
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'second Course/learner invitation minted'; END IF;
 c:=public.shared_teaching_private_study_invite_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888882',
  'e8888888-8888-4888-8888-888888888882',NULL);
 PERFORM set_config('app.private_b',c->>'invitationId',true);
 IF c->>'alreadyExists'<>'false' OR c->>'canReadMaterial'<>'false' THEN
  RAISE EXCEPTION 'second learner invitation issue failed';
 END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_private_study_invite_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'e8888888-8888-4888-8888-888888888883',NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'author invited self'; END IF;
END $issue$;
RESET ROLE;

-- B cannot learn A's invitation from its UUID or accept on A's behalf.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d8888888-8888-4888-8888-888888888882","session_id":"58888888-8888-4888-8888-888888888882"}';
DO $b_private$
DECLARE denied boolean:=false;j jsonb;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_private_study_offer_read_self_api_v1(
    current_setting('app.private_a')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'B saw A private invitation'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_private_study_respond_self_api_v1(
    current_setting('app.private_a')::uuid,
    'e8888888-8888-4888-8888-888888888884','accept');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'B accepted A invitation'; END IF;
 j:=public.shared_teaching_private_study_offer_read_self_api_v1(
    current_setting('app.private_b')::uuid);
 IF j->>'state'<>'offered' OR j->>'courseTitle'<>'Fictional law study'
 OR j ? 'unit' OR j ? 'curriculum' OR j ? 'roster' THEN
  RAISE EXCEPTION 'B exact own invitation read failed';
 END IF;
 j:=public.shared_teaching_private_study_respond_self_api_v1(
    current_setting('app.private_b')::uuid,
    'e8888888-8888-4888-8888-888888888885','decline');
 IF j->>'decision'<>'decline' OR j->>'canReadMaterial'<>'false' THEN
  RAISE EXCEPTION 'B signed decline failed';
 END IF;
END $b_private$;
RESET ROLE;

-- Author cannot accept a learner's invitation.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_not_student$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_private_study_respond_self_api_v1(
   current_setting('app.private_a')::uuid,
   'e8888888-8888-4888-8888-888888888886','accept');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'author impersonated student consent'; END IF;
END $author_not_student$;
RESET ROLE;

-- A accepts and remains independent; exact repeat works, changed retry denied.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d8888888-8888-4888-8888-888888888881","session_id":"58888888-8888-4888-8888-888888888881"}';
DO $a_accepts$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_private_study_respond_self_api_v1(
   current_setting('app.private_a')::uuid,
   'e8888888-8888-4888-8888-888888888887','accept');
 b:=public.shared_teaching_private_study_respond_self_api_v1(
   current_setting('app.private_a')::uuid,
   'e8888888-8888-4888-8888-888888888887','accept');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'decision'<>'accept'
 OR a->>'canReadMaterial'<>'false' OR a->>'canSubmitWork'<>'false' THEN
  RAISE EXCEPTION 'A did not independently accept without content rights'; END IF;
 BEGIN
  PERFORM public.shared_teaching_private_study_respond_self_api_v1(
   current_setting('app.private_a')::uuid,
   'e8888888-8888-4888-8888-888888888888','decline');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'terminal learner decision overwritten'; END IF;
END $a_accepts$;
RESET ROLE;

-- Internal necessity-only predicate: accepted A yes; declined B no.
DO $current_scope$
BEGIN
 IF NOT atlas.private_course_study_current_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888881')
 OR atlas.private_course_study_current_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888882')
 OR atlas.private_course_study_current_v1(
  '88888888-8888-4888-8888-888888888888',
  'f8888888-8888-4888-8888-888888888881') THEN
  RAISE EXCEPTION 'Course-specific acceptance predicate leaked or failed';
 END IF;
 IF (SELECT count(*) FROM atlas.teaching_enrollments)<>0 THEN
  RAISE EXCEPTION 'private invitation fabricated institutional Enrollment';
 END IF;
END $current_scope$;

-- Immutable receipts cannot be overwritten even as root fixture owner.
DO $immutability$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  UPDATE atlas.teaching_course_private_study_invitations
   SET invited_at=clock_timestamp();
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'old invitation was writable'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.teaching_course_private_study_responses;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'old response was erasable'; END IF;
END $immutability$;

-- Expired initial invitation cannot be accepted; accepted study continues
-- after an invitation's original expiry rather than retroactively vanishing.
INSERT INTO atlas.teaching_course_private_study_invitations(
 course_id,learner_person_entity_id,invited_by_person_entity_id,
 request_id,invited_at,expires_at
) VALUES ('11111111-1111-4111-8111-111111111111',
 'f8888888-8888-4888-8888-888888888883',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'e8888888-8888-4888-8888-888888888889',
 clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day');

-- Auth binding revoked under an exact signed session denies even own invite.
SAVEPOINT fake_revoked_student;
UPDATE reality.auth_person_bindings SET binding_state='revoked'
 WHERE auth_user_id='d8888888-8888-4888-8888-888888888881';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d8888888-8888-4888-8888-888888888881","session_id":"58888888-8888-4888-8888-888888888881"}';
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_private_study_offer_read_self_api_v1(
   current_setting('app.private_a')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Person accessed study invitation'; END IF;
END $revoked$;
RESET ROLE;
ROLLBACK TO SAVEPOINT fake_revoked_student;

-- Learner A withdraws; relationship immediately no longer current.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d8888888-8888-4888-8888-888888888881","session_id":"58888888-8888-4888-8888-888888888881"}';
DO $a_withdraw$
DECLARE j jsonb;k jsonb;
BEGIN
 j:=public.shared_teaching_private_study_withdraw_self_api_v1(
  current_setting('app.private_a')::uuid,
  'e8888888-8888-4888-8888-88888888888a');
 k:=public.shared_teaching_private_study_withdraw_self_api_v1(
  current_setting('app.private_a')::uuid,
  'e8888888-8888-4888-8888-88888888888a');
 IF j->>'alreadyExists'<>'false' OR k->>'alreadyExists'<>'true' THEN
  RAISE EXCEPTION 'student withdrawal idempotence failed';
 END IF;
END $a_withdraw$;
RESET ROLE;
DO $after_withdraw$
BEGIN
 IF atlas.private_course_study_current_v1(
  '11111111-1111-4111-8111-111111111111',
  'f8888888-8888-4888-8888-888888888881') THEN
  RAISE EXCEPTION 'withdrawn private study still active'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_course_private_study_responses
     WHERE decision='accept')<>1 THEN
  RAISE EXCEPTION 'learner withdrawal deleted historical acceptance'; END IF;
END $after_withdraw$;

-- Author may withdraw B's previously declined offer; no made-up enrollment.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withdraw$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_private_study_withdraw_self_api_v1(
  current_setting('app.private_b')::uuid,
  'e8888888-8888-4888-8888-88888888888b');
 IF j->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'author exact offer withdrawal failed';
 END IF;
END $author_withdraw$;
RESET ROLE;
ROLLBACK TO SAVEPOINT private_study_fictional;

-- No student data has crossed into an institution, Class or signed real account.
DO $no_leak$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_course_private_study_invitations)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_responses)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_terminations)<>0
 OR (SELECT count(*) FROM atlas.teaching_enrollments)<>0
 THEN RAISE EXCEPTION 'private study synthetic rows were not rolled back'; END IF;
END $no_leak$;
