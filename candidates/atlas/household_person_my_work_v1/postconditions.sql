begin;
do $plan_test$
declare body text;
begin
 if has_function_privilege('anon','public.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text)','EXECUTE')
 or not has_function_privilege('authenticated','public.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text)','EXECUTE')
 or has_function_privilege('authenticated','atlas.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text)','EXECUTE')
 then raise exception 'Placement ACL failed'; end if;
 select pg_get_functiondef('atlas.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text)'::regprocedure) into body;
 if position('atlas.require_household_governor_self_v1' in body)=0
 or position('atlas.personal_week_work_fit_preview_self_api_v1' in body)=0
 or position('v_allocation.assignee_canonical_person_id is distinct from v_person' in lower(body))=0
 or position('sourceActionId' in body)=0
 or position('insert into atlas.work_items' in lower(body))>0
 or position('''clockAdmitted'',false' in body)=0
 then raise exception 'Placement source boundary failed'; end if;
 if not exists(select 1 from pg_trigger t
   where t.tgrelid='atlas.work_items'::regclass and t.tgname='work_items_complete_household_original_plan_v1'
    and not t.tgisinternal and t.tgenabled='O') then raise exception 'Plan closure trigger missing'; end if;
 select pg_get_functiondef('atlas.guard_household_work_plan_v1()'::regprocedure) into body;
 if position('source_qualified_physical_actual' in body)=0 or position('atlas.require_household_governor_self_v1' in body)=0
 or position('to_jsonb(OLD)' in body)=0 then raise exception 'Terminal-only receipt guard missing'; end if;
 begin
   perform public.place_household_laundry_original_work_self_api_v1(gen_random_uuid(),current_date,gen_random_uuid(),'Confirm test placement.');
   raise exception 'Unsigned placement unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end;
$plan_test$;
rollback;
