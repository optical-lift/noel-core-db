-- HELD postcondition: disposable PG17 current-schema signed clone ONLY.
DO $anna_two_root_post$
BEGIN
  IF to_regprocedure('atlas.capture_anna_weeding_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.enqueue_new_field_row_weeding_task_v1()') IS NOT NULL
     OR to_regprocedure('atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.reconcile_anna_serial_weeding_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.reorder_anna_deadline_weeding_queue_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regprocedure('atlas.weeding_cycle_v1(uuid)') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR (SELECT count(*) FROM atlas.task_release_queue_items)<>97
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='completed')<>7
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='skipped')<>27
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='completed')<>2
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='skipped')<>2
  THEN RAISE EXCEPTION 'Held Anna service-root source lost a preserved original or changed history';
  END IF;
END $anna_two_root_post$;
