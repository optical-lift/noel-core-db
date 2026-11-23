-- Fictional PG17 only: role transition and client denial; NOT signed GoTrue.
-- Invoked after the existing fixed callback candidate and runtime candidate.
BEGIN;
CREATE FUNCTION pg_temp.expect_callback_runtime_denial(p_sql text,p_state text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'Unauthorized runtime statement succeeded' USING ERRCODE='P0001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_state THEN RAISE; END IF;
  END;
END $$;

-- A connection using the login still has NO direct callback access.
SET LOCAL ROLE transcript_core_private_callback_runtime_v1;
DO $$BEGIN
  IF current_user <> 'transcript_core_private_callback_runtime_v1'
  THEN RAISE EXCEPTION 'Wrong runtime identity'; END IF;
END$$;
SELECT pg_temp.expect_callback_runtime_denial(
  'SELECT transcript_core_callback_v1.private_register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '42501');
SELECT pg_temp.expect_callback_runtime_denial(
  'SET LOCAL ROLE authenticated','42501');

-- This one fixed role transition is permitted INSIDE the transaction.
SET LOCAL ROLE transcript_core_private_callback_executor_v1;
DO $$BEGIN
  IF current_user <> 'transcript_core_private_callback_executor_v1'
  THEN RAISE EXCEPTION 'SET-only executor transition failed'; END IF;
END$$;
-- Claims and original source are invalid; the inner fixed function must deny.
SELECT pg_temp.expect_callback_runtime_denial(
  'SELECT transcript_core_callback_v1.private_register_verified_manuscript_original_v1(
    NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::text)',
  '22023');
RESET ROLE;
ROLLBACK;
-- A failed/ended transaction cannot leave transaction-local executor authority.
SELECT 'PASS held runtime-login SET-only and missing-claims denial (UNSIGNED)' AS result;
