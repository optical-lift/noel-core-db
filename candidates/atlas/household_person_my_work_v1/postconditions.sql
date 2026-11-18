begin;
do $test$
declare body text;
begin
 if has_function_privilege('anon','public.household_person_my_work_self_api_v1(integer,uuid)','EXECUTE')
 or not has_function_privilege('authenticated','public.household_person_my_work_self_api_v1(integer,uuid)','EXECUTE')
 or has_function_privilege('authenticated','atlas.household_person_my_work_self_api_v1(integer,uuid)','EXECUTE')
 then raise exception 'Household Person projection ACL failed'; end if;
 select pg_get_functiondef('atlas.household_person_my_work_self_api_v1(integer,uuid)'::regprocedure) into body;
 if position('atlas.reality_access_self_api_v1()' in body)=0
 or position('a.assignee_canonical_person_id=v_person' in body)=0
 or position('m.user_id=auth.uid()' in body)=0
 or position('n.current_work_item_id=w.id' in body)=0
 or position('plan_allocation_id=allocation_id' in body)=0
 or position('''clockAdmitted'',false' in body)=0
 or position('''canPlace'',false' in body)=0
 then raise exception 'Original work/source boundaries absent'; end if;
 -- No signed-session construction in production. This is a clone-only call.
 begin
  perform public.household_person_my_work_self_api_v1(50,null);
  raise exception 'Anonymous or unbound self read unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end;
$test$;
rollback;
