DO $check$ DECLARE sig text; f oid; BEGIN
 IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='atlas' AND table_name='task_entries' AND column_name='details' AND is_nullable='YES') THEN RAISE EXCEPTION 'Personal initial details source absent'; END IF;
 FOREACH sig IN ARRAY ARRAY['atlas.create_personal_task_initial_details_self_api_v1(text,date,text,text)','public.create_personal_task_initial_details_self_api_v1(text,date,text,text)','atlas.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text)','public.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text)','atlas.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text)','public.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text)'] LOOP
 f:=to_regprocedure(sig); IF f IS NULL OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('service_role',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE') OR (SELECT prosecdef FROM pg_proc WHERE oid=f) IS DISTINCT FROM (sig LIKE 'atlas.%') THEN RAISE EXCEPTION 'Details entry custody failed: %',sig; END IF; END LOOP;
 IF has_function_privilege('authenticated','atlas.create_atlas_task_initial_details_internal_v1(text,date,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Private writer exposed'; END IF;
END $check$;

DO $projection$ DECLARE definition text; BEGIN
 SELECT prosrc INTO definition FROM pg_proc WHERE oid=to_regprocedure('atlas.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)');
 IF definition IS NULL OR position('company_work_native_ledger_owner_self_v1' IN definition)=0
  OR position('w.created_by_user_id=auth.uid()' IN definition)=0
  OR position('w.has_exact_ledger_evidence' IN definition)=0
  OR position('authoredInstructions' IN definition)=0
  OR position('i.submitted_by_person_id=v_actor_person_id' IN definition)=0
  OR position('w.metadata->>''createdByPersonId''=v_actor_person_id::text' IN definition)=0
 THEN RAISE EXCEPTION 'Existing native projection author boundary absent'; END IF;
END $projection$;
