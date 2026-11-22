-- HELD SOURCE ONLY. Not an executable or authorized production migration.
-- Atlas P0 #532, SRC-RETIRE-01: old pot-up serial Task-release branch.
-- Nine historical pot-up queue rows: five completed, four skipped; preserve
-- all source relationships, original Work, Tasks, Requirements, Actuals,
-- boundary-event evidence, shared queue summary and non-pot-up history.
-- Independent service/admin caller cutoff remains UNAUTHORIZED/UNRESOLVED.
-- No production DROP without original-source protected signed clone proof,
-- owner-reviewed canonical version generation and NEW exact release approval.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $atlas_pot_up_original_source_guard$
DECLARE
  r record;
  v_oid oid;
  v_mentions integer;
BEGIN
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.planned_work_occurrences') IS NULL
     OR to_regclass('atlas.requirement_boundary_events') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regclass('cron.job') IS NULL
  THEN RAISE EXCEPTION 'Expected historical pot-up and canonical custody absent';
  END IF;
  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial')<>9
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='completed')<>5
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='skipped')<>4
  THEN RAISE EXCEPTION 'Historical pot-up queue inventory changed; review required';
  END IF;

  FOR r IN SELECT * FROM (VALUES
   ('advance_pot_up_serial_queue_v1'::text,
    'atlas.advance_pot_up_serial_queue_v1()'::text,
    'b9e2f2f8c3fb494d5cea9325b182eefc'::text,0::integer,true),
   ('apply_pot_up_serial_release_effect_v1',
    'atlas.apply_pot_up_serial_release_effect_v1(uuid,date)',
    'd2367f8500b8131d78679c20046e5cf3',1,false),
   ('release_next_task_in_queue_v1',
    'atlas.release_next_task_in_queue_v1(uuid,text,date)',
    'f0457263c5e559bfe47feaf477111412',1,false)
  ) AS expected(name,signature,source_md5,known_db_callers,service_grant) LOOP
    v_oid:=to_regprocedure(r.signature);
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM r.source_md5
    THEN RAISE EXCEPTION 'Original pot-up function changed: %',r.name;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
        AND p.proowner='postgres'::regrole AND p.prosecdef
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')=r.service_grant
    ) THEN RAISE EXCEPTION 'Original function ACL/owner changed: %',r.name;
    END IF;
    IF EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgfoid=v_oid AND NOT t.tgisinternal)
       OR EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid=v_oid AND d.deptype='n')
       OR EXISTS(SELECT 1 FROM cron.job c WHERE position(r.name IN lower(c.command))>0)
    THEN RAISE EXCEPTION 'Function gained trigger/catalog/cron dependent: %',r.name;
    END IF;
    SELECT count(*) INTO v_mentions
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN('atlas','public') AND p.oid<>v_oid
       AND p.prokind IN('f','p')
       AND position(r.name IN lower(pg_get_functiondef(p.oid)))>0;
    IF v_mentions IS DISTINCT FROM r.known_db_callers
    THEN RAISE EXCEPTION 'Pot-up DB caller topology drift: %',r.name;
    END IF;
  END LOOP;

  IF NOT EXISTS(
       SELECT 1 FROM pg_proc p
       WHERE p.oid=to_regprocedure('atlas.advance_pot_up_serial_queue_v1()')
         AND position('apply_pot_up_serial_release_effect_v1' IN lower(pg_get_functiondef(p.oid)))>0)
     OR NOT EXISTS(
       SELECT 1 FROM pg_proc p
       WHERE p.oid=to_regprocedure('atlas.apply_pot_up_serial_release_effect_v1(uuid,date)')
         AND position('release_next_task_in_queue_v1' IN lower(pg_get_functiondef(p.oid)))>0)
  THEN RAISE EXCEPTION 'Expected original pot-up serial chain changed';
  END IF;

  PERFORM set_config('atlas.pot_up_queue_total_before',
      (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.pot_up_queue_fingerprint_before',
      (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
       FROM atlas.task_release_queue_items q),true);
  PERFORM set_config('atlas.pot_up_work_before',
      (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.pot_up_task_before',
      (SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.pot_up_requirements_before',
      (SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.pot_up_occurrences_before',
      (SELECT count(*)::text FROM atlas.planned_work_occurrences),true);
  PERFORM set_config('atlas.pot_up_boundaries_before',
      (SELECT count(*)::text FROM atlas.requirement_boundary_events),true);
END $atlas_pot_up_original_source_guard$;

-- Retire only the three original, dependency-closed OLD Task-release routines.
-- Never DROP CASCADE. No queue tables, audit history or canonical Work touched.
DROP FUNCTION atlas.advance_pot_up_serial_queue_v1() RESTRICT;
DROP FUNCTION atlas.apply_pot_up_serial_release_effect_v1(uuid,date) RESTRICT;
DROP FUNCTION atlas.release_next_task_in_queue_v1(uuid,text,date) RESTRICT;

DO $atlas_pot_up_original_no_loss$
BEGIN
  IF to_regprocedure('atlas.advance_pot_up_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.apply_pot_up_serial_release_effect_v1(uuid,date)') IS NOT NULL
     OR to_regprocedure('atlas.release_next_task_in_queue_v1(uuid,text,date)') IS NOT NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
  THEN RAISE EXCEPTION 'Pot-up retirement or shared custody postcondition failed';
  END IF;
  IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
       IS DISTINCT FROM current_setting('atlas.pot_up_queue_total_before')
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
         FROM atlas.task_release_queue_items q)
       IS DISTINCT FROM current_setting('atlas.pot_up_queue_fingerprint_before')
     OR (SELECT count(*)::text FROM atlas.work_items)
       IS DISTINCT FROM current_setting('atlas.pot_up_work_before')
     OR (SELECT count(*)::text FROM atlas.tasks)
       IS DISTINCT FROM current_setting('atlas.pot_up_task_before')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
       IS DISTINCT FROM current_setting('atlas.pot_up_requirements_before')
     OR (SELECT count(*)::text FROM atlas.planned_work_occurrences)
       IS DISTINCT FROM current_setting('atlas.pot_up_occurrences_before')
     OR (SELECT count(*)::text FROM atlas.requirement_boundary_events)
       IS DISTINCT FROM current_setting('atlas.pot_up_boundaries_before')
  THEN RAISE EXCEPTION 'Original historical queue / canonical records changed';
  END IF;
END $atlas_pot_up_original_no_loss$;
COMMIT;
