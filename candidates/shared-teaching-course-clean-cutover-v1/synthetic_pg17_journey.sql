-- Fictional-only, same-session isolated PG17 SOURCE test.
-- Run only via scripts/test-shared-course-clean-cutover-synthetic-pg17.sh
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.shared_course_clone='approved';
\i /source/candidates/shared-teaching-course-clean-cutover-v1/fixture_synthetic_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_first_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_first_clone_postconditions.sql

-- Writer tests MUST rollback to restore an empty Course root for exact adoption.
SAVEPOINT writer_contract;
-- This synthetic author access grant is rolled back before M2 copies the
-- original fictional legacy pilot receipt.
INSERT INTO titus.course_authoring_access_grants(
 person_entity_id,grant_source_auth_user_id,grant_kind,
 grant_source_receipt,state,granted_at,valid_until)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'private_pilot','fictional-temporary-m1-access','active',now(),NULL);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $writer$
DECLARE a uuid; b uuid; result jsonb; denied boolean:=false;
BEGIN
 result:=public.shared_teaching_course_create_self_api_v1(
  '9aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fictional author Course');
 a:=(result->>'courseId')::uuid;
 IF result->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'new Person-first Course did not create';
 END IF;
 result:=public.shared_teaching_course_create_self_api_v1(
  '9aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Fictional author Course');
 b:=(result->>'courseId')::uuid;
 IF a IS DISTINCT FROM b OR result->>'alreadyExists'<>'true' THEN
  RAISE EXCEPTION 'same request did not return same Course UUID';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '9aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Different title');
 EXCEPTION WHEN unique_violation THEN
  denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed-title retry was admitted'; END IF;
END
$writer$;

-- A Titus UI entitlement is separate from the universal Course root.
DO $license$
DECLARE access jsonb;
BEGIN
 access:=public.titus_authoring_access_self_api_v1();
 IF access->>'canUseTitus'<>'true' THEN
  RAISE EXCEPTION 'original pilot author should have Titus app access';
 END IF;
END
$license$;
-- Browser authenticated roles do not inherit canonical Course table reads.
DO $deny_direct$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM id FROM atlas.teaching_courses LIMIT 1;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'direct table read leaked'; END IF;
END
$deny_direct$;

SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $outsider$
DECLARE v_id uuid;
BEGIN
 -- This outsider may create their OWN fictional Course, but cannot force a
 -- second ID for the author's idempotency request or write by Course ID.
 SELECT (public.shared_teaching_course_create_self_api_v1(
  '9aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Outsider own Course')->>'courseId')::uuid INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'other Person cannot create own Course'; END IF;
END
$outsider$;

SET LOCAL request.jwt.claims='{}';
DO $anonymous$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '9bbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Unauthorized Course');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'no-Person actor was admitted'; END IF;
END
$anonymous$;
RESET ROLE;
ROLLBACK TO SAVEPOINT writer_contract;

-- A revoked Person cannot invoke the Course creation source.
SAVEPOINT revoked_test;
UPDATE reality.auth_person_bindings SET binding_state='revoked'
 WHERE auth_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '9ccccccc-cccc-4ccc-8ccc-cccccccccccc','Revoked Course');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked actor was admitted'; END IF;
END
$revoked$;
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_test;

-- A JWT subject alone is never enough: require a CURRENT session ID.
SAVEPOINT missing_current_session;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $missing_session$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '97777777-7777-4777-8777-777777777777','No session');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'JWT without session ID created Course'; END IF;
END
$missing_session$;
RESET ROLE;
ROLLBACK TO SAVEPOINT missing_current_session;

-- Signed but expired session is denied even with an active Person binding.
SAVEPOINT session_expired;
UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute'
 WHERE user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $expired_session$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '98888888-8888-4888-8888-888888888888','Expired session');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'expired session created Course'; END IF;
END
$expired_session$;
RESET ROLE;
ROLLBACK TO SAVEPOINT session_expired;

-- Current JWT subject with another Person's session is not sufficient.
SAVEPOINT wrong_session_owner;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $wrong_owner$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '99999999-9999-4999-8999-999999999999','Wrong session owner');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'mismatched session created Course'; END IF;
END
$wrong_owner$;
RESET ROLE;
ROLLBACK TO SAVEPOINT wrong_session_owner;

