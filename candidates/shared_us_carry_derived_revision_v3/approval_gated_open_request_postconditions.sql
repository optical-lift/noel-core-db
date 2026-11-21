-- Acceptance F: real narrow backend role, explicit request only; no event.
-- Disposable synthetic data. Existing http fixture includes test_plan_02.
BEGIN;
INSERT INTO us.financial_expectation_plans
 (id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
VALUES
 ('cccccccc-3333-4333-8333-333333333333',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'synthetic_primary_01','Synthetic primary source',
  '2027-01-01','2027-03-31','synthetic:primary-source'),
 ('cccccccc-4444-4444-8444-444444444444',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'synthetic_additional_01','Synthetic extra source',
  '2027-01-01','2027-03-31','synthetic:extra-source'),
 ('cccccccc-5555-4555-8555-555555555555',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'synthetic_unadopted_01','Synthetic draft-only source',
  '2027-01-01','2027-03-31','synthetic:draft-source');

INSERT INTO us.financial_expectation_revisions
 (id,owner_auth_user_id,plan_id,revision,standing,source_ref)
VALUES
 ('eeeeeeee-3333-4333-8333-333333333333',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'cccccccc-3333-4333-8333-333333333333',
  1,'draft','synthetic:primary-revision'),
 ('eeeeeeee-4444-4444-8444-444444444444',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'cccccccc-4444-4444-8444-444444444444',
  1,'draft','synthetic:extra-revision'),
 ('eeeeeeee-5555-4555-8555-555555555555',
  'aaaaaaaa-3333-4333-8333-333333333333',
  'cccccccc-5555-4555-8555-555555555555',
  1,'draft','synthetic:draft-revision');
INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,
  economic_scope,money_role,expectation_state,forecast_amount)
VALUES
 ('aaaaaaaa-3333-4333-8333-333333333333',
  'eeeeeeee-3333-4333-8333-333333333333',
  '2027-01-01','primary_income','household','available_inflow','estimated',100),
 ('aaaaaaaa-3333-4333-8333-333333333333',
  'eeeeeeee-4444-4444-8444-444444444444',
  '2027-01-01','extra_income','household','available_inflow','estimated',22);

-- Emulate two pre-Carry legacy adopted plans in the disposable fixture.
-- Restore the immutability trigger immediately after the synthetic seed.
ALTER TABLE us.financial_expectation_revisions DISABLE TRIGGER financial_revisions_immutable;
UPDATE us.financial_expectation_revisions SET standing='adopted'
 WHERE id IN ('eeeeeeee-3333-4333-8333-333333333333',
              'eeeeeeee-4444-4444-8444-444444444444');
ALTER TABLE us.financial_expectation_revisions ENABLE TRIGGER financial_revisions_immutable;

DO $grantproof$
DECLARE sig text:='us.carry_request_financial_open_v3(uuid,text,text,text)';
BEGIN
 IF NOT pg_catalog.has_function_privilege('us_carry_backend',sig,'EXECUTE')
    OR pg_catalog.has_function_privilege('anon',sig,'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated',sig,'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',sig,'EXECUTE')
    OR pg_catalog.has_table_privilege('us_carry_backend','us.carry_financial_open_requests_v3','INSERT')
    OR pg_catalog.has_table_privilege('us_carry_backend','us.carry_case_events_v1','INSERT')
    OR pg_catalog.has_table_privilege('us_carry_backend','us.carry_case_streams_v1','INSERT')
    OR pg_catalog.has_function_privilege('us_carry_backend',
      'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Request-only role acquired forbidden authority'; END IF;
END $grantproof$;

SET LOCAL ROLE us_carry_backend;
DO $proof$
DECLARE r jsonb; v_id text;
BEGIN
 -- No plan activation follows from reading, only an explicit exact request.
 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'bbbbbbbb-3333-4333-8333-333333333333',
     'synthetic_primary_01','explicit-primary-001','primary');
   RAISE EXCEPTION 'Outsider requested owner Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'aaaaaaaa-3333-4333-8333-333333333333',
     'synthetic_unadopted_01','explicit-unadopted-001','primary');
   RAISE EXCEPTION 'Draft baseline treated as adopted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'aaaaaaaa-3333-4333-8333-333333333333',
     'synthetic_additional_01','explicit-additional-001','additional');
   RAISE EXCEPTION 'Extra Case opened before primary';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'aaaaaaaa-2222-4222-8222-222222222222',
     'test_plan_02','explicit-existing-001','primary');
   RAISE EXCEPTION 'Duplicate request allowed for already open stream';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 SELECT us.carry_request_financial_open_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',
   'synthetic_primary_01','explicit-primary-001','primary') INTO r;
 v_id:=r->>'request_id';
 IF r->>'status'<>'pending_independent_approval'
    OR r->>'case_kind'<>'primary'
    OR r->>'case_opened'<>'false'
    OR r->>'recorded_event'<>'false'
    OR r->>'replayed'<>'false'
    OR v_id IS NULL
 THEN RAISE EXCEPTION 'Open request unexpectedly opened an event: %',r; END IF;

 SELECT us.carry_request_financial_open_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',
   'synthetic_primary_01','explicit-primary-001','primary') INTO r;
 IF r->>'request_id'<>v_id OR r->>'replayed'<>'true'
 THEN RAISE EXCEPTION 'Request retry was not idempotent: %',r; END IF;

 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'aaaaaaaa-3333-4333-8333-333333333333',
     'synthetic_primary_01','explicit-different-001','primary');
   RAISE EXCEPTION 'Different action created duplicate opening request';
 EXCEPTION WHEN unique_violation THEN NULL; END;

 BEGIN
   PERFORM us.carry_request_financial_open_v3(
     'aaaaaaaa-3333-4333-8333-333333333333',
     'synthetic_additional_01','explicit-additional-002','additional');
   RAISE EXCEPTION 'Pending primary allowed further case opening';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_append_ordinary_event_v3(
     'aaaaaaaa-3333-4333-8333-333333333333',
     'dddddddd-2222-4222-8222-222222222222',
     'self-approval-001','FACT_ASSERTED',NULL,
     'USER_ASSERTED','us:self:request',
     '{"reason":"Unauthorized ordinary event","value":"forbidden"}'::jsonb,5);
   RAISE EXCEPTION 'Request role may append unapproved events';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   INSERT INTO us.carry_case_streams_v1(
     owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
   VALUES ('aaaaaaaa-3333-4333-8333-333333333333',
           'invalid-direct-case','financial_expectation',
           'cccccccc-3333-4333-8333-333333333333');
   RAISE EXCEPTION 'Raw stream INSERT allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $proof$;

RESET ROLE;
DO $audit$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM us.carry_financial_open_requests_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected precisely one pending request, got %',n; END IF;
 SELECT count(*) INTO n FROM us.carry_case_streams_v1 s
  WHERE s.financial_plan_id='cccccccc-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Pending request unexpectedly opened canonical Case'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_events_v1 e
  WHERE e.owner_auth_user_id='aaaaaaaa-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Pending request created immutable events'; END IF;
END $audit$;
ROLLBACK;
