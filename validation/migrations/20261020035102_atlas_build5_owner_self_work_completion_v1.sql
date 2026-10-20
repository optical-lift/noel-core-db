-- Disposable clone static security and semantics checks.
do $verify$
declare v_name text; v_fn text;
begin
  foreach v_name in array array[
    'self_adopt_existing_company_work_owner_self_api_v1(uuid,uuid,uuid,text)',
    'self_responsible_company_work_today_self_api_v1(integer)',
    'report_self_responsible_company_work_self_api_v1(uuid,text,text,jsonb)'
  ] loop
    if to_regprocedure('atlas.'||v_name) is null
       or to_regprocedure('public.'||v_name) is null then
      raise exception 'Missing Build 5 canonical principal-worker API: %',v_name;
    end if;
    if not has_function_privilege('authenticated',
       to_regprocedure('public.'||v_name),'EXECUTE')
       or has_function_privilege('anon',
       to_regprocedure('public.'||v_name),'EXECUTE')
       or (select prosecdef from pg_proc where oid=to_regprocedure('public.'||v_name))
       or not (select prosecdef from pg_proc where oid=to_regprocedure('atlas.'||v_name)) then
      raise exception 'Build 5 public/private function privilege split failed: %',v_name;
    end if;
  end loop;

  select pg_get_functiondef(
    'atlas.self_adopt_existing_company_work_owner_self_api_v1(uuid,uuid,uuid,text)'::regprocedure)
    into v_fn;
  if position('company_work_native_ledger_owner_self_v1' in v_fn)=0
    or position('current_effective_organization_membership_v1' in v_fn)=0
    or position('work_allocations' in v_fn)=0
    or position('company_work_native_ledger_relevance' in v_fn)=0
    or position('self_adoption' in v_fn)=0
    or position('insert into atlas.work_items' in lower(v_fn))>0
    or position('organization_employee_seats' in v_fn)>0 then
    raise exception 'Owner self-adoption does not prove canonical Work/owner gate';
  end if;

  select pg_get_functiondef(
    'atlas.report_self_responsible_company_work_self_api_v1(uuid,text,text,jsonb)'::regprocedure)
    into v_fn;
  if position('selfPersonId' in v_fn)=0
    or position('reported_by_institutional_person_record_id' in v_fn)=0
    or position('ordinary_company_work_worker_attestation_v1' in v_fn)=0
    or position('work_result_acceptances' in v_fn)=0
    or position('work_execution_results' in v_fn)=0
    or position('employeeSeatRequired' in v_fn)=0
    or position('worker_day' in lower(v_fn))>0 then
    raise exception 'Principal self-result has an ungoverned or employee-only path';
  end if;

  select pg_get_functiondef(
    'atlas.self_responsible_company_work_today_self_api_v1(integer)'::regprocedure)
    into v_fn;
  if position('atlas.current_person_id_v1' in v_fn)=0
    or position('owner_self_adoption_existing_company_work' in v_fn)=0
    or position('sourceDateIsNotInstitutionalSchedule' in v_fn)=0
    or position('organization_employee_seats' in v_fn)>0 then
    raise exception 'Personal Today self-work projection not Person-rooted';
  end if;
end
$verify$;
