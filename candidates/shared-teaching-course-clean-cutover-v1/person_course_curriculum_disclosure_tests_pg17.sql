-- HELD M3.12: explicitly author-issued sealed Version read to exact
-- fictional current institutional governor, with independent dynamic rights.
-- Synthetic PG17 only. No real signed HTTP, production rows or deployment.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_course_curriculum_disclosure_candidate.sql

DO $private_decision_acl$
BEGIN
 IF has_table_privilege('authenticated',
  'atlas.teaching_course_curriculum_disclosure_decisions','SELECT')
 OR has_table_privilege('authenticated',
  'atlas.teaching_course_curriculum_disclosure_decisions','INSERT')
 OR has_function_privilege('anon',
  'public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('anon',
  'public.shared_teaching_course_curriculum_governor_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_course_curriculum_governor_read_self_api_v1(uuid,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'author-issued curriculum disclosure ACL incorrect';
 END IF;
END $private_decision_acl$;

SAVEPOINT author_institution_curriculum_disclosure_fixture;

-- Existing immutable Version from M3.9 is author-owned, but was not sealed
-- during M3.11 because that isolated positive test rolled back its rows.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $seal_once_and_propose$
DECLARE a jsonb;b jsonb;
BEGIN
 a:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  '96666666-6666-4666-8666-666666666666');
 IF a->>'institutionCanRead'<>'false' OR a->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'sealed author Course was not private by default';
 END IF;
 b:=public.shared_teaching_course_operating_propose_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '77777777-7777-4777-8777-777777777777',
  'c6666666-6666-4666-8666-666666666666');
 IF b->>'state'<>'proposed' THEN
  RAISE EXCEPTION 'specific author Course relationship not proposed';
 END IF;
END $seal_once_and_propose$;
RESET ROLE;

-- Fixed invitation ID is test fixture setup, never browser permission.
UPDATE atlas.teaching_course_operating_standings
 SET id='e6666666-6666-4666-8666-666666666666'
 WHERE request_id='c6666666-6666-4666-8666-666666666666';

-- Even a current root governor cannot discover private curriculum from
-- merely knowing the UUID, original Version or author proposal.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $proposal_and_seal_are_not_disclosure$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'sealed curriculum exposed before institution acceptance';
 END IF;
END $proposal_and_seal_are_not_disclosure$;

DO $independent_governor_acceptance$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_operating_accept_self_api_v1(
  'e6666666-6666-4666-8666-666666666666',
  'a7777777-7777-4777-8777-777777777777',
  'f6666666-6666-4666-8666-666666666666');
 IF j->>'state'<>'accepted' OR j->>'operatingAuthorityGranted'<>'false' THEN
  RAISE EXCEPTION 'exact independent governor acceptance failed';
 END IF;
END $independent_governor_acceptance$;

DO $acceptance_is_not_curriculum_disclosure$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'accepted institution had implicit sealed curriculum access';
 END IF;
END $acceptance_is_not_curriculum_disclosure$;

DO $governor_not_author_of_release$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666665',
   'allow_sealed_curriculum');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'institution self-issued author private content release';
 END IF;
END $governor_not_author_of_release$;
RESET ROLE;

-- The author releases title and Version use independently, but *still*
-- does not grant curriculum reading until a third explicit author act.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $two_insufficient_author_permissions$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   'd6666666-6666-4666-8666-666666666664','allow_title');
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666663','allow_draft_offering');
END $two_insufficient_author_permissions$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $draft_version_use_is_not_curriculum_read$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'author title/Version use implicitly disclosed manuscript';
 END IF;
END $draft_version_use_is_not_curriculum_read$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $actual_author_curriculum_release$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666662',
   'allow_sealed_curriculum');
 b:=public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666662',
   'allow_sealed_curriculum');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'eventSequence'<>b->>'eventSequence'
 OR a->>'canOpenOffering'<>'false' OR a->>'canEnroll'<>'false'
 OR a ? 'curriculum' THEN
  RAISE EXCEPTION 'separate author curriculum release receipt was wrong';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666662',
   'withhold_sealed_curriculum');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'changed author curriculum decision reused original request';
 END IF;
END $actual_author_curriculum_release$;

-- Author release does not turn a Person into an institutional governor.
DO $author_does_not_inherit_governor_identity$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'Course author became institution by releasing curriculum';
 END IF;
