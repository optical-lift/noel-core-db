-- Candidate validation in disposable clone only. Do not use this file
-- as a substitute for owner/non-root signed-in API verification.
DO $validation$
DECLARE
  v_public oid := to_regprocedure('public.organization_work_accountability_self_api_v1()');
  v_atlas oid := to_regprocedure('atlas.organization_work_accountability_self_api_v1()');
  v_effective_owner oid := to_regprocedure('atlas.is_effective_organization_owner_v1(uuid)');
  v_owner oid := to_regprocedure('atlas.is_organization_owner(uuid)');
  v_membership oid := to_regprocedure('atlas.current_effective_organization_membership_v1(uuid)');
  v_public_definition text;
  v_atlas_definition text;
  v_effective_owner_definition text;
  v_owner_definition text;
  v_membership_definition text;
BEGIN
  IF v_public IS NULL OR v_atlas IS NULL OR v_effective_owner IS NULL
    OR v_owner IS NULL OR v_membership IS NULL THEN
    RAISE EXCEPTION 'Missing transport or governing authorization function';
  END IF;

  IF NOT has_schema_privilege('authenticated', 'atlas', 'USAGE')
    OR NOT has_function_privilege('authenticated', v_public, 'EXECUTE')
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
  v_effective_owner_definition := pg_get_functiondef(v_effective_owner);
  v_owner_definition := pg_get_functiondef(v_owner);
  v_membership_definition := pg_get_functiondef(v_membership);

  IF position('atlas.organization_work_accountability_self_api_v1()' IN v_public_definition) = 0
    OR position('auth.uid()' IN v_atlas_definition) = 0
    OR position('atlas.is_effective_organization_owner_v1(' IN v_atlas_definition) = 0
    OR position('atlas.is_organization_owner(' IN v_effective_owner_definition) = 0
    OR position('atlas.current_principal_id_v1()' IN v_effective_owner_definition) = 0
    OR v_effective_owner_definition !~* 'root_governing'
    OR position('atlas.current_effective_organization_membership_v1(' IN v_owner_definition) = 0
    OR v_owner_definition !~* 'role[[:space:]]*=[[:space:]]*''owner'''
    OR position('atlas.organization_membership_present_effective_at_v1(' IN v_membership_definition) = 0 THEN
    RAISE EXCEPTION 'Transport diverged from the current effective owner/governing authorization chain';
  END IF;
END;
$validation$;
