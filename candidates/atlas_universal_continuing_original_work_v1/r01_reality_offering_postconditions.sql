-- R01 protected-clone postconditions. Execute only after composing the
-- source into a disposable, production-schema-shaped database and ROLLBACK.
-- These are structural and synthetic unsigned checks, NOT signed human tests.
DO $r01_post$
DECLARE v_functions text[]:=ARRAY[
 'atlas.owner_establish_standing_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])',
 'atlas.standing_care_next_governed_service_day_v1(timestamptz,text,jsonb,date)',
 'atlas.owner_preview_standing_care_candidates_self_api_v1(uuid,uuid,uuid,uuid,text,date,uuid,integer)',
 'atlas.standing_care_next_subject_internal_v1(uuid,uuid)',
 'atlas.standing_care_auto_successor_authorized_v1(uuid,uuid,jsonb)',
 'atlas.advance_owner_standing_campaign_after_actual_internal_v1(uuid)',
 'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)'
]; v_name text; v_fn oid; v_guard text; v_actual text;
BEGIN
 IF to_regclass('atlas.work_lifecycle_events_v1') IS NULL
    OR to_regprocedure('atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'R01 missing one original-Work lifecycle'; END IF;
 FOREACH v_name IN ARRAY v_functions LOOP
   v_fn:=to_regprocedure(v_name);
   IF v_fn IS NULL THEN RAISE EXCEPTION 'R01 missing exact function: %',v_name; END IF;
   IF has_function_privilege('anon',v_fn,'EXECUTE')
     OR has_function_privilege('authenticated',v_fn,'EXECUTE')
     OR has_function_privilege('service_role',v_fn,'EXECUTE')
   THEN RAISE EXCEPTION 'R01 draft function prematurely exposed: %',v_name; END IF;
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('atlas.guard_work_allocation_responsibility_establishment_v2()'))
 INTO v_guard;
 IF v_guard NOT LIKE '%capability_root_authority_context_self_v1%'
   OR v_guard NOT LIKE '%standing_continuing_source_admission_v1%'
   OR v_guard NOT LIKE '%standing_care_auto_successor_authorized_v1%'
   OR v_guard NOT LIKE '%owner_preapproved_standing_care_actual_successor_v1%'
 THEN RAISE EXCEPTION 'R01 lost live Ledger root or existing native-source protection'; END IF;
 SELECT pg_get_functiondef(to_regprocedure('atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)'))
 INTO v_actual;
 IF v_actual NOT LIKE '%apply_work_lifecycle_transition_internal_v1%'
   OR v_actual NOT LIKE '%advance_owner_standing_campaign_after_actual_internal_v1%'
   OR v_actual NOT LIKE '%source_continuation_needs_review%'
   OR v_actual NOT LIKE '%historicalRecordedCompletion%'
 THEN RAISE EXCEPTION 'R01 care Actual lost unified Done or safe continuation'; END IF;
 -- A continuation is NOT authorized by a hardcoded old farm calendar.
 IF pg_get_functiondef(to_regprocedure(
   'atlas.standing_care_next_governed_service_day_v1(timestamptz,text,jsonb,date)'
 )) NOT LIKE '%extract(isodow FROM v_next)%'
 OR pg_get_functiondef(to_regprocedure(
   'atlas.advance_owner_standing_campaign_after_actual_internal_v1(uuid)'
 )) NOT LIKE '%sourceStandingWorkdaysIso%'
 OR pg_get_functiondef(to_regprocedure(
   'atlas.advance_owner_standing_campaign_after_actual_internal_v1(uuid)'
 )) LIKE '%extract(dow FROM v_next_date)%'
 THEN RAISE EXCEPTION 'R01 successor has no approved governing workday proof'; END IF;
 IF (SELECT count(*) FROM atlas.work_result_contract_policies
   WHERE contract_key='continuing_care_actual_v1'
    AND source_domain='organization' AND acceptance_mode='domain_adapter'
    AND active)<>1
 THEN RAISE EXCEPTION 'R01 source-qualified care Result contract missing'; END IF;
END;
$r01_post$;

-- A deliberately unsigned unknown-work request must fail closed and must
-- never create a real Work, allocation, care Result or rhythm satisfaction.
DO $r01_negative$
DECLARE v_rejected boolean:=false;
BEGIN
 BEGIN
   PERFORM atlas.advance_owner_standing_campaign_after_actual_internal_v1(
    '00000000-0000-4000-8000-000000000001'::uuid);
 EXCEPTION WHEN OTHERS THEN v_rejected:=true;
 END;
 IF NOT v_rejected THEN
   RAISE EXCEPTION 'R01 unsigned unknown physical Result did not deny';
 END IF;
END;
$r01_negative$;
