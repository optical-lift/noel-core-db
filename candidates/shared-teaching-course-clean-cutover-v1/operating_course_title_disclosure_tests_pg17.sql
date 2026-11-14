-- HELD M3.8 PG17-only fiction: actual author-issued Course title disclosure.
-- No production Course/Person/Teaching data or authenticated HTTP traffic.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/operating_course_title_disclosure_candidate.sql

DO $source_acl$
BEGIN
 IF has_table_privilege('authenticated',
  'atlas.teaching_course_operating_title_disclosure_events','SELECT')
 OR has_table_privilege('authenticated',
  'atlas.teaching_course_operating_title_disclosure_events','INSERT')
 OR has_table_privilege('anon',
  'atlas.teaching_course_operating_title_disclosure_events','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_operating_title_read_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_operating_title_decide_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_operating_title_read_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_operating_title_decide_self_api_v1(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'title disclosure source exposed directly or lacks signed RPC';
 END IF;
END
$source_acl$;

SAVEPOINT title_disclosure_journey;
-- Author initiates a NEW exact proposal; institutional acceptance M3.7
-- already withdrew a previous one (historical acceptance not usable).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $title_new_author_proposal$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_operating_propose_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '77777777-7777-4777-8777-777777777777',
  '66666666-6666-4666-8666-666666666669');
 IF j->>'state'<>'proposed' THEN
  RAISE EXCEPTION 'new fictional title invitation not proposed'; END IF;
END
$title_new_author_proposal$;
RESET ROLE;
-- A fixed synthetic invitation ID is private fixture setup, not browser
-- authority or source manipulation in any real data.
UPDATE atlas.teaching_course_operating_standings
 SET id='e9999999-9999-4999-8999-999999999999'
 WHERE request_id='66666666-6666-4666-8666-666666666669';

-- No title is visible from a proposal alone, even to a real root governor.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $title_preaccept_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
   'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'proposal alone exposed Course title'; END IF;
END
$title_preaccept_denied$;
DO $accept_for_title$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_operating_accept_self_api_v1(
   'e9999999-9999-4999-8999-999999999999',
   'a7777777-7777-4777-8777-777777777777',
   'f9999999-9999-4999-8999-999999999999');
 IF j->>'state'<>'accepted' OR j->>'operatingAuthorityGranted'<>'false' THEN
  RAISE EXCEPTION 'fictional title acceptance failed'; END IF;
END
$accept_for_title$;
DO $title_pregrant_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
   'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'acceptance without author disclosure exposed title'; END IF;
END
$title_pregrant_denied$;
RESET ROLE;

-- Institution governor cannot grant their own access; author must permit.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $operator_cannot_self_disclose$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
   'e9999999-9999-4999-8999-999999999999',
   'd9999999-9999-4999-8999-999999999998','allow_title');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'institution granted author title disclosure'; END IF;
END
$operator_cannot_self_disclose$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_exact_allow$
DECLARE j jsonb;k jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e9999999-9999-4999-8999-999999999999',
  'd9999999-9999-4999-8999-999999999999','allow_title');
 k:=public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e9999999-9999-4999-8999-999999999999',
  'd9999999-9999-4999-8999-999999999999','allow_title');
 IF j->>'alreadyExists'<>'false' OR k->>'alreadyExists'<>'true'
 OR j->>'eventSequence'<>k->>'eventSequence' THEN
  RAISE EXCEPTION 'author title allow replay not idempotent'; END IF;
 BEGIN
  PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
   'e9999999-9999-4999-8999-999999999999',
   'd9999999-9999-4999-8999-999999999999','withhold_title');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed author event replay was allowed'; END IF;
END
$author_exact_allow$;
-- Author itself did not receive institution operating rights.
DO $author_not_institution$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
   'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author inherited institution root from title grant'; END IF;
END
$author_not_institution$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $title_only_positive$
DECLARE j jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 IF j->>'contractVersion'<>'shared_course_operating_title_read_v1'
 OR j->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR j->>'ledgerId'<>'77777777-7777-4777-8777-777777777777'
 OR j->>'title'<>'Fictional law study' OR j->>'scope'<>'course_title_only'
 OR j ? 'material' OR j ? 'units'
 OR j->>'canReadMaterials'<>'false' OR j->>'canCreateOffering'<>'false'
 OR j->>'canPublishVersion'<>'false' THEN
  RAISE EXCEPTION 'author-disclosed title read exceeded exact scope';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'title disclosure leaked private manuscript'; END IF;
END
$title_only_positive$;
RESET ROLE;

-- Current title consent is a decision event, not a durable unconditional
-- privilege. A new withhold immediately denies the SAME still-signed actor.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withholds$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e9999999-9999-4999-8999-999999999999',
  'd9999999-9999-4999-8999-999999999997','withhold_title');
END
$author_withholds$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $read_denied_after_withhold$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withheld title still disclosed'; END IF;
END
$read_denied_after_withhold$;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_reallows$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e9999999-9999-4999-8999-999999999999',
  'd9999999-9999-4999-8999-999999999996','allow_title');
END
$author_reallows$;
RESET ROLE;

-- Despite title allow, every current source condition must still hold.
SAVEPOINT title_grant_expired;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $expired_entitlement_read_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Teaching entitlement still reads title'; END IF;
END
$expired_entitlement_read_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT title_grant_expired;

SAVEPOINT title_activation_ended;
UPDATE atlas.capability_activations SET state='suspended'
 WHERE id='a7777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $inactive_activation_read_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'suspended Teaching activation still reads title'; END IF;
END
$inactive_activation_read_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT title_activation_ended;

SAVEPOINT title_root_ended;
UPDATE atlas.principal_ledger_authorities SET status='ended'
 WHERE authority_kind='root_governing';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $root_removed_read_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'ended governor authority still reads title'; END IF;
END
$root_removed_read_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT title_root_ended;

SAVEPOINT title_session_invalid;
UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute'
 WHERE user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $session_expired_read_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'expired session still reads title'; END IF;
END
$session_expired_read_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT title_session_invalid;

SAVEPOINT title_ledger_retired;
UPDATE ledger.ledgers SET ledger_state='retired'
 WHERE id='77777777-7777-4777-8777-777777777777';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $native_ledger_retired_read_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'inactive canonical Ledger still reads title'; END IF;
END
$native_ledger_retired_read_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT title_ledger_retired;

DO $title_audit_history$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_operating_title_disclosure_events
    WHERE proposal_id='e9999999-9999-4999-8999-999999999999')<>3 THEN
  RAISE EXCEPTION 'wrong source Course identity or title event history'; END IF;
END
$title_audit_history$;

-- Author withdraws the proposal. Prior valid disclosure/acceptance receipts
-- remain as history, but can no longer justify a read.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $title_author_withdraw$
BEGIN
 PERFORM public.shared_teaching_course_operating_withdraw_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '66666666-6666-4666-8666-666666666669');
END
$title_author_withdraw$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $withdrawn_author_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_operating_title_read_self_api_v1(
  'e9999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn author consent left title available'; END IF;
END
$withdrawn_author_denied$;
RESET ROLE;

-- The ephemeral source record is temporary; application release remains held.
ROLLBACK TO SAVEPOINT title_disclosure_journey;
