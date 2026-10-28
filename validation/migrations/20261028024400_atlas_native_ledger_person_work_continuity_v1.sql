-- Read-only postconditions after clone applies the exact candidate migration.
DO $verify_native_work_continuity$
DECLARE
  v_internal oid := to_regprocedure('atlas.owner_continue_membership_work_as_person_under_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_external oid := to_regprocedure('public.owner_continue_membership_work_as_person_under_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_definition text;
BEGIN
  IF v_internal IS NULL OR v_external IS NULL THEN
    RAISE EXCEPTION 'Person responsibility continuity API and its public carrier must exist';
  END IF;
  IF has_function_privilege('anon',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_external,'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous must not execute Person Work continuity';
  END IF;
  IF NOT has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_external,'EXECUTE') THEN
    RAISE EXCEPTION 'Signed Person must be able to reach the governed API';
  END IF;
  SELECT pg_get_functiondef(v_internal) INTO v_definition;
  IF position('company_work_native_ledger_owner_self_v1' IN v_definition)=0
    OR position('organization_membership_present_effective_at_v1' IN v_definition)=0
    OR position('person_has_native_ledger_connection_v1' IN v_definition)=0
    OR position('assign_native_ledger_company_work_under_scope_owner_self_api_v1' IN v_definition)=0
    OR position('source-proven before continuity' IN v_definition)=0
    OR position('Existing responsibility does not belong to the same canonical Person' IN v_definition)=0
    OR position('historicAllocationPreserved' IN v_definition)=0
  THEN
    RAISE EXCEPTION 'Source guard/receipt contract incomplete';
  END IF;
END
$verify_native_work_continuity$;
