-- HELD Titus U1.1: isolated-fictional PG17 proof. The user/issuer/session
-- stubs here are NOT signed GoTrue, not production-shaped and not authority
-- to establish a real institution, manager, invitation, admission or license.
SAVEPOINT titus_account_issuer_probe;
-- The earlier platform-pilot tests create their own responsibility fixture
-- only in a rolled-back savepoint. Model exact reality source here as source
-- evidence for this isolated candidate, NOT a grant issued by this migration.
CREATE TABLE reality.responsibility_relations(
 id uuid PRIMARY KEY,
 carrier_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 responsibility_key text NOT NULL,
 jurisdiction_kind text NOT NULL,
 jurisdiction_entity_id uuid REFERENCES reality.entities(id),
 jurisdiction_domain text,
 relation_state text NOT NULL,
 permitted_operations text[] NOT NULL,
 began_at timestamptz NOT NULL,
 ended_at timestamptz,
 scope jsonb NOT NULL DEFAULT '{}'::jsonb
);
\i /source/candidates/shared-teaching-course-clean-cutover-v1/titus_institution_account_admission_issuer_candidate.sql

DO $u11_acl$
BEGIN
 IF has_table_privilege('authenticated','titus.institution_account_invitations_v1','SELECT')
 OR has_table_privilege('authenticated','titus.institution_account_invitations_v1','INSERT')
 OR has_table_privilege('authenticated','titus.institution_account_invitation_cancellations_v1','INSERT')
 OR has_function_privilege('authenticated',
  'titus.require_current_institution_account_manager_self_v1(uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_institution_account_invite_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_institution_account_accept_self_api_v1(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_institution_account_withdraw_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.titus_institution_account_invite_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.titus_institution_account_accept_self_api_v1(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'U1 invitation/admission ACL widened'; END IF;
 IF (SELECT count(*) FROM titus.institution_account_invitations_v1)<>0
 OR (SELECT count(*) FROM titus.institution_account_admissions_v1)<>0
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0 THEN
  RAISE EXCEPTION 'U1 issuer candidate seeded admission, pilot or Course'; END IF;
END $u11_acl$;

-- The canonical Ledger owner/participant is not a manager of Titus accounts.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $not_manager$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_invite_self_api_v1(
   '77777777-7777-4777-8777-777777777777',
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'f1000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'ordinary Person issued institution invitation'; END IF;
END $not_manager$;
RESET ROLE;

-- A real institution responsibility must also identify THIS exact Ledger.
-- The same institution subject on a different Ledger is insufficient.
SAVEPOINT wrong_ledger_manager;
INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_entity_id,relation_state,permitted_operations,began_at,scope)
VALUES('f1000000-0000-4000-8000-000000000009',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_institution_account_management','entity',
 '44444444-4444-4444-8444-444444444444',
 'active',ARRAY['invite']::text[],clock_timestamp()-interval '1 day',
 '{"ledgerId":"77777777-7777-4777-8777-999999999999"}');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $wrong_ledger_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_invite_self_api_v1(
   '77777777-7777-4777-8777-777777777777',
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'f1000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'manager jurisdiction leaked into wrong Ledger'; END IF;
END $wrong_ledger_denied$;
RESET ROLE;
ROLLBACK TO SAVEPOINT wrong_ledger_manager;

-- Fictional explicit manager responsibility (precisely the existing Reality
-- relation type and exact institution/Ledger), issued by scratch fixture only.
INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_entity_id,relation_state,permitted_operations,began_at,
 scope)
VALUES(
 'f1000000-0000-4000-8000-000000000011',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_institution_account_management','entity',
 '44444444-4444-4444-8444-444444444444','active',
 ARRAY['invite','withdraw','cancel']::text[],clock_timestamp()-interval '1 day',
 '{"ledgerId":"77777777-7777-4777-8777-777777777777"}');

-- Recipients cannot issue their own institutional account.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient_cannot_issue$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_invite_self_api_v1(
   '77777777-7777-4777-8777-777777777777',
   'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'f1000000-0000-4000-8000-000000000012');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'recipient became manager by signing in'; END IF;
END $recipient_cannot_issue$;

-- No admission or another Person's private scope before recipient acceptance.
DO $recipient_before_accept$
DECLARE r jsonb;
BEGIN
 r:=public.titus_account_contexts_self_api_v1();
 IF r->'institutions'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'invitation alone admitted recipient'; END IF;
END $recipient_before_accept$;
RESET ROLE;

-- Issuer creates an invitation addressed to a known canonical Person.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue_one$
DECLARE first jsonb;again jsonb;denied boolean:=false;
BEGIN
 first:=public.titus_institution_account_invite_self_api_v1(
  '77777777-7777-4777-8777-777777777777',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'f1000000-0000-4000-8000-000000000013');
 again:=public.titus_institution_account_invite_self_api_v1(
  '77777777-7777-4777-8777-777777777777',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'f1000000-0000-4000-8000-000000000013');
 IF first->>'alreadyExists'<>'false' OR again->>'alreadyExists'<>'true'
 OR first->>'invitationId'<>again->>'invitationId' THEN
  RAISE EXCEPTION 'institution invite lost idempotent receipt'; END IF;
 PERFORM set_config('app.titus_test_invite_id',first->>'invitationId',true);
 BEGIN
  PERFORM public.titus_institution_account_invite_self_api_v1(
   '77777777-7777-4777-8777-777777777777',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'f1000000-0000-4000-8000-000000000013');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'invite retry silently changed recipient'; END IF;
END $issue_one$;
RESET ROLE;

-- Issuer cannot accept for recipient, even knowing exact invitation ID.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issuer_cannot_accept$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_accept_self_api_v1(
   current_setting('app.titus_test_invite_id')::uuid,
   'f1000000-0000-4000-8000-000000000014');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'issuer manufactured recipient consent'; END IF;
END $issuer_cannot_accept$;
RESET ROLE;

-- Recipient performs a distinct signed acceptance. Retry is idempotent.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient_accepts$
DECLARE v jsonb;retry jsonb;listed jsonb;
BEGIN
 v:=public.titus_institution_account_accept_self_api_v1(
  current_setting('app.titus_test_invite_id')::uuid,
  'f1000000-0000-4000-8000-000000000015');
 retry:=public.titus_institution_account_accept_self_api_v1(
  current_setting('app.titus_test_invite_id')::uuid,
  'f1000000-0000-4000-8000-000000000015');
 IF v->>'alreadyExists'<>'false' OR retry->>'alreadyExists'<>'true'
 OR v->>'admissionId'<>retry->>'admissionId' THEN
  RAISE EXCEPTION 'recipient self-accept was not idempotent'; END IF;
 PERFORM set_config('app.titus_test_admission_id',v->>'admissionId',true);
 listed:=public.titus_account_contexts_self_api_v1();
 IF jsonb_array_length(listed->'institutions')<>1
 OR listed->'personal'->>'personId'<>'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
 OR listed->'institutions'->0->>'institutionId'<>'44444444-4444-4444-8444-444444444444'
 THEN RAISE EXCEPTION 'signed acceptance not reflected in own scope'; END IF;
END $recipient_accepts$;
RESET ROLE;

-- Issuer may not cancel an already accepted invitation: only a governed
-- withdrawal can end the recipient's independently accepted institution scope.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $cannot_cancel_accepted$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_cancel_invite_self_api_v1(
   current_setting('app.titus_test_invite_id')::uuid,
   'f1000000-0000-4000-8000-000000000029');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'accepted institution was cancellable as unused invite'; END IF;
END $cannot_cancel_accepted$;
RESET ROLE;

-- Manager, who is a distinct Person, cannot automatically borrow the
-- admitted person's university context merely by issuing invitations.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $manager_not_admitted$
DECLARE v jsonb;denied boolean:=false;
BEGIN
 v:=public.titus_account_contexts_self_api_v1();
 IF v->'institutions'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'manager became enrolled merely by issuance'; END IF;
 BEGIN
  PERFORM public.titus_account_context_check_self_api_v1(
   'institution','77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'manager borrowed recipient account'; END IF;
END $manager_not_admitted$;
RESET ROLE;

-- A later independently authorized manager can withdraw the person's
-- institutional account, without deleting their personal source history.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $manager_withdraws$
DECLARE v jsonb;again jsonb;
BEGIN
 v:=public.titus_institution_account_withdraw_self_api_v1(
  current_setting('app.titus_test_admission_id')::uuid,
  'f1000000-0000-4000-8000-000000000016');
 again:=public.titus_institution_account_withdraw_self_api_v1(
  current_setting('app.titus_test_admission_id')::uuid,
  'f1000000-0000-4000-8000-000000000016');
 IF v->>'alreadyExists'<>'false' OR again->>'alreadyExists'<>'true' THEN
  RAISE EXCEPTION 'withdrawal request not append-only/idempotent'; END IF;
END $manager_withdraws$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient_after_withdrawal$
DECLARE v jsonb;denied boolean:=false;
BEGIN
 v:=public.titus_account_contexts_self_api_v1();
 IF v->'institutions'<>'[]'::jsonb
 OR v->'personal'->>'personId'<>'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
 THEN RAISE EXCEPTION 'university withdrawal changed personal identity'; END IF;
 BEGIN
  PERFORM public.titus_institution_account_accept_self_api_v1(
   current_setting('app.titus_test_invite_id')::uuid,
   'f1000000-0000-4000-8000-000000000015');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'old accepted invite revived after withdrawal'; END IF;
END $recipient_after_withdrawal$;
RESET ROLE;

-- Another issued invitation may be cancelled only by a currently authorized
-- manager before it is accepted. Cancellation cannot terminate an accepted
-- admission; that requires a withdrawal receipt.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $cancel_unused_invite$
DECLARE i jsonb;c jsonb;
BEGIN
 i:=public.titus_institution_account_invite_self_api_v1(
 '77777777-7777-4777-8777-777777777777',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'f1000000-0000-4000-8000-000000000017');
 PERFORM set_config('app.titus_test_cancelled_invite',i->>'invitationId',true);
 c:=public.titus_institution_account_cancel_invite_self_api_v1(
  (i->>'invitationId')::uuid,'f1000000-0000-4000-8000-000000000018');
 IF c->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'cancelled invitation returned conflicting origin'; END IF;
END $cancel_unused_invite$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $cannot_claim_cancelled$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_accept_self_api_v1(
   current_setting('app.titus_test_cancelled_invite')::uuid,
   'f1000000-0000-4000-8000-000000000019');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'cancelled invitation was accepted'; END IF;
END $cannot_claim_cancelled$;
RESET ROLE;

-- A manager whose source standing ends before acceptance cannot complete
-- an outstanding invitation through an old credential.
SAVEPOINT issuer_revoke_probe;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue_then_revoke$
DECLARE v jsonb;
BEGIN
 v:=public.titus_institution_account_invite_self_api_v1(
 '77777777-7777-4777-8777-777777777777',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'f1000000-0000-4000-8000-000000000020');
 PERFORM set_config('app.titus_test_revoked_invite',v->>'invitationId',true);
END $issue_then_revoke$;
RESET ROLE;
UPDATE reality.responsibility_relations
 SET relation_state='ended',ended_at=clock_timestamp()
 WHERE id='f1000000-0000-4000-8000-000000000011';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $stale_issuer_rejected$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_institution_account_accept_self_api_v1(
   current_setting('app.titus_test_revoked_invite')::uuid,
   'f1000000-0000-4000-8000-000000000021');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'stale manager invitation was accepted'; END IF;
END $stale_issuer_rejected$;
RESET ROLE;
ROLLBACK TO SAVEPOINT issuer_revoke_probe;

-- An exited person can be invited anew under a NEW original and may
-- personally withdraw. The old admission/withdrawal are never overwritten.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $reinvite_after_exit$
DECLARE i jsonb;
BEGIN
 i:=public.titus_institution_account_invite_self_api_v1(
  '77777777-7777-4777-8777-777777777777',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'f1000000-0000-4000-8000-000000000022');
 PERFORM set_config('app.titus_test_rejoin_invite',i->>'invitationId',true);
END $reinvite_after_exit$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $self_withdrawal$
DECLARE a jsonb;v jsonb;list jsonb;
BEGIN
 a:=public.titus_institution_account_accept_self_api_v1(
  current_setting('app.titus_test_rejoin_invite')::uuid,
  'f1000000-0000-4000-8000-000000000023');
 IF a->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'rejoin did not issue new immutable admission'; END IF;
 v:=public.titus_institution_account_withdraw_self_api_v1(
  (a->>'admissionId')::uuid,
  'f1000000-0000-4000-8000-000000000024');
 IF v->>'ended'<>'true' THEN RAISE EXCEPTION 'self exit not issued'; END IF;
 list:=public.titus_account_contexts_self_api_v1();
 IF list->'institutions'<>'[]'::jsonb OR
  list->'personal'->>'personId'<>'dddddddd-dddd-4ddd-8ddd-dddddddddddd' THEN
  RAISE EXCEPTION 'self exit removed personal account or left institution'; END IF;
END $self_withdrawal$;
RESET ROLE;

-- This synthetic source never creates separate Auth identities, an institution,
-- Course, paid seat or an actual Titus purchase grant.
DO $u11_postcondition$
BEGIN
 IF (SELECT count(*) FROM auth.users)<>2
 OR (SELECT count(*) FROM reality.auth_person_bindings)<>2
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0
 OR (SELECT count(*) FROM atlas.teaching_courses)<>0 THEN
  RAISE EXCEPTION 'U1 admission test altered identity/license or Course baseline';
 END IF;
END $u11_postcondition$;

ROLLBACK TO SAVEPOINT titus_account_issuer_probe;
