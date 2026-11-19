DO $verify$ BEGIN
 IF to_regprocedure('public.record_ledger_work_self_api_v2(uuid,text,date,text)') IS NULL
 OR to_regprocedure('public.connected_person_company_work_day_self_api_v2(date,text)') IS NULL
 THEN RAISE EXCEPTION 'Required exact public source contracts absent'; END IF;
 IF has_function_privilege('anon','public.record_ledger_work_self_api_v2(uuid,text,date,text)','execute')
 OR has_function_privilege('anon','public.connected_person_company_work_day_self_api_v2(date,text)','execute')
 OR has_function_privilege('anon','atlas.record_ledger_work_self_api_v2(uuid,text,date,text)','execute')
 OR has_function_privilege('anon','atlas.connected_person_company_work_day_self_api_v2(date,text)','execute')
 THEN RAISE EXCEPTION 'Anonymous source authority'; END IF;
 IF NOT has_function_privilege('authenticated','public.record_ledger_work_self_api_v2(uuid,text,date,text)','execute')
 OR NOT has_function_privilege('authenticated','public.connected_person_company_work_day_self_api_v2(date,text)','execute')
 THEN RAISE EXCEPTION 'Signed surface absent'; END IF;
END $verify$;