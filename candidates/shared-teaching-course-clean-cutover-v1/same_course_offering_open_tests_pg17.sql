-- HELD M3.13 full fictional same-Course Offering opening plus hard data-plane
-- old-enrollment denial. No real person, migration, teaching or production.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/same_course_offering_open_fixture_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/same_course_offering_open_candidate.sql

DO $open_source_acl$
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.teaching_course_offering_open_decision_events','SELECT')
 OR has_table_privilege('authenticated',
   'atlas.teaching_course_offering_open_issuances','INSERT')
 OR has_table_privilege('authenticated',
   'atlas.teaching_enrollments','INSERT')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_offering_open_decide_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_offering_open_decide_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT EXISTS (SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='atlas.teaching_enrollments'::regclass
   AND t.tgname='shared_course_enrollment_pending_v1'
   AND NOT t.tgisinternal)
 OR NOT EXISTS (SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='atlas.teaching_course_offerings'::regclass
   AND t.tgname='shared_course_offerings_exact_identity_v1'
   AND NOT t.tgisinternal) THEN
  RAISE EXCEPTION 'shared Offering opening and enrollment source custody missing';
 END IF;
END $open_source_acl$;

SAVEPOINT shared_offering_open_journey;

-- Seal the immutable existing Version and issue one new exact institutional
-- relation, after the prior consent tests rolled back.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_seals_and_proposes_open$
DECLARE s jsonb;p jsonb;
BEGIN
 s:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  '95555555-5555-4555-8555-555555555555');
 IF s->>'institutionCanRead'<>'false' THEN
  RAISE EXCEPTION 'source sealed curriculum was institution-readable by default';
 END IF;
 p:=public.shared_teaching_course_operating_propose_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '77777777-7777-4777-8777-777777777777',
  'c5555555-5555-4555-8555-555555555555');
 IF p->>'state'<>'proposed' THEN
  RAISE EXCEPTION 'separate author Course proposal failed';
 END IF;
END $author_seals_and_proposes_open$;
RESET ROLE;
UPDATE atlas.teaching_course_operating_standings
 SET id='e5555555-5555-4555-8555-555555555555'
 WHERE request_id='c5555555-5555-4555-8555-555555555555';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $independent_governor_accepts$
DECLARE a jsonb;
BEGIN
 a:=public.shared_teaching_course_operating_accept_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  'a7777777-7777-4777-8777-777777777777',
  'f5555555-5555-4555-8555-555555555555');
 IF a->>'state'<>'accepted' OR a->>'operatingAuthorityGranted'<>'false' THEN
  RAISE EXCEPTION 'accepted relationship accidentally granted teaching operation';
 END IF;
END $independent_governor_accepts$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_three_distinct_prior_permissions$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  'd5555555-5555-4555-8555-555555555551','allow_title');
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  current_setting('app.fictional_published_version_id')::uuid,
  'd5555555-5555-4555-8555-555555555552','allow_draft_offering');
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  current_setting('app.fictional_published_version_id')::uuid,
  'd5555555-5555-4555-8555-555555555553','allow_sealed_curriculum');
END $author_three_distinct_prior_permissions$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_creates_only_draft$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_offering_draft_create_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  current_setting('app.fictional_published_version_id')::uuid,
  'a5555555-5555-4555-8555-555555555555',
  'cohort',NULL,NULL);
 IF j->>'offeringState'<>'draft' OR j->>'canOpen'<>'false' THEN
  RAISE EXCEPTION 'author prior 3 permissions alone opened an Offering';
 END IF;
 PERFORM set_config('app.fictional_open_offering_id',j->>'offeringId',true);
END $governor_creates_only_draft$;

-- Before a separate author open decision, new open must fail even if
-- institution has signed root, valid Teaching and full sealed curriculum.
DO $no_implicit_open$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'accepted curriculum/open-capable Ledger implied author opening';
 END IF;
END $no_implicit_open$;

-- More important than an adapter: a privileged prior institution-first RPC
-- can call UPDATE on the Offering but cannot forge a current issuance.
DO $legacy_transition_cannot_open$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM atlas.fictional_legacy_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied OR EXISTS(SELECT 1 FROM atlas.teaching_course_offering_open_issuances) THEN
  RAISE EXCEPTION 'prior privileged transition bypassed the source issuer';
 END IF;
END $legacy_transition_cannot_open$;
RESET ROLE;

-- The author is not the institutional governor and must issue *this one*
-- draft's own allow, never merely the wider immutable Version use.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_open_receipt$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  'd5555555-5555-4555-8555-555555555554','allow_open_offering');
 b:=public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  'd5555555-5555-4555-8555-555555555554','allow_open_offering');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'canEnroll'<>'false' OR a->>'canAppointTeacher'<>'false'
 OR a->>'decision'<>'allow_open_offering' THEN
  RAISE EXCEPTION 'independent author Offering open permit or replay wrong';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_decide_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   'd5555555-5555-4555-8555-555555555554','withhold_open_offering');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed immutable author request allowed'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author impersonated institutional issuer'; END IF;
END $author_open_receipt$;

-- A withhold is immediately effective before any open action.
DO $author_withholds_open$
BEGIN
 PERFORM public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  'd5555555-5555-4555-8555-555555555555','withhold_open_offering');
END $author_withholds_open$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $author_withhold_blocks_governor$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withheld exact Offering still opened'; END IF;
END $author_withhold_blocks_governor$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_reallows_open$
BEGIN
 PERFORM public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  'd5555555-5555-4555-8555-555555555556','allow_open_offering');
