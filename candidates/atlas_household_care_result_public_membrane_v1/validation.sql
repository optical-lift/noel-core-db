-- Postcondition assertions for local disposable schema clone only.
DO $validation$
DECLARE
  v_api regprocedure := to_regprocedure('public.principal_record_household_care_result_api_v1(jsonb)');
  v_source regprocedure := to_regprocedure('atlas.principal_record_household_care_result_api_v1(jsonb)');
BEGIN
  IF v_api IS NULL OR v_source IS NULL THEN
    RAISE EXCEPTION 'Household care-result source/public membrane is missing.';
  END IF;
  IF has_function_privilege('anon',v_api,'EXECUTE') THEN
    RAISE EXCEPTION 'Household care-result public RPC is not anon-authorized.';
  END IF;
  IF NOT has_function_privilege('authenticated',v_api,'EXECUTE') THEN
    RAISE EXCEPTION 'Signed-in Person cannot call the governed care-result membrane.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_api
      AND p.prosecdef AND p.provolatile='v'
      AND pg_get_functiondef(p.oid) LIKE '%auth.uid()%'
      AND pg_get_functiondef(p.oid) LIKE '%atlas.principal_record_household_care_result_api_v1%'
  ) THEN
    RAISE EXCEPTION 'Missing signed-in actor boundary or owning-domain delegation.';
  END IF;
END
$validation$;
