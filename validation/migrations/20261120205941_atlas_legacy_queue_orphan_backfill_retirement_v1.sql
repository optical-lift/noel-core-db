-- HELD read-only postconditions, disposable clone only.
-- Actual original-row hashes and signed negative clients are distinct release gates.
DO $atlas_legacy_queue_backfill_postconditions$
BEGIN
  IF to_regprocedure('atlas.backfill_active_task_release_gates_v1()') IS NOT NULL THEN
    RAISE EXCEPTION 'obsolete legacy backfill function still installed';
  END IF;
  IF to_regclass('atlas.task_release_queue_items') IS NULL THEN
    RAISE EXCEPTION 'old queue table unexpectedly missing';
  END IF;
  IF to_regclass('atlas.work_items') IS NULL THEN
    RAISE EXCEPTION 'canonical original Work unexpectedly missing';
  END IF;
END
$atlas_legacy_queue_backfill_postconditions$;
