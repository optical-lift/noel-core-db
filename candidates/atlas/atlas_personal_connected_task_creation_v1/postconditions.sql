DO $check$ DECLARE sig text; f oid;
BEGIN
 FOREACH sig IN ARRAY ARRAY['atlas.personal_connected_task_choices_self_api_v1()','public.personal_connected_task_choices_self_api_v1()','atlas.create_connected_personal_task_self_api_v1(text,date,uuid,uuid)','public.create_connected_personal_task_self_api_v1(text,date,uuid,uuid)','atlas.create_self_ledger_task_self_api_v1(uuid,text,date,uuid)','public.create_self_ledger_task_self_api_v1(uuid,text,date,uuid)','atlas.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid)','public.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid)'] LOOP
 f:=to_regprocedure(sig);
 IF f IS NULL OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('service_role',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE')
 OR (SELECT prosecdef FROM pg_proc WHERE oid=f) IS DISTINCT FROM (sig LIKE 'atlas.%')
 THEN RAISE EXCEPTION 'Signed adapter custody failed: %',sig; END IF;
 END LOOP;
END $check$;
