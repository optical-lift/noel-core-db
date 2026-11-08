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
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
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

SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
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
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
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

-- Duplicate active Person resolutions MUST be denied rather than arbitrary.
SAVEPOINT ambiguous_actor;
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','person','fictional-second-binding');
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','active');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
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
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $grant_copy$
DECLARE result jsonb;
BEGIN
 result:=public.titus_authoring_access_self_api_v1();
 IF result->>'canUseTitus'<>'true' THEN
  RAISE EXCEPTION 'migrated source pilot grant did not authorize Titus app';
 END IF;
END
$grant_copy$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
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
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
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

-- Entire test rolls back on network-isolated container. Nothing is released.
ROLLBACK;
