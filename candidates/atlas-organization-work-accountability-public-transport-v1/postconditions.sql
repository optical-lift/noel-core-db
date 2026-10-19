-- Candidate validation in disposable clone only. Do not use this file
-- as a substitute for owner/non-root signed-in API verification.
DO $validation$
DECLARE
  v_public oid := to_regprocedure('public.organization_work_accountability_self_api_v1()');
  v_atlas oid := to_regprocedure('atlas.organization_work_accountability_self_api_v1()');
  v_public_definition text;
  v_atlas_definition text;
BEGIN
  IF v_public IS NULL OR v_atlas IS NULL THEN
    RAISE EXCEPTION 'Missing source function or authenticated transport';
  END IF;

  IF NOT has_function_privilege('authenticated', v_public, 'EXECUTE')
    OR has_function_privilege('anon', v_public, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', v_atlas, 'EXECUTE')
    OR has_function_privilege('anon', v_atlas, 'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected authorization grants on owner-work transport';
  END IF;

  IF (SELECT prosecdef FROM pg_proc WHERE oid = v_public)
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_atlas) THEN
    RAISE EXCEPTION 'Public transport must be invoker; source must retain governed definer boundary';
  END IF;

  v_public_definition := pg_get_functiondef(v_public);
  v_atlas_definition := pg_get_functiondef(v_atlas);
  IF position('atlas.organization_work_accountability_self_api_v1()' IN v_public_definition) = 0
    OR v_atlas_definition !~* 'owner_membership'
    OR v_atlas_definition !~* 'role[[:space:]]*=[[:space:]]*''owner''' THEN
    RAISE EXCEPTION 'Transport diverged from the active owner-only source reader';
  END IF;
END;
$validation$;
