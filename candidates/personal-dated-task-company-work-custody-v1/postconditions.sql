-- Protected disposable production-schema clone assertions; no live user mutation.
DO $check$
BEGIN
 IF to_regprocedure('atlas.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)') IS NULL
 OR to_regprocedure('public.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)') IS NULL THEN
   RAISE EXCEPTION 'Owner source-custody promotion not installed';
 END IF;
 IF NOT (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname='promote_personal_dated_task_to_company_work_self_api_v1') THEN
   RAISE EXCEPTION 'Governing owner gate must run in guarded internal definer';
 END IF;
 IF (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='promote_personal_dated_task_to_company_work_self_api_v1') THEN
   RAISE EXCEPTION 'Public transport must be invoker';
 END IF;
 IF has_function_privilege('anon',
   'public.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('anon',
   'atlas.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous user must not promote personal source';
 END IF;
 IF NOT has_function_privilege('authenticated',
   'public.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Authenticated owner transport not granted';
 END IF;
 IF position('source_object_type=''personal_dated_task''' IN
   pg_get_functiondef('atlas.set_atlas_task_done_self_api_v1(uuid,boolean)'::regprocedure))=0 THEN
   RAISE EXCEPTION 'Original personal task independently completable';
 END IF;
 IF position('institutionalWorkItemId' IN
   pg_get_functiondef('atlas.atlas_task_day_self_api_v1(date)'::regprocedure))=0 THEN
   RAISE EXCEPTION 'Original personal daily task is not visibly source-linked';
 END IF;
END
$check$;
