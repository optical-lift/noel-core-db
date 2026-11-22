-- HELD postconditions: disposable signed current-schema PG17 clone ONLY.
-- The original progression trigger was separately retired; not part of this SQL.
DO $orphan_cancel_queue_post$
BEGIN
 IF to_regprocedure('atlas.skip_cancelled_occurrence_release_queue_v1()') IS NOT NULL
    OR to_regprocedure('atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid)') IS NULL
    OR to_regprocedure('atlas.reconcile_anna_serial_weeding_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.reorder_anna_deadline_weeding_queue_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
    OR to_regprocedure('atlas.weeding_cycle_v1(uuid)') IS NULL
    OR to_regclass('atlas.task_release_queue_items') IS NULL
    OR to_regclass('atlas.work_items') IS NULL
    OR (SELECT count(*) FROM atlas.task_release_queue_items)<>97
    OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')<>15
    OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')<>82
    OR EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='flower_harvest_bucket_observations_queue_preparation_v1' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Orphan trigger retirement lost preserved source or history'; END IF;
END $orphan_cancel_queue_post$;
