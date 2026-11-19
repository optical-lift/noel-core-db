-- Read-only candidate clone postconditions; signed fixture required separately.
DO $check$ BEGIN
 IF NOT has_function_privilege('authenticated','public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)','EXECUTE')
 OR has_function_privilege('anon','public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon','public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('authenticated','atlas.native_intake_responsibility_owner_context_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('authenticated','atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Unexpected native-intake RPC privilege'; END IF;
 IF position('native_ledger_intake_responsibility_v1' in pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))=0
 THEN RAISE EXCEPTION 'Exact allocation guard extension missing';END IF;
END $check$;
