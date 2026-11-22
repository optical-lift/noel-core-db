-- HELD local current-schema clone postcondition. Not a release receipt.
DO $atlas_pot_up_post$
BEGIN
  IF to_regprocedure('atlas.advance_pot_up_serial_queue_v1()') IS NOT NULL
     OR to_regprocedure('atlas.apply_pot_up_serial_release_effect_v1(uuid,date)') IS NOT NULL
     OR to_regprocedure('atlas.release_next_task_in_queue_v1(uuid,text,date)') IS NOT NULL
     OR to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='completed')<>5
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='skipped')<>4
  THEN RAISE EXCEPTION 'Original pot-up historical queue or canonical custody changed';
  END IF;
END $atlas_pot_up_post$;
