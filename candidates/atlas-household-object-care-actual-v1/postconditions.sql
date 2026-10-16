-- Identity-free structural gates for the *staged*, dependent Household object-care actual.
do $$
declare
 v_writer text;
 v_public text;
begin
 if to_regclass('atlas.household_care_objects') is null
    or to_regclass('atlas.household_object_care_requirements') is null
    or to_regprocedure('atlas.record_current_household_claim_evidence_api_v1(jsonb)') is null then
   raise exception 'Household care prerequisite objects/membrane missing.';
 end if;
 select pg_get_functiondef(to_regprocedure('atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)')::oid)
   into v_writer;
 select pg_get_functiondef(to_regprocedure('public.record_personal_cleaning_object_actual_self_api_v1(jsonb)')::oid)
   into v_public;
 if v_writer is null or v_public is null then
   raise exception 'Object care physical actual command or public membrane missing.';
 end if;
 if position('household_care_objects' in v_writer)=0
    or position('household_object_care_requirements' in v_writer)=0
    or position('record_current_household_claim_evidence_api_v1' in v_writer)=0
    or position('care_performed' in v_writer)=0
    or position('notWholeRoomRestoration' in v_writer)=0 then
   raise exception 'Object care source/result boundary incomplete.';
 end if;
 if not has_function_privilege('authenticated','public.record_personal_cleaning_object_actual_self_api_v1(jsonb)'::regprocedure,'EXECUTE')
    or has_function_privilege('anon','public.record_personal_cleaning_object_actual_self_api_v1(jsonb)'::regprocedure,'EXECUTE')
    or has_function_privilege('anon','atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)'::regprocedure,'EXECUTE') then
   raise exception 'Object care result authenticated/anonymous execution boundary incorrect.';
 end if;
 if not exists(
   select 1 from atlas.authenticated_rpc_registry r
   where r.signature='atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)'
     and r.review_status='active' and r.authenticated_execute_expected
     and r.security_definer_expected and r.service_execute_expected
     and not r.anonymous_execute_expected
 ) then
   raise exception 'Object care writer RPC custody registration absent.';
 end if;
end $$;
