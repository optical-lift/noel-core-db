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
DECLARE v jsonb;
BEGIN
  v:=us.carry_review_derived_revision_v3(
   'aaaaaaaa-1111-4111-8111-111111111111',
   'dddddddd-1111-4111-8111-111111111111',4);
  IF v->>'candidate_digest'<>
    '15969e9a70508c8d822c102c7f86b1a6973024eaa1c9a2137283d01f2037499a'
    OR (v->>'line_count')::integer<>2
    OR v->'lines'->0->>'forecast_amount'<>'100.00'
    OR v->'lines'->1->>'forecast_amount'<>'125.00'
    OR v ? 'plan_id'
    OR v->>'adopted'<>'false'
  THEN
   RAISE EXCEPTION 'Derived review values or Python canonical digest mismatched: %',v;
  END IF;

  BEGIN
    PERFORM us.carry_review_derived_revision_v3(
     'bbbbbbbb-1111-4111-8111-111111111111',
     'dddddddd-1111-4111-8111-111111111111',4);
    RAISE EXCEPTION 'Outsider review unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM us.carry_review_derived_revision_v3(
     'aaaaaaaa-1111-4111-8111-111111111111',
     'dddddddd-1111-4111-8111-111111111111',3);
    RAISE EXCEPTION 'Stale review unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
END
$proof$;
ROLLBACK;
