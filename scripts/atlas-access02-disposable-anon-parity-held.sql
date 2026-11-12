-- ACCESS-02 EXACT LOCAL-CLONE ACL PARITY ONLY; never a migration.
-- A supabase user-schema dump may restore an extra anon EXECUTE entry even
-- when the live public REST wrapper grants EXECUTE to authenticated only.
-- Restore only that single wrapper's known released access boundary.
BEGIN;
DO $access02_parity_before$
DECLARE
  v_native oid := to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)');
  v_rest oid := to_regprocedure('public.connected_person_my_work_self_api_v1(integer,uuid)');
BEGIN
  IF current_setting('access02.disposable_clone',true) IS DISTINCT FROM 'true'
    OR current_database()<>'postgres' THEN
    RAISE EXCEPTION 'REFUSE ACCESS02 ACL parity outside disposable clone';
  END IF;
  IF v_native IS NULL OR v_rest IS NULL THEN
    RAISE EXCEPTION 'REFUSE ACCESS02 missing exact two Work function identities';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=v_native
      AND p.prosecdef AND p.provolatile='s'
      AND p.prorettype='jsonb'::regtype
      AND ('search_path=""'=ANY(p.proconfig))
      AND position('AND coalesce(relevance.has_relevance,false)'
          IN pg_get_functiondef(p.oid))>0
      AND p.proacl IS NOT NULL
      AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'REFUSE ACCESS02 unexpected internal native Work source/ACL'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=v_rest
      AND p.prosecdef AND p.provolatile='s'
      AND p.prorettype='jsonb'::regtype
      AND ('search_path=pg_catalog'=ANY(p.proconfig))
      AND md5(pg_get_functiondef(p.oid))=
        'c47a7961a04f6b834b65a851253990da'
      AND p.proacl IS NOT NULL
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM aclexplode(p.proacl) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
  ) THEN RAISE EXCEPTION 'REFUSE ACCESS02 unexpected REST Work wrapper source/ACL'; END IF;
  IF has_function_privilege('anon',v_rest,'EXECUTE')
     AND NOT EXISTS (
        SELECT 1 FROM pg_proc p,aclexplode(p.proacl) acl
        WHERE p.oid=v_rest
          AND acl.grantee='anon'::regrole::oid
          AND acl.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'REFUSE ACCESS02 unexpected inherited anonymous EXECUTE';
  END IF;
END;
$access02_parity_before$;

-- ONLY the REST wrapper; never modify the internal source or any grants.
REVOKE EXECUTE ON FUNCTION public.connected_person_my_work_self_api_v1(integer,uuid) FROM anon;

DO $access02_parity_after$
DECLARE
  v_rest oid := to_regprocedure('public.connected_person_my_work_self_api_v1(integer,uuid)');
BEGIN
  IF current_setting('access02.disposable_clone',true) IS DISTINCT FROM 'true'
    OR v_rest IS NULL
    OR has_function_privilege('anon',v_rest,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_rest,'EXECUTE')
    OR EXISTS (
       SELECT 1 FROM pg_proc p,aclexplode(p.proacl) acl
       WHERE p.oid=v_rest AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) THEN
    RAISE EXCEPTION 'REFUSE ACCESS02 clone REST anonymous ACL parity failed';
  END IF;
END;
$access02_parity_after$;
COMMIT;
