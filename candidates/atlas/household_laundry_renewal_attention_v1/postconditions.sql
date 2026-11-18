begin;
do $test$
declare fn text; role_name text; body text;
begin
 foreach fn in array array['household_laundry_renewal_attention_self_api_v1()','record_household_laundry_renewal_not_ready_self_api_v1(uuid,uuid,uuid,uuid)'] loop
   if not has_function_privilege('authenticated','public.'||fn,'EXECUTE') then raise exception 'Signed adapter missing'; end if;
   foreach role_name in array array['anon','service_role'] loop
     if has_function_privilege(role_name,'public.'||fn,'EXECUTE') then raise exception 'Unexpected adapter grant'; end if;
   end loop;
   foreach role_name in array array['anon','authenticated','service_role'] loop
     if has_function_privilege(role_name,'atlas.'||fn,'EXECUTE') then raise exception 'Private function grant'; end if;
   end loop;
   body:=lower(pg_get_functiondef(('atlas.'||fn)::regprocedure));
   if body like '%insert into atlas.work_items%' or body like '%insert into atlas.household_need_occurrences_v1%'
    or body like '%insert into atlas.tasks%' or body like '%insert into atlas.rhythm_satisfactions%'
    or body like '%update atlas.household_rhythms%' or body like '%insert into atlas.task_release_queue_items%'
    then raise exception 'Renewal must not issue or alter Work or recurrence authority'; end if;
 end loop;
 begin perform public.household_laundry_renewal_attention_self_api_v1(); raise exception 'Unsigned read accepted';
 exception when insufficient_privilege then null; end;
 begin perform public.record_household_laundry_renewal_not_ready_self_api_v1(null,null,null,null); raise exception 'Unsigned write accepted';
 exception when insufficient_privilege then null; end;
end;
$test$;
rollback;