-- A retired binding must not be resurrected because its status stayed active.
SAVEPOINT retired_binding;
UPDATE reality.auth_person_bindings SET retired_at=clock_timestamp()
 WHERE auth_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $retired_binding$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '9eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Retired binding');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'retired binding created Course'; END IF;
END
$retired_binding$;
RESET ROLE;
ROLLBACK TO SAVEPOINT retired_binding;

-- Duplicate active Person resolutions MUST be denied rather than arbitrary.
SAVEPOINT ambiguous_actor;
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','person','fictional-second-binding');
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','active');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $ambiguous$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(
   '9ddddddd-dddd-4ddd-8ddd-dddddddddddd','Ambiguous Course');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'ambiguous Person was admitted'; END IF;
END
$ambiguous$;
RESET ROLE;
ROLLBACK TO SAVEPOINT ambiguous_actor;

-- M2 copies same fictional old Course UUID and exact original text, IDs,
-- revision numbers, request IDs, source auth and timestamps.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_exact_adoption_candidate.sql

DO $m2_proof$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 OR NOT EXISTS(
  SELECT 1 FROM atlas.teaching_courses WHERE
  id='11111111-1111-4111-8111-111111111111'
  AND created_by_person_entity_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  AND ledger_id IS NULL AND created_by_principal_id IS NULL) THEN
  RAISE EXCEPTION 'single original identity not adopted faithfully';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_drafts_v1)<>1 THEN
  RAISE EXCEPTION 'source unexpectedly deleted during copy stage';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_units
  WHERE kind='assignment' AND display_position<>2) THEN
  RAISE EXCEPTION 'Homework draft changed position';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions
  WHERE body_text=E'Before\r\nAfter') THEN
  RAISE EXCEPTION 'CRLF history not preserved';
 END IF;
END
$m2_proof$;

-- The old pilot grant has migrated to Person-source without retaining
-- an Auth-owned workspace entitlement as the long-term access original.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $grant_copy$
DECLARE result jsonb;
BEGIN
 result:=public.titus_authoring_access_self_api_v1();
 IF result->>'canUseTitus'<>'true' THEN
  RAISE EXCEPTION 'migrated source pilot grant did not authorize Titus app';
 END IF;
END
$grant_copy$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_grant$
DECLARE result jsonb;
BEGIN
 result:=public.titus_authoring_access_self_api_v1();
 IF result->>'canUseTitus'<>'false' THEN
  RAISE EXCEPTION 'another Person inherited a Titus entitlement';
 END IF;
END
$no_grant$;
RESET ROLE;
SAVEPOINT revoke_grant;
UPDATE titus.course_authoring_access_grants SET state='revoked'
 WHERE person_entity_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $denied_license$
DECLARE result jsonb;
BEGIN
 result:=public.titus_authoring_access_self_api_v1();
 IF result->>'canUseTitus'<>'false' THEN
  RAISE EXCEPTION 'revoked Titus entitlement leaked';
 END IF;
END
$denied_license$;
RESET ROLE;
ROLLBACK TO SAVEPOINT revoke_grant;

-- Person-first authoring operations read the SAME adopted Course UUID and
-- append revisions without rewrites. This is synthetic, not real signed JWT.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/canonical_authoring_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/canonical_authoring_clone_postconditions.sql
SAVEPOINT authoring_rollback;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $authoring$
DECLARE
 c jsonb; m jsonb; u jsonb; outl jsonb;
 bad boolean:=false; new_unit uuid;
BEGIN
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF jsonb_array_length(c->'courses')<>1 OR
    (c->'courses'->0->>'courseId')::uuid
      IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'Course catalog identity differs after adoption';
 END IF;
 m:=public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 IF (m->'material'->>'revisionNumber')::int<>1 OR
    m->'material'->>'text'<>E'Teaching source\n\nObservation: א\n' THEN
  RAISE EXCEPTION 'founding manuscript cannot be reopened';
 END IF;
 outl:=public.shared_teaching_course_outline_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 IF jsonb_array_length(outl->'units')<>2 THEN
  RAISE EXCEPTION 'original Class/Homework outline not seen';
 END IF;
 u:=public.shared_teaching_course_unit_read_self_api_v1(
    '31111111-1111-4111-8111-111111111111');
 IF (u->'material'->>'revisionNumber')::int<>2 THEN
  RAISE EXCEPTION 'original Unit revisions not reopened';
 END IF;
 m:=public.shared_teaching_course_material_save_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f4111111-1111-4111-8111-111111111111',
   1,'New author text');
 IF (m->'material'->>'revisionNumber')::int<>2 THEN
  RAISE EXCEPTION 'new manuscript revision not appended';
 END IF;
 m:=public.shared_teaching_course_material_save_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f4111111-1111-4111-8111-111111111111',
   1,'New author text');
 IF (m->'material'->>'revisionNumber')::int<>2 THEN
  RAISE EXCEPTION 'replay duplicated manuscript revision';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_save_self_api_v1(
    '11111111-1111-4111-8111-111111111111',
    'f4111111-1111-4111-8111-111111111111',
    1,'Changed retry');
 EXCEPTION WHEN unique_violation THEN bad:=true;
 END;
 IF NOT bad THEN RAISE EXCEPTION 'changed manuscript retry admitted'; END IF;
 bad:=false;
 BEGIN
  PERFORM public.shared_teaching_course_material_save_self_api_v1(
    '11111111-1111-4111-8111-111111111111',
    'f4222222-2222-4222-8222-222222222222',
    1,'stale write');
 EXCEPTION WHEN serialization_failure THEN bad:=true;
 END;
 IF NOT bad THEN RAISE EXCEPTION 'stale manuscript overwrite admitted'; END IF;
 u:=public.shared_teaching_course_unit_save_self_api_v1(
   '31111111-1111-4111-8111-111111111111',
   'f4333333-3333-4333-8333-333333333333',
   2,'Revised third Unit edition');
 IF (u->'material'->>'revisionNumber')::int<>3 THEN
  RAISE EXCEPTION 'Unit revision not appended';
 END IF;
 outl:=public.shared_teaching_course_unit_create_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f4444444-4444-4444-8444-444444444444',
   'assignment','Second homework draft');
 IF jsonb_array_length(outl->'units')<>3 THEN
  RAISE EXCEPTION 'Unit create did not return three originals';
 END IF;
 outl:=public.shared_teaching_course_unit_create_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'f4444444-4444-4444-8444-444444444444',
   'assignment','Second homework draft');
 IF jsonb_array_length(outl->'units')<>3 THEN
  RAISE EXCEPTION 'Unit create retry minted another original';
 END IF;
 new_unit:=(outl->'units'->2->>'unitId')::uuid;
 outl:=public.shared_teaching_course_unit_move_self_api_v1(
   '11111111-1111-4111-8111-111111111111',new_unit,'up');
 IF jsonb_array_length(outl->'units')<>3 OR
   (outl->'units'->1->>'unitId')::uuid IS DISTINCT FROM new_unit THEN
  RAISE EXCEPTION 'bounded ordered Unit move broke unique positions';
 END IF;
END
$authoring$;
RESET ROLE;
-- Cross-original byte comparison runs as scratch postgres, not as a client.
-- Author client access to this table must remain denied.
DO $source_integrity$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_course_manuscript_revisions
   WHERE course_id='11111111-1111-4111-8111-111111111111'
   AND revision_number=1 AND body_text=E'Teaching source\n\nObservation: א\n') THEN
  RAISE EXCEPTION 'new edit overwrote original founding manuscript';
 END IF;
END
$source_integrity$;

-- Other current People, withdrawn actors and anonymous requests cannot read
-- the author's Course/Unit originals, even if they know the immutable UUIDs.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $outsider_material$
DECLARE denied boolean:=false; j jsonb;
BEGIN
 j:=public.shared_teaching_course_catalog_self_api_v1();
 IF jsonb_array_length(j->'courses')<>0 THEN
  RAISE EXCEPTION 'outsider sees another author Course in catalog';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider read author manuscript'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_unit_read_self_api_v1(
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider read author Unit'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_unit_save_self_api_v1(
   '31111111-1111-4111-8111-111111111111',
   'f4555555-5555-4555-8555-555555555555',
   2,'Outsider overwrite');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider wrote author Unit'; END IF;
END
$outsider_material$;
RESET ROLE;
ROLLBACK TO SAVEPOINT authoring_rollback;

-- Entire test rolls back on network-isolated container. Nothing is released.
ROLLBACK;
