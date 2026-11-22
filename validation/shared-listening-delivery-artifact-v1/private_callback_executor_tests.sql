-- HELD synthetic PG17 ACL/negative boundary proof; UNSIGNED fixture only.
-- The existing genuine GoTrue/Storage protected clone MUST separately prove
-- the same executable callbacks with real owner/editor/viewer/outsider tokens.
BEGIN;

CREATE FUNCTION pg_temp.expect_private_callback_denial(
  p_sql text,p_expected text)
RETURNS void LANGUAGE plpgsql AS $denial$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'Unauthorized callback succeeded' USING ERRCODE='P0001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_expected THEN RAISE; END IF;
  END;
END $denial$;

-- None of the three client/service roles can invoke a private wrapper.
SET LOCAL ROLE anon;
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.private_register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '42501');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.private_complete_verified_listening_production_v1(
    NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::text,
    NULL::jsonb,NULL::jsonb,NULL::jsonb)',
  '42501');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.private_register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '42501');
RESET ROLE;

-- The dedicated NOLOGIN role can ONLY enter the two wrappers.
-- Even under that role, invalid source/evidence is denied by the existing
-- canonical invoker function; direct inner invocation remains impossible.
SET LOCAL ROLE transcript_core_private_callback_executor_v1;
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '42501');
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.complete_verified_listening_production_v1(
    NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::text,
    NULL::jsonb,NULL::jsonb,NULL::jsonb)',
  '42501');
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.private_register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '22023');
SELECT pg_temp.expect_private_callback_denial(
  'SELECT transcript_core.private_complete_verified_listening_production_v1(
    NULL::uuid,NULL::uuid,NULL::integer,NULL::uuid,NULL::text,
    NULL::jsonb,NULL::jsonb,NULL::jsonb)',
  '22023');
RESET ROLE;

ROLLBACK;
SELECT 'PASS held fixed private callback ACL and invalid-intent denial (UNSIGNED)' AS result;
