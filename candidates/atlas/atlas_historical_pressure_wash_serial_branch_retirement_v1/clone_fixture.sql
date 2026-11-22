-- HELD TEST INPUT only. Never copy live people, Work or queue rows.
-- The production-shaped isolated clone must provide original schema objects.
SELECT 1/(CASE WHEN
 to_regclass('atlas.task_release_queue_items') IS NOT NULL
 AND (SELECT count(*) FROM atlas.task_release_queue_items)=97
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))=0
 AND (SELECT count(*) FROM atlas.task_release_queue_items
     WHERE queue_key='anna_gentle_pressure_wash_aug_2026' AND state='skipped')=5
 AND to_regprocedure('atlas.advance_gentle_pressure_wash_serial_queue_v1()') IS NOT NULL
 AND to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NOT NULL
 THEN 1 ELSE 0 END) AS original_legacy_pressure_wash_read_only_precondition;
