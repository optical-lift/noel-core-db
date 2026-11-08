-- Fictional-only, same-session isolated PG17 SOURCE test.
-- Run only via scripts/test-shared-course-clean-cutover-synthetic-pg17.sh
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.shared_course_clone='approved';
\i /source/candidates/shared-teaching-course-clean-cutover-v1/fixture_synthetic_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_temporary_manifest.sql
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
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

-- Deliberately corrupt cloned target *after* successful adoption. The
-- independent byte attestation must reject it; then rollback only mutation.
-- This proves a passing source-copy test is not a vacuous count-only test.
SAVEPOINT byte_mutation;
UPDATE atlas.teaching_course_manuscript_revisions
 SET body_text=replace(body_text,E'\n',E'\r\n')
 WHERE course_id='11111111-1111-4111-8111-111111111111';
\set ON_ERROR_STOP off
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql
\set byte_mutation_sqlstate :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT byte_mutation;
SELECT (:'byte_mutation_sqlstate'='23514') AS byte_mutation_detected \gset
\if :byte_mutation_detected
\else
  \echo 'FAILED: private manuscript line-ending mutation escaped the byte postcondition'
  SELECT 1/0 AS byte_attestation_missed_mutation;
\endif

-- Independent Unit order is part of the original history; altering it must
-- be rejected even when no text or identity changed.
SAVEPOINT order_mutation;
UPDATE atlas.teaching_course_units SET display_position=256
 WHERE unit_id='31111111-1111-4111-8111-111111111111';
\set ON_ERROR_STOP off
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql
\set order_mutation_sqlstate :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT order_mutation;
SELECT (:'order_mutation_sqlstate'='23514') AS order_mutation_detected \gset
\if :order_mutation_detected
\else
  \echo 'FAILED: original Unit ordering mutation escaped the postcondition'
  SELECT 1/0 AS unit_order_attestation_missed_mutation;
\endif

-- Recheck pristine original after negative tests.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql

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

-- M3.5: author initiates a relationship to one genuine Reality Ledger.
-- This is only a private, retractable proposal. It grants NO institution power.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/operating_standing_proposal_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/operating_standing_clone_postconditions.sql

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $operator_proposal$
DECLARE
 v_course uuid:='11111111-1111-4111-8111-111111111111';
 v_ledger uuid:='77777777-7777-4777-8777-777777777777';
 v_req uuid:='66666666-6666-4666-8666-666666666666';
 j jsonb;k jsonb;items jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_course_operating_propose_self_api_v1(
  v_course,v_ledger,v_req);
 IF j->>'state'<>'proposed' OR (j->>'courseId')::uuid<>v_course THEN
  RAISE EXCEPTION 'author intent failed to reference same Course original';
 END IF;
 k:=public.shared_teaching_course_operating_propose_self_api_v1(
  v_course,v_ledger,v_req);
 IF k->>'proposalId'<>j->>'proposalId' THEN
  RAISE EXCEPTION 'institutional proposal replay created a second relation';
 END IF;
 items:=public.shared_teaching_course_operating_proposals_self_api_v1(v_course);
 IF jsonb_array_length(items->'proposals')<>1 THEN
  RAISE EXCEPTION 'author could not read exact own proposal';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_operating_propose_self_api_v1(
   v_course,'88888888-8888-4888-8888-888888888888',v_req);
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'changed Ledger accepted for same request';
 END IF;
 k:=public.shared_teaching_course_operating_withdraw_self_api_v1(
  v_course,v_req);
 IF k->>'state'<>'withdrawn' THEN
  RAISE EXCEPTION 'original proposal was not withdrawn';
 END IF;
 k:=public.shared_teaching_course_operating_withdraw_self_api_v1(
  v_course,v_req);
 IF k->>'state'<>'withdrawn' THEN
  RAISE EXCEPTION 'withdraw replay was not idempotent';
 END IF;
 k:=public.shared_teaching_course_operating_propose_self_api_v1(
  v_course,v_ledger,
  '66666666-6666-4666-8666-666666666667');
 IF k->>'state'<>'proposed' OR k->>'proposalId'=j->>'proposalId' THEN
  RAISE EXCEPTION 'new proposal after withdrawal was not distinct';
 END IF;
END
$operator_proposal$;

DO $no_direct_ledger_power$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM 1 FROM atlas.teaching_course_operating_standings LIMIT 1;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'author browser can directly read operating table';
 END IF;
END
$no_direct_ledger_power$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_outsider_intent$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_proposals_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider read private intent'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_operating_propose_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   '77777777-7777-4777-8777-777777777777',
   '66666666-6666-4666-8666-666666666668');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider proposed on foreign Course'; END IF;
END
$no_outsider_intent$;
RESET ROLE;

DO $no_premature_operation$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  UPDATE atlas.teaching_course_operating_standings
   SET proposal_state='active'
   WHERE proposal_state='proposed';
 EXCEPTION WHEN check_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN
  RAISE EXCEPTION 'active institutional authority could be faked by proposal';
 END IF;
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 THEN
  RAISE EXCEPTION 'institutional intent duplicated Course original';
 END IF;
END
$no_premature_operation$;

