-- HELD M1.1 owner choices 5B/6D/7C: transferable code + recipient claim.
-- Fictional PG17 only, single-claim test policy, no real granted product issuer,
-- no paid/free-trial source and NO production person, Course or migration.
SAVEPOINT titus_private_pilot_probe;
CREATE TABLE reality.responsibility_relations(
 id uuid PRIMARY KEY,
 carrier_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 responsibility_key text NOT NULL,
 jurisdiction_kind text NOT NULL,
 jurisdiction_domain text,
 relation_state text NOT NULL,
 permitted_operations text[] NOT NULL,
 began_at timestamptz NOT NULL,
 ended_at timestamptz
);
\i /source/candidates/shared-teaching-course-clean-cutover-v1/titus_pilot_issuer_candidate.sql

DO $pilot_acl$
BEGIN
 IF has_table_privilege('authenticated','titus.course_authoring_pilot_codes','SELECT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_codes','INSERT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_code_claims','SELECT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_code_claims','INSERT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_code_cancellations','SELECT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_code_cancellations','INSERT')
 OR has_table_privilege('anon','titus.course_authoring_pilot_codes','SELECT')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_code_issue_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_code_claim_self_api_v1(text,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.titus_private_pilot_code_claim_self_api_v1(text,uuid)','EXECUTE')
 OR has_function_privilege('authenticated',
  'titus.require_current_pilot_issuer_self_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'untrusted audience can read/grant pilot source'; END IF;
END $pilot_acl$;

-- No seeded issuer, Person license, code, Course or institution.
DO $blank_pilot$
BEGIN
 IF (SELECT count(*) FROM titus.course_authoring_pilot_codes)<>0
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>0 THEN
  RAISE EXCEPTION 'pilot source seeded product or university'; END IF;
END $blank_pilot$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $ordinary_cannot_issue$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_code_issue_self_api_v1(
   'c0000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'ordinary login minted pilot code'; END IF;
END $ordinary_cannot_issue$;
RESET ROLE;

-- Explicit fictional responsibility only; the pilot mechanism does NOT mint
-- authority. Separately signed admin C has an independent delegated grant.
INSERT INTO auth.users(id) VALUES('a9999999-9999-4999-8999-999999999993');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES(
 '59999999-9999-4999-8999-999999999993',
 'a9999999-9999-4999-8999-999999999993',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key)
 VALUES('d9999999-9999-4999-8999-999999999993',
 'person','fictional-pilot-platform-delegate');
INSERT INTO reality.auth_person_bindings(
 auth_user_id,person_entity_id,binding_state)
VALUES('a9999999-9999-4999-8999-999999999993',
 'd9999999-9999-4999-8999-999999999993','active');

INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_domain,relation_state,permitted_operations,began_at,ended_at)
VALUES
 ('c0000000-0000-4000-8000-000000000040',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'titus_private_pilot_issuance','domain','titus','active',
  ARRAY['issue_pilot_code','revoke_pilot_code','end_pilot_access']::text[],
  clock_timestamp()-interval '1 day',NULL),
 ('c0000000-0000-4000-8000-000000000041',
  'd9999999-9999-4999-8999-999999999993',
  'titus_private_pilot_issuance','domain','titus','active',
  ARRAY['revoke_pilot_code','end_pilot_access']::text[],
  clock_timestamp()-interval '1 day',NULL);

-- B has a current Person but no issuer authority.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $learner_cannot_issue$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_code_issue_self_api_v1(
   'c0000000-0000-4000-8000-000000000002');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'nonissuer created a product code'; END IF;
END $learner_cannot_issue$;
RESET ROLE;

-- The source author/owner may issue one unassigned transferable secret.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue_one_code$
DECLARE a jsonb;b jsonb;code text;
BEGIN
 a:=public.titus_private_pilot_code_issue_self_api_v1(
  'c0000000-0000-4000-8000-000000000003');
 b:=public.titus_private_pilot_code_issue_self_api_v1(
  'c0000000-0000-4000-8000-000000000003');
 code:=a->>'code';
 IF a->>'alreadyExists'<>'false'
 OR b->>'alreadyExists'<>'true' OR b ? 'code'
 OR a->>'codeId'<>b->>'codeId'
 OR code !~ '^TITUS-[A-F0-9]{64}$' OR
 a->>'grantActive'<>'false' OR a->>'claimCapacity'<>'1' THEN
  RAISE EXCEPTION 'issue was not one-time transferable and secret-safe';
 END IF;
 PERFORM set_config('app.private_test_code',code,true);
 PERFORM set_config('app.private_test_code_id',a->>'codeId',true);
END $issue_one_code$;
RESET ROLE;
DO $only_hash_stored$
BEGIN
 IF (SELECT count(*) FROM titus.course_authoring_pilot_codes
   WHERE code_id=current_setting('app.private_test_code_id')::uuid
   AND code_hash=encode(sha256(
     convert_to(current_setting('app.private_test_code'),'UTF8')),'hex'))<>1
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>0 THEN
  RAISE EXCEPTION 'code plaintext stored or issuance auto-granted'; END IF;
END $only_hash_stored$;

-- The issuer cannot use their own code to mint an unrequested grant.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $no_issuer_self_claim$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_code_claim_self_api_v1(
   current_setting('app.private_test_code'),
   'c0000000-0000-4000-8000-000000000004');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'issuer self-claimed pilot license'; END IF;
END $no_issuer_self_claim$;
RESET ROLE;

-- B has the bearer secret but not yet a grant. Unknown/invalid code denied.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $invalid_code_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_code_claim_self_api_v1(
  'TITUS-0000000000000000000000000000000000000000000000000000000000000000',
  'c0000000-0000-4000-8000-000000000005');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'unknown bearer minted a grant'; END IF;
END $invalid_code_denied$;
RESET ROLE;

-- Source issuer standing loss or revoked source Auth prevents any new claim.
UPDATE reality.responsibility_relations SET relation_state='paused'
 WHERE id='c0000000-0000-4000-8000-000000000040';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $issuer_no_longer_authorized$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.private_test_code'),
  'c0000000-0000-4000-8000-000000000006');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'stale issuer code still granted'; END IF;
END $issuer_no_longer_authorized$;
RESET ROLE;
UPDATE reality.responsibility_relations SET relation_state='active'
 WHERE id='c0000000-0000-4000-8000-000000000040';

SAVEPOINT pilot_issuer_auth_revoked;
UPDATE reality.auth_person_bindings SET binding_state='revoked'
 WHERE auth_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $issuer_auth_no_longer_current$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.private_test_code'),
  'c0000000-0000-4000-8000-000000000007');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked issuer Auth bound pilot still grantable'; END IF;
