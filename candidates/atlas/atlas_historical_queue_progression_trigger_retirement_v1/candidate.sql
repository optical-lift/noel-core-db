-- HELD Atlas Package B: remove six obsolete queue progression triggers ONLY.
-- Owner states 2026 historical queue obligations are complete/not current.
-- This intentionally preserves the separately governed physical harvest→preparation
-- consequence, all original source records, and canonical Work/Need history.
-- DO NOT claim full legacy-table retirement or spring 2027 policy completion.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $atlas_old_queue_trigger_guard$
DECLARE
  v_table text;
  v_trigger text;
  v_expected_hash text;
  v_actual_hash text;
BEGIN
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL THEN
    RAISE EXCEPTION 'canonical Work, Requirements, or source queue missing; stop';
  END IF;
  -- Transaction-scoped no-loss row census. Works in real and fictional clone DB.
  PERFORM set_config('atlas.legacy_queue_rows_before',
    (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.legacy_queue_taskless_before',
    (SELECT count(*)::text FROM atlas.task_release_queue_items WHERE task_id IS NULL),true);
  PERFORM set_config('atlas.canonical_work_rows_before',
    (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.canonical_requirement_rows_before',
    (SELECT count(*)::text FROM atlas.work_requirements),true);

  FOR v_table,v_trigger,v_expected_hash IN SELECT * FROM (VALUES
    ('atlas.tasks','advance_anna_weeding_serial_queue_v1','348116cfbcf6eb1673396b8146ef17a3'),
    ('atlas.tasks','advance_gentle_pressure_wash_serial_queue_v1','5e1be616bd7fbc71a84dcd4435147b7e'),
    ('atlas.tasks','advance_owner_completion_gated_queue_v1','f1ec5832c2582ad7f3c2fa18806f0cad'),
    ('atlas.tasks','advance_pot_up_serial_queue_v1','6950717abd48657b03b289ae5f46036c'),
    ('atlas.planned_work_occurrences','planned_occurrence_release_queue_cancel_skip_v1','eb8ef90bc69fa9f2c7fc4f6e297285fa'),
    ('atlas.tasks','zzzzzzzzzzzzzz_capture_anna_weeding_serial_queue_v1','2abc80b0f11c3db4e819e707511d07e0')
  ) AS expected(table_name,trigger_name,def_hash)
  LOOP
    SELECT md5(pg_get_triggerdef(t.oid,true))
      INTO v_actual_hash
    FROM pg_trigger t
    WHERE t.tgrelid=v_table::regclass
      AND t.tgname=v_trigger
      AND NOT t.tgisinternal;

    IF v_actual_hash IS DISTINCT FROM v_expected_hash THEN
      RAISE EXCEPTION 'named historical trigger changed or missing: % on %',v_trigger,v_table;
    END IF;
  END LOOP;
  -- Harvest preparation remains a separate live consequence; never sever here.
  IF (SELECT md5(pg_get_triggerdef(t.oid,true))
        FROM pg_trigger t
        WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
          AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1')
      IS DISTINCT FROM 'f5ef28f4f1c4c3232341ddf186e7b6e3' THEN
    RAISE EXCEPTION 'harvest preparation consequence changed; stop';
  END IF;
END
$atlas_old_queue_trigger_guard$;

DROP TRIGGER advance_anna_weeding_serial_queue_v1 ON atlas.tasks RESTRICT;
DROP TRIGGER advance_gentle_pressure_wash_serial_queue_v1 ON atlas.tasks RESTRICT;
DROP TRIGGER advance_owner_completion_gated_queue_v1 ON atlas.tasks RESTRICT;
DROP TRIGGER advance_pot_up_serial_queue_v1 ON atlas.tasks RESTRICT;
DROP TRIGGER planned_occurrence_release_queue_cancel_skip_v1 ON atlas.planned_work_occurrences RESTRICT;
DROP TRIGGER zzzzzzzzzzzzzz_capture_anna_weeding_serial_queue_v1 ON atlas.tasks RESTRICT;

DO $atlas_old_queue_trigger_postcheck$
BEGIN
  IF EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE NOT t.tgisinternal AND t.tgname IN (
      'advance_anna_weeding_serial_queue_v1','advance_gentle_pressure_wash_serial_queue_v1','advance_owner_completion_gated_queue_v1','advance_pot_up_serial_queue_v1','planned_occurrence_release_queue_cancel_skip_v1','zzzzzzzzzzzzzz_capture_anna_weeding_serial_queue_v1'
    )
  ) THEN
    RAISE EXCEPTION 'obsolete historical progression trigger still installed';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
      AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'harvest preparation consequence was lost';
  END IF;
  IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
       IS DISTINCT FROM current_setting('atlas.legacy_queue_rows_before',true)
    OR (SELECT count(*)::text FROM atlas.task_release_queue_items WHERE task_id IS NULL)
       IS DISTINCT FROM current_setting('atlas.legacy_queue_taskless_before',true)
    OR (SELECT count(*)::text FROM atlas.work_items)
       IS DISTINCT FROM current_setting('atlas.canonical_work_rows_before',true)
    OR (SELECT count(*)::text FROM atlas.work_requirements)
       IS DISTINCT FROM current_setting('atlas.canonical_requirement_rows_before',true) THEN
      RAISE EXCEPTION 'source queue, original Work or Requirement changed; stop';
  END IF;
END
$atlas_old_queue_trigger_postcheck$;
COMMIT;
