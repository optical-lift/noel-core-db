DO $verify$
BEGIN
 IF to_regclass('atlas.company_work_result_contract_bindings_v1') IS NULL
 THEN RAISE EXCEPTION 'Missing immutable audited Work result contract binding'; END IF;
 IF has_table_privilege('authenticated','atlas.company_work_result_contract_bindings_v1','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_result_contract_bindings_v1','INSERT')
    OR has_table_privilege('anon','atlas.company_work_result_contract_bindings_v1','SELECT')
 THEN RAISE EXCEPTION 'Binding history must remain RPC-only'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname='bind_ordinary_company_work_result_contract_self_api_v1'
     AND NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
     AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 ) THEN RAISE EXCEPTION 'Missing guarded public binding transport'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
     pg_get_functiondef('atlas.bind_ordinary_company_work_result_contract_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))=0
 OR position('company_work_native_ledger_exact_source_v1' IN
     pg_get_functiondef('atlas.bind_ordinary_company_work_result_contract_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))=0
 OR position('result_contract_key IS NULL' IN
     pg_get_functiondef('atlas.bind_ordinary_company_work_result_contract_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Missing dual root, exact Ledger proof or write-once contract'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies
   WHERE contract_key='ordinary_company_work_manager_acceptance_v1' AND active
     AND source_domain='organization' AND acceptance_mode='manager_acceptance')
 THEN RAISE EXCEPTION 'Ordinary Company Work acceptance contract unavailable'; END IF;
END
$verify$;
