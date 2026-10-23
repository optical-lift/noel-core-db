-- Protected clone-only structural proof.
do $check$ begin
 if to_regprocedure('public.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)') is null
 or to_regprocedure('atlas.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)') is null then
   raise exception 'Missing governed person history reader';
 end if;
 if has_function_privilege('anon','public.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
 or not has_function_privilege('authenticated','public.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
 or has_function_privilege('authenticated','atlas.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
 then raise exception 'Person history reader grants invalid'; end if;
 raise notice 'Governed Person source history read-only membrane and grants exist';
end $check$;
