-- Schema assertions only; protects the proposed candidate against
-- accidental PUBLIC grants and mistaken second Work storage.
DO $proof$
BEGIN
 IF to_regclass('atlas.ledger_occurrence_work_actions_v1') IS NULL
  OR to_regclass('atlas.ledger_occurrence_work_attention_v1') IS NULL THEN
  RAISE EXCEPTION 'Source-owned action/attention tables missing';
 END IF;
 IF to_regprocedure('atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)') IS NULL
 OR to_regprocedure('atlas.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text)') IS NULL
 OR to_regprocedure('atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)') IS NULL
 OR to_regprocedure('atlas.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text)') IS NULL
 OR to_regprocedure('atlas.my_ledger_event_work_attention_self_api_v1()') IS NULL
 OR to_regprocedure('atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'Missing shared-work extension API';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='guard_blocked_ledger_occurrence_completion_v1')
 THEN RAISE EXCEPTION 'Blocked Work does not protect source Done RPC'; END IF;
 IF has_table_privilege('authenticated','atlas.ledger_occurrence_work_actions_v1','SELECT')
  OR has_table_privilege('authenticated','atlas.ledger_occurrence_work_attention_v1','SELECT')
  OR has_function_privilege('anon','atlas.my_ledger_event_work_attention_self_api_v1()','EXECUTE')
  OR has_function_privilege('anon','atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
  OR has_function_privilege('authenticated','atlas.assert_ledger_occurrence_work_link_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Direct table/internal or anonymous access leaked'; END IF;
 IF NOT has_function_privilege('authenticated',
  'atlas.my_ledger_event_work_attention_self_api_v1()','EXECUTE')
  OR NOT has_function_privilege('authenticated',
  'atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Personal attention or existing Work contract missing'; END IF;
 IF (SELECT count(*) FROM information_schema.columns
  WHERE table_schema='atlas' AND table_name='ledger_occurrence_work_attention_v1'
   AND column_name='person_entity_id')<>1
 THEN RAISE EXCEPTION 'Personal attention not connected to canonical Person'; END IF;
END
$proof$;

-- The following uses ONLY disposable, synthetic identities. It exercises
-- actual SQL API functions under role authenticated, with a local synthetic
-- Auth-session claim, not a cryptographically signed GoTrue session.
-- It is never applied to production and always rolls back its test data.
BEGIN;

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES
 ('f5200000-0000-4000-8000-000000000102','atlas-event-proof-subject-f520','organization','Disposable Event Institution'),
 ('f5200000-0000-4000-8000-000000000021','atlas-event-proof-person-1','person','Disposable Person 1'),
 ('f5200000-0000-4000-8000-000000000022','atlas-event-proof-person-2','person','Disposable Person 2'),
 ('f5200000-0000-4000-8000-000000000023','atlas-event-proof-person-3','person','Disposable Person 3'),
 ('f5200000-0000-4000-8000-000000000024','atlas-event-proof-person-4','person','Disposable Person 4');

INSERT INTO atlas.organizations(id,stable_key,name)
VALUES ('f5200000-0000-4000-8000-000000000101','atlas-event-proof-org-f520','Disposable Event Institution');

INSERT INTO ledger.onboarding_cases(
 id,subject_entity_id,practitioner_person_entity_id,desired_ledger_name,onboarding_state)
VALUES ('f5200000-0000-4000-8000-000000000103','f5200000-0000-4000-8000-000000000102','f5200000-0000-4000-8000-000000000021',
 'Disposable Event Ledger','ready_to_activate');

INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000102','f5200000-0000-4000-8000-000000000103',
 'atlas-event-proof-ledger-f520','Disposable Event Ledger');

INSERT INTO atlas.ledgers(id,stable_key,organization_id,name)
VALUES ('f5200000-0000-4000-8000-000000000104','atlas-event-proof-ledger-f520','f5200000-0000-4000-8000-000000000101','Disposable Event Ledger');

INSERT INTO atlas.ledger_organization_participations(
 ledger_id,organization_id,participation_kind,status)
VALUES ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000101','operating','active');

INSERT INTO local_intel.occurrences(
 id,stable_key,title,occurrence_type,start_at,end_at,status)
VALUES
 ('f5200000-0000-4000-8000-000000000201','atlas-event-proof-f520-a','Disposable October Event A',
 'community_event','2026-10-30 23:00+00','2026-10-31 01:00+00','scheduled'),
 ('f5200000-0000-4000-8000-000000000202','atlas-event-proof-f520-b','Disposable October Event B',
 'community_event','2026-10-30 23:00+00','2026-10-31 01:00+00','scheduled');

INSERT INTO ledger.occurrence_calendar_bindings(ledger_id,occurrence_id,binding_state)
VALUES ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000201','active'),
       ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000202','active');

INSERT INTO atlas.organization_occurrence_bindings(organization_id,occurrence_id,binding_state)
VALUES ('f5200000-0000-4000-8000-000000000101','f5200000-0000-4000-8000-000000000201','active'),
       ('f5200000-0000-4000-8000-000000000101','f5200000-0000-4000-8000-000000000202','active');

INSERT INTO auth.users(id,instance_id,aud,role,email,created_at,updated_at)
VALUES ('f5200000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','atlas-event-proof-1@example.invalid',now(),now()),
 ('f5200000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','atlas-event-proof-2@example.invalid',now(),now()),
 ('f5200000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','atlas-event-proof-3@example.invalid',now(),now()),
 ('f5200000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','atlas-event-proof-4@example.invalid',now(),now());

INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
VALUES ('f5200000-0000-4000-8000-000000000011','f5200000-0000-4000-8000-000000000001',now(),now()),
 ('f5200000-0000-4000-8000-000000000012','f5200000-0000-4000-8000-000000000002',now(),now()),
 ('f5200000-0000-4000-8000-000000000013','f5200000-0000-4000-8000-000000000003',now(),now()),
 ('f5200000-0000-4000-8000-000000000014','f5200000-0000-4000-8000-000000000004',now(),now());

INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state)
VALUES ('f5200000-0000-4000-8000-000000000001','f5200000-0000-4000-8000-000000000021','active'),
 ('f5200000-0000-4000-8000-000000000002','f5200000-0000-4000-8000-000000000022','active'),
 ('f5200000-0000-4000-8000-000000000003','f5200000-0000-4000-8000-000000000023','active'),
 ('f5200000-0000-4000-8000-000000000004','f5200000-0000-4000-8000-000000000024','active');

INSERT INTO ledger.seats(ledger_id,person_entity_id,seat_state)
VALUES ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000021','active'),
 ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000022','active'),
 ('f5200000-0000-4000-8000-000000000104','f5200000-0000-4000-8000-000000000023','active');

SET LOCAL ROLE authenticated;
DO $event_work_proof$
DECLARE
 v_read jsonb;
 v_create jsonb;
 v_retry jsonb;
 v_done jsonb;
 v_third jsonb;
 v_work uuid;
 v_denied boolean;
 v_index jsonb;
BEGIN
 -- Person 1 creates ordinary Work in the first of two same-date Events.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000001',true);
 PERFORM set_config('request.jwt.claims',
   jsonb_build_object('sub','f5200000-0000-4000-8000-000000000001','role','authenticated','session_id','f5200000-0000-4000-8000-000000000011')::text,true);
 v_index:=atlas.ledger_occurrence_shared_index_self_api_v1('f5200000-0000-4000-8000-000000000104'::uuid);
 IF jsonb_array_length(v_index->'events')<>2 THEN
   RAISE EXCEPTION 'Signed-style Event source index did not expose two exact same-date Occurrences: %',v_index;
 END IF;
 v_create:=atlas.create_ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid,'Book music','f520-local-created-1');
 IF v_create->>'ok'<>'true' OR v_create->>'assignmentCreated'<>'false'
    OR v_create->>'workerDayCreated'<>'false' THEN
  RAISE EXCEPTION 'First collaborative Work creation contract failed: %',v_create;
 END IF;
 v_work:=(v_create->>'workItemId')::uuid;
 v_retry:=atlas.create_ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid,'Book music','f520-local-created-1');
 IF (v_retry->>'workItemId')::uuid<>v_work OR v_retry->>'idempotent'<>'true' THEN
  RAISE EXCEPTION 'Replay must reuse exact Work identity: %',v_retry;
 END IF;
 -- Allocation absence is verified after RESET ROLE, using local validator custody.

 -- Person 2 can mark this same source Work done without accepting assignment.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000002',true);
 PERFORM set_config('request.jwt.claims',
   jsonb_build_object('sub','f5200000-0000-4000-8000-000000000002','role','authenticated','session_id','f5200000-0000-4000-8000-000000000012')::text,true);
 v_read:=atlas.ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid);
 IF jsonb_array_length(v_read->'work')<>1
    OR v_read#>>'{work,0,canMarkDone}'<>'true' THEN
  RAISE EXCEPTION 'Person 2 cannot see actionable exact source Work: %',v_read;
 END IF;
 v_done:=atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid,v_work,'f520-local-done-1');
 IF v_done->>'ok'<>'true'
    OR v_done->>'markedByPersonId'<>'f5200000-0000-4000-8000-000000000022'
    OR v_done->>'physicalPerformerAsserted'<>'false' THEN
  RAISE EXCEPTION 'Independent collaborator result contract failed: %',v_done;
 END IF;
 v_retry:=atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid,v_work,'f520-local-done-1');
 IF v_retry->>'idempotent'<>'true'
    OR (v_retry->>'resultId')::uuid<>(v_done->>'resultId')::uuid THEN
  RAISE EXCEPTION 'Done replay failed receipt identity: %',v_retry;
 END IF;

 -- Person 3 sees one completed Work item; second same-date Event sees none.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000003',true);
 PERFORM set_config('request.jwt.claims',
   jsonb_build_object('sub','f5200000-0000-4000-8000-000000000003','role','authenticated','session_id','f5200000-0000-4000-8000-000000000013')::text,true);
 v_third:=atlas.ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid);
 IF jsonb_array_length(v_third->'work')<>1
    OR v_third#>>'{work,0,state}'<>'completed'
    OR v_third#>>'{work,0,markedDoneBy}'<>'Disposable Person 2' THEN
  RAISE EXCEPTION 'Person 3 cannot read true shared state/actor: %',v_third;
 END IF;
 v_read:=atlas.ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000202'::uuid);
 IF jsonb_array_length(v_read->'work')<>0 THEN
  RAISE EXCEPTION 'Two Events on one date were conflated: %',v_read;
 END IF;

 -- Fully authenticated fourth Person without Ledger seat must be denied.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000004',true);
 PERFORM set_config('request.jwt.claims',
   jsonb_build_object('sub','f5200000-0000-4000-8000-000000000004','role','authenticated','session_id','f5200000-0000-4000-8000-000000000014')::text,true);
 v_denied:=false;
 BEGIN
   PERFORM atlas.ledger_occurrence_shared_index_self_api_v1('f5200000-0000-4000-8000-000000000104'::uuid);
 EXCEPTION WHEN insufficient_privilege THEN
   v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Unseated Person read succeeded'; END IF;
 v_denied:=false;
 BEGIN
   PERFORM atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
    'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000201'::uuid,v_work,'f520-illicit-done');
 EXCEPTION WHEN insufficient_privilege THEN
   v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Unseated Person mutated Work'; END IF;

 -- A real connected actor still cannot cross the Event boundary.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000001',true);
 PERFORM set_config('request.jwt.claims',
   jsonb_build_object('sub','f5200000-0000-4000-8000-000000000001','role','authenticated','session_id','f5200000-0000-4000-8000-000000000011')::text,true);
 v_denied:=false;
 BEGIN
  PERFORM atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
   'f5200000-0000-4000-8000-000000000101'::uuid,'f5200000-0000-4000-8000-000000000104'::uuid,'f5200000-0000-4000-8000-000000000202'::uuid,v_work,'f520-cross-event');
 EXCEPTION WHEN insufficient_privilege THEN
  v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Cross-Event Work authority leaked'; END IF;
 RAISE NOTICE 'PASS disposable three-Person create/done/reconcile plus fourth outsider and same-day Event denial';