-- M4 private-Course retirement simulation ONLY in fictional PG17.
-- The source originals were stored in the session-private manifest before M1.
-- Delete children explicitly, then DROP RESTRICT rather than CASCADE. Verify
-- the SAME retained Course history without reading any old source table.
SAVEPOINT fictional_private_retirement;
DELETE FROM titus.customer_course_unit_revisions_v1;
DELETE FROM titus.customer_course_material_revisions_v1;
DELETE FROM titus.customer_course_units_v1;
DELETE FROM titus.customer_course_drafts_v1;
DROP TABLE titus.customer_course_unit_revisions_v1 RESTRICT;
DROP TABLE titus.customer_course_material_revisions_v1 RESTRICT;
DROP TABLE titus.customer_course_units_v1 RESTRICT;
DROP TABLE titus.customer_course_drafts_v1 RESTRICT;

\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

-- Even with the old source removed in the scratch savepoint, mutating a
-- retained Unit revision must fail against the independent private manifest.
SAVEPOINT retained_unit_mutation;
UPDATE atlas.teaching_course_unit_revisions
 SET body_text=body_text||E'\r'
 WHERE revision_id='41111111-1111-4111-8111-111111111111';
\set ON_ERROR_STOP off
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql
\set postretirement_mutation_sqlstate :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT retained_unit_mutation;
SELECT (:'postretirement_mutation_sqlstate'='23514') AS retained_revision_change_detected \gset
\if :retained_revision_change_detected
\else
 SELECT 1/0 AS manifest_failed_to_detect_retained_unit_mutation;
\endif
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

DO $retired_private_shape$
BEGIN
 IF to_regclass('titus.customer_course_drafts_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_units_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_material_revisions_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_unit_revisions_v1') IS NOT NULL THEN
  RAISE EXCEPTION 'old private Course table survived fictional DROP RESTRICT';
 END IF;
END
$retired_private_shape$;
ROLLBACK TO SAVEPOINT fictional_private_retirement;

-- Exercise the actual HELD three-tranche M4 deletion SQL against a richer,
-- synthetic relational graph. This is NOT a restored production schema.
SAVEPOINT full_m4_retirement;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/m4_synthetic_retirement_fixture.sql

-- Unknown downstream reader MUST block DROP RESTRICT, not be cascaded away.\n-- This deliberately induced dependency is removed before actual M4 execution.\nSAVEPOINT unexpected_course_reader;\nCREATE VIEW public.fictional_unlisted_course_reader_v1 AS\n SELECT id FROM public.titus_course_prerequisites_v1;\nSAVEPOINT expected_dependency_block;\n\\set ON_ERROR_STOP off\nDROP VIEW public.titus_course_prerequisites_v1 RESTRICT;\n\\set course_dependency_sqlstate :SQLSTATE\n\\set ON_ERROR_STOP on\nROLLBACK TO SAVEPOINT expected_dependency_block;\nSELECT (:'course_dependency_sqlstate'='2BP01') AS unexpected_dependency_blocked \\gset\n\\if :unexpected_dependency_blocked\n\\else\n SELECT 1/0 AS unexpected_view_dependency_was_silently_dropped;\n\\endif\nROLLBACK TO SAVEPOINT unexpected_course_reader;\n\n-- Full original-set and grant attestation succeeds before deleting source.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/legacy_private_course_retirement_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/legacy_course_shell_retirement_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/legacy_mcmillan_program_retirement_candidate.sql

-- Old shared research table STRUCTURES are reusable, but only the retired
-- program's rows have vanished. Independent lesson/source originals survive.
DO $full_m4_result$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 OR
    to_regclass('titus.courses') IS NOT NULL OR
    to_regclass('titus.course_slots') IS NOT NULL OR
    to_regclass('titus.customer_course_drafts_v1') IS NOT NULL OR
    to_regclass('titus.customer_workspaces_v1') IS NOT NULL OR
    to_regprocedure('public.titus_customer_catalog_self_api_v1()') IS NOT NULL OR
    to_regclass('public.titus_courses_v1') IS NOT NULL OR\n    to_regclass('public.titus_course_prerequisites_v1') IS NOT NULL OR\n    to_regclass('public.titus_course_word_pattern_boards_v1') IS NOT NULL OR
    EXISTS(SELECT 1 FROM titus.programs) OR
    EXISTS(SELECT 1 FROM titus.curriculum_versions) OR
    EXISTS(SELECT 1 FROM titus.canon_claims) OR
    EXISTS(SELECT 1 FROM titus.formation_units) OR
    EXISTS(SELECT 1 FROM titus.teacher_source_adjudications) OR\n    EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace\n     WHERE n.nspname='public' AND c.relname LIKE 'titus_course%'\n       AND c.relkind IN ('v','m')) THEN
   RAISE EXCEPTION 'full three-tranche M4 retirement did not remove retired roots';
 END IF;
 IF (SELECT count(*) FROM titus.lesson_packets)<>1 OR
    (SELECT count(*) FROM titus.teacher_source_units)<>1 OR
    (SELECT count(*) FROM titus.lesson_teacher_source_links)<>1 OR
    EXISTS(SELECT 1 FROM titus.lesson_teacher_source_links WHERE adjudication_id IS NOT NULL)
 THEN
   RAISE EXCEPTION 'M4 accidentally destroyed independent lesson/source originals';
 END IF;
END
$full_m4_result$;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql
ROLLBACK TO SAVEPOINT full_m4_retirement;

-- Entire test rolls back on network-isolated container. Nothing is released.
ROLLBACK;
