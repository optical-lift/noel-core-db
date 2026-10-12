BEGIN;
DO $validation$
DECLARE v_def text;
BEGIN
 IF to_regprocedure('atlas.reality_discovery_first_day_status_self_api_v1()') IS NULL
    OR to_regprocedure('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)') IS NULL
    OR to_regprocedure('atlas.reality_discovery_orientation_profile_self_api_v1()') IS NULL
 THEN RAISE EXCEPTION 'First-use Foundry routing RPCs missing'; END IF;
 SELECT pg_get_functiondef('atlas.reality_discovery_first_day_status_self_api_v1()'::regprocedure) INTO v_def;
 IF position('v_bookplate_captured and v_orientation_captured' in v_def)=0
    OR position('not v_bookplate_captured or not v_orientation_captured' in v_def)=0
    OR position('IndexIsNotMandatoryOnboarding' in v_def)=0
 THEN RAISE EXCEPTION 'First-day completion still requires obsolete Index selection'; END IF;
 SELECT pg_get_functiondef('atlas.reality_discovery_orientation_profile_self_api_v1()'::regprocedure) INTO v_def;
 IF position('order by occurred_at desc,id desc' in v_def)=0
 THEN RAISE EXCEPTION 'New explicit orientation cannot supersede an older Index event'; END IF;
 SELECT pg_get_functiondef('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)'::regprocedure) INTO v_def;
 IF position('v_domain_filter_source' in v_def)=0
    OR position('human_field_orientation' in v_def)=0
    OR position('v_domain_filter_captured' in v_def)=0
    OR position('humanFieldOrIndexConstrainsFirstDayQuestions' in v_def)=0
 THEN RAISE EXCEPTION 'Discovery questions do not use selected Field in absence of Index'; END IF;
 IF has_function_privilege('anon','atlas.reality_discovery_first_day_status_self_api_v1()','EXECUTE')
    OR has_function_privilege('anon','atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)','EXECUTE')
    OR NOT has_function_privilege('authenticated','atlas.reality_discovery_first_day_status_self_api_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'First-day function access boundary widened or broken'; END IF;
END $validation$;
ROLLBACK;
