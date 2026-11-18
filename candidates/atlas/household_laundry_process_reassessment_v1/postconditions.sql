begin;
do $test$
declare fn text; p text; role_name text;
begin
 foreach fn in array array['household_laundry_reassessment_self_api_v1()','record_household_laundry_reassessment_self_api_v1(uuid,uuid,integer,uuid)','record_household_laundry_wash_finished_self_api_v1(uuid,uuid,uuid,boolean)','record_household_laundry_drying_started_self_api_v1(uuid,uuid,text)'] loop
  foreach role_name in array array['anon','service_role'] loop
   if has_function_privilege(role_name,'public.'||fn,'EXECUTE') then raise exception 'Unexpected public adapter grant'; end if;
  end loop;
  if not has_function_privilege('authenticated','public.'||fn,'EXECUTE')
   or has_function_privilege('authenticated','atlas.'||fn,'EXECUTE')
  then raise exception 'Signed adapter membrane failed'; end if;
 end loop;
 foreach p in array array['atlas.evidence_records','atlas.care_current_state'] loop
  if has_table_privilege('authenticated',p,'INSERT') or has_table_privilege('authenticated',p,'UPDATE')
   or has_table_privilege('authenticated',p,'DELETE') or has_table_privilege('anon',p,'INSERT')
  then raise exception 'Direct source mutation exposed'; end if;
 end loop;
 begin perform public.household_laundry_reassessment_self_api_v1(); raise exception 'Unsigned read accepted';
 exception when insufficient_privilege then null; end;
end;
$test$;
rollback;
