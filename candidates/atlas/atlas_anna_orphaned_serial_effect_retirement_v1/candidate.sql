-- HELD SOURCE-ONLY retirement of the unmounted Anna-specific serial
-- completion trigger function and its exclusively owned release-effect leaf.
-- Neither function has an attached trigger, scheduler caller, or normal-user
-- EXECUTE permission in the adjudicated production source. One calls the other.
-- This does NOT delete legacy history, Work, Tasks, queue storage, or a real
-- farm-domain function still in use. No production run is authorized here.
-- Exact current-schema signed clone, canonical generator, separate version-
-- specific owner approval and Noel protected release remain mandatory.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $atlas_anna_orphan_branch_before$
DECLARE
  v_root oid := to_regprocedure('atlas.advance_anna_weeding_serial_queue_v1()');
  v_effect oid := to_regprocedure('atlas.apply_anna_weeding_serial_release_effect_v1(uuid,date)');
  v_rec record;
  v_root_mentions integer;
  v_effect_mentions integer;
BEGIN
  IF v_root IS NULL OR v_effect IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'Exact orphan source, original/canonical tables or scheduler catalog absent; stop';
  END IF;
  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')<>82
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')<>15
     OR EXISTS (SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation')<>34 THEN
    RAISE EXCEPTION 'Original owner-adjudicated historical queue or Anna subset drifted; stop';
  END IF;
  FOR v_rec IN SELECT * FROM (VALUES
    (v_root,'3e19f0db48bb781ee09c28b120e39bf9'::text),
    (v_effect,'c6b7a5ef66b56461c1195935cd69089d'::text)
  ) AS fixed(function_oid,expected_source_md5)
  LOOP
    IF md5(pg_get_functiondef(v_rec.function_oid))
       IS DISTINCT FROM v_rec.expected_source_md5 THEN
      RAISE EXCEPTION 'Exact orphan function source drifted; stop';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p
       WHERE p.oid=v_rec.function_oid AND p.proowner='postgres'::regrole
         AND p.prosecdef AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
         AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
         AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')) THEN
      RAISE EXCEPTION 'Original orphan owner, source/privilege custody differs; stop';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t
        WHERE t.tgfoid=v_rec.function_oid AND NOT t.tgisinternal)
       OR EXISTS (SELECT 1 FROM pg_depend d
        WHERE d.refobjid=v_rec.function_oid AND d.deptype='n')
       OR EXISTS (SELECT 1 FROM cron.job j
        WHERE position((SELECT proname FROM pg_proc WHERE oid=v_rec.function_oid)
          IN lower(j.command))>0) THEN
      RAISE EXCEPTION 'Found a live trigger, catalog or scheduled caller; stop';
    END IF;
  END LOOP;
  SELECT count(*) INTO v_root_mentions
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_root AND p.prokind IN ('f','p')
      AND n.nspname NOT IN('information_schema','pg_catalog')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND position('advance_anna_weeding_serial_queue_v1'
        IN lower(pg_get_functiondef(p.oid)))>0;
  SELECT count(*) INTO v_effect_mentions
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_effect AND p.prokind IN ('f','p')
      AND n.nspname NOT IN('information_schema','pg_catalog')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND position('apply_anna_weeding_serial_release_effect_v1'
        IN lower(pg_get_functiondef(p.oid)))>0;
  IF v_root_mentions<>0 OR v_effect_mentions<>1
     OR position('apply_anna_weeding_serial_release_effect_v1'
        IN lower(pg_get_functiondef(v_root)))=0 THEN
    RAISE EXCEPTION 'Original root/effect caller frontier changed; stop';
  END IF;

  PERFORM set_config('atlas.anna_orphan_queue_before',
    (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.anna_orphan_legacy_tasks_before',
    (SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.anna_orphan_work_before',
    (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.anna_orphan_requirements_before',
    (SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.anna_orphan_queuementions_before',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname IN ('atlas','public') AND p.prokind IN ('f','p')
      AND position('task_release_queue_items' IN lower(pg_get_functiondef(p.oid)))>0),true);
  PERFORM set_config('atlas.anna_orphan_trigger_before',
    (SELECT count(*)::text FROM pg_trigger t
      JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas' AND NOT t.tgisinternal),true);
END $atlas_anna_orphan_branch_before$;

DROP FUNCTION atlas.advance_anna_weeding_serial_queue_v1() RESTRICT;
DROP FUNCTION atlas.apply_anna_weeding_serial_release_effect_v1(uuid,date) RESTRICT;

DO $atlas_anna_orphan_branch_after$
BEGIN
  IF to_regprocedure('atlas.advance_anna_weeding_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.apply_anna_weeding_serial_release_effect_v1(uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Original orphan functions still exist; stop';
  END IF;
  IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
       IS DISTINCT FROM current_setting('atlas.anna_orphan_queue_before')
     OR (SELECT count(*)::text FROM atlas.tasks)
       IS DISTINCT FROM current_setting('atlas.anna_orphan_legacy_tasks_before')
     OR (SELECT count(*)::text FROM atlas.work_items)
       IS DISTINCT FROM current_setting('atlas.anna_orphan_work_before')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
       IS DISTINCT FROM current_setting('atlas.anna_orphan_requirements_before') THEN
    RAISE EXCEPTION 'Original records or canonical Work changed; stop';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname IN ('atlas','public') AND p.prokind IN ('f','p')
      AND position('task_release_queue_items' IN lower(pg_get_functiondef(p.oid)))>0)
     <>current_setting('atlas.anna_orphan_queuementions_before')::integer-2 THEN
    RAISE EXCEPTION 'Queue source-reference reduction was not exact; stop';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas' AND NOT t.tgisinternal)
    <>current_setting('atlas.anna_orphan_trigger_before')::integer THEN
    RAISE EXCEPTION 'An unrelated trigger changed; stop';
  END IF;
  IF to_regprocedure('atlas.capture_anna_weeding_serial_queue_v1()') IS NULL
     OR to_regprocedure('atlas.reconcile_anna_serial_weeding_v1(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Separate still-adjudicating Anna source was removed; stop';
  END IF;
END $atlas_anna_orphan_branch_after$;
COMMIT;
