-- HELD local clone postconditions; independent signed/full-row proof still required.
DO $atlas_pressure_wash_post$
BEGIN
 IF to_regprocedure('atlas.advance_gentle_pressure_wash_serial_queue_v1()') IS NOT NULL
 OR to_regprocedure('atlas.release_next_pressure_wash_task_v1(uuid,date)') IS NOT NULL
 OR to_regprocedure('atlas.release_pressure_wash_queue_item_v1(uuid,date)') IS NOT NULL
 OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
 OR to_regclass('atlas.task_release_queue_items') IS NULL
 OR to_regclass('atlas.work_items') IS NULL
 OR to_regclass('atlas.work_requirements') IS NULL
 OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_gentle_pressure_wash_aug_2026' AND state='skipped')<>5
 THEN RAISE EXCEPTION 'Pressure-wash candidate original-source preservation failed';
 END IF;
END $atlas_pressure_wash_post$;
