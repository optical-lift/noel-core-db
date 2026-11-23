-- HELD SOURCE / REVIEW ONLY — NOT approved for validation admission or production execution.
-- Atlas P0 #532: orphaned historical cancelled-occurrence queue trigger FUNCTION only.
-- Its six-trigger historical progression package was released as 20261121154334;
-- the former planned-occurrence trigger is absent. Preserve that custody and all
-- original terminal queue evidence, Work, Task, occurrences and other functions.
-- Do not turn approval of source review into permission for a live DROP.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $orphan_cancel_queue_source_guard$
DECLARE
  v_oid oid;
  r record;
BEGIN
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.planned_work_occurrences') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('cron.job') IS NULL
  THEN RAISE EXCEPTION 'Original source queue / canonical source custody missing'; END IF;

  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')<>15
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')<>82
     OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('queued','active'))
  THEN RAISE EXCEPTION 'Original historical queue state changed'; END IF;

  v_oid:=to_regprocedure('atlas.skip_cancelled_occurrence_release_queue_v1()');
  IF v_oid IS NULL
     OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM 'be031c4bda0d3b0b31e38204ce03bb41'
  THEN RAISE EXCEPTION 'Orphan cancelled-occurrence trigger function absent or source changed'; END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=v_oid AND p.proowner='postgres'::regrole AND p.prosecdef
        AND p.prorettype='pg_catalog.trigger'::regtype
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'Trigger function identity/owner/ACL changed'; END IF;

  IF EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgfoid=v_oid AND NOT t.tgisinternal)
     OR EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid=v_oid AND d.deptype='n')
     OR EXISTS(SELECT 1 FROM cron.job c WHERE c.active AND position('skip_cancelled_occurrence_release_queue_v1' IN lower(c.command))>0)
     OR EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname IN('atlas','public') AND p.oid<>v_oid AND p.prokind IN('f','p')
         AND position('skip_cancelled_occurrence_release_queue_v1' IN lower(pg_get_functiondef(p.oid)))>0
     )
  THEN RAISE EXCEPTION 'Previously orphaned cancelled queue trigger gained a live dependency'; END IF;

  IF EXISTS (
     SELECT 1 FROM pg_trigger t
     WHERE t.tgname='planned_occurrence_release_queue_cancel_skip_v1'
       AND t.tgrelid='atlas.planned_work_occurrences'::regclass AND NOT t.tgisinternal
  ) THEN RAISE EXCEPTION 'Old progression trigger reappeared; release already settled'; END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger t
      WHERE t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
        AND t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
        AND NOT t.tgisinternal
  ) THEN RAISE EXCEPTION 'Protected distinct harvest-preparation trigger missing'; END IF;

  -- All other still-live serial-family functions remain exact and in scope for
  -- their own later source/caller/disclosure cutover, not this one-function DROP.
  FOR r IN SELECT * FROM (VALUES
   ('atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid)'::text,'876a3ea0a00956dbecf4092f350c0534'::text),
   ('atlas.reconcile_anna_serial_weeding_v1(uuid)','03588820cd1f3001c2236c329a5ff0ea'),
   ('atlas.reorder_anna_deadline_weeding_queue_v1(uuid)','868e37c7bbbf318bf8045c9af94abbda'),
   ('atlas.sync_task_release_queue_summary_v1(uuid,text)','ade073264f4ee0ea6055b943a590bd73'),
   ('atlas.weeding_cycle_v1(uuid)','382e9e491911cf7ed71b0698a91f297a')
  ) AS required(signature,source_md5)
  LOOP
    IF to_regprocedure(r.signature) IS NULL
       OR md5(pg_get_functiondef(to_regprocedure(r.signature))) IS DISTINCT FROM r.source_md5
    THEN RAISE EXCEPTION 'Protected remaining serial-family source drift: %',r.signature; END IF;
  END LOOP;

  PERFORM set_config('atlas.cancelled_queue_row_hash',
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
       FROM atlas.task_release_queue_items q),true);
  PERFORM set_config('atlas.cancelled_queue_count',(SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.cancelled_queue_work',(SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.cancelled_queue_tasks',(SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.cancelled_queue_requirements',(SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.cancelled_queue_occurrences',(SELECT count(*)::text FROM atlas.planned_work_occurrences),true);
END $orphan_cancel_queue_source_guard$;

-- ONE source-closed legacy trigger function, not the historical queue or any
-- active physical-planting/worker-day/disclosure function; never CASCADE.
-- Execute only after independently governed signed full-schema proof,
-- canonical number generation, and fresh exact production owner approval.
DROP FUNCTION atlas.skip_cancelled_occurrence_release_queue_v1() RESTRICT;

DO $orphan_cancel_queue_no_loss$
BEGIN
  IF to_regprocedure('atlas.skip_cancelled_occurrence_release_queue_v1()') IS NOT NULL
     OR (SELECT count(*)::text FROM atlas.task_release_queue_items)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_count')
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
          FROM atlas.task_release_queue_items q)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_row_hash')
     OR (SELECT count(*)::text FROM atlas.work_items)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_work')
     OR (SELECT count(*)::text FROM atlas.tasks)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_tasks')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_requirements')
     OR (SELECT count(*)::text FROM atlas.planned_work_occurrences)
          IS DISTINCT FROM current_setting('atlas.cancelled_queue_occurrences')
     OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgname='flower_harvest_bucket_observations_queue_preparation_v1' AND NOT t.tgisinternal)
  THEN RAISE EXCEPTION 'Orphan trigger-function retirement changed canonical/historical custody'; END IF;
END $orphan_cancel_queue_no_loss$;
COMMIT;
