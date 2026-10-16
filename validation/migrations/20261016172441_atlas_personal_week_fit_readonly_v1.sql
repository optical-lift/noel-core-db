-- Postconditions to run only on disposable production-schema clone after candidate applied.
-- Positive authenticated fixture with a test native Personal Atlas remains required.
do $check$
begin
 if to_regprocedure('atlas.personal_week_planning_context_self_api_v1(date)') is null
  or to_regprocedure('public.personal_week_planning_context_self_api_v1(date)') is null
  or to_regprocedure('atlas.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)') is null
  or to_regprocedure('public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)') is null then
   raise exception 'Personal week fit contract functions are missing';
 end if;
 if has_function_privilege('anon','public.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or has_function_privilege('anon','public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE')
  or has_function_privilege('authenticated','atlas.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or has_function_privilege('authenticated','atlas.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE') then
   raise exception 'Private/internal planning contracts leaked to an unauthorized caller';
 end if;
 if not has_function_privilege('authenticated','public.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or not has_function_privilege('authenticated','public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE') then
   raise exception 'Missing authenticated read-only proxy EXECUTE grant';
 end if;
 if (select count(*) from atlas.authenticated_rpc_registry where signature in (
  'public.personal_week_planning_context_self_api_v1(date)',
  'public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)'
 ) and classification='app_endpoint' and review_status='active'
     and authenticated_execute_expected=true and anonymous_execute_expected=false)<>2 then
   raise exception 'Personal planning RPC registry is incomplete';
 end if;
end
$check$;
