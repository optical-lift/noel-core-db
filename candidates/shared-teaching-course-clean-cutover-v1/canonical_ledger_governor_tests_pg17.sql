-- HELD M3.6 isolated test: fictional signed roles, NOT real GoTrue.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/canonical_ledger_governor_fixture_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/canonical_ledger_governor_candidate.sql

DO $private_source$
BEGIN
 IF has_function_privilege('authenticated',
  'atlas.require_shared_course_native_ledger_governor_self_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'atlas.require_shared_course_native_ledger_governor_self_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'internal governor guard accidentally exposed';
 END IF;
 IF to_regprocedure('public.shared_teaching_course_operating_accept_self_api_v1(uuid)')
    IS NOT NULL THEN
  RAISE EXCEPTION 'unreviewed institutional operating acceptance installed';
 END IF;
END
$private_source$;

-- Author proposal is NOT a governor appointment. No teaching rights.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_has_no_root$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'Course author became native Ledger governor'; END IF;
 rejected:=false;
 BEGIN
  PERFORM atlas.require_shared_course_native_ledger_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'browser called private governor guard'; END IF;
END
$author_has_no_root$;

-- An independent actor with real CURRENT principal-root proof is eligible
-- as a governor; this grants neither Course access nor Teaching operation.
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $fictional_governor$
BEGIN
 IF NOT public.clone_test_shared_course_governor_self_v1(
  '77777777-7777-4777-8777-777777777777') THEN
  RAISE EXCEPTION 'exact signed governor denied';
 END IF;
END
$fictional_governor$;

-- Known UUID or a JWT alone cannot grant the current authoritative root.
DO $no_known_ledger_forge$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '88888888-8888-4888-8888-888888888888');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'unknown Ledger was authorized'; END IF;
END
$no_known_ledger_forge$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $no_current_session$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'session-less governor passed'; END IF;
END
$no_current_session$;
RESET ROLE;

-- Each changed source condition must cause an independent DENIAL. All changes
-- are isolated and restored before the next positive or negative proof.
SAVEPOINT root_ended;
UPDATE atlas.principal_ledger_authorities SET status='ended'
 WHERE authority_kind='root_governing';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $root_ended_denied$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'revoked root retained governing power'; END IF;
END
$root_ended_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT root_ended;

SAVEPOINT participation_ended;
UPDATE atlas.ledger_organization_participations SET status='ended'
 WHERE participation_kind='governing';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $participation_denied$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'ended institution governance remained effective'; END IF;
END
$participation_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT participation_ended;

SAVEPOINT carrier_retired;
UPDATE atlas.ledgers SET status='retired'
 WHERE id='77777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $carrier_denied$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'inactive exact legacy authority carrier accepted'; END IF;
END
$carrier_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT carrier_retired;

SAVEPOINT native_retired;
UPDATE ledger.ledgers SET ledger_state='retired'
 WHERE id='77777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $native_denied$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'retired native Ledger governed'; END IF;
END
$native_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT native_retired;

SAVEPOINT org_retired;
UPDATE atlas.organizations SET status='retired'
 WHERE id='b7777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $org_denied$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.clone_test_shared_course_governor_self_v1(
   '77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 IF NOT rejected THEN RAISE EXCEPTION 'inactive governing organization approved'; END IF;
END
$org_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT org_retired;

-- Source and Course untouched; no active standing, new Course or grant.
DO $no_grants_from_governor_check$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 OR
    EXISTS (SELECT 1 FROM atlas.teaching_course_operating_standings
      WHERE proposal_state<>'proposed' AND proposal_state<>'withdrawn') THEN
  RAISE EXCEPTION 'governor precondition mutated Course / standing';
 END IF;
END
$no_grants_from_governor_check$;
