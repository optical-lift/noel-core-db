-- Validation in disposable production-shaped clone; asserts access, name routing and provenance boundaries.
do $atlas_api_check$
declare name text; public_oid oid; inner_oid oid; arguments text; body text;
begin
for name in select unnest(array['connected_ledger_inbox_self_api_v1','connected_ledger_person_choices_self_api_v1','connected_ledger_respond_self_api_v1','connected_ledger_send_self_api_v1','connected_person_company_work_day_self_api_v1','delete_unlinked_personal_task_self_api_v1','native_today_work_void_preflight_self_api_v1','owner_create_native_ledger_today_work_self_api_v1','owner_native_ledger_blocker_detail_self_api_v1','owner_set_connected_person_work_day_self_api_v1','owner_void_native_today_work_self_api_v1','personal_archived_tasks_day_self_api_v1','set_personal_task_archive_self_api_v1']) loop
 select a.oid, pg_get_function_identity_arguments(a.oid) into inner_oid, arguments
 from pg_proc a join pg_namespace n on n.oid=a.pronamespace
 where n.nspname='atlas' and a.proname=name;
 if inner_oid is null or arguments is null then
  raise exception 'Canonical Atlas RPC absent: %',name;end if;
 select p.oid into public_oid
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=name
 and pg_get_function_identity_arguments(p.oid)=arguments;
 if public_oid is null then
   raise exception 'Browser public RPC bridge missing: %(%)',name,arguments;end if;
 if not has_function_privilege('authenticated',public_oid,'EXECUTE')
    or has_function_privilege('anon',public_oid,'EXECUTE')
    or has_function_privilege('public',public_oid,'EXECUTE') then
   raise exception 'Browser RPC bridge grants unsafe: %',name;end if;
 if not has_function_privilege('authenticated',inner_oid,'EXECUTE')
    or has_function_privilege('anon',inner_oid,'EXECUTE') then
   raise exception 'Canonical Atlas RPC grants unsafe: %',name;end if;
 if exists(select 1 from pg_proc p where p.oid=public_oid and p.prosecdef=true)
    then raise exception 'Public wrapper must not bypass caller by SECURITY DEFINER: %',name;end if;
 select pg_get_functiondef(public_oid) into body;
 if position('atlas.'||name in body)=0 then
   raise exception 'Browser bridge does not call the intended canonical Atlas source: %',name;end if;
end loop;
if has_table_privilege('authenticated','atlas.ledger_person_dispatches','SELECT')
 or has_table_privilege('authenticated','atlas.ledger_person_dispatches','INSERT')
 or has_table_privilege('anon','atlas.ledger_person_dispatches','SELECT') then
 raise exception 'No direct access to canonical Ledger dispatch source is allowed';end if;
end $atlas_api_check$;
