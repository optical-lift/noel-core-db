-- Schema-only postconditions, no protected person/event data.
DO $proof$
DECLARE
  v_pair text;
  v_kind text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_pair
    FROM pg_constraint c
    WHERE c.conrelid='atlas.work_item_context_links'::regclass
      AND c.conname='work_item_context_links_subject_pair_v1';
  IF v_pair IS NULL OR position('temporal' in v_pair)=0
     OR position('occurrence' in v_pair)=0 THEN
    RAISE EXCEPTION 'Event context pair not admitted';
  END IF;
  SELECT acceptance_mode INTO v_kind
    FROM atlas.work_result_contract_policies
    WHERE contract_key='ledger_occurrence_shared_confirmation_v1'
      AND source_domain='organization' AND active;
  IF v_kind IS DISTINCT FROM 'domain_adapter' THEN
    RAISE EXCEPTION 'Shared checklist confirmation policy missing/mismatched';
  END IF;
  IF to_regprocedure('atlas.ledger_occurrence_shared_index_self_api_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)') IS NULL
     OR to_regprocedure('atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Required source operation was not created';
  END IF;
  IF has_function_privilege('anon','atlas.ledger_occurrence_shared_index_self_api_v1(uuid)','EXECUTE')
     OR has_function_privilege('anon','atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Source boundary leaked privileged function access';
  END IF;
  IF NOT has_function_privilege('authenticated','atlas.ledger_occurrence_shared_index_self_api_v1(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Authenticated source operations missing';
  END IF;
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
 IF EXISTS(select 1 from atlas.work_allocations where work_item_id=v_work) THEN
  RAISE EXCEPTION 'Shared checklist falsely generated an allocation';
 END IF;

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
RESET ROLE;
ROLLBACK;
