-- HELD U1 account-context candidate test. Fictional isolated PG17, NOT signed
-- production-GoTrue evidence, a customer account issuer or a released migration.
SAVEPOINT titus_account_context_probe;

DO $u1_blank$
BEGIN
 IF (SELECT count(*) FROM titus.institution_account_admissions_v1)<>0
 OR (SELECT count(*) FROM titus.institution_account_admission_withdrawals_v1)<>0
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0 THEN
  RAISE EXCEPTION 'Titus context source seeded admission or license';
 END IF;
 IF has_table_privilege('authenticated',
  'titus.institution_account_admissions_v1','SELECT')
 OR has_table_privilege('authenticated',
  'titus.institution_account_admissions_v1','INSERT')
 OR has_table_privilege('authenticated',
  'titus.institution_account_admission_withdrawals_v1','INSERT')
 OR has_table_privilege('anon',
  'titus.institution_account_admissions_v1','SELECT')
 OR has_function_privilege('authenticated',
  'titus.require_current_account_context_self_v1(text,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_account_contexts_self_api_v1()','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.titus_account_contexts_self_api_v1()','EXECUTE')
 THEN
  RAISE EXCEPTION 'untrusted Titus account context source privilege';
 END IF;
END $u1_blank$;

-- A current signed Person can see their personal context without a license.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $u1_person_without_institution$
DECLARE r jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF r->>'contractVersion'<>'titus_account_contexts_v1'
 OR r->'personal'->>'personId'<>'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
 OR r->'institutions'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'unlicensed Person was not personal-only';
 END IF;
 IF public.titus_account_context_check_self_api_v1('personal',NULL)
  ->'context'->>'kind'<>'personal' THEN
  RAISE EXCEPTION 'personal context failed';
 END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'Ledger presence automatically admitted university';
 END IF;
 denied:=false;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'personal','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'personal scope accepted institution ID'; END IF;
END $u1_person_without_institution$;
RESET ROLE;

-- Synthetic source-only admission: privileged fixture owner, NOT a real
-- institutional issuer or acceptance writer. The actual issuance authority
-- remains held for U1 review.
INSERT INTO titus.institution_account_admissions_v1(
 admission_id,person_entity_id,institution_entity_id,ledger_id,
 issued_by_person_entity_id,issue_receipt,acceptance_receipt,
 issued_at,accepted_at)
VALUES(
 'f1000000-0000-4000-8000-000000000001',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 '44444444-4444-4444-8444-444444444444',
 '77777777-7777-4777-8777-777777777777',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'fictional-issuer-u1-001','fictional-acceptance-u1-001',
 clock_timestamp()-interval '5 minutes',
 clock_timestamp()-interval '4 minutes');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $u1_person_can_switch$
DECLARE r jsonb; selected jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF jsonb_array_length(r->'institutions')<>1
 OR r->'personal'->>'personId'<>'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
 OR r->'institutions'->0->>'ledgerId'<>'77777777-7777-4777-8777-777777777777' THEN
  RAISE EXCEPTION 'one signer lacks isolated personal and admitted institution contexts';
 END IF;
 selected:=public.titus_account_context_check_self_api_v1(
  'institution','77777777-7777-4777-8777-777777777777');
 IF selected->'context'->>'institutionId'<>'44444444-4444-4444-8444-444444444444'
 OR selected->'context'->>'personId'<>'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' THEN
  RAISE EXCEPTION 'institution selector changed the signer identity';
 END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'forged institutional context was admitted'; END IF;
END $u1_person_can_switch$;

-- Caller must not SELECT admissions or invoke private helper as browser role.
DO $u1_direct_denial$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM admission_id FROM titus.institution_account_admissions_v1;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'browser read private Titus admissions'; END IF;
 denied:=false;
 BEGIN
  PERFORM titus.require_current_account_context_self_v1('personal',NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'browser invoked private source helper'; END IF;
END $u1_direct_denial$;

-- A separately signed other Person cannot see or claim A's university scope.
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $u1_outsider_denial$
DECLARE r jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF r->'personal'->>'personId'<>'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
 OR r->'institutions'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'outsider learned admitted account context';
 END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'different signed Person borrowed A institution'; END IF;
END $u1_outsider_denial$;

-- Wrong session owner cannot reuse a known Auth user and context.
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $u1_wrong_session$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_account_contexts_self_api_v1();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'wrong session owner saw account selector'; END IF;
END $u1_wrong_session$;
RESET ROLE;

-- Duplicate unwithdrawn admissions for one Person/Ledger make the whole
-- institution disappear; never pick a lucky LIMIT 1.
SAVEPOINT titus_account_duplicate_probe;
INSERT INTO titus.institution_account_admissions_v1(
 admission_id,person_entity_id,institution_entity_id,ledger_id,
 issued_by_person_entity_id,issue_receipt,acceptance_receipt,
 issued_at,accepted_at)
VALUES('f1000000-0000-4000-8000-000000000002',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 '44444444-4444-4444-8444-444444444444',
 '77777777-7777-4777-8777-777777777777',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'fictional-issuer-u1-002','fictional-acceptance-u1-002',
 clock_timestamp()-interval '5 minutes',
 clock_timestamp()-interval '4 minutes');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $u1_duplicate_is_denied$
DECLARE r jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF r->'institutions'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'ambiguous Titus institution returned as authorized';
 END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'ambiguous duplicate admission allowed'; END IF;
END $u1_duplicate_is_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT titus_account_duplicate_probe;

-- Withdraw the admission without mutating it. Revoke *university* access
-- while the same Person's personal account and Auth binding remain valid.
INSERT INTO titus.institution_account_admission_withdrawals_v1(
 admission_id,ended_by_person_entity_id,withdrawal_receipt,ended_at)
VALUES('f1000000-0000-4000-8000-000000000001',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'fictional-u1-withdrawal-001',
 clock_timestamp()-interval '1 minute');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $u1_withdrawal$
DECLARE r jsonb;denied boolean:=false;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF r->'institutions'<>'[]'::jsonb
 OR r->'personal'->>'personId'<>'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' THEN
  RAISE EXCEPTION 'institution exit destroyed personal account or leaked context';
 END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn institution remained admitted'; END IF;
END $u1_withdrawal$;
RESET ROLE;

DO $u1_history_immutable$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  UPDATE titus.institution_account_admissions_v1
  SET institution_entity_id='44444444-4444-4444-8444-444444444444'
  WHERE admission_id='f1000000-0000-4000-8000-000000000001';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'admission history was mutable'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM titus.institution_account_admission_withdrawals_v1;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawal history was mutable'; END IF;
END $u1_history_immutable$;

-- Restore exact prior fictitious actor/course/ledger sources. New schema exists
-- only inside the outer synthetic BEGIN, which is rolled back by its harness.
ROLLBACK TO SAVEPOINT titus_account_context_probe;
