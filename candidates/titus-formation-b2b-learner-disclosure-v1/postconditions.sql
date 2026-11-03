\set ON_ERROR_STOP on
-- FICTIONAL negative + functional test; no signed GoTrue, no real learner.
-- Verifies explicit self-declaration receipt is NOT effective reviewer access.
SELECT set_config('titus.b2b_fixture_current_person',
 '00000000-0000-4000-8000-000000000101',false);
SELECT set_config('titus.disclosure_fixture_auth_uid',
 '00000000-0000-4000-8000-000000000901',false);
SELECT set_config('titus.disclosure_fixture_session',
 '00000000-0000-4000-8000-000000000902',false);

DO $test$
DECLARE
 v_learner uuid := '00000000-0000-4000-8000-000000000101';
 v_reviewer uuid := '00000000-0000-4000-8000-000000000102';
 v_response uuid := '00000000-0000-4000-8000-000000000501';
 v_request uuid := '00000000-0000-4000-8000-000000000911';
 v_request2 uuid := '00000000-0000-4000-8000-000000000912';
 v_request3 uuid := '00000000-0000-4000-8000-000000000913';
 v_request4 uuid := '00000000-0000-4000-8000-000000000914';
 v_receipt uuid;
 v_result jsonb;
 v_old_text text;
