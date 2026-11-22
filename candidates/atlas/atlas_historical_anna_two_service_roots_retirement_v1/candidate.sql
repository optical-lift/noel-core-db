-- HELD SOURCE ONLY — NOT an executable/authorized production migration.
-- Atlas P0 #532 SRC-RETIRE-01: original Anna weeding service-only queue roots.
-- Owner has NOT yet authorized cutoff of unknown independent service/admin callers.
-- No source admission, signed proof, migration generation or live release authorized.
-- Preserve all 97 original terminal queue records; 34 Anna weeding rotation
-- (7 completed / 27 skipped) and 4 field row weeding (2 completed / 2 skipped).
-- Never delete historical Tasks/occurrences, Work/Requirements/Actuals, or
-- remaining five protected physical-worker-day/disclosure/summary routines.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $anna_two_root_source_guard$
DECLARE
  r record;
  v_oid oid;
  v_mentions integer;
BEGIN
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.farms') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.planned_work_occurrences') IS NULL
     OR to_regclass('atlas.requirement_boundary_events') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('cron.job') IS NULL
  THEN RAISE EXCEPTION 'Expected current historical queue and canonical custody absent';
  END IF;

  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='completed')<>7
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='skipped')<>27
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='completed')<>2
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='skipped')<>2
  THEN RAISE EXCEPTION 'Original Anna/field-weeding historical queue evidence drifted';
  END IF;

  FOR r IN SELECT * FROM (VALUES
    ('capture_anna_weeding_serial_queue_v1'::text,
     'atlas.capture_anna_weeding_serial_queue_v1()'::text,
     '10edcd4405074cc0e82a772be6bbed16'::text),
    ('enqueue_new_field_row_weeding_task_v1',
     'atlas.enqueue_new_field_row_weeding_task_v1()',
     '69beed27375cfcd1e0653d8113090e49')
  ) AS expected(name,signature,source_md5) LOOP
    v_oid:=to_regprocedure(r.signature);
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM r.source_md5
    THEN RAISE EXCEPTION 'Original Anna service root source changed: %',r.name;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
        AND p.proowner='postgres'::regrole AND p.prosecdef
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
    ) THEN RAISE EXCEPTION 'Original Anna service root owner/ACL drift: %',r.name;
    END IF;
    IF EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgfoid=v_oid AND NOT t.tgisinternal)
       OR EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid=v_oid AND d.deptype='n')
       OR EXISTS(SELECT 1 FROM cron.job c WHERE c.active AND position(r.name IN lower(c.command))>0)
    THEN RAISE EXCEPTION 'Anna service root has trigger, catalog or cron dependent: %',r.name;
    END IF;
    SELECT count(*) INTO v_mentions
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN ('atlas','public') AND p.oid<>v_oid AND p.prokind IN ('f','p')
       AND position(r.name IN lower(pg_get_functiondef(p.oid)))>0;
    IF v_mentions<>0 THEN RAISE EXCEPTION 'Anna service root gained database caller: %',r.name; END IF;
  END LOOP;

  -- The other five serial-family routines are NOT part of this release.
  -- Keep their exact current definitions and their authorized consequences.
  FOR r IN SELECT * FROM (VALUES
    ('atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid)'::text,'876a3ea0a00956dbecf4092f350c0534'::text),
    ('atlas.reconcile_anna_serial_weeding_v1(uuid)','03588820cd1f3001c2236c329a5ff0ea'),
    ('atlas.reorder_anna_deadline_weeding_queue_v1(uuid)','868e37c7bbbf318bf8045c9af94abbda'),
    ('atlas.sync_task_release_queue_summary_v1(uuid,text)','ade073264f4ee0ea6055b943a590bd73'),
    ('atlas.weeding_cycle_v1(uuid)','382e9e491911cf7ed71b0698a91f297a')
  ) AS current_source(signature,source_md5) LOOP
    v_oid:=to_regprocedure(r.signature);
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM r.source_md5
    THEN RAISE EXCEPTION 'Protected current physical/disclosure/summary source drift: %',r.signature;
    END IF;
  END LOOP;

  PERFORM set_config('atlas.anna_two_queue_count',(SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.anna_two_queue_hash',
      (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
       FROM atlas.task_release_queue_items q),true);
  PERFORM set_config('atlas.anna_two_work_count',(SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.anna_two_task_count',(SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.anna_two_req_count',(SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.anna_two_occ_count',(SELECT count(*)::text FROM atlas.planned_work_occurrences),true);
  PERFORM set_config('atlas.anna_two_boundary_count',(SELECT count(*)::text FROM atlas.requirement_boundary_events),true);
END $anna_two_root_source_guard$;

-- ONLY if independently owner-approved AFTER genuine current-source signed
-- disposable full-Atlas no-loss clone proof and new exact production approval.
-- Never CASCADE. Historical queue/canonical records are not touched.
DROP FUNCTION atlas.capture_anna_weeding_serial_queue_v1() RESTRICT;
DROP FUNCTION atlas.enqueue_new_field_row_weeding_task_v1() RESTRICT;

DO $anna_two_root_no_loss$
BEGIN
  IF to_regprocedure('atlas.capture_anna_weeding_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.enqueue_new_field_row_weeding_task_v1()') IS NOT NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regprocedure('atlas.weeding_cycle_v1(uuid)') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR (SELECT count(*)::text FROM atlas.task_release_queue_items)
          IS DISTINCT FROM current_setting('atlas.anna_two_queue_count')
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
         FROM atlas.task_release_queue_items q)
          IS DISTINCT FROM current_setting('atlas.anna_two_queue_hash')
     OR (SELECT count(*)::text FROM atlas.work_items)
          IS DISTINCT FROM current_setting('atlas.anna_two_work_count')
     OR (SELECT count(*)::text FROM atlas.tasks)
          IS DISTINCT FROM current_setting('atlas.anna_two_task_count')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
          IS DISTINCT FROM current_setting('atlas.anna_two_req_count')
     OR (SELECT count(*)::text FROM atlas.planned_work_occurrences)
          IS DISTINCT FROM current_setting('atlas.anna_two_occ_count')
     OR (SELECT count(*)::text FROM atlas.requirement_boundary_events)
          IS DISTINCT FROM current_setting('atlas.anna_two_boundary_count')
  THEN RAISE EXCEPTION 'Anna service-root retirement or historical/canonical no-loss failed';
  END IF;
END $anna_two_root_no_loss$;
COMMIT;
