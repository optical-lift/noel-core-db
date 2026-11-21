-- HELD v3 increment C: real derived review / exact Python digest parity.
-- Required source order: finance, Carry v1, dated-v2, v3 floor, ordinary v3,
-- derived review. SQL fixture is entirely synthetic; transaction ROLLBACK.
BEGIN;
INSERT INTO us.financial_expectation_plans
 (id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
VALUES (
 'cccccccc-1111-4111-8111-111111111111',
 'aaaaaaaa-1111-4111-8111-111111111111',
 'test_plan_01','Disposable forecast fixture',
 '2027-01-01','2027-03-31','test:v3:source'
);
INSERT INTO us.financial_expectation_revisions
 (id,owner_auth_user_id,plan_id,revision,standing,source_ref)
VALUES (
 'eeeeeeee-1111-4111-8111-111111111111',
 'aaaaaaaa-1111-4111-8111-111111111111',
 'cccccccc-1111-4111-8111-111111111111',
 1,'draft','test:v3:baseline'
);
INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,
 money_role,expectation_state,forecast_amount)
VALUES (
 'aaaaaaaa-1111-4111-8111-111111111111',
 'eeeeeeee-1111-4111-8111-111111111111',
 '2027-01-01','synthetic_income','household','available_inflow','estimated',100
);
INSERT INTO us.carry_case_streams_v1
 (id,owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
VALUES (
 'dddddddd-1111-4111-8111-111111111111',
 'aaaaaaaa-1111-4111-8111-111111111111',
 'test_stream_01','financial_expectation',
 'cccccccc-1111-4111-8111-111111111111'
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-1111-4111-8111-111111111111','opened001','CASE_OPENED',
 NULL,'USER_ASSERTED','test:v3:source',
 '{"question":"What is the synthetic financial forecast?"}'::jsonb,1
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-1111-4111-8111-111111111111','initial_seal_01','REVISION_SEALED',
 NULL,'COMMITTED','test:v3:source',
 '{"revision_id":"eeeeeeee-1111-4111-8111-111111111111"}'::jsonb,2
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-1111-4111-8111-111111111111','baseline_import_01','BASELINE_IMPORTED',
 NULL,'OBSERVED','test:v3:source',
 '{"revision_id":"eeeeeeee-1111-4111-8111-111111111111"}'::jsonb,3
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-1111-4111-8111-111111111111','proposed_feb_01','FORECAST_LINE_PROPOSED',
 NULL,'PROJECTED','test:v3:source',
 '{"reason":"Synthetic February estimate","value":{
   "period_month":"2027-02-01","line_key":"monthly_income",
   "economic_scope":"household","subject_key":null,
   "money_role":"available_inflow","expectation_state":"estimated",
   "forecast_amount":"125.00","currency":"USD","explanation":null
 }}'::jsonb,4
);

SET LOCAL ROLE service_role;
DO $proof$
DECLARE
 v jsonb;
 v_receipt record;
 v_retry record;
 v_plan uuid:='cccccccc-1111-4111-8111-111111111111';
 v_stream uuid:='dddddddd-1111-4111-8111-111111111111';
 v_owner uuid:='aaaaaaaa-1111-4111-8111-111111111111';
 v_digest text:='15969e9a70508c8d822c102c7f86b1a6973024eaa1c9a2137283d01f2037499a';
