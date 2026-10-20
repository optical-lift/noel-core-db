-- Run on the disposable clone after applying the candidate, then again
-- read-only against production after owner-triggered protected release.
do $test$
declare
  v_names text[]:=array[
    'atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)',
    'atlas.company_work_connected_person_choices_owner_self_api_v1(uuid,uuid,integer,uuid)',
    'public.company_work_connected_person_choices_owner_self_api_v1(uuid,uuid,integer,uuid)',
    'atlas.offer_connected_person_company_work_owner_self_api_v1(uuid,uuid,uuid,uuid,text)',
    'atlas.establish_connected_person_company_work_from_offer_v1(uuid,text,text,uuid)',
    'atlas.respond_connected_person_company_work_self_api_v1(uuid,text)',
    'atlas.witness_connected_person_company_work_uptake_owner_self_api_v1(uuid,uuid,uuid,text)',
    'atlas.connected_person_company_work_today_self_api_v1(integer)',
    'atlas.connected_person_company_work_offers_self_api_v1()',
    'atlas.report_connected_person_company_work_self_api_v1(uuid,text,text,jsonb)',
    'atlas.witness_connected_person_company_work_result_owner_self_api_v1(uuid,uuid,uuid,text,text,text)',
    'public.offer_connected_person_company_work_owner_self_api_v1(uuid,uuid,uuid,uuid,text)',
    'public.respond_connected_person_company_work_self_api_v1(uuid,text)',
    'public.witness_connected_person_company_work_uptake_owner_self_api_v1(uuid,uuid,uuid,text)',
    'public.connected_person_company_work_today_self_api_v1(integer)',
    'public.connected_person_company_work_offers_self_api_v1()',
    'public.report_connected_person_company_work_self_api_v1(uuid,text,text,jsonb)',
    'public.witness_connected_person_company_work_result_owner_self_api_v1(uuid,uuid,uuid,text,text,text)'
  ];
  v_name text;
begin
  foreach v_name in array v_names loop
    if to_regprocedure(v_name) is null then
      raise exception 'Missing governed Person-connected Company Work function: %',v_name;
    end if;
  end loop;
  if (select is_nullable from information_schema.columns
      where table_schema='atlas' and table_name='work_allocations'
        and column_name='assignee_membership_id')<>'YES'
    or (select is_nullable from information_schema.columns
      where table_schema='atlas'
        and table_name='company_work_initial_responsibility_offers'
        and column_name='target_membership_id')<>'YES' then
    raise exception 'Person-native nullable-membership carriers not installed';
  end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='atlas' and table_name='work_allocations'
      and column_name='assignee_canonical_person_id') then
    raise exception 'Canonical responsible Person column missing';
  end if;
  if not exists(select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='work_allocations'
      and t.tgname='work_allocations_canonical_person_immutable_v1'
      and t.tgenabled='O') then
    raise exception 'Canonical Person allocation mutation guard missing';
  end if;
  if (select count(*) from atlas.work_allocations a
      where a.state='active' and a.allocation_role='responsible'
        and a.assignee_membership_id is null
        and a.assignee_canonical_person_id is null)>0 then
    raise exception 'An active allocation has neither Person nor membership';
  end if;
  if has_function_privilege('authenticated',
      'atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)',
      'EXECUTE') then
    raise exception 'Cross-Ledger connection predicate must remain private';
  end if;
  if has_function_privilege('anon',
      'public.company_work_connected_person_choices_owner_self_api_v1(uuid,uuid,integer,uuid)',
      'EXECUTE') then
    raise exception 'Anonymous Ledger connection roster exposed';
  end if;
  if position('ledger.seats' in pg_get_functiondef(
      'atlas.company_work_connected_person_choices_owner_self_api_v1(uuid,uuid,integer,uuid)'::regprocedure))=0 then
    raise exception 'Work recipient chooser is not Ledger-seat sourced';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname like '%connected_person_company_work%'
      and has_function_privilege('anon',p.oid,'EXECUTE')) then
    raise exception 'Anonymous Person work transport exposed';
  end if;
end
$test$;
select 'person_connected_company_work_postconditions_v1' as contract,
       count(*) filter(where a.state='active' and a.allocation_role='responsible') as active_responsibilities,
       count(*) filter(where a.state='active' and a.allocation_role='responsible'
         and a.assignee_membership_id is null
         and a.assignee_canonical_person_id is not null) as person_native_responsibilities
  from atlas.work_allocations a;
