-- Gate G1 nomination-only negative/grants test. Disposable PG only.
BEGIN;
INSERT INTO auth.users(id) VALUES
 ('aaaaaaaa-3333-4333-8333-333333333333'),
 ('bbbbbbbb-3333-4333-8333-333333333333'),
 ('cccccccc-3333-4333-8333-333333333333'),
 ('dddddddd-3333-4333-8333-333333333333');
INSERT INTO reality.entities(id,entity_kind,identity_state) VALUES
 ('11111111-3333-4333-8333-333333333333','person','canonical'),
 ('22222222-3333-4333-8333-333333333333','person','canonical'),
 ('33333333-3333-4333-8333-333333333333','person','disputed'),
 ('44444444-3333-4333-8333-333333333333','person','canonical');
INSERT INTO reality.auth_person_bindings
 (id,auth_user_id,person_entity_id,binding_state) VALUES
 ('eeeeeeee-3333-4333-8333-333333333333',
  'aaaaaaaa-3333-4333-8333-333333333333',
  '11111111-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-4444-4444-8444-444444444444',
  'bbbbbbbb-3333-4333-8333-333333333333',
  '22222222-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-5555-4555-8555-555555555555',
  'cccccccc-3333-4333-8333-333333333333',
  '33333333-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-6666-4666-8666-666666666666',
  'dddddddd-3333-4333-8333-333333333333',
  '44444444-3333-4333-8333-333333333333','retired');

INSERT INTO us.financial_expectation_plans
 (id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
 VALUES('99999999-3333-4333-8333-333333333333',
        'aaaaaaaa-3333-4333-8333-333333333333',
        'synthetic_nominate_01','Synthetic nomination-only source',
        '2027-01-01','2027-03-31','synthetic:native:source');
INSERT INTO us.financial_expectation_revisions
 (id,owner_auth_user_id,plan_id,revision,standing,source_ref)
 VALUES('88888888-3333-4333-8333-333333333333',
        'aaaaaaaa-3333-4333-8333-333333333333',
        '99999999-3333-4333-8333-333333333333',
        1,'draft','synthetic:native:revision');
INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,
  economic_scope,money_role,expectation_state,forecast_amount)
 VALUES('aaaaaaaa-3333-4333-8333-333333333333',
        '88888888-3333-4333-8333-333333333333',
        '2027-01-01','source_income','household','available_inflow','estimated',20);

-- Synthetic legacy adopted original, not possible as an independent
-- application operation. Re-enable source trigger immediately.
ALTER TABLE us.financial_expectation_revisions
 DISABLE TRIGGER financial_revisions_immutable;
UPDATE us.financial_expectation_revisions SET standing='adopted'
 WHERE id='88888888-3333-4333-8333-333333333333';
ALTER TABLE us.financial_expectation_revisions
 ENABLE TRIGGER financial_revisions_immutable;

DO $grants$
DECLARE v text:='us.carry_nominate_primary_reviewer_v3(uuid,uuid,uuid,text)';
BEGIN
 IF NOT has_function_privilege('us_carry_backend',v,'EXECUTE')
 OR has_function_privilege('anon',v,'EXECUTE')
 OR has_function_privilege('authenticated',v,'EXECUTE')
 OR has_function_privilege('service_role',v,'EXECUTE')
 OR has_table_privilege('us_carry_backend',
                        'us.carry_primary_reviewer_nominations_v3','SELECT')
 OR has_table_privilege('us_carry_backend',
                        'us.carry_primary_reviewer_nominations_v3','INSERT')
 OR has_table_privilege('us_carry_backend','reality.auth_person_bindings','SELECT')
 OR has_table_privilege('us_carry_backend','auth.users','SELECT')
 OR has_table_privilege('us_carry_backend','us.carry_case_events_v1','INSERT')
 THEN RAISE EXCEPTION 'Nomination granted direct read, write or public access'; END IF;
END $grants$;

SET LOCAL ROLE us_carry_backend;
DO $proof$
DECLARE v_req jsonb; v_nom jsonb; v_id uuid;
BEGIN
 v_req:=us.carry_request_financial_open_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',
    'synthetic_nominate_01','synthetic_req_01','primary');
 v_id:=(v_req->>'request_id')::uuid;
 IF v_req->>'status'<>'pending_independent_approval'
 THEN RAISE EXCEPTION 'F opening request unavailable'; END IF;

 BEGIN
   PERFORM us.carry_nominate_primary_reviewer_v3(
    'bbbbbbbb-3333-4333-8333-333333333333',v_id,
    '22222222-3333-4333-8333-333333333333','other-owner-key-01');
   RAISE EXCEPTION 'Outsider nominated reviewer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '11111111-3333-4333-8333-333333333333','self-person-key-01');
   RAISE EXCEPTION 'Owner self nominated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '33333333-3333-4333-8333-333333333333','disputed-person-01');
   RAISE EXCEPTION 'Disputed identity nominated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '44444444-3333-4333-8333-333333333333','retired-person-01');
   RAISE EXCEPTION 'Retired identity nominated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 v_nom:=us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '22222222-3333-4333-8333-333333333333','nominate-reviewer-01');
 IF v_nom->>'status'<>'pending_nominee_acceptance'
 OR v_nom->>'case_opened'<>'false'
 OR v_nom->>'financial_access_granted'<>'false'
 OR v_nom->>'approval_authority_granted'<>'false'
 OR v_nom->>'recorded_event'<>'false'
 OR v_nom->>'replayed'<>'false'
 OR v_nom->>'nomination_id' IS NULL
 OR v_nom ? 'nominee_auth_user_id'
 THEN RAISE EXCEPTION 'G1 nomination incorrectly granted authority: %',v_nom; END IF;

 IF (us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '22222222-3333-4333-8333-333333333333',
    'nominate-reviewer-01')->>'replayed')<>'true'
 THEN RAISE EXCEPTION 'Nomination retry not idempotent'; END IF;

 BEGIN
   PERFORM us.carry_nominate_primary_reviewer_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',v_id,
    '22222222-3333-4333-8333-333333333333',
    'changed-nomination-01');
   RAISE EXCEPTION 'Conflicting nomination accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;

 BEGIN
   PERFORM count(*) FROM us.carry_primary_reviewer_nominations_v3;
   RAISE EXCEPTION 'Raw nomination table SELECT allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
   PERFORM us.carry_append_ordinary_event_v3(
    'aaaaaaaa-3333-4333-8333-333333333333',
    'dddddddd-2222-4222-8222-222222222222',
    'fake-approved-01','FACT_ASSERTED',NULL,
    'USER_ASSERTED','us:self:nomination',
    '{"reason":"Nomination is not approval","value":1}'::jsonb,5);
   RAISE EXCEPTION 'Nominated reviewer can append Carry event';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $proof$;
RESET ROLE;
DO $audit$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM us.carry_primary_reviewer_nominations_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Nomination duplicate or missing'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_streams_v1
 WHERE financial_plan_id='99999999-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Nomination opened a Case'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_events_v1
 WHERE owner_auth_user_id='aaaaaaaa-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Nomination appended financial events'; END IF;
END $audit$;
ROLLBACK;
