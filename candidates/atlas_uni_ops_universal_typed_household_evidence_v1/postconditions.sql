-- DISPOSABLE current-schema PostgreSQL only. Not a signed positive.
DO $post$
DECLARE v_fn oid :=
  to_regprocedure('atlas.universal_rulebook_household_native_evidence_internal_v1(uuid,uuid)');
BEGIN
 IF v_fn IS NULL THEN
   RAISE EXCEPTION 'Typed Household source function missing';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_proc p
   WHERE p.oid=v_fn AND p.prosecdef AND p.provolatile='s'
     AND position('search_path=' in array_to_string(p.proconfig,','))>0
 ) THEN
   RAISE EXCEPTION 'Native Household source must remain private signed STABLE';
 END IF;
 IF has_function_privilege('anon',v_fn,'EXECUTE')
    OR has_function_privilege('authenticated',v_fn,'EXECUTE')
    OR has_function_privilege('service_role',v_fn,'EXECUTE') THEN
   RAISE EXCEPTION 'Native Household evidence was accidentally exposed';
 END IF;
 IF to_regprocedure('public.universal_rulebook_household_native_evidence_internal_v1(uuid,uuid)') IS NOT NULL THEN
   RAISE EXCEPTION 'A public Household evidence mirror is not authorized';
 END IF;
 RAISE NOTICE 'PASS TYPED Household native source private ACL, never policy/Work authority';
END
$post$;
