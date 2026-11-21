-- Draft protected-clone structural postconditions. Cannot replace
-- independently signed owner/worker/outsider/anonymous HTTP acceptance.
DO $standing_policy$
DECLARE
 v_table regclass:=to_regclass('atlas.continuing_work_source_governance_events_v1');
 v_policy regprocedure:=to_regprocedure('atlas.owner_decide_continuing_source_governance_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid)');
 v_public_policy regprocedure:=to_regprocedure('public.owner_decide_continuing_source_governance_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid)');
 v_eligibility regprocedure:=to_regprocedure('atlas.continuing_work_source_eligibility_self_api_v1(uuid,uuid,uuid)');
 v_public_eligibility regprocedure:=to_regprocedure('public.continuing_work_source_eligibility_self_api_v1(uuid,uuid,uuid)');
 v_observation regprocedure:=to_regprocedure('atlas.record_standing_care_observation_self_api_v1(uuid,uuid,uuid,text,text,uuid)');
 v_public_observation regprocedure:=to_regprocedure('public.record_standing_care_observation_self_api_v1(uuid,uuid,uuid,text,text,uuid)');
 v_sql text;
BEGIN
 IF v_table IS NULL OR v_policy IS NULL OR v_public_policy IS NULL
 OR v_eligibility IS NULL OR v_public_eligibility IS NULL
 OR v_observation IS NULL OR v_public_observation IS NULL
 THEN RAISE EXCEPTION 'Standing authority, eligibility, and signed physical evidence sources required'; END IF;
 IF NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid=v_table)
 OR has_table_privilege('anon',v_table,'SELECT')
 OR has_table_privilege('authenticated',v_table,'SELECT')
 OR has_table_privilege('authenticated',v_table,'INSERT')
 OR has_table_privilege('service_role',v_table,'INSERT') THEN
   RAISE EXCEPTION 'Raw standing authority history is exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=v_table
   AND t.tgname='continuing_work_source_governance_append_only_v1'
   AND NOT t.tgisinternal) THEN
   RAISE EXCEPTION 'Standing authority event history must be immutable'; END IF;
 IF has_function_privilege('anon',v_policy,'EXECUTE')
 OR has_function_privilege('authenticated',v_policy,'EXECUTE')
 OR has_function_privilege('service_role',v_policy,'EXECUTE')
 OR has_function_privilege('anon',v_eligibility,'EXECUTE')
 OR has_function_privilege('authenticated',v_eligibility,'EXECUTE')
 OR has_function_privilege('anon',v_observation,'EXECUTE')
 OR has_function_privilege('authenticated',v_observation,'EXECUTE')
 OR has_function_privilege('anon',v_public_policy,'EXECUTE')
 OR has_function_privilege('anon',v_public_eligibility,'EXECUTE')
 OR has_function_privilege('anon',v_public_observation,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_policy,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_eligibility,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_observation,'EXECUTE')
 THEN
   RAISE EXCEPTION 'Signed public and restricted private standing seams are not separated';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_eligibility
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_policy
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_observation
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 THEN RAISE EXCEPTION 'Standing source functions require fixed empty search paths'; END IF;
 v_sql:=pg_get_functiondef(v_eligibility);
 IF position('last_qualifying_satisfaction_id' IN v_sql)=0
 OR position('inferred_from_clock' IN v_sql)=0
 OR position('last_observation_id' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('work_items' IN v_sql)=0
 OR position('planned_work_occurrences' IN v_sql)=0
 THEN RAISE EXCEPTION 'Standing eligibility must check physical source, policy and prior Work'; END IF;
 IF v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
 OR v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_execution_plans'
 THEN RAISE EXCEPTION 'Eligibility read source must not fabricate original Work or date'; END IF;
 v_sql:=pg_get_functiondef(v_observation);
 IF position('auth.uid()' IN v_sql)=0
 OR position('standing_source_observed' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('care_observation_events' IN v_sql)=0
 OR position('person_has_native_ledger_connection_v1' IN v_sql)=0
 THEN RAISE EXCEPTION 'Signed physical evidence lacks real Person or current source gates'; END IF;
 IF v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
 OR v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_execution_plans'
 THEN RAISE EXCEPTION 'Worker observation cannot generate Work or schedule Today'; END IF;
 RAISE NOTICE 'Standing source policy and current physical evidence are source-governed. Work admission remains a separate gate.';
END;
$standing_policy$;
