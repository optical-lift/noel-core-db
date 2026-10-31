-- Future v3 source-only access postconditions. Deliberately NOT yet executable
-- against current production or held v1/v2: v3 adoption is unfinished.
BEGIN;
DO $test$
DECLARE v_sig text := 'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)';
BEGIN
 IF pg_catalog.has_table_privilege('service_role',
   'us.financial_expectation_revisions','INSERT') THEN
   RAISE EXCEPTION 'Unrestricted revision insertion remains permitted'; END IF;
 IF pg_catalog.has_table_privilege('service_role',
   'us.financial_expectation_lines','INSERT') THEN
   RAISE EXCEPTION 'Unrestricted dated line insertion remains permitted'; END IF;
 IF pg_catalog.has_function_privilege('service_role',v_sig,'EXECUTE') THEN
   RAISE EXCEPTION 'Legacy appender still permits direct draft sealing'; END IF;
 IF pg_catalog.to_regprocedure('us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint)')
   IS NULL THEN
   RAISE EXCEPTION 'Narrow event-derived adoption entrypoint missing'; END IF;
 IF pg_catalog.has_function_privilege('anon',
   'us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint)','EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint)','EXECUTE') THEN
   RAISE EXCEPTION 'Direct public or authenticated adoption grant exposed'; END IF;
 IF pg_catalog.has_table_privilege('anon','us.carry_case_events_v1','SELECT')
 OR pg_catalog.has_table_privilege('authenticated','us.carry_case_events_v1','SELECT') THEN
   RAISE EXCEPTION 'Private Carry history is directly readable'; END IF;
END
$test$;
ROLLBACK;
