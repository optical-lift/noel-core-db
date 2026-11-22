-- HELD SOURCE ONLY, NOT AN EXECUTABLE PRODUCTION MIGRATION.
-- Atlas P0 #532: potential orphan August-2026 pressure-wash serial Task release.
-- The 5 original queue records are all skipped; preserve them and every Work,
-- Task, Requirement, Actual and other queue record in original custody.
-- EXTERNAL SERVICE/ADMIN CALLER DISCONTINUATION IS NOT YET PROVEN.
-- No production DROP without independent signed clone, immutable versioned
-- generator, app/service source closure and a NEW exact owner release approval.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $atlas_pressure_wash_original_source_guard$
DECLARE
  r record;
  v_oid oid;
  v_external_mentions integer;
  v_expected_mentions integer;
BEGIN
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regclass('cron.job') IS NULL
  THEN
    RAISE EXCEPTION 'Expected original queue/current Work and scheduler custody unavailable';
  END IF;
  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
     OR (SELECT count(*) FROM atlas.task_release_queue_items
         WHERE queue_key='anna_gentle_pressure_wash_aug_2026')<>5
     OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items
         WHERE queue_key='anna_gentle_pressure_wash_aug_2026' AND state<>'skipped')
  THEN
    RAISE EXCEPTION 'Original pressure-wash queue states or historical counts drifted';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('advance_gentle_pressure_wash_serial_queue_v1'::text,
      'atlas.advance_gentle_pressure_wash_serial_queue_v1()'::text,
      'a1e91245470dc25a831f4cdd36f37ae6'::text,
      0::integer),
    ('release_next_pressure_wash_task_v1',
      'atlas.release_next_pressure_wash_task_v1(uuid,date)',
      'bb7c8e11e676fe309c7446bf6f80e354',1),
    ('release_pressure_wash_queue_item_v1',
      'atlas.release_pressure_wash_queue_item_v1(uuid,date)',
      '2d1387e95d290fefdf4b8104c8694cdd',1)
  ) AS original(name,signature,source_md5,known_db_callers) LOOP
    v_oid:=to_regprocedure(r.signature);
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM r.source_md5 THEN
      RAISE EXCEPTION 'Original guarded pressure-wash source changed: %',r.name;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
      AND p.proowner='postgres'::regrole AND p.prosecdef
      AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND has_function_privilege('service_role',p.oid,'EXECUTE')) THEN
      RAISE EXCEPTION 'Original pressure-wash owner or privileges changed: %',r.name;
    END IF;
    IF EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgfoid=v_oid AND NOT t.tgisinternal)
       OR EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid=v_oid AND d.deptype='n')
       OR EXISTS(SELECT 1 FROM cron.job c WHERE position(r.name in lower(c.command))>0)
    THEN
      RAISE EXCEPTION 'Pressure-wash source has new trigger, catalog or scheduled dependent: %',r.name;
    END IF;
    SELECT count(*) INTO v_external_mentions
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN('atlas','public') AND p.prokind IN('f','p')
      AND p.oid<>v_oid AND position(r.name IN lower(pg_get_functiondef(p.oid)))>0;
    IF v_external_mentions IS DISTINCT FROM r.known_db_callers THEN
      RAISE EXCEPTION 'Pressure-wash caller count drift: %',r.name;
    END IF;
    -- Each of the two helper routines is called only by its immediately
    -- preceding original branch member, not by other installed SQL sources.
    IF r.name='release_next_pressure_wash_task_v1' AND NOT EXISTS(
      SELECT 1 FROM pg_proc p
      WHERE p.oid=to_regprocedure('atlas.advance_gentle_pressure_wash_serial_queue_v1()')
      AND position(r.name IN lower(pg_get_functiondef(p.oid)))>0
    ) THEN
      RAISE EXCEPTION 'Original advance-to-next pressure-wash chain changed';
    END IF;
    IF r.name='release_pressure_wash_queue_item_v1' AND NOT EXISTS(
      SELECT 1 FROM pg_proc p
      WHERE p.oid=to_regprocedure('atlas.release_next_pressure_wash_task_v1(uuid,date)')
      AND position(r.name IN lower(pg_get_functiondef(p.oid)))>0
    ) THEN
      RAISE EXCEPTION 'Original next-to-release pressure-wash chain changed';
    END IF;
  END LOOP;
  PERFORM set_config('atlas.old_pressure_wash_queue_count',
    (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.old_pressure_wash_work_count',
    (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.old_pressure_wash_task_count',
    (SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.old_pressure_wash_requirement_count',
    (SELECT count(*)::text FROM atlas.work_requirements),true);
END $atlas_pressure_wash_original_source_guard$;

-- Retire this original THREE-function serial branch only. No CASCADE.
-- Do not drop shared queue-summary, its 12 other installed callers, original
-- queue/history, crop audit view, worker-day readers or governed Work.
DROP FUNCTION atlas.advance_gentle_pressure_wash_serial_queue_v1() RESTRICT;
DROP FUNCTION atlas.release_next_pressure_wash_task_v1(uuid,date) RESTRICT;
DROP FUNCTION atlas.release_pressure_wash_queue_item_v1(uuid,date) RESTRICT;

DO $atlas_pressure_wash_original_no_loss$
BEGIN
  IF to_regprocedure('atlas.advance_gentle_pressure_wash_serial_queue_v1()') IS NOT NULL
    OR to_regprocedure('atlas.release_next_pressure_wash_task_v1(uuid,date)') IS NOT NULL
    OR to_regprocedure('atlas.release_pressure_wash_queue_item_v1(uuid,date)') IS NOT NULL
    OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
    OR to_regclass('atlas.task_release_queue_items') IS NULL
    OR to_regclass('atlas.work_items') IS NULL THEN
    RAISE EXCEPTION 'Pressure-wash retirement structure, shared queue reader or canonical Work wrong';
  END IF;
  IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
      IS DISTINCT FROM current_setting('atlas.old_pressure_wash_queue_count')
    OR (SELECT count(*)::text FROM atlas.work_items)
      IS DISTINCT FROM current_setting('atlas.old_pressure_wash_work_count')
    OR (SELECT count(*)::text FROM atlas.tasks)
      IS DISTINCT FROM current_setting('atlas.old_pressure_wash_task_count')
    OR (SELECT count(*)::text FROM atlas.work_requirements)
      IS DISTINCT FROM current_setting('atlas.old_pressure_wash_requirement_count') THEN
    RAISE EXCEPTION 'Original queue/Work/Task/Requirement row counts changed';
  END IF;
END $atlas_pressure_wash_original_no_loss$;
COMMIT;