END
$event_work_proof$;

-- A second source-backed Work identity remains ONE reality when related to
-- two Events. An Event Block and Reopen affect the shared Work globally.
DO $event_extension_proof$
DECLARE v_work uuid;v_created jsonb;v_receipt jsonb;v_reader jsonb;
 v_personal jsonb;v_denied boolean;v_attended jsonb;v_unlinked jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000001',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000001',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000011')::text,true);
 v_created:=atlas.create_ledger_occurrence_shared_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid,
  'Arrange parking','extension-f520-create');
 v_work:=(v_created->>'workItemId')::uuid;
 v_receipt:=atlas.link_existing_ledger_event_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000202'::uuid,
  v_work,'extension-f520-link');
 IF v_receipt->>'workCustodyChanged'<>'false'
   OR (v_receipt->>'workItemId')::uuid<>v_work THEN
  RAISE EXCEPTION 'Existing Work link cloned or transferred source custody';
 END IF;
 v_receipt:=atlas.direct_ledger_event_work_attention_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid,
  v_work,'f5200000-0000-4000-8000-000000000022'::uuid,true,
  'extension-f520-direct');
 IF v_receipt->>'workOwnershipTransferred'<>'false' THEN
   RAISE EXCEPTION 'Personal attention transferred source custody';
 END IF;

 -- Person 2 can block from Event B, without becoming Worker/assignee.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000002',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000002',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000012')::text,true);
 v_personal:=atlas.my_ledger_event_work_attention_self_api_v1();
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_personal->'items') row_item
   WHERE row_item->>'workItemId'=v_work::text
     AND row_item->>'occurrenceId'='f5200000-0000-4000-8000-000000000201'
 ) THEN RAISE EXCEPTION 'Source-linked Work not present in Person attention'; END IF;
 v_receipt:=atlas.change_ledger_event_ordinary_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000202'::uuid,v_work,
  'blocked','extension-f520-block','Blocked until another resource is available');
 v_reader:=atlas.ledger_occurrence_work_extension_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid);
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_reader->'work') row_item
   WHERE row_item->>'workItemId'=v_work::text
    AND row_item->>'state'='blocked' AND row_item->>'canMarkDone'='false'
 ) THEN RAISE EXCEPTION 'One Work blocked in Event B not blocked in Event A'; END IF;

 -- Even the original Done kernel must not bypass the blocked source.
 v_denied:=false;
 BEGIN
  PERFORM atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
   'f5200000-0000-4000-8000-000000000101'::uuid,
   'f5200000-0000-4000-8000-000000000104'::uuid,
   'f5200000-0000-4000-8000-000000000201'::uuid,
    v_work,'extension-f520-bypass-attempt');
 EXCEPTION WHEN check_violation THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Done bypassed a global Work block'; END IF;

 -- Person 3 can reopen in Event A and remove Event B without deleting Work.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000003',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000003',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000013')::text,true);
 PERFORM atlas.change_ledger_event_ordinary_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid,
   v_work,'reopened','extension-f520-reopen',null);
 v_unlinked:=atlas.change_ledger_event_ordinary_work_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000202'::uuid,
   v_work,'removed','extension-f520-unlink',null);
 v_reader:=atlas.ledger_occurrence_work_extension_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid);
 IF v_unlinked->>'underlyingWorkCancelled'<>'false'
    OR NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_reader->'work') row_item
      WHERE row_item->>'workItemId'=v_work::text
        AND row_item->>'workState'='open'
    ) THEN
  RAISE EXCEPTION 'Event unlink cancelled or replaced underlying Work';
 END IF;

 -- Old Event A source Work remains; Person 1 checks it off.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000001',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000001',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000011')::text,true);
 v_receipt:=atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
  'f5200000-0000-4000-8000-000000000101'::uuid,
  'f5200000-0000-4000-8000-000000000104'::uuid,
  'f5200000-0000-4000-8000-000000000201'::uuid,
  v_work,'extension-f520-done');
 IF v_receipt->>'workState'<>'completed' THEN
  RAISE EXCEPTION 'Ordinary Work completion lost after Event unlink';
 END IF;
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000002',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000002',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000012')::text,true);
 v_personal:=atlas.my_ledger_event_work_attention_self_api_v1();
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_personal->'items') row_item
   WHERE row_item->>'workItemId'=v_work::text) THEN
   RAISE EXCEPTION 'Completed Work left ghost personal attention';
 END IF;

 -- Fourth authenticated synthetic outsider gets neither linked Work nor attention.
 PERFORM set_config('request.jwt.claim.sub','f5200000-0000-4000-8000-000000000004',true);
 PERFORM set_config('request.jwt.claims',
  jsonb_build_object('sub','f5200000-0000-4000-8000-000000000004',
    'role','authenticated','session_id','f5200000-0000-4000-8000-000000000014')::text,true);
 v_denied:=false;
 BEGIN
  PERFORM atlas.ledger_occurrence_work_extension_self_api_v1(
   'f5200000-0000-4000-8000-000000000101'::uuid,
   'f5200000-0000-4000-8000-000000000104'::uuid,
   'f5200000-0000-4000-8000-000000000201'::uuid);
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Unseated Person inspected Event extension'; END IF;
 RAISE NOTICE 'PASS linked Work, global Block/Reopen, context Remove, personal attention and outsider denial';
END
$event_extension_proof$;

RESET ROLE;
DO $private_validator$
BEGIN
 IF EXISTS (
   SELECT 1 FROM atlas.work_allocations a
   JOIN atlas.work_items w ON w.id=a.work_item_id
   WHERE w.organization_id='f5200000-0000-4000-8000-000000000101'::uuid
     AND w.stable_key LIKE 'ledger-occurrence-shared:%'
 ) THEN
   RAISE EXCEPTION 'Ordinary Event checklist falsely generated a Work allocation';
 END IF;
END
$private_validator$;
ROLLBACK;