BEGIN
 v:=us.carry_review_derived_revision_v3(v_owner,v_stream,4);
 IF v->>'candidate_digest'<>v_digest OR (v->>'line_count')::int<>2 THEN
   RAISE EXCEPTION 'Source preview did not match canonical portable forecast';
 END IF;
 BEGIN
  PERFORM * FROM us.carry_adopt_derived_revision_v3(
    v_owner,v_stream,'bad_digest_001',4,repeat('0',64));
  RAISE EXCEPTION 'Unreviewed digest was approved';
 EXCEPTION WHEN serialization_failure THEN NULL;
 END;
 BEGIN
  PERFORM * FROM us.carry_adopt_derived_revision_v3(
    'bbbbbbbb-1111-4111-8111-111111111111',
    v_stream,'wrong_owner_001',4,v_digest);
  RAISE EXCEPTION 'Outsider approval accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;

 SELECT * INTO v_receipt FROM us.carry_adopt_derived_revision_v3(
   v_owner,v_stream,'approved_01',4,v_digest);
 IF v_receipt.revision_id IS NULL OR v_receipt.revision_number<>2
    OR v_receipt.seal_sequence<>5 OR v_receipt.replayed THEN
   RAISE EXCEPTION 'SQL derived adoption did not seal exactly once'; END IF;

 SELECT * INTO v_retry FROM us.carry_adopt_derived_revision_v3(
   v_owner,v_stream,'approved_01',4,v_digest);
 IF NOT v_retry.replayed OR v_retry.revision_id<>v_receipt.revision_id
   OR v_retry.seal_event_id<>v_receipt.seal_event_id THEN
   RAISE EXCEPTION 'Identical approved action was not idempotent'; END IF;
 BEGIN
  PERFORM * FROM us.carry_adopt_derived_revision_v3(
    v_owner,v_stream,'approved_01',4,repeat('1',64));
  RAISE EXCEPTION 'Changed fingerprint was replayed';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 BEGIN
  PERFORM * FROM us.carry_adopt_derived_revision_v3(
    v_owner,v_stream,'another_approval_01',4,v_digest);
  RAISE EXCEPTION 'Competing action reused a stale cutoff';
 EXCEPTION WHEN serialization_failure THEN NULL;
 END;
 BEGIN
  INSERT INTO us.financial_expectation_revisions DEFAULT VALUES;
  RAISE EXCEPTION 'App role inserted independent revision after adoption';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  PERFORM * FROM us.carry_append_event_v1(
   v_stream,'forged_seal_01','REVISION_SEALED',NULL,'DERIVED','test:v3:source',
   '{"revision_id":"eeeeeeee-1111-4111-8111-111111111111"}'::jsonb,6);
  RAISE EXCEPTION 'App role invoked unrestricted seal';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$proof$;
RESET ROLE;
DO $final$
DECLARE v_new uuid;
BEGIN
 IF (SELECT count(*) FROM us.financial_expectation_revisions
      WHERE plan_id='cccccccc-1111-4111-8111-111111111111')<>2
 THEN RAISE EXCEPTION 'Failed attempts created an extra revision'; END IF;
 SELECT id INTO v_new FROM us.financial_expectation_revisions
 WHERE plan_id='cccccccc-1111-4111-8111-111111111111'
   AND revision=2 AND standing='adopted';
 IF v_new IS NULL THEN RAISE EXCEPTION 'New revision not adopted'; END IF;
 IF (SELECT count(*) FROM us.carry_case_events_v1
      WHERE stream_id='dddddddd-1111-4111-8111-111111111111')<>5
 THEN RAISE EXCEPTION 'Rejected approvals modified event history'; END IF;
 IF (SELECT count(*) FROM us.financial_expectation_lines
      WHERE revision_id=v_new)<>2
 THEN RAISE EXCEPTION 'Unchanged or changed monthly line missing'; END IF;
 IF (SELECT count(*) FROM us.financial_expectation_lines
       WHERE revision_id='eeeeeeee-1111-4111-8111-111111111111'
         AND forecast_amount=100.00)<>1
 THEN RAISE EXCEPTION 'Original financial baseline changed'; END IF;
 IF (SELECT count(*) FROM us.financial_expectation_lines
       WHERE revision_id=v_new AND
       ((period_month='2027-01-01' AND forecast_amount=100.00) OR
        (period_month='2027-02-01' AND forecast_amount=125.00)))<>2
 THEN RAISE EXCEPTION 'Rebuilt monetary lines do not match review'; END IF;
END
$final$;
ROLLBACK;
