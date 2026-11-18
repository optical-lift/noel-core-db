-- HELD M3.7: two independent fictional authenticated actors, one Course,
-- one exact canonical Ledger, current Teaching entitlement, no operation.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/operating_standing_acceptance_fixture_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/operating_standing_acceptance_candidate.sql
DO $acceptance_privilege_check$
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_course_operating_standings','UPDATE')
 OR has_table_privilege('authenticated','atlas.teaching_course_operating_standings','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_operating_accept_self_api_v1(uuid,uuid,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'acceptance opened direct standing mutation or anonymous operation';
 END IF;
 IF NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_operating_accept_self_api_v1(uuid,uuid,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'signed acceptance API unavailable';
 END IF;
END
$acceptance_privilege_check$;

DO $fix_exact_proposal_id$
DECLARE v_id uuid;
BEGIN
 SELECT id INTO v_id FROM atlas.teaching_course_operating_standings
 WHERE course_id='11111111-1111-4111-8111-111111111111'
 AND request_id='66666666-6666-4666-8666-666666666667';
 IF v_id IS NULL THEN RAISE EXCEPTION 'author proposal missing'; END IF;
 -- Use an explicit fixed test ID under the fixture's privileged role so
 -- the following fictional signed POST contains the actual invitation ID.
 UPDATE atlas.teaching_course_operating_standings
 SET id='e7777777-7777-4777-8777-777777777777'
 WHERE id=v_id;
END
$fix_exact_proposal_id$;

-- The author authored the proposal but cannot sign the Ledger's acceptance.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $not_author_self_authorization$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   (SELECT id FROM atlas.teaching_course_operating_standings LIMIT 1),
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 -- Since the private table cannot be read by the browser, the first
 -- statement itself must reject rather than disclosing proposal rows.
 IF NOT rejected THEN RAISE EXCEPTION 'author exposed institutional proposal table'; END IF;
END
$not_author_self_authorization$;
RESET ROLE;

-- Internal test fixture resolves the exact author proposal ID without ever
-- exposing its Course text to the institutional governor.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_cannot_accept$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'Course author self-accepted a Ledger'; END IF;
END
$author_cannot_accept$;
RESET ROLE;

-- No Teaching entitlement means even a signed source governor cannot accept.
SAVEPOINT revoked_teaching_entitlement;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_entitlement$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'governor accepted without Teaching grant'; END IF;
END
$no_entitlement$;
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_teaching_entitlement;

-- No current active exact-subject Teaching activation also denies.
SAVEPOINT suspended_teaching_activation;
UPDATE atlas.capability_activations SET state='suspended'
 WHERE id='a7777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_activation$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'governor accepted inactive Teaching'; END IF;
END
$no_activation$;
RESET ROLE;
ROLLBACK TO SAVEPOINT suspended_teaching_activation;

-- A known proposal UUID is NOT enough for an unassigned Ledger actor.
-- The fixture's governor is the outsider Person in the earlier author test,
-- but now holds independently grounded institutional root authority.

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $accepted_exactly_once$
DECLARE a jsonb; b jsonb; rejected boolean:=false;
BEGIN
 a:=public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 IF a->>'state'<>'accepted' OR a->>'operatingAuthorityGranted'<>'false'
 OR a->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'accepted receipt pretended to grant Course operation';
 END IF;
 b:=public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 IF b->>'alreadyExists'<>'true' OR b->>'proposalId'<>a->>'proposalId' THEN
  RAISE EXCEPTION 'institutional acceptance replay was not idempotent';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f8888888-8888-4888-8888-888888888888');
 EXCEPTION WHEN unique_violation THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'changed institutional acceptance request accepted'; END IF;
 rejected:=false;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'operator acceptance revealed author manuscript'; END IF;
END
$accepted_exactly_once$;
RESET ROLE;

DO $no_course_duplicated$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 OR
    (SELECT count(*) FROM atlas.teaching_course_operating_standings
      WHERE operator_acceptance_state='accepted')<>1 OR
    NOT EXISTS (
      SELECT 1 FROM atlas.teaching_course_operating_standings
      WHERE id='e7777777-7777-4777-8777-777777777777'
      AND proposal_state='proposed'
      AND operator_acceptance_state='accepted'
      AND operator_accepted_by_person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    ) THEN
  RAISE EXCEPTION 'two-party receipt changed Course identity or actor';
 END IF;
END
$no_course_duplicated$;

-- Retraction after consent MUST invalidate it without erasing the receipt.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_retracted$
DECLARE result jsonb;
BEGIN
 result:=public.shared_teaching_course_operating_withdraw_self_api_v1(
 '11111111-1111-4111-8111-111111111111',
 '66666666-6666-4666-8666-666666666667');
 IF result->>'state'<>'withdrawn' THEN RAISE EXCEPTION 'author cannot withdraw accepted intent'; END IF;
END
$author_retracted$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_revival$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_accept_self_api_v1(
   'e7777777-7777-4777-8777-777777777777',
   'a7777777-7777-4777-8777-777777777777',
   'f7777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'institution revived withdrawn author proposal'; END IF;
END
$no_revival$;
RESET ROLE;

DO $acceptance_not_operation$
BEGIN
 IF EXISTS (SELECT 1 FROM atlas.teaching_course_operating_standings
   WHERE operator_acceptance_state='accepted' AND proposal_state='proposed')
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1 THEN
  RAISE EXCEPTION 'consent withdrawal did not cancel current relation';
 END IF;
END
$acceptance_not_operation$;