BEGIN
 SELECT raw_text INTO v_old_text FROM titus.formation_responses
 WHERE formation_response_id=v_response;

 -- No Person may fabricate consent from another learner's profile.
 PERFORM set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000103',false);
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request);
 IF v_result->>'state'<>'not_available' THEN
  RAISE EXCEPTION 'unbound Person consented to another response: %',v_result;
 END IF;
 PERFORM set_config('titus.b2b_fixture_current_person','',false);
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request);
 IF v_result->>'state'<>'unauthorized' THEN
  RAISE EXCEPTION 'missing actor permitted declaration';
 END IF;
 PERFORM set_config('titus.b2b_fixture_current_person',v_learner::text,false);

 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_learner,'consent',v_request);
 IF v_result->>'state'<>'not_available' THEN
  RAISE EXCEPTION 'self as reviewer permitted';
 END IF;
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   '00000000-0000-4000-8000-000000000503',
   v_reviewer,'consent',v_request);
 IF v_result->>'state'<>'not_available' THEN
  RAISE EXCEPTION 'different Formation Unit permitted';
 END IF;
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'withdraw',v_request);
 IF v_result->>'state'<>'no_prior_consent' THEN
  RAISE EXCEPTION 'withdrawal without preceding consent should fail';
 END IF;

 -- The actual user must express a specific decision; no server synthesizes it.
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request);
 IF v_result->>'state'<>'recorded'
  OR v_result->>'effectiveDisclosure'<>'false'
  OR v_result->>'replayed'<>'false' THEN
  RAISE EXCEPTION 'explicit decision receipt is not recorded or incorrectly granted: %',v_result;
 END IF;
 v_receipt:=(v_result->>'decisionId')::uuid;
 IF NOT EXISTS (
  SELECT 1 FROM titus.formation_review_disclosure_decisions_v1
  WHERE decision_id=v_receipt AND learner_person_entity_id=v_learner
    AND reviewer_person_entity_id=v_reviewer
    AND issuer_auth_user_id='00000000-0000-4000-8000-000000000901'
    AND issuer_auth_session_id='00000000-0000-4000-8000-000000000902'
    AND decision_kind='consent' AND sequence_no=1
    AND prior_decision_id IS NULL
    AND expires_at=issued_at+interval '30 days'
 ) THEN RAISE EXCEPTION 'decision source identity or expiry not persisted'; END IF;

 -- Idempotency returns the same receipt; conflicting request ID is denied.
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request);
 IF v_result->>'state'<>'recorded' OR v_result->>'replayed'<>'true'
   OR (v_result->>'decisionId')::uuid IS DISTINCT FROM v_receipt THEN
  RAISE EXCEPTION 'same request was duplicated';
 END IF;
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,'00000000-0000-4000-8000-000000000103','consent',v_request);
 IF v_result->>'state'<>'conflicting_request' THEN
  RAISE EXCEPTION 'conflicting idempotency key accepted';
 END IF;
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request2);
 IF v_result->>'state'<>'already_in_state' THEN
  RAISE EXCEPTION 'duplicate active consent accepted';
 END IF;

 -- Even if B2B structural receipts match, source issuance and writer stay off.
 IF titus.formation_review_source_issuance_verified_v1(v_response)
     IS DISTINCT FROM false
   OR titus.formation_response_work_authority_gate_v1()
     IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'learner declaration opened a teaching-review gate';
 END IF;

 -- The other Person cannot withdraw the learner's decision.
 PERFORM set_config('titus.b2b_fixture_current_person',
   '00000000-0000-4000-8000-000000000102',false);
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'withdraw',v_request2);
 IF v_result->>'state'<>'not_available' THEN
  RAISE EXCEPTION 'reviewer withdrew learner decision';
 END IF;
 PERFORM set_config('titus.b2b_fixture_current_person',v_learner::text,false);

 -- Malformed/missing issuer session/auth never issues a receipt.
 PERFORM set_config('titus.disclosure_fixture_session','bad-session',false);
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'withdraw',v_request2);
 IF v_result->>'state'<>'unauthorized' THEN
  RAISE EXCEPTION 'malformed auth session passed';
 END IF;
 PERFORM set_config('titus.disclosure_fixture_session',
   '00000000-0000-4000-8000-000000000902',false);
 PERFORM set_config('titus.disclosure_fixture_auth_uid','',false);
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'withdraw',v_request2);
 IF v_result->>'state'<>'unauthorized' THEN
  RAISE EXCEPTION 'absent auth user passed';
 END IF;
 PERFORM set_config('titus.disclosure_fixture_auth_uid',
   '00000000-0000-4000-8000-000000000901',false);

 -- Withdrawal MUST survive a subsequently retired learner binding and stale Unit.
 UPDATE titus.teacher_person_bindings
   SET binding_state='retired',retired_at=now()
   WHERE person_entity_id=v_learner;
 UPDATE titus.formation_units SET review_state='needs_review'
   WHERE formation_unit_id='00000000-0000-4000-8000-000000000301';
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'withdraw',v_request2);
 IF v_result->>'state'<>'recorded'
  OR v_result->>'effectiveDisclosure'<>'false' THEN
  RAISE EXCEPTION 'retirement blocked lawful learner withdrawal: %',v_result;
 END IF;
 IF (SELECT count(*) FROM titus.formation_review_disclosure_decisions_v1
     WHERE formation_response_id=v_response AND reviewer_person_entity_id=v_reviewer)<>2
 THEN RAISE EXCEPTION 'expected consent and withdrawal append history'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM titus.formation_review_disclosure_decisions_v1 d
  WHERE d.formation_response_id=v_response AND d.sequence_no=2
    AND d.prior_decision_id=v_receipt
    AND d.decision_kind='withdraw' AND d.expires_at IS NULL
 ) THEN RAISE EXCEPTION 'withdrawal chain invalid'; END IF;
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request3);
 IF v_result->>'state'<>'not_available' THEN
  RAISE EXCEPTION 'retired learner re-consented';
 END IF;
 UPDATE titus.teacher_person_bindings
   SET binding_state='active',retired_at=NULL
   WHERE person_entity_id=v_learner;
 UPDATE titus.formation_units SET review_state='current'
   WHERE formation_unit_id='00000000-0000-4000-8000-000000000301';
 v_result:=titus.record_formation_review_disclosure_intent_self_v1(
   v_response,v_reviewer,'consent',v_request3);
 IF v_result->>'state'<>'recorded' THEN
  RAISE EXCEPTION 'new explicit consent cannot follow withdrawal';
 END IF;
 IF (SELECT count(*) FROM titus.formation_review_disclosure_decisions_v1
    WHERE formation_response_id=v_response
      AND reviewer_person_entity_id=v_reviewer)<>3 THEN
   RAISE EXCEPTION 'duplicate / missing decision event';
 END IF;

 -- Direct mutations of any stored decision always fail.
 BEGIN
  UPDATE titus.formation_review_disclosure_decisions_v1
  SET decision_kind='withdraw' WHERE decision_id=v_receipt;
  RAISE EXCEPTION 'unexpected direct update success';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='unexpected direct update success' THEN RAISE; END IF;
 END;
 BEGIN
  DELETE FROM titus.formation_review_disclosure_decisions_v1
  WHERE decision_id=v_receipt;
  RAISE EXCEPTION 'unexpected direct delete success';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='unexpected direct delete success' THEN RAISE; END IF;
 END;

 IF (SELECT raw_text FROM titus.formation_responses
      WHERE formation_response_id=v_response) IS DISTINCT FROM v_old_text THEN
   RAISE EXCEPTION 'consent handler modified original learner text';
 END IF;
 IF EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema='titus'
    AND table_name='formation_review_disclosure_decisions_v1'
    AND column_name='raw_text'
 ) THEN RAISE EXCEPTION 'learner text copied to consent evidence'; END IF;

 IF has_table_privilege('anon','titus.formation_review_disclosure_decisions_v1','SELECT')
   OR has_table_privilege('authenticated',
     'titus.formation_review_disclosure_decisions_v1','INSERT')
   OR has_function_privilege('anon',
     'titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid)','EXECUTE')
   OR has_function_privilege('authenticated',
     'titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'browser privilege opened'; END IF;
 IF EXISTS (
  SELECT 1 FROM pg_proc p
  WHERE p.oid='titus.record_formation_review_disclosure_intent_self_v1(uuid,uuid,text,uuid)'::regprocedure
     AND p.prosecdef
 ) THEN RAISE EXCEPTION 'SECURITY DEFINER accidentally added'; END IF;
 IF NOT (
  SELECT relrowsecurity FROM pg_class
  WHERE oid='titus.formation_review_disclosure_decisions_v1'::regclass
 ) THEN RAISE EXCEPTION 'RLS disabled'; END IF;
END;
$test$;
SELECT 'PASS: fictional signed-actor stand-in, source-only disclosure decisions; ZERO reviewer authority' AS verdict;
