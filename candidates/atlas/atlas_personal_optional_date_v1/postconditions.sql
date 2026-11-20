DO $check$ DECLARE sig text; f oid;
BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='atlas' AND ((table_name='task_entries' AND column_name='due_date') OR (table_name='personal_task_amendment_events_v1' AND column_name IN ('before_due_date','after_due_date'))) AND is_nullable<>'YES') THEN RAISE EXCEPTION 'Optional date source contract absent'; END IF;
 FOREACH sig IN ARRAY ARRAY['atlas.create_atlas_task_self_api_v1(text,date,text)','public.create_atlas_task_self_api_v1(text,date,text)','atlas.atlas_task_day_self_api_v1(date)','public.atlas_task_day_self_api_v1(date)','atlas.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)','public.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)','atlas.personal_archived_tasks_day_self_api_v1(date)','public.personal_archived_tasks_day_self_api_v1(date)'] LOOP
 f:=to_regprocedure(sig);
 -- Preserve exact pre-existing wrapper/internal custody, verified from live catalog.
 IF f IS NULL OR has_function_privilege('anon',f,'EXECUTE')
 OR has_function_privilege('authenticated',f,'EXECUTE') IS DISTINCT FROM (sig NOT LIKE 'atlas.create_atlas_task_self_api_v1(%' AND sig NOT LIKE 'atlas.atlas_task_day_self_api_v1(%')
 OR has_function_privilege('service_role',f,'EXECUTE') IS DISTINCT FROM (sig LIKE 'public.%')
 OR (SELECT prosecdef FROM pg_proc WHERE oid=f) IS DISTINCT FROM (sig LIKE 'atlas.%' OR sig LIKE 'public.create_atlas_task_self_api_v1(%' OR sig LIKE 'public.atlas_task_day_self_api_v1(%') THEN RAISE EXCEPTION 'Original date API custody failed: % (oid=%, anon=%, auth=%, service=%, definer=%)',sig,f,has_function_privilege('anon',f,'EXECUTE'),has_function_privilege('authenticated',f,'EXECUTE'),has_function_privilege('service_role',f,'EXECUTE'),(SELECT prosecdef FROM pg_proc WHERE oid=f); END IF;
 END LOOP;
END $check$;
