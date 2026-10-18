DO $check$
BEGIN
 IF to_regprocedure('atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)') IS NULL
 OR to_regprocedure('public.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)') IS NULL
 THEN RAISE EXCEPTION 'Missing owner appointment-to-member guarded adapter'; END IF;
 IF has_function_privilege('anon',
 'public.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous must not propose standing worker authority'; END IF;
 IF NOT has_function_privilege('authenticated',
 'public.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Authenticated source transport missing'; END IF;
 IF (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='propose_company_work_standing_scope_by_appointment_self_api_v1')
 THEN RAISE EXCEPTION 'Public transport must be invoker'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
  pg_get_functiondef('atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner exact Ledger root required'; END IF;
 IF position('a.id=p_appointment_id' IN
  pg_get_functiondef('atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Exact Position appointment required'; END IF;
END
$check$;