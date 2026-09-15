begin;

do $$
declare
  v_missing text[] := '{}';
begin
  if to_regprocedure('atlas.organization_company_work_people_api_v1(uuid)') is null then v_missing:=array_append(v_missing,'atlas.organization_company_work_people_api_v1'); end if;
  if to_regprocedure('atlas.company_work_employee_home_self_api_v1()') is null then v_missing:=array_append(v_missing,'atlas.company_work_employee_home_self_api_v1'); end if;
  if to_regprocedure('atlas.company_work_worker_day_refresh_self_api_v1(date,integer)') is null then v_missing:=array_append(v_missing,'atlas.company_work_worker_day_refresh_self_api_v1'); end if;
  if to_regprocedure('atlas.company_work_worker_day_self_api_v1(date,integer)') is null then v_missing:=array_append(v_missing,'atlas.company_work_worker_day_self_api_v1'); end if;
  if to_regprocedure('atlas.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'atlas.organization_owner_appoint_employee_position_api_v1'); end if;
  if to_regprocedure('public.company_work_employee_home_self_api_v1()') is null then v_missing:=array_append(v_missing,'public.company_work_employee_home_self_api_v1'); end if;
  if to_regprocedure('public.company_work_worker_day_refresh_self_api_v1(date,integer)') is null then v_missing:=array_append(v_missing,'public.company_work_worker_day_refresh_self_api_v1'); end if;
  if to_regprocedure('public.company_work_worker_day_self_api_v1(date,integer)') is null then v_missing:=array_append(v_missing,'public.company_work_worker_day_self_api_v1'); end if;
  if to_regprocedure('public.organization_company_work_people_api_v1(uuid)') is null then v_missing:=array_append(v_missing,'public.organization_company_work_people_api_v1'); end if;
  if to_regprocedure('public.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'public.organization_owner_appoint_employee_position_api_v1'); end if;
  if array_length(v_missing,1) is not null then raise exception 'Missing Package 2 functions: %',v_missing; end if;

  if has_function_privilege('anon','public.company_work_employee_home_self_api_v1()','execute') then raise exception 'Anon can execute employee home.'; end if;
  if has_function_privilege('anon','public.organization_company_work_people_api_v1(uuid)','execute') then raise exception 'Anon can execute management people read.'; end if;
  if has_function_privilege('anon','public.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text)','execute') then raise exception 'Anon can appoint employee Position.'; end if;
  if not has_function_privilege('authenticated','public.company_work_employee_home_self_api_v1()','execute') then raise exception 'Authenticated cannot execute employee home.'; end if;
  if not has_function_privilege('authenticated','public.company_work_worker_day_self_api_v1(date,integer)','execute') then raise exception 'Authenticated cannot read Worker Day.'; end if;
  if not has_function_privilege('authenticated','public.worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb)','execute') then raise exception 'Authenticated cannot report governed Company Work result.'; end if;

  if has_function_privilege('authenticated','atlas.company_work_employee_home_self_api_v1()','execute') then raise exception 'Internal employee home leaked from atlas schema.'; end if;
  if has_function_privilege('authenticated','atlas.organization_owner_appoint_employee_position_api_v1(uuid,uuid,uuid,text)','execute') then raise exception 'Internal Position writer leaked from atlas schema.'; end if;
  if to_regprocedure('public.worker_delivery_employee_transition_self_api_v1(uuid,text,uuid,timestamptz,text)') is not null then raise exception 'Legacy Start/Stop worker transition was exposed through public schema.'; end if;
end;
$$;

rollback;