END $author_does_not_inherit_governor_identity$;

SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $current_governor_can_read_only_sealed_version$
DECLARE j jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 IF j->>'contractVersion'<>'shared_course_curriculum_governor_read_v1'
 OR j->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR j->>'ledgerId'<>'77777777-7777-4777-8777-777777777777'
 OR j->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR j->>'scope'<>'sealed_version_curriculum_to_current_governor_only'
 OR j->>'canEnroll'<>'false'
 OR j->>'canOpenOffering'<>'false'
 OR j->>'canAppointTeacher'<>'false'
 OR j->'curriculum'->'definition'->>'title'<>'Founding Course definition'
 OR j->'curriculum'->'manuscript'->>'text'
    IS DISTINCT FROM E'Teaching source\n\nObservation: א\n'
 OR jsonb_array_length(j->'curriculum'->'units')<>2 THEN
  RAISE EXCEPTION 'exact sealed Version curriculum read or scope failed';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'sealed Version release exposed live private editor'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   '99999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor read a foreign/unknown Version'; END IF;
END $current_governor_can_read_only_sealed_version$;
RESET ROLE;

-- An author's new withhold event is immediately effective to SAME actor.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_revokes_curriculum$
BEGIN
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666661',
   'withhold_sealed_curriculum');
END $author_revokes_curriculum$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $revoke_is_immediate$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'curriculum remained open after author withhold'; END IF;
END $revoke_is_immediate$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_releases_again$
BEGIN
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-666666666660',
   'allow_sealed_curriculum');
END $author_releases_again$;
RESET ROLE;

-- Each one of the other independent conditions still defeats the release.
SAVEPOINT curriculum_governor_revoked;
UPDATE atlas.principal_ledger_authorities SET status='ended'
 WHERE authority_kind='root_governing';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_root_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked institutional root still read curriculum'; END IF;
END $no_root_no_curriculum$;
RESET ROLE;
ROLLBACK TO SAVEPOINT curriculum_governor_revoked;

SAVEPOINT curriculum_teaching_revoked;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_teaching_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Teaching entitlement still read curriculum'; END IF;
END $no_teaching_no_curriculum$;
RESET ROLE;
ROLLBACK TO SAVEPOINT curriculum_teaching_revoked;

SAVEPOINT curriculum_session_revoked;
UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute'
 WHERE user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_session_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'stale operator session still read curriculum'; END IF;
END $no_session_no_curriculum$;
RESET ROLE;
ROLLBACK TO SAVEPOINT curriculum_session_revoked;

-- Withdraw source title or Version use: each immediately shuts down source.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_title_revoked$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   'd6666666-6666-4666-8666-66666666665f','withhold_title');
END $author_title_revoked$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_title_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn title permission still read curriculum'; END IF;
END $no_title_no_curriculum$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_title_reallowed_and_version_revoked$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   'd6666666-6666-4666-8666-66666666665e','allow_title');
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-66666666665d','withhold_draft_offering');
END $author_title_reallowed_and_version_revoked$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_version_use_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Version use still read curriculum'; END IF;
END $no_version_use_no_curriculum$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_version_reallow_then_relationship_withdraw$
BEGIN
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid,
   'd6666666-6666-4666-8666-66666666665c','allow_draft_offering');
 PERFORM public.shared_teaching_course_operating_withdraw_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'c6666666-6666-4666-8666-666666666666');
END $author_version_reallow_then_relationship_withdraw$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_active_author_relationship_no_curriculum$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_governor_read_self_api_v1(
   'e6666666-6666-4666-8666-666666666666',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn proposal left curriculum visible'; END IF;
END $no_active_author_relationship_no_curriculum$;
RESET ROLE;

DO $no_duplicate_course_and_auditable_decisions$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_curriculum_disclosure_decisions
  WHERE proposal_id='e6666666-6666-4666-8666-666666666666')<>3
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_operating_standings
  WHERE id='e6666666-6666-4666-8666-666666666666'
    AND proposal_state='withdrawn' AND operator_acceptance_state='accepted') THEN
  RAISE EXCEPTION 'source curriculum disclosure violated original custody';
 END IF;
END $no_duplicate_course_and_auditable_decisions$;
ROLLBACK TO SAVEPOINT author_institution_curriculum_disclosure_fixture;