END $issuer_auth_no_longer_current$;
RESET ROLE;
ROLLBACK TO SAVEPOINT pilot_issuer_auth_revoked;

-- A separate delegated administrator cancels an unclaimed alternate code.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue_to_cancel$
DECLARE j jsonb;
BEGIN
 j:=public.titus_private_pilot_code_issue_self_api_v1(
  'c0000000-0000-4000-8000-000000000008');
 PERFORM set_config('app.cancel_code',j->>'code',true);
 PERFORM set_config('app.cancel_code_id',j->>'codeId',true);
END $issue_to_cancel$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"a9999999-9999-4999-8999-999999999993","session_id":"59999999-9999-4999-8999-999999999993"}';
DO $delegate_cancels_code$
DECLARE a jsonb;b jsonb;
BEGIN
 a:=public.titus_private_pilot_code_cancel_self_api_v1(
  current_setting('app.cancel_code_id')::uuid,
  'c0000000-0000-4000-8000-000000000009');
 b:=public.titus_private_pilot_code_cancel_self_api_v1(
  current_setting('app.cancel_code_id')::uuid,
  'c0000000-0000-4000-8000-000000000009');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true' THEN
  RAISE EXCEPTION 'delegated cancellation idempotence failed'; END IF;
END $delegate_cancels_code$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $cancelled_bearer_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.cancel_code'),
  'c0000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'cancelled transferable code still grantable'; END IF;
END $cancelled_bearer_denied$;
RESET ROLE;

-- The actual claimant was not named at issuance. Independently signed B
-- receives an indefinite product pilot but NO Course or institution.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $signed_person_claims_code$
DECLARE a jsonb;b jsonb;c jsonb; denied boolean:=false;
BEGIN
 a:=public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.private_test_code'),
  'c0000000-0000-4000-8000-000000000011');
 b:=public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.private_test_code'),
  'c0000000-0000-4000-8000-000000000011');
 c:=public.titus_authoring_access_self_api_v1();
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'grantActive'<>'true' OR c->>'canUseTitus'<>'true' THEN
  RAISE EXCEPTION 'signed recipient did not activate one pilot'; END IF;
 BEGIN
 PERFORM public.titus_private_pilot_code_claim_self_api_v1(
  current_setting('app.private_test_code'),
  'c0000000-0000-4000-8000-000000000012');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'same bearer minted second receipt'; END IF;
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF c->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'claim fabricated a Course'; END IF;
END $signed_person_claims_code$;
RESET ROLE;

