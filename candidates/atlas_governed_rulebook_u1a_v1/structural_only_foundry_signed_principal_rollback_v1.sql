-- U1A original Foundry signed principal source: compile-only/negative-source test.
-- This is NOT a migration or a live signed authorization test.
-- Exact Noel native signed principal definition md5 (read-only 2026-11-03):
-- e69b3383920f43c664d58e4b527c6d6d
BEGIN;
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 IF current_database()<>'atlas_work_disposable'
  OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
  OR current_setting('port')='55432'
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR to_regprocedure('atlas.foundry_current_signed_principal_v1()') IS NOT NULL
  OR to_regclass('atlas.principals') IS NULL
  OR to_regclass('auth.users') IS NULL
  OR to_regclass('auth.sessions') IS NULL
  OR to_regprocedure('auth.uid()') IS NULL
  OR to_regprocedure('auth.jwt()') IS NULL
  OR to_regrole('authenticated') IS NULL
  OR to_regrole('anon') IS NULL
  OR to_regrole('service_role') IS NULL
 THEN RAISE EXCEPTION 'Existing original native signed Principal schema dependencies unavailable on disposable clone'
  USING ERRCODE='42501';
 END IF;
END $preflight$;

-- BEGIN VERBATIM REVIEWED NOEL SIGNED PRINCIPAL SOURCE

CREATE OR REPLACE FUNCTION atlas.foundry_current_signed_principal_v1()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','pg_temp'
AS $fn$
DECLARE v_user uuid:=auth.uid();
        v_session uuid;
        v_principal uuid;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id=v_user AND u.is_anonymous=false
    AND (u.banned_until IS NULL OR u.banned_until<=now())
  ) THEN
    RAISE EXCEPTION 'Active non-anonymous Atlas sign-in required' USING ERRCODE='42501';
  END IF;
  BEGIN
    v_session:=NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid signed session' USING ERRCODE='42501';
  END;
  IF v_session IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    WHERE s.id=v_session AND s.user_id=v_user
    AND (s.not_after IS NULL OR s.not_after>now())
  ) THEN
    RAISE EXCEPTION 'Revoked or missing signed session' USING ERRCODE='42501';
  END IF;
  SELECT p.id INTO v_principal FROM atlas.principals p
    WHERE p.user_id=v_user AND p.status='active';
  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Active Atlas Principal required' USING ERRCODE='42501';
  END IF;
  RETURN v_principal;
END
$fn$;
REVOKE ALL ON FUNCTION atlas.foundry_current_signed_principal_v1()
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.foundry_current_signed_principal_v1()
  TO authenticated;
-- END VERBATIM REVIEWED NOEL SIGNED PRINCIPAL SOURCE

DO $contract$
DECLARE
 v_owner text;
 v_acl text;
 v_definer boolean;
 v_definition_md5 text;
 v_denied boolean:=false;
BEGIN
 SELECT pg_get_userbyid(p.proowner),coalesce(p.proacl::text,'NULL'),
        p.prosecdef,md5(pg_get_functiondef(p.oid))
 INTO v_owner,v_acl,v_definer,v_definition_md5
 FROM pg_proc p
 WHERE p.oid='atlas.foundry_current_signed_principal_v1()'::regprocedure;
 IF v_owner<>'postgres'
    OR v_definer IS DISTINCT FROM true
    OR v_acl<>'{postgres=X/postgres,authenticated=X/postgres}'
    OR v_definition_md5<>'e69b3383920f43c664d58e4b527c6d6d'
 THEN RAISE EXCEPTION 'Foundry signed Principal definition or permissions differ from native Noel'
  USING ERRCODE='42501';
 END IF;
 -- Without an actual GoTrue signed session, the unaltered source MUST deny.
 -- This is not an attempt to forge or impersonate a user.
 BEGIN
  PERFORM atlas.foundry_current_signed_principal_v1();
 EXCEPTION WHEN SQLSTATE '42501' THEN
  v_denied:=true;
 END;
 IF NOT v_denied THEN
  RAISE EXCEPTION 'Original signed Principal source accepted an unsigned session'
   USING ERRCODE='42501';
 END IF;
 RAISE NOTICE 'FOUNDRY_SIGNED_PRINCIPAL_STRUCTURAL_PASS: exact source grants and unsigned denial';
END $contract$;
ROLLBACK;
