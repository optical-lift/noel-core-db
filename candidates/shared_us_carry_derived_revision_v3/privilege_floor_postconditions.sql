-- HELD v3 increment A / disposable PostgreSQL acceptance only.
-- Fail against v1/v2 alone. PASS only after privilege_floor_candidate.sql.
-- NOT the full v3 adoption/reviewer postconditions; those remain held.
BEGIN;
DO $verify$
BEGIN
  IF pg_catalog.has_table_privilege(
    'service_role','us.financial_expectation_revisions','INSERT')
  THEN RAISE EXCEPTION 'service_role may still insert a financial revision'; END IF;

  IF pg_catalog.has_table_privilege(
    'service_role','us.financial_expectation_lines','INSERT')
  THEN RAISE EXCEPTION 'service_role may still insert forecast lines'; END IF;

  IF pg_catalog.has_function_privilege(
    'service_role',
    'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
  THEN RAISE EXCEPTION 'service_role may still bypass adoption via v1 seal'; END IF;

  IF pg_catalog.has_function_privilege(
    'anon',
    'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)',
    'EXECUTE')
    OR pg_catalog.has_function_privilege(
      'authenticated',
      'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)',
      'EXECUTE')
  THEN RAISE EXCEPTION 'Carry v1 appender exposed to a client role'; END IF;
END
$verify$;
ROLLBACK;

-- Perform actual forbidden operations as service_role. No synthetic owner
-- identifiers or source financial values are needed to prove denial.
BEGIN;
SET LOCAL ROLE service_role;
DO $forbidden$
BEGIN
  BEGIN
    INSERT INTO us.financial_expectation_revisions DEFAULT VALUES;
    RAISE EXCEPTION 'service_role revision INSERT unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO us.financial_expectation_lines DEFAULT VALUES;
    RAISE EXCEPTION 'service_role line INSERT unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM event_id FROM us.carry_append_event_v1(
      NULL::uuid,NULL::text,NULL::text,NULL::date,
      NULL::text,NULL::text,NULL::jsonb,NULL::bigint
    );
    RAISE EXCEPTION 'service_role v1 appender EXECUTE unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$forbidden$;
ROLLBACK;
