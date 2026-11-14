-- Held P1 disposable PG17 schema ACL recovery; NO production migration.
-- Verified live Noel pg_namespace.nspacl on 2026-11-05:
-- {postgres=UC/postgres,anon=U/postgres,authenticated=U/postgres,
--  service_role=U/postgres}
-- The test's read-only pg_dump --no-acl deliberately omits these grants.
-- USAGE resolves names only, never grants EXECUTE on private operations,
-- SELECT/INSERT/UPDATE on tables, a Person identity, or Ledger authority.
-- Recreate only the live namespace USAGE in a truly disposable database.
DO $preflight$
BEGIN
 IF to_regnamespace('atlas') IS NULL
    OR to_regprocedure('atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)') IS NULL
    OR to_regprocedure('atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'STOP: source-backed schema and private functions required before ACL recovery';
 END IF;
END;$preflight$;

GRANT USAGE ON SCHEMA atlas TO anon, authenticated, service_role;

DO $assert$
BEGIN
 IF NOT has_schema_privilege('anon','atlas','USAGE')
    OR NOT has_schema_privilege('authenticated','atlas','USAGE')
    OR NOT has_schema_privilege('service_role','atlas','USAGE')
    OR has_schema_privilege('authenticated','atlas','CREATE')
    OR has_function_privilege('anon',
         'atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    OR has_function_privilege('anon',
         'atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)','EXECUTE')
 THEN
    RAISE EXCEPTION 'STOP: restored namespace access does not match live no-execute/no-create boundary';
 END IF;
 RAISE NOTICE 'PASS exact live Atlas schema USAGE recovered without private scope EXECUTE for anon';
END;$assert$;
