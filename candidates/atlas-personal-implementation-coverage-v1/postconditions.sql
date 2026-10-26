-- Run ONLY in an authorized disposable production-shaped schema clone AFTER
-- applying the generated migration. No user rows, paid state, or real data.
DO $proof$
DECLARE
  v_function oid;
  v_wrapper oid;
BEGIN
  v_function := to_regprocedure('atlas.implementation_personal_coverage_self_v1(uuid)');
  v_wrapper := to_regprocedure('public.implementation_personal_coverage_self_api_v1(uuid)');
  IF v_function IS NULL OR v_wrapper IS NULL THEN
    RAISE EXCEPTION 'personal coverage read membrane absent';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid IN (v_function,v_wrapper)
      AND (p.provolatile <> 's' OR NOT p.prosecdef)
  ) THEN
    RAISE EXCEPTION 'coverage must be STABLE and SECURITY DEFINER';
  END IF;
  IF has_function_privilege('anon',v_wrapper,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_wrapper,'EXECUTE') THEN
    RAISE EXCEPTION 'coverage API execute grants not bounded';
  END IF;
  IF has_function_privilege('authenticated',v_function,'EXECUTE') THEN
    RAISE EXCEPTION 'internal coverage function exposed';
  END IF;
END;
$proof$;
