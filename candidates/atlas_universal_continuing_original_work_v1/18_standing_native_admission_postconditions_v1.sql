-- HELD: stand-alone source checks on the original native Work architecture.
DO $admission_gate$
DECLARE
 v_internal regprocedure:=to_regprocedure('atlas.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)');
 v_public regprocedure:=to_regprocedure('public.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)');
 v_source regprocedure:=to_regprocedure('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)');
 v_native regprocedure:=to_regprocedure('atlas.guard_work_allocation_responsibility_establishment_v2()');
 v_sql text;
BEGIN
 IF v_internal IS NULL OR v_public IS NULL OR v_source IS NULL OR v_native IS NULL
 THEN RAISE EXCEPTION 'Exact native standing Work admission source missing'; END IF;
 IF has_function_privilege('anon',v_public,'EXECUTE')
 OR has_function_privilege('anon',v_internal,'EXECUTE')
 OR has_function_privilege('authenticated',v_internal,'EXECUTE')
 OR has_function_privilege('service_role',v_internal,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
 THEN RAISE EXCEPTION 'Client may bypass signed standing source membrane'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p
   WHERE p.oid=v_internal AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 THEN RAISE EXCEPTION 'Standing source admission must use empty pinned search path'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint con
    WHERE con.conrelid='atlas.company_work_native_ledger_relevance'::regclass
    AND con.conname='company_work_relevance_evidence_separation_v1'
    AND position('continuing_work_source_governance_events_v1' IN pg_get_constraintdef(con.oid))>0)
 THEN RAISE EXCEPTION 'Standing source must have bounded, verified Ledger relevance'; END IF;
 v_sql:=pg_get_functiondef(v_source);
 IF position('booking_requests' IN v_sql)=0
 OR position('booking_offerings' IN v_sql)=0
 OR position('continuing_work_source_governance_events_v1' IN v_sql)=0
 THEN RAISE EXCEPTION 'Native Ledger exact source lost existing or new proof'; END IF;
 v_sql:=pg_get_functiondef(v_native);
 IF position('standing_continuing_source_admission_v1' IN v_sql)=0
 OR position('standingPolicyEventId' IN v_sql)=0
 OR position('delegated_under_standing_scope' IN v_sql)=0
 THEN RAISE EXCEPTION 'Current native responsibility trigger lacks exact standing authorization'; END IF;
 v_sql:=pg_get_functiondef(v_internal);
 IF position('source_qualified_and_timing_eligible' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('continuing-work:organization:' IN v_sql)=0
 OR position('existing original or legacy Work' IN lower(v_sql))=0
 OR position('care_current_state' IN v_sql)=0
 OR position('source_verified' IN v_sql)=0
 OR position('work_execution_plans' IN v_sql)=0
 OR position('noClockAdmission' IN v_sql)=0
 THEN RAISE EXCEPTION 'Standing admission source lacks current Work/physical/Person-day guard'; END IF;
 RAISE NOTICE 'One canonical original Work, one Person allocation and a deliberately selected service day remain source-gated.';
END;
$admission_gate$;
