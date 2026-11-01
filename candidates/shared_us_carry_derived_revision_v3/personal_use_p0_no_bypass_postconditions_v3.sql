-- P0: disposable SQL privilege postconditions, no live data.
BEGIN;
DO $check$
DECLARE role_name text; function_sig text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','us_carry_backend'] LOOP
  FOREACH function_sig IN ARRAY ARRAY[
   'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)',
   'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)',
   'us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint,text)'
  ] LOOP
   IF has_function_privilege(role_name,function_sig,'EXECUTE') THEN
    RAISE EXCEPTION 'Legacy writer remains executable: % %',role_name,function_sig;
   END IF;
  END LOOP;
 END LOOP;
 IF NOT has_function_privilege('us_carry_backend',
     'us.carry_approve_and_open_primary_v3(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('us_carry_backend',
     'us.carry_read_owned_history_v3(uuid,uuid,bigint,integer)','EXECUTE')
 OR has_table_privilege('us_carry_backend','us.carry_case_events_v1','INSERT')
 OR has_table_privilege('us_carry_backend','us.carry_case_streams_v1','INSERT')
 OR has_table_privilege('service_role','us.carry_case_streams_v1','INSERT')
 OR has_table_privilege('service_role','us.carry_case_streams_v1','SELECT')
 OR has_table_privilege('service_role','us.carry_case_events_v1','SELECT')
 OR has_table_privilege('service_role','us.financial_expectation_lines','INSERT')
 OR has_table_privilege('service_role','us.financial_expectation_revisions','INSERT')
 THEN RAISE EXCEPTION 'P0 role floor broke narrow custody or failed to block inserts'; END IF;
END $check$;
SET LOCAL ROLE service_role;
DO $denials$
BEGIN
 BEGIN
  PERFORM us.carry_append_ordinary_event_v3(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
  RAISE EXCEPTION 'Legacy ordinary writer permission unexpectedly available';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_adopt_derived_revision_v3(NULL,NULL,NULL,NULL,NULL);
  RAISE EXCEPTION 'Legacy adoption writer permission unexpectedly available';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denials$;
RESET ROLE;
SET LOCAL ROLE us_carry_backend;
DO $backend$
BEGIN
 BEGIN
  PERFORM us.carry_append_event_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
  RAISE EXCEPTION 'Original appender permission unexpectedly available';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_append_ordinary_event_v3(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
  RAISE EXCEPTION 'Narrow backend ordinary writer permission unexpectedly available';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $backend$;
ROLLBACK;
