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
-- G2 acceptance + explicit owner grant, expiry constraints, revocation and
-- amount-free source review; all original G1 negative tests above still apply.
DO $scope_grants$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'us.carry_accept_primary_reviewer_v3(uuid,uuid,text)',
  'us.carry_grant_primary_attestation_v3(uuid,uuid,text,timestamptz)',
  'us.carry_revoke_primary_attestation_v3(uuid,uuid,text,text)',
  'us.carry_read_primary_attestation_v3(uuid,uuid)'
 ] LOOP
  IF NOT has_function_privilege('us_carry_backend',sig,'EXECUTE')
    OR has_function_privilege('anon',sig,'EXECUTE')
    OR has_function_privilege('authenticated',sig,'EXECUTE')
    OR has_function_privilege('service_role',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'G2 private function grant unexpected: %',sig; END IF;
 END LOOP;
END $scope_grants$;
DO $g2$
DECLARE v_req jsonb; v_nom jsonb; v_acc jsonb; v_grant jsonb;
        v_summary jsonb; v_revoke jsonb; n uuid; exp timestamptz;
BEGIN
 v_req:=us.carry_request_financial_open_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',
  'synthetic_nominate_01','synthetic_req_01','primary');
 v_nom:=us.carry_nominate_primary_reviewer_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',
  (v_req->>'request_id')::uuid,
  '22222222-3333-4333-8333-333333333333','nominate-reviewer-01');
 n:=(v_nom->>'nomination_id')::uuid;

 BEGIN
  PERFORM us.carry_read_primary_attestation_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n);
  RAISE EXCEPTION 'Nomination alone exposed attestation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
  PERFORM us.carry_grant_primary_attestation_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',
   n,'premature-grant-001',pg_catalog.now()+interval '1 day');
  RAISE EXCEPTION 'Owner granted without independent nominee consent';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 BEGIN
  PERFORM us.carry_accept_primary_reviewer_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',n,'self-accept-key-001');
  RAISE EXCEPTION 'Owner accepted on behalf of nominee';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 v_acc:=us.carry_accept_primary_reviewer_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n,'reviewer-accept-001');
 IF v_acc->>'state'<>'accepted_pending_owner_disclosure_grant'
  OR v_acc->>'financial_access_granted'<>'false'
  OR v_acc->>'approval_authority_granted'<>'false'
  OR v_acc->>'case_opened'<>'false'
  OR v_acc->>'recorded_event'<>'false'
  OR v_acc->>'replayed'<>'false'
 THEN RAISE EXCEPTION 'Nominee acceptance exceeded scope: %',v_acc; END IF;

 IF (us.carry_accept_primary_reviewer_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n,
   'reviewer-accept-001')->>'replayed')<>'true'
 THEN RAISE EXCEPTION 'Nominee acceptance retry duplicated'; END IF;
 BEGIN
  PERFORM us.carry_accept_primary_reviewer_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n,'changed-accept-001');
  RAISE EXCEPTION 'Conflicting nominee acceptance accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;

 BEGIN
  PERFORM us.carry_read_primary_attestation_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n);
  RAISE EXCEPTION 'Acceptance alone exposed attestation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_primary_attestation_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',
   n,'nominee-self-grant-001',pg_catalog.now()+interval '1 day');
  RAISE EXCEPTION 'Nominee granted themselves financial disclosure';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_primary_attestation_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',
   n,'expired-grant-001',pg_catalog.now()-interval '1 hour');
  RAISE EXCEPTION 'Past expiry accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_primary_attestation_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',
   n,'too-long-grant-001',pg_catalog.now()+interval '30 days');
  RAISE EXCEPTION 'Month-long grant accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

 exp:=pg_catalog.now()+interval '1 day';
 v_grant:=us.carry_grant_primary_attestation_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',n,'owner-grant-001',exp);
 IF v_grant->>'scope'<>'opening_attestation_only'
  OR v_grant->>'financial_lines_visible'<>'false'
  OR v_grant->>'event_approval_allowed'<>'false'
  OR v_grant->>'replayed'<>'false'
 THEN RAISE EXCEPTION 'Granted too much: %',v_grant; END IF;
 IF (us.carry_grant_primary_attestation_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',n,
  'owner-grant-001',exp)->>'replayed')<>'true'
 THEN RAISE EXCEPTION 'Grant retry did not replay'; END IF;

 BEGIN
  PERFORM us.carry_read_primary_attestation_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',n);
  RAISE EXCEPTION 'Owner forged nominee attestation reader';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_primary_attestation_v3(
   'cccccccc-3333-4333-8333-333333333333',n);
  RAISE EXCEPTION 'Outsider read nominee attestation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 v_summary:=us.carry_read_primary_attestation_v3(
  'bbbbbbbb-3333-4333-8333-333333333333',n);
 IF v_summary->>'scope'<>'opening_attestation_only'
  OR (v_summary->>'baseline_line_count')::integer<>1
  OR length(v_summary->>'baseline_snapshot_digest')<>64
  OR v_summary->>'financial_lines_visible'<>'false'
  OR v_summary->>'event_approval_allowed'<>'false'
  OR v_summary ? 'plan_key'
  OR v_summary ? 'forecast_amount'
  OR v_summary ? 'owner_auth_user_id'
  OR v_summary ? 'lines'
 THEN RAISE EXCEPTION 'Private attestation response exceeded scope: %',v_summary; END IF;

 BEGIN
  PERFORM us.carry_revoke_primary_attestation_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n,
   'nominee-revoke-001','No owner authority here');
  RAISE EXCEPTION 'Nominee revoked owner scope';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 v_revoke:=us.carry_revoke_primary_attestation_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',n,
  'owner-revoke-001','Owner withdrew reviewer access');
 IF v_revoke->>'review_access'<>'revoked'
  OR v_revoke->>'event_approval_allowed'<>'false'
  OR v_revoke->>'replayed'<>'false'
 THEN RAISE EXCEPTION 'Revocation response wrong: %',v_revoke; END IF;
 IF (us.carry_revoke_primary_attestation_v3(
  'aaaaaaaa-3333-4333-8333-333333333333',n,
  'owner-revoke-001','Owner withdrew reviewer access')->>'replayed')<>'true'
 THEN RAISE EXCEPTION 'Revocation retry did not replay'; END IF;

 BEGIN
  PERFORM us.carry_read_primary_attestation_v3(
   'bbbbbbbb-3333-4333-8333-333333333333',n);
  RAISE EXCEPTION 'Revoked nominee still saw attestation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_primary_attestation_v3(
   'aaaaaaaa-3333-4333-8333-333333333333',n,'owner-grant-001',exp);
  RAISE EXCEPTION 'Revoked grant could be re-enabled by replay';
 EXCEPTION WHEN unique_violation THEN NULL; END;

 BEGIN
  PERFORM count(*) FROM us.carry_primary_review_disclosure_grants_v3;
  RAISE EXCEPTION 'Backend role can read raw grant rows';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $g2$;
RESET ROLE;
DO $audit$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM us.carry_primary_reviewer_nominations_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Nomination duplicate or missing'; END IF;
 SELECT count(*) INTO n FROM us.carry_primary_reviewer_acceptances_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Acceptances duplicated or missing'; END IF;
 SELECT count(*) INTO n FROM us.carry_primary_review_disclosure_grants_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Scoped grant duplicated or missing'; END IF;
 SELECT count(*) INTO n FROM us.carry_primary_review_disclosure_revocations_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Revocation duplicated or missing'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_streams_v1
 WHERE financial_plan_id='99999999-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Nomination opened a Case'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_events_v1
 WHERE owner_auth_user_id='aaaaaaaa-3333-4333-8333-333333333333';
 IF n<>0 THEN RAISE EXCEPTION 'Nomination appended financial events'; END IF;
END $audit$;
ROLLBACK;
