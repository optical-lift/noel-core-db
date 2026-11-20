-- Read-only postconditions for the reviewed full-schema clone, no fixtures required.
do $$
declare r text; priv text;
begin
 if not exists(select 1 from pg_catalog.pg_class where oid='transcript_core.delivery_package_artifacts'::regclass and relrowsecurity) then
  raise exception 'Listening binding RLS missing';
 end if;
 if not exists(select 1 from pg_catalog.pg_trigger where tgrelid='transcript_core.delivery_package_artifacts'::regclass and tgname='guard_listening_delivery_artifact_v1' and tgenabled='O' and not tgisinternal) then
  raise exception 'Listening binding guard missing';
 end if;
 if exists(select 1 from pg_catalog.pg_proc where oid='transcript_core.bind_verified_listening_delivery_artifact_v1(uuid,uuid,text,bigint,text,text)'::regprocedure and prosecdef) then
  raise exception 'Unexpected privileged intake function';
 end if;
 foreach r in array array['anon','authenticated','service_role'] loop
   foreach priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
     if pg_catalog.has_table_privilege(r,'transcript_core.delivery_package_artifacts',priv) then
       raise exception 'Unexpected listening binding privilege % for %',priv,r;
     end if;
   end loop;
   if pg_catalog.has_function_privilege(r,'transcript_core.guard_listening_delivery_artifact_v1()','EXECUTE')
    or pg_catalog.has_function_privilege(r,'transcript_core.bind_verified_listening_delivery_artifact_v1(uuid,uuid,text,bigint,text,text)','EXECUTE') then
     raise exception 'Unexpected listening binding function grant to %',r;
   end if;
 end loop;
 if exists (select 1 from transcript_core.delivery_package_artifacts) then raise exception 'Candidate must not seed binding rows'; end if;
end;
$$;
select 'PASS held listening artifact source shape, private invoker and zero-seed custody' as result;
