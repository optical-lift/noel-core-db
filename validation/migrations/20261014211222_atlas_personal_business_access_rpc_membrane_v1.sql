-- Postconditions for Atlas Business read membrane. No user data is examined.
DO $validation$
DECLARE
  v_oid oid := to_regprocedure('public.reality_access_self_api_v1()');
BEGIN
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'Missing authenticated Business Reality access wrapper';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid=v_oid AND prosecdef AND provolatile='s'
      AND 'search_path=pg_catalog'=ANY(proconfig)
  ) THEN
    RAISE EXCEPTION 'Wrapper must remain stable, SECURITY DEFINER and fixed-search-path';
  END IF;

  IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated role cannot read canonical self access';
  END IF;
  IF has_function_privilege('anon',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous must not execute the Reality access wrapper';
  END IF;
  IF position('atlas.reality_access_self_api_v1' in pg_get_functiondef(v_oid))=0 THEN
    RAISE EXCEPTION 'Wrapper no longer delegates to canonical Reality access';
  END IF;
END;
$validation$;
