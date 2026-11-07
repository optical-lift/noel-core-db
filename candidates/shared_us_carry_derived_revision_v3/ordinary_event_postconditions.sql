-- HELD v3 increment B / disposable PostgreSQL only.
-- Apply on top of finance, Carry v1, dated v2, privilege floor, ordinary wrapper.
-- A real signed user test is separately required at the private Us HTTP boundary.
BEGIN;
DO $priv$
BEGIN
  IF NOT pg_catalog.has_function_privilege(
    'service_role',
    'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
  THEN RAISE EXCEPTION 'Bounded service event writer unavailable'; END IF;
  IF pg_catalog.has_function_privilege(
    'anon',
    'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
    OR pg_catalog.has_function_privilege(
    'authenticated',
    'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
  THEN RAISE EXCEPTION 'Ordinary event writer exposed to clients'; END IF;
  IF pg_catalog.has_function_privilege(
    'service_role',
    'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
  THEN RAISE EXCEPTION 'Unrestricted v1 seal reachable by service role'; END IF;
END
$priv$;

-- Synthetic, fixed, clearly non-user fixtures. This entire transaction rolls
-- back, even after a successful owner event insertion.
INSERT INTO us.financial_expectation_plans(
  id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref
)
VALUES(
  'cccccccc-1111-4111-8111-111111111111',
  'aaaaaaaa-1111-4111-8111-111111111111',
  'test_plan_01','Synthetic acceptance only',
  '2026-01-01','2026-12-31','test:v3:owner'
);
INSERT INTO us.carry_case_streams_v1(
  id,owner_auth_user_id,stream_key,subject_kind,financial_plan_id
)
VALUES(
  'dddddddd-1111-4111-8111-111111111111',
  'aaaaaaaa-1111-4111-8111-111111111111',
  'test_stream_01','financial_expectation',
  'cccccccc-1111-4111-8111-111111111111'
);
SET LOCAL ROLE service_role;

DO $event$
DECLARE
  v_event_id uuid;
  v_sequence bigint;
  v_replayed boolean;
BEGIN
  SELECT a.event_id,a.event_sequence,a.replayed
   INTO v_event_id,v_sequence,v_replayed
  FROM us.carry_append_ordinary_event_v3(
    'aaaaaaaa-1111-4111-8111-111111111111',
    'dddddddd-1111-4111-8111-111111111111',
    'opened001','CASE_OPENED',NULL,'USER_ASSERTED',
    'test:v3:owner', '{"question":"Will the synthetic event open?"}'::jsonb,1
  ) a;
  IF v_event_id IS NULL OR v_sequence<>1 OR v_replayed
  THEN RAISE EXCEPTION 'Owner ordinary event was not recorded'; END IF;

  SELECT a.event_id,a.event_sequence,a.replayed
   INTO v_event_id,v_sequence,v_replayed
  FROM us.carry_append_ordinary_event_v3(
    'aaaaaaaa-1111-4111-8111-111111111111',
    'dddddddd-1111-4111-8111-111111111111',
    'opened001','CASE_OPENED',NULL,'USER_ASSERTED',
    'test:v3:owner', '{"question":"Will the synthetic event open?"}'::jsonb,1
  ) a;
  IF v_sequence<>1 OR NOT v_replayed
  THEN RAISE EXCEPTION 'Ordinary event idempotency failed'; END IF;

  BEGIN
    PERFORM event_id FROM us.carry_append_ordinary_event_v3(
      'bbbbbbbb-1111-4111-8111-111111111111',
      'dddddddd-1111-4111-8111-111111111111',
      'outside001','FACT_ASSERTED',NULL,'USER_ASSERTED',
      'test:v3:owner', '{"reason":"Outside actor", "value":true}'::jsonb,2
    );
    RAISE EXCEPTION 'Outsider wrote owner stream';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM event_id FROM us.carry_append_ordinary_event_v3(
      'aaaaaaaa-1111-4111-8111-111111111111',
      'dddddddd-1111-4111-8111-111111111111',
      'sealing001','REVISION_SEALED',NULL,'DERIVED',
      'test:v3:owner', '{"revision_id":"00000000-0000-0000-0000-000000000000"}'::jsonb,2
    );
    RAISE EXCEPTION 'Ordinary wrapper allowed REVISION_SEALED';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$event$;

RESET ROLE;
DO $count$
BEGIN
 IF (SELECT count(*) FROM us.carry_case_events_v1
      WHERE stream_id='dddddddd-1111-4111-8111-111111111111')<>1
 THEN RAISE EXCEPTION 'Rejected event changed immutable history'; END IF;
END
$count$;
ROLLBACK;
