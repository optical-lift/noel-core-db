-- Postconditions for Atlas Build 5 Today/Person native Work candidate.
-- Execute in disposable production-shaped schema clone after candidate migration.
do $test$
declare
 v_nullable text;
begin
 select is_nullable into v_nullable from information_schema.columns
 where table_schema='atlas' and table_name='work_execution_plans'
   and column_name='assignee_membership_id';
 if v_nullable is distinct from 'YES' then
   raise exception 'Person-native plans must not require employee/organization membership';
 end if;
 if not exists (
   select 1 from information_schema.columns
   where table_schema='atlas' and table_name='work_time_contracts'
     and column_name='due_on_date' and data_type='date'
 ) then
   raise exception 'Independent canonical date-only deadline is missing';
 end if;
 if to_regprocedure('atlas.owner_create_native_ledger_today_work_self_api_v1(uuid,uuid,uuid,text,date,date,text,boolean)') is null then
   raise exception 'Canonical owner Today command not published';
 end if;
 if to_regprocedure('atlas.connected_person_company_work_day_self_api_v1(date)') is null then
   raise exception 'Person Day projection missing';
 end if;
 if to_regprocedure('atlas.set_personal_task_archive_self_api_v1(uuid,boolean)') is null
    or to_regprocedure('atlas.personal_archived_tasks_day_self_api_v1(date)') is null then
   raise exception 'Owner archive custody or retrieval command missing';
 end if;
 if not exists(
   select 1 from information_schema.columns
   where table_schema='atlas' and table_name='task_entries'
     and column_name='archived_at' and data_type='timestamp with time zone'
 ) then raise exception 'Personal archive state is not durable'; end if;
 if has_function_privilege('anon','atlas.set_personal_task_archive_self_api_v1(uuid,boolean)','EXECUTE')
    or has_function_privilege('anon','atlas.personal_archived_tasks_day_self_api_v1(date)','EXECUTE') then
   raise exception 'Anonymous personal archive access is exposed';
 end if;
 if to_regprocedure('atlas.delete_unlinked_personal_task_self_api_v1(uuid)') is null then
   raise exception 'Safe permanent personal task deletion command is missing';
 end if;
 if has_function_privilege('anon','atlas.delete_unlinked_personal_task_self_api_v1(uuid)','EXECUTE') then
   raise exception 'Anonymous personal task deletion is exposed';
 end if;
 if has_function_privilege('anon','atlas.owner_create_native_ledger_today_work_self_api_v1(uuid,uuid,uuid,text,date,date,text,boolean)','EXECUTE') then
   raise exception 'Anonymous owner Work creation is exposed';
 end if;
 if has_function_privilege('anon','atlas.connected_person_company_work_day_self_api_v1(date)','EXECUTE') then
   raise exception 'Anonymous Person Day read is exposed';
 end if;
end
$test$;

-- Acceptance still requires signed-in, source-grounded end-to-end exercise in
-- the protected environment. No invented Marshall receipt or fake auth context.
