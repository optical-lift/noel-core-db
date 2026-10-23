-- Reviewed candidate postconditions for a disposable production-schema clone.
-- No fixture rows or real personal data are needed for structural validation.
do $check$
declare v jsonb;
begin
 if to_regclass('atlas.person_recognition_rule_permissions_v1') is null
    or to_regprocedure('atlas.recognize_body_weight_sentence_v1(text)') is null
    or to_regprocedure('public.person_measurement_recognition_self_api_v1(uuid)') is null
    or to_regprocedure('public.set_person_measurement_rule_self_api_v1(uuid,boolean)') is null
    or to_regprocedure('public.person_body_weight_history_self_api_v1(integer,text)') is null then
    raise exception 'Required source-backed measurement functions/permissions missing';
 end if;
 if not (select relrowsecurity from pg_catalog.pg_class
         where oid='atlas.person_recognition_rule_permissions_v1'::regclass)
    or pg_catalog.has_table_privilege('anon','atlas.person_recognition_rule_permissions_v1','SELECT')
    or pg_catalog.has_table_privilege('authenticated','atlas.person_recognition_rule_permissions_v1','SELECT')
    or pg_catalog.has_function_privilege('anon','public.set_person_measurement_rule_self_api_v1(uuid,boolean)','EXECUTE')
    or pg_catalog.has_function_privilege('anon','public.person_body_weight_history_self_api_v1(integer,text)','EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated','public.person_measurement_recognition_self_api_v1(uuid)','EXECUTE') then
    raise exception 'RLS and callable permission boundaries are inconsistent';
 end if;
 v:=atlas.recognize_body_weight_sentence_v1('I weighed 172 pounds this morning.');
 if (v->>'value')::numeric<>172
    or (v->>'canonicalValueKg')::numeric<>78.01788764
    or v->>'observedAt' is not null
    or atlas.recognize_body_weight_sentence_v1('I weighed my dog 172 pounds.') is not null
    or atlas.recognize_body_weight_sentence_v1('I weighed 172.') is not null then
    raise exception 'Conservative deterministic grammar contract failed';
 end if;
 raise notice 'Measurement grammar and privileges verified on disposable schema clone. Signed Supabase sessions must still be tested separately.';
end $check$;
