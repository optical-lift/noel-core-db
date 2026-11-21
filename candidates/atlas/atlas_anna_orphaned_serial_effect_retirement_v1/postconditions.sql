-- HELD current-schema protected clone postconditions (not production DDL).
DO $atlas_anna_orphan_postconditions$
DECLARE
  v_ref_count integer;
BEGIN
  IF to_regprocedure('atlas.advance_anna_weeding_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.apply_anna_weeding_serial_release_effect_v1(uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'Old unmounted Anna completion branch remains; stop';
  END IF;
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('atlas.tasks') IS NULL THEN
    RAISE EXCEPTION 'Original source or canonical Work disappeared; stop';
  END IF;
  IF (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation')<>34
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))<>0 THEN
    RAISE EXCEPTION 'Synthetic historical queue records changed; stop';
  END IF;
  IF to_regprocedure('atlas.capture_anna_weeding_serial_queue_v1()') IS NULL
     OR to_regprocedure('atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.reconcile_anna_serial_weeding_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.reorder_anna_deadline_weeding_queue_v1(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Separate unadjudicated Anna branch changed; stop';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t WHERE t.tgrelid='atlas.tasks'::regclass
      AND t.tgname='trg_assign_anna_maintenance_collection_task_v1'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Unadjudicated Anna assignment trigger changed; stop';
  END IF;
  SELECT count(*) INTO v_ref_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('atlas','public') AND p.prokind IN('f','p')
      AND position('task_release_queue_items' IN lower(pg_get_functiondef(p.oid)))>0;
  IF v_ref_count NOT IN (25,27) THEN
    RAISE EXCEPTION 'Unexpected original queue reader census after bounded retirement; stop';
  END IF;
END $atlas_anna_orphan_postconditions$;
