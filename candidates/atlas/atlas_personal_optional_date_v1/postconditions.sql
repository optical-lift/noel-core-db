DO $check$ DECLARE sig text; f oid;
BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='atlas' AND ((table_name='task_entries' AND column_name='due_date') OR (table_name='personal_task_amendment_events_v1' AND column_name IN ('before_due_date','after_due_date'))) AND is_nullable<>'YES') THEN RAISE EXCEPTION 'Optional date source contract absent'; END IF;
 FOREACH sig IN ARRAY ARRAY['atlas.create_atlas_task_self_api_v1(text,date,text)','public.create_atlas_task_self_api_v1(text,date,text)','atlas.atlas_task_day_self_api_v1(date)','public.atlas_task_day_self_api_v1(date)','atlas.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)','public.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)','atlas.personal_archived_tasks_day_self_api_v1(date)','public.personal_archived_tasks_day_self_api_v1(date)'] LOOP
 f:=to_regprocedure(sig);
 IF f IS NULL OR has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE') OR (SELECT prosecdef FROM pg_proc WHERE oid=f) IS DISTINCT FROM (sig LIKE 'atlas.%') THEN RAISE EXCEPTION 'Original date API custody failed: %',sig; END IF;
 END LOOP;
END $check$;
