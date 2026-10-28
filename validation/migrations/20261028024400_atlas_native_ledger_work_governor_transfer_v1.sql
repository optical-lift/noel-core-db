-- Read-only source custody postconditions for disposable clone.
DO $verify_governor_work_transfer$
DECLARE
  v_internal oid:=to_regprocedure('atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_public oid:=to_regprocedure('public.owner_transfer_existing_work_under_native_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_definition text;
BEGIN
  IF v_internal IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Canonical Work governed transfer source absent';
  END IF;
  IF has_function_privilege('anon',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous must not be able to invoke Work transfer';
  END IF;
  IF NOT has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Signed native Ledger governor must be able to reach source';
  END IF;
  SELECT pg_get_functiondef(v_internal) INTO v_definition;
  IF position('company_work_native_ledger_owner_self_v1' IN v_definition)=0
    OR position('person_has_native_ledger_connection_v1' IN v_definition)=0
    OR position('company_work_native_ledger_relevance' IN v_definition)=0
    OR position('assign_native_ledger_company_work_under_scope_owner_self_api_v1' IN v_definition)=0
    OR position('accepted_by_person_id' IN v_definition)=0
    OR position('p_expected_prior_allocation_id' IN v_definition)=0
    OR position('previousResponsibilityPreservedAsHistory' IN v_definition)=0
  THEN
    RAISE EXCEPTION 'Governor scope, preserved original, or receipt validation absent';
  END IF;
  IF position('organization_memberships' IN v_definition)>0
    OR position('farm_memberships' IN v_definition)>0
    OR position('employee_seats' IN v_definition)>0 THEN
    RAISE EXCEPTION 'Work transfer must never derive authorization from legacy membership';
  END IF;
END
$verify_governor_work_transfer$;