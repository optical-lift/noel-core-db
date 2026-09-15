do $validation$
declare
  v_refresh text;
  v_day text;
begin
  if to_regprocedure('atlas.inherit_legacy_quick_complete_result_contract_trigger_v1()') is null then
    raise exception 'missing legacy quick-complete inheritance trigger function';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='work_execution_adapters'
      and t.tgname='work_execution_adapters_inherit_legacy_quick_complete_v1'
      and not t.tgisinternal
  ) then
    raise exception 'missing work_execution_adapters quick-complete succession trigger';
  end if;

  if to_regprocedure('atlas.promote_legacy_owner_week_projection_plans_v1(uuid,uuid,date,integer)') is null then
    raise exception 'missing legacy owner-week plan succession function';
  end if;

  if to_regprocedure('atlas.company_work_projection_result_reporting_self_v1(uuid)') is null then
    raise exception 'missing employee projection result-reportability function';
  end if;

  select pg_get_functiondef('atlas.company_work_worker_day_refresh_self_api_v1(date,integer)'::regprocedure)
    into v_refresh;
  if position('promote_legacy_owner_week_projection_plans_v1' in v_refresh)=0 then
    raise exception 'Worker Day refresh does not promote legacy owner-week evidence into canonical execution plans';
  end if;

  select pg_get_functiondef('atlas.company_work_worker_day_self_api_v1(date,integer)'::regprocedure)
    into v_day;
  if position('resultReporting' in v_day)=0
     or position('company_work_projection_result_reporting_self_v1' in v_day)=0 then
    raise exception 'Worker Day read does not expose explicit result reportability';
  end if;

  if has_function_privilege('anon','atlas.company_work_projection_result_reporting_self_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.company_work_projection_result_reporting_self_v1(uuid)','EXECUTE') then
    raise exception 'internal result-reportability helper leaked to browser roles';
  end if;

  if has_function_privilege('anon','public.company_work_worker_day_self_api_v1(date,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.company_work_worker_day_self_api_v1(date,integer)','EXECUTE') then
    raise exception 'Worker Day browser membrane grants are incorrect';
  end if;

  if has_function_privilege('anon','public.company_work_worker_day_refresh_self_api_v1(date,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.company_work_worker_day_refresh_self_api_v1(date,integer)','EXECUTE') then
    raise exception 'Worker Day refresh browser membrane grants are incorrect';
  end if;
end;
$validation$;