-- A THIRD independently signed Person can possess a transferred code, but
-- cannot claim the original once B has consumed it. This is not an identity
-- prebinding: the winner was not named at issuance.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"a9999999-9999-4999-8999-999999999993","session_id":"59999999-9999-4999-8999-999999999993"}';
DO $separate_person_cannot_double_claim$
DECLARE denied boolean:=false;j jsonb;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_code_claim_self_api_v1(
   current_setting('app.private_test_code'),
   'c0000000-0000-4000-8000-000000000014');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'third signed Person reused consumed pilot'; END IF;
 j:=public.titus_authoring_access_self_api_v1();
 IF j->>'canUseTitus'<>'false' THEN
  RAISE EXCEPTION 'platform delegated administrator received implicit license'; END IF;
END $separate_person_cannot_double_claim$;
RESET ROLE;

-- A mere claimant/student may never terminate their own grant by calling
-- the platform-admin operation; revocation is a separately authorized act.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $learner_cannot_admin_end$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_access_end_self_api_v1(
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'c0000000-0000-4000-8000-000000000015');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'student exercised platform issuer permission'; END IF;
END $learner_cannot_admin_end$;
RESET ROLE;

DO $claimed_pilot_has_no_deadline$
BEGIN
 IF (SELECT count(*) FROM titus.course_authoring_pilot_code_claims)<>1
 OR (SELECT count(*) FROM titus.course_authoring_access_grants g
  WHERE g.person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  AND g.grant_source_receipt='pilotcode:'||current_setting('app.private_test_code_id')
  AND g.state='active' AND g.valid_until IS NULL)<>1
 OR (SELECT count(*) FROM titus.course_authoring_pilot_code_cancellations)<>1
 OR (SELECT count(*) FROM atlas.teaching_courses)<>0
 THEN RAISE EXCEPTION 'pilot source expiry/custody/blank state wrong'; END IF;
END $claimed_pilot_has_no_deadline$;

-- The delegated Titus administrator, NOT a mere Course teacher, deliberately
-- ends accepted pilot. Source status event remains immutable.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"a9999999-9999-4999-8999-999999999993","session_id":"59999999-9999-4999-8999-999999999993"}';
DO $delegate_ends_access$
DECLARE a jsonb;b jsonb;
BEGIN
 a:=public.titus_private_pilot_access_end_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000013');
 b:=public.titus_private_pilot_access_end_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000013');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true' THEN
  RAISE EXCEPTION 'admin termination not append-only/idempotent'; END IF;
END $delegate_ends_access$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $terminated_access_denied$
DECLARE a jsonb;
BEGIN
 a:=public.titus_authoring_access_self_api_v1();
 IF a->>'canUseTitus'<>'false' THEN
  RAISE EXCEPTION 'admin-ended pilot still permits authoring'; END IF;
END $terminated_access_denied$;
RESET ROLE;

-- No bearer is stored in rows; code/cancellation/claim/status origins survive
-- privileged attempted edits. All synthetic accounts/authority/data roll back.
DO $immovable_history$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM titus.course_authoring_access_status_events e
  WHERE e.person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  AND e.next_state='revoked' AND e.source_evidence_receipt=
   'pilotend:c0000000-0000-4000-8000-000000000013')<>1 THEN
  RAISE EXCEPTION 'termination event missing'; END IF;
 BEGIN
  UPDATE titus.course_authoring_pilot_codes SET code_hash=repeat('0',64);
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot code original rewritten'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM titus.course_authoring_pilot_code_claims;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot claim erased'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM titus.course_authoring_pilot_code_cancellations;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot cancellation erased'; END IF;
END $immovable_history$;
ROLLBACK TO SAVEPOINT titus_private_pilot_probe;
DO $probe_rolled_back$
BEGIN
 IF to_regclass('reality.responsibility_relations') IS NOT NULL
 OR to_regclass('titus.course_authoring_pilot_codes') IS NOT NULL
 OR to_regclass('titus.course_authoring_pilot_code_claims') IS NOT NULL
 OR to_regclass('titus.course_authoring_pilot_code_cancellations') IS NOT NULL
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0
 OR (SELECT count(*) FROM titus.course_authoring_access_status_events)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>0 THEN
  RAISE EXCEPTION 'transferable pilot scratch fixture leaked source'; END IF;
END $probe_rolled_back$;
