-- Direct Ledger-issued Work is its own governed Person-native establishment basis.
do $check$
declare signature text;
begin
 if not exists(select 1 from pg_constraint
   where conrelid='atlas.work_allocations'::regclass
    and conname='work_allocations_exact_assignee_carrier_v1'
    and pg_get_constraintdef(oid) like '%ledger_connection_direct_assignment%') then
  raise exception 'Exact native Person allocation does not include direct Ledger assignment';end if;
 for signature in select unnest(array[
  'atlas.validate_active_work_allocation_membership_v1()',
  'atlas.validate_work_execution_plan_v1()',
  'atlas.connected_person_company_work_today_self_api_v1(integer)',
  'atlas.connected_person_company_work_day_self_api_v1(date)',
  'atlas.report_connected_person_company_work_internal_v1(uuid,text,text,jsonb,text,uuid,text)',
  'atlas.connected_person_place_work_self_api_v1(uuid,date,text)',
  'atlas.guard_work_allocation_responsibility_establishment_v2()'
 ]) loop
  if position('ledger_connection_direct_assignment' in pg_get_functiondef(to_regprocedure(signature)))=0
  then raise exception 'Direct connection Work not governed by %',signature;end if;
 end loop;
 if to_regprocedure('public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)') is null
  or to_regprocedure('atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)') is null
  then raise exception 'Missing protected and public direct-assignment RPC';end if;
 if has_function_privilege('anon','public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)','EXECUTE')
  or not has_function_privilege('authenticated','public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)','EXECUTE')
  then raise exception 'Direct assignment must require authenticated user';end if;
 if exists(select 1 from pg_proc where oid='public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)'::regprocedure and prosecdef)
 then raise exception 'Browser bridge must remain invoker';end if;
 if position('active_mutual_native_ledger_connections' in pg_get_functiondef(
    'atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))=0
 then raise exception 'Source guard must verify real Ledger seats';end if;
 if position('personDayPlacementEstablished' in pg_get_functiondef(
    'atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)'::regprocedure))=0
 then raise exception 'Direct Ledger Work requires a dated Day plan';end if;
end$check$;