-- UNIVERSAL COMMON SOURCE ONLY: run on a disposable production-shaped clone.
-- This is a structural and grants check, not a genuine signed positive test.
DO $postconditions$
DECLARE
  v_fn oid := to_regprocedure(
    'atlas.universal_rulebook_common_source_preflight_internal_v1(uuid,uuid,uuid)'
  );
  v_security_definer boolean;
  v_stable boolean;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'Held universal common preflight missing';
  END IF;
  SELECT p.prosecdef,(p.provolatile='s')
    INTO v_security_definer,v_stable
  FROM pg_catalog.pg_proc p
  WHERE p.oid=v_fn;

  IF v_security_definer IS DISTINCT FROM true
     OR v_stable IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Universal preflight must retain current signed source checks';
  END IF;

  IF pg_catalog.has_function_privilege('anon',v_fn,'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated',v_fn,'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role',v_fn,'EXECUTE') THEN
    RAISE EXCEPTION 'Private source preflight has a public transport grant';
  END IF;

  IF to_regprocedure(
      'public.universal_rulebook_common_source_preflight_internal_v1(uuid,uuid,uuid)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'Unexpected public source preflight mirror';
  END IF;

  RAISE NOTICE 'PASS U1 universal COMMON root/Requirement/Subject structural and ACL, no domain or policy admission';
END
$postconditions$;
