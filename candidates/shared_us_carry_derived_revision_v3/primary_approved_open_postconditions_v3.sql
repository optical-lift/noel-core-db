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


-- All following operations are synthetic and roll back on exit.
DO $grants$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
 'us.carry_authorize_primary_open_approval_v3(uuid,uuid,text,timestamptz)',
 'us.carry_approve_and_open_primary_v3(uuid,uuid,text)'
 ] LOOP
  IF NOT has_function_privilege('us_carry_backend',sig,'EXECUTE')
    OR has_function_privilege('service_role',sig,'EXECUTE')
    OR has_function_privilege('authenticated',sig,'EXECUTE')
    OR has_function_privilege('anon',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'G3 function privilege failed: %',sig; END IF;
 END LOOP;
 IF has_table_privilege('us_carry_backend','us.carry_case_events_v1','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_case_streams_v1','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_primary_open_approval_grants_v3','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_primary_open_approval_decisions_v3','SELECT')
  OR has_function_privilege('us_carry_backend',
   'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Dedicated backend acquired direct writer or reader'; END IF;
END $grants$;

SET LOCAL ROLE us_carry_backend;
DO $g3$
DECLARE o uuid:='aaaaaaaa-3333-4333-8333-333333333333';
 r uuid:='bbbbbbbb-3333-4333-8333-333333333333';
 req jsonb; nom jsonb; consent jsonb; read_grant jsonb;
 approval_grant jsonb; decision jsonb; replay jsonb;
 n uuid; exp timestamptz; st uuid;
BEGIN
 req:=us.carry_request_financial_open_v3(
  o,'synthetic_nominate_01','synthetic_req_01','primary');
 nom:=us.carry_nominate_primary_reviewer_v3(
  o,(req->>'request_id')::uuid,'22222222-3333-4333-8333-333333333333',
  'nominate-reviewer-01');
 n:=(nom->>'nomination_id')::uuid;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'approval-without-grant-01');
  RAISE EXCEPTION 'G1 nomination alone opened canonical Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 consent:=us.carry_accept_primary_reviewer_v3(r,n,'g3-independent-consent-001');
 IF consent->>'approval_authority_granted'<>'false'
 THEN RAISE EXCEPTION 'Acceptance already grants approval'; END IF;
 exp:=pg_catalog.now()+interval '2 hours';
 read_grant:=us.carry_grant_primary_attestation_v3(o,n,'g3-read-scope-001',exp);
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'approval-read-only-01');
  RAISE EXCEPTION 'G2 attestation alone opened Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   r,n,'nominee-self-authorize-001',exp);
  RAISE EXCEPTION 'Nominee granted own opening approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   o,n,'too-long-approval-001',pg_catalog.now()+interval '6 days');
  RAISE EXCEPTION 'G3 expiry exceeded G2 expiry';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 approval_grant:=us.carry_authorize_primary_open_approval_v3(
   o,n,'owner-explicit-g3-approval-001',pg_catalog.now()+interval '1 hour');
 IF approval_grant->>'scope'<>'open_primary_case_and_import_attested_baseline'
 OR approval_grant->>'decision_recorded'<>'false'
 OR approval_grant->>'case_opened'<>'false'
 OR approval_grant->>'recorded_event'<>'false'
 OR approval_grant->>'replayed'<>'false'
 OR approval_grant->>'expires_at' IS NULL
 THEN RAISE EXCEPTION 'G3 grant did not remain non-durable: %',approval_grant; END IF;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(o,n,'owner-self-approve-001');
  RAISE EXCEPTION 'Owner signed own approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(
   'cccccccc-3333-4333-8333-333333333333',n,'outsider-approve-001');
  RAISE EXCEPTION 'Outsider approved primary Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 decision:=us.carry_approve_and_open_primary_v3(r,n,'approver-signed-g3-001');
 IF decision->>'status'<>'approved_primary_opened'
 OR (decision->>'event_count')::integer<>2
 OR decision->>'replayed'<>'false'
 OR decision->>'stream_id' IS NULL OR decision->>'approval_decision_id' IS NULL
 THEN RAISE EXCEPTION 'Independent approval did not atomically open history: %',decision; END IF;
 st:=(decision->>'stream_id')::uuid;
 replay:=us.carry_approve_and_open_primary_v3(r,n,'approver-signed-g3-001');
 IF replay->>'replayed'<>'true' OR replay->>'stream_id'<>st::text
 OR replay->>'approval_decision_id'<>decision->>'approval_decision_id'
 THEN RAISE EXCEPTION 'G3 signed replay was not idempotent: %',replay; END IF;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'different-decision-g3-001');
  RAISE EXCEPTION 'Changed decision key created another approval';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   o,n,'new-grant-after-opening-001',pg_catalog.now()+interval '30 minutes');
  RAISE EXCEPTION 'Owner reopened grant for already opened Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_append_event_v1(
    st,'direct-appender-should-deny-001','FACT_ASSERTED',NULL,
    'USER_ASSERTED','us:forbidden:direct',
    '{"reason":"Bypass prohibited","value":true}'::jsonb,3);
  RAISE EXCEPTION 'Backend gained legacy event append';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $g3$;
RESET ROLE;
DO $audit$
DECLARE n integer; s uuid; owner_id uuid:='aaaaaaaa-3333-4333-8333-333333333333';
 rev_id uuid:='88888888-3333-4333-8333-333333333333';
 d us.carry_primary_open_approval_decisions_v3%ROWTYPE;
BEGIN
 SELECT count(*) INTO n FROM us.carry_primary_open_approval_grants_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected exactly one explicit G3 approval grant'; END IF;
 SELECT count(*) INTO n FROM us.carry_primary_open_approval_decisions_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected exactly one independent decision'; END IF;
 SELECT * INTO d FROM us.carry_primary_open_approval_decisions_v3 LIMIT 1;
 IF d.owner_auth_user_id<>owner_id
  OR d.approver_auth_user_id<>'bbbbbbbb-3333-4333-8333-333333333333'
  OR d.owner_person_entity_id=d.approver_person_entity_id
  OR d.baseline_revision_id<>rev_id
 THEN RAISE EXCEPTION 'Two canonical Person witnesses misattributed'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_streams_v1
 WHERE financial_plan_id='99999999-3333-4333-8333-333333333333';
 IF n<>1 THEN RAISE EXCEPTION 'Primary Case duplicated'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_events_v1
 WHERE stream_id=d.canonical_stream_id;
 IF n<>2 THEN RAISE EXCEPTION 'Wrong immutable event count'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM us.carry_case_events_v1 a
  JOIN us.carry_case_events_v1 b ON b.stream_id=a.stream_id
  WHERE a.id=d.case_opened_event_id AND b.id=d.baseline_imported_event_id
   AND a.stream_sequence=1 AND b.stream_sequence=2
   AND a.event_type='CASE_OPENED' AND b.event_type='BASELINE_IMPORTED'
   AND a.actor_auth_user_id=owner_id AND b.actor_auth_user_id=owner_id
   AND b.previous_event_digest=a.event_digest
   AND b.payload->>'revision_id'=rev_id::text
   AND (b.payload->>'line_count')::integer=d.baseline_line_count
   AND b.payload->>'snapshot_digest'=d.baseline_snapshot_digest
 ) THEN RAISE EXCEPTION 'Canonical pair provenance/digest/approval mismatch'; END IF;
 SELECT count(*) INTO n FROM us.financial_expectation_revisions
 WHERE id=rev_id AND standing='adopted';
 IF n<>1 THEN RAISE EXCEPTION 'Original baseline was modified'; END IF;
END $audit$;
ROLLBACK;
