-- Run only against a disposable PostgreSQL test database after the exact candidate.
do $proof$
declare v jsonb;
begin
 v:=atlas.recognize_body_weight_sentence_v1('I weighed 172 pounds this morning.');
 if v->>'measurementKind'<>'body_weight' or v->>'unit'<>'lb'
    or (v->>'value')::numeric<>172
    or (v->>'canonicalValueKg')::numeric<>78.01788764
    or v->>'observedAt' is not null then
   raise exception 'Weight source/unit/time recognition failed';
 end if;
 if atlas.recognize_body_weight_sentence_v1('my weight was 80 kg today.') is null
    or atlas.recognize_body_weight_sentence_v1('I weighed my dog 172 pounds.') is not null
    or atlas.recognize_body_weight_sentence_v1('I weighed 172.') is not null
    or atlas.recognize_body_weight_sentence_v1('My right knee hurts.') is not null then
   raise exception 'Grammar accepted an ambiguous or unrelated statement';
 end if;
 if pg_catalog.has_function_privilege('anon','public.person_body_weight_history_self_api_v1(integer,text)','EXECUTE')
   or pg_catalog.has_function_privilege('anon','public.set_person_measurement_rule_self_api_v1(uuid,boolean)','EXECUTE')
   or pg_catalog.has_table_privilege('authenticated','atlas.person_recognition_rule_permissions_v1','SELECT')
   or not (select relrowsecurity from pg_catalog.pg_class where oid='atlas.person_recognition_rule_permissions_v1'::regclass) then
   raise exception 'Owner boundary or anon grants are invalid';
 end if;
end $proof$;