END $author_reallows_open$;
RESET ROLE;

-- The institution still must be currently source-governed. Test removal of
-- independent authority, Teaching entitlement and current signed session.
SAVEPOINT open_root_revoked;
UPDATE atlas.principal_ledger_authorities SET status='ended'
 WHERE authority_kind='root_governing';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $root_lost_open_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'ended governor root opened Course Offering'; END IF;
END $root_lost_open_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT open_root_revoked;

SAVEPOINT open_teaching_revoked;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $teaching_lost_open_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Teaching entitlement opened Offering'; END IF;
END $teaching_lost_open_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT open_teaching_revoked;

SAVEPOINT open_operator_session_expired;
UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute'
 WHERE user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $expired_session_open_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'expired signed session opened Offering'; END IF;
END $expired_session_open_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT open_operator_session_expired;

-- A still-present author open consent is insufficient if exact Version
-- curriculum release is revoked independently.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_revokes_content_before_open$
BEGIN
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  current_setting('app.fictional_published_version_id')::uuid,
  'd5555555-5555-4555-8555-555555555557','withhold_sealed_curriculum');
END $author_revokes_content_before_open$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_content_permission_no_open$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'withheld sealed curriculum still opened Offering'; END IF;
END $no_content_permission_no_open$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_releases_content_again$
BEGIN
 PERFORM public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
  'e5555555-5555-4555-8555-555555555555',
  current_setting('app.fictional_published_version_id')::uuid,
  'd5555555-5555-4555-8555-555555555558','allow_sealed_curriculum');
END $author_releases_content_again$;
RESET ROLE;

-- Only NOW may the separate governor open one original Offering.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $exact_governor_open_one_offering$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 b:=public.shared_teaching_course_offering_open_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  '85555555-5555-4555-8555-555555555555');
 IF a->>'offeringId'<>current_setting('app.fictional_open_offering_id')
 OR a->>'offeringState'<>'open' OR a->>'alreadyExists'<>'false'
 OR b->>'alreadyExists'<>'true'
 OR a->>'canEnroll'<>'false' OR a->>'canAppointTeacher'<>'false'
 OR a->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR a->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR a->>'ledgerId'<>'77777777-7777-4777-8777-777777777777' THEN
  RAISE EXCEPTION 'exact source issuer did not open same Course Offering';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   '85555555-5555-4555-8555-555555555559');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed opening request reused immutable issuer'; END IF;
END $exact_governor_open_one_offering$;

-- Old privileged enrollment is explicitly denied at data-plane, even on
-- an actually 'open' Offering. No teacher or learner participation is issued.
DO $old_privileged_enrollment_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM atlas.fictional_legacy_enroll_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   (SELECT id FROM atlas.people ORDER BY id LIMIT 1));
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'legacy root Enrollment inserted after shared Course opened';
 END IF;
END $old_privileged_enrollment_denied$;
RESET ROLE;

DO $same_one_course_open_no_students$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings
   WHERE operating_proposal_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offering_open_issuances)<>1
 OR (SELECT count(*) FROM atlas.teaching_enrollments)<>0
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
   JOIN atlas.teaching_course_offering_open_issuances i ON i.offering_id=o.id
  WHERE o.id=current_setting('app.fictional_open_offering_id')::uuid
   AND o.course_id='11111111-1111-4111-8111-111111111111'
   AND o.course_version_id=current_setting('app.fictional_published_version_id')::uuid
   AND o.state='open' AND o.opened_at=i.opened_at
   AND o.operating_proposal_id=i.proposal_id
   AND o.ledger_id='77777777-7777-4777-8777-777777777777') THEN
  RAISE EXCEPTION 'source opened more than one original or allowed enrollments';
 END IF;
 BEGIN
  INSERT INTO atlas.teaching_enrollments(ledger_id,offering_id,person_id)
  VALUES ('77777777-7777-4777-8777-777777777777',
   current_setting('app.fictional_open_offering_id')::uuid,
   (SELECT id FROM atlas.people ORDER BY id LIMIT 1));
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'privileged direct enrollment defeated table guard'; END IF;
 denied:=false;
 BEGIN UPDATE atlas.teaching_course_offerings
   SET state='closed',closed_at=clock_timestamp()
   WHERE id=current_setting('app.fictional_open_offering_id')::uuid;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'old unissued close mutated shared Offering'; END IF;
 denied:=false;
 BEGIN DELETE FROM atlas.teaching_course_offering_open_issuances;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'immutable source opening issuance was deleted'; END IF;
END $same_one_course_open_no_students$;

-- After source opening, author withholds author permission: persisted state
-- is a historical issued fact, NOT ongoing ability to enroll/teach.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withholds_after_open$
BEGIN
 PERFORM public.shared_teaching_course_offering_open_decide_self_api_v1(
  current_setting('app.fictional_open_offering_id')::uuid,
  'd5555555-5555-4555-8555-55555555555a','withhold_open_offering');
END $author_withholds_after_open$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_new_operating_authority_from_old_receipt$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_open_self_api_v1(
   current_setting('app.fictional_open_offering_id')::uuid,
   '85555555-5555-4555-8555-555555555555');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'replay ignored later author withhold of operational authority';
 END IF;
END $no_new_operating_authority_from_old_receipt$;
RESET ROLE;

ROLLBACK TO SAVEPOINT shared_offering_open_journey;
