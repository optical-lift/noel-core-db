-- HELD SOURCE ONLY: proposed private callback LOGIN/SET membership.
-- NOT a production migration; no credentials, password, host, job, or media.
-- The released executor itself remains NOLOGIN and has only two fixed
-- private SECURITY DEFINER wrappers. A separate owner decision is required
-- for canonical migration generation, production release and secret custody.
BEGIN;

DO $runtime_preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname='transcript_core_private_callback_runtime_v1'
  ) THEN RAISE EXCEPTION 'Dedicated runtime login already exists'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname='transcript_core_private_callback_executor_v1'
      AND NOT rolcanlogin AND NOT rolinherit AND NOT rolbypassrls
  ) THEN RAISE EXCEPTION 'Released NOLOGIN callback executor is required'; END IF;
  IF to_regnamespace('transcript_core_callback_v1') IS NULL OR
     to_regprocedure('transcript_core_callback_v1.private_register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)') IS NULL OR
     to_regprocedure('transcript_core_callback_v1.private_complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'Both released fixed callbacks are required'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid
    WHERE r.rolname='transcript_core_private_callback_executor_v1' AND m.set_option
  ) THEN RAISE EXCEPTION 'Unexpected prior callback SET membership; reconcile custody'; END IF;
END $runtime_preflight$;

-- Password is deliberately NULL. In a later, separately approved step the
-- approved host/custody service must provision its own rotated credential.
-- NOINHERIT prevents access to executor privileges until one explicit,
-- transaction-local SET ROLE by the independently authorized host.
CREATE ROLE transcript_core_private_callback_runtime_v1
  LOGIN PASSWORD NULL NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS;

GRANT transcript_core_private_callback_executor_v1
  TO transcript_core_private_callback_runtime_v1
  WITH SET TRUE, INHERIT FALSE, ADMIN FALSE;

COMMENT ON ROLE transcript_core_private_callback_runtime_v1 IS
  'HELD proposed private callback host login; no password or host; only SET into fixed-function NOLOGIN executor, never a publisher or public user';

COMMIT;
