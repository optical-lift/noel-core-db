-- Source-linked clone postconditions for historical queue progression retirement.
-- No production Task/Work state is modified or adjudicated by this source.
DO $atlas_old_queue_retirement_clone_postconditions$
BEGIN
  IF EXISTS(
    SELECT 1 FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname IN (
        'planned_occurrence_release_queue_cancel_skip_v1',
        'advance_anna_weeding_serial_queue_v1',
        'advance_gentle_pressure_wash_serial_queue_v1',
        'advance_owner_completion_gated_queue_v1',
        'advance_pot_up_serial_queue_v1',
        'zzzzzzzzzzzzzz_capture_anna_weeding_serial_queue_v1'
      )
  ) THEN
    RAISE EXCEPTION 'retired progression trigger still installed';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgrelid='atlas.flower_harvest_bucket_observations'::regclass
      AND tgname='flower_harvest_bucket_observations_queue_preparation_v1'
  ) THEN
    RAISE EXCEPTION 'live harvest-preparation consequence absent';
  END IF;
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL THEN
    RAISE EXCEPTION 'source evidence or canonical originals lost';
  END IF;
END $atlas_old_queue_retirement_clone_postconditions$;
