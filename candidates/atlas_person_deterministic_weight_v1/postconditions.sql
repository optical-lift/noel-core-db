-- Post-release CLONE checks only. This file is not a production migration.
select atlas.recognize_body_weight_sentence_v1('I weighed 172 pounds this morning.') as weighed_172;
select atlas.recognize_body_weight_sentence_v1('My right knee hurts today.') as unmatched_symptom;
select atlas.recognize_body_weight_sentence_v1('I weighed my dog 172 pounds.') as unmatched_third_party;
select atlas.recognize_body_weight_sentence_v1('I weighed 172.') as unknown_unit;
select n.nspname,p.proname,p.prosecdef,has_function_privilege('authenticated',p.oid,'execute') authenticated,
 has_function_privilege('anon',p.oid,'execute') anonymous
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where p.proname in ('person_measurement_recognition_self_api_v1','set_person_measurement_rule_self_api_v1',
 'person_body_weight_history_self_api_v1','recognize_body_weight_sentence_v1')
and n.nspname in ('atlas','public');
-- Follow with two genuinely separate signed-in sessions and an unauthenticated denial,
-- not SQL spoofing of auth.uid().