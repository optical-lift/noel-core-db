do $validation$
declare
  v_refresh text;
  v_reconcile text;
begin
  if to_regprocedure('atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer)') is null then
    raise exception 'missing canonical Company Work Worker Day projection reconciler';
  end if;

  select pg_get_functiondef('atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer)'::regprocedure)
    into v_reconcile;
  if position('projectionAuthority' in v_reconcile)=0
     or position('work_execution_plans' in v_reconcile)=0
     or position('locked=true' in replace(v_reconcile,' ',''))=0 then
    raise exception 'canonical Worker Day projection reconciler is not plan-driven and locked';
  end if;

  select pg_get_functiondef('atlas.company_work_worker_day_refresh_self_api_v1(date,integer)'::regprocedure)
    into v_refresh;
  if position('promote_legacy_owner_week_projection_plans_v1' in v_refresh)=0 then
    raise exception 'Employee Worker Day refresh no longer preserves explicit owner-week evidence into canonical plans';
  end if;
  if position('reconcile_company_work_worker_day_projections_v1' in v_refresh)=0 then
    raise exception 'Employee Worker Day refresh does not reconcile canonical execution plans into employee projections';
  end if;
  if position('refresh_worker_week_projection_internal_v1' in v_refresh)>0 then
    raise exception 'Employee Atlas still invokes the destructive legacy worker-week capacity refresh';
  end if;
  if position('legacyCapacityRefreshInvoked' in v_refresh)=0
     or position('company_work_worker_day_refresh_v3' in v_refresh)=0 then
    raise exception 'Employee Worker Day refresh does not expose the new canonical reconciliation contract';
  end if;

  if has_function_privilege('anon','atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer)','EXECUTE')
     or has_function_privilege('authenticated','atlas.reconcile_company_work_worker_day_projections_v1(uuid,uuid,uuid,uuid,date,integer)','EXECUTE') then
    raise exception 'internal canonical Worker Day projection reconciler leaked to browser roles';
  end if;

  if has_function_privilege('anon','public.company_work_worker_day_refresh_self_api_v1(date,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.company_work_worker_day_refresh_self_api_v1(date,integer)','EXECUTE') then
    raise exception 'Employee Worker Day refresh browser membrane grants are incorrect';
  end if;
end;
$validation$;
