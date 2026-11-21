-- Dedicated fake fixture for restricted Us FastAPI integration.
-- Persistent only inside the disposable RiverSong test database; cleanup deletes the entire PG cluster.
-- Deliberately do not leave this synthetic fixture in shared or production databases.
-- HELD v3 increment C: real derived review / exact Python digest parity.
-- Required source order: finance, Carry v1, dated-v2, v3 floor, ordinary v3,
-- derived review. SQL fixture is entirely synthetic; transaction ROLLBACK.
INSERT INTO us.financial_expectation_plans
 (id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
VALUES (
 'cccccccc-2222-4222-8222-222222222222',
 'aaaaaaaa-2222-4222-8222-222222222222',
 'test_plan_02','Disposable forecast fixture',
 '2027-01-01','2027-03-31','test:v3:source'
);
INSERT INTO us.financial_expectation_revisions
 (id,owner_auth_user_id,plan_id,revision,standing,source_ref)
VALUES (
 'eeeeeeee-2222-4222-8222-222222222222',
 'aaaaaaaa-2222-4222-8222-222222222222',
 'cccccccc-2222-4222-8222-222222222222',
 1,'draft','test:v3:baseline'
);
INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,
 money_role,expectation_state,forecast_amount)
VALUES (
 'aaaaaaaa-2222-4222-8222-222222222222',
 'eeeeeeee-2222-4222-8222-222222222222',
 '2027-01-01','synthetic_income','household','available_inflow','estimated',100
);
INSERT INTO us.carry_case_streams_v1
 (id,owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
VALUES (
 'dddddddd-2222-4222-8222-222222222222',
 'aaaaaaaa-2222-4222-8222-222222222222',
 'test_stream_02','financial_expectation',
 'cccccccc-2222-4222-8222-222222222222'
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-2222-4222-8222-222222222222','opened001','CASE_OPENED',
 NULL,'USER_ASSERTED','test:v3:source',
 '{"question":"What is the synthetic financial forecast?"}'::jsonb,1
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-2222-4222-8222-222222222222','initial_seal_01','REVISION_SEALED',
 NULL,'COMMITTED','test:v3:source',
 '{"revision_id":"eeeeeeee-2222-4222-8222-222222222222"}'::jsonb,2
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-2222-4222-8222-222222222222','baseline_import_01','BASELINE_IMPORTED',
 NULL,'OBSERVED','test:v3:source',
 '{"revision_id":"eeeeeeee-2222-4222-8222-222222222222"}'::jsonb,3
);
SELECT event_sequence FROM us.carry_append_event_v1(
 'dddddddd-2222-4222-8222-222222222222','proposed_feb_01','FORECAST_LINE_PROPOSED',
 NULL,'PROJECTED','test:v3:source',
 '{"reason":"Synthetic February estimate","value":{
   "period_month":"2027-02-01","line_key":"monthly_income",
   "economic_scope":"household","subject_key":null,
   "money_role":"available_inflow","expectation_state":"estimated",
   "forecast_amount":"125.00","currency":"USD","explanation":null
 }}'::jsonb,4
);


