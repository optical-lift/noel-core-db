-- Protected-clone gate: source-gated no-duplicate legacy rhythm task cutover.
-- Execute AFTER release_candidate.sql. No actual historical tasks modified.
DO $post$
BEGIN
  IF to_regprocedure('atlas.continuing_rhythm_original_work_has_custody_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.ensure_rhythm_task_v1(uuid,text,timestamp with time zone)') IS NULL
    OR to_regprocedure('atlas.guard_continuing_original_rhythm_old_carrier_v1()') IS NULL
  THEN
    RAISE EXCEPTION 'Legacy-clock-to-canonical-original membrane is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.tasks'::regclass
      AND t.tgname='z_guard_continuing_original_rhythm_old_task_v1'
      AND t.tgenabled IN ('O','A')
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.planned_work_occurrences'::regclass
      AND t.tgname='z_guard_continuing_original_rhythm_old_occurrence_v1'
      AND t.tgenabled IN ('O','A')
  ) THEN
    RAISE EXCEPTION 'Direct old task/occurrence path still unprotected';
  END IF;
  IF has_function_privilege('anon',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
    OR has_function_privilege('authenticated',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
    OR has_function_privilege('service_role',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Internal cutover classifier must not become a discoverable reader';
  END IF;
  IF to_regprocedure('atlas.farm_rhythm_tick_v1(uuid,timestamp with time zone,integer)') IS NULL
  THEN
    RAISE EXCEPTION 'Original unadopted farm rhythm clock changed unexpectedly';
  END IF;
  RAISE NOTICE 'Source guard presence confirmed; actual same-Need synthetic positive+negative test still required';
END;
$post$;

-- Protected-clone fixture must establish synthetic owned/assigned original
-- Work for one exact rhythm in a rollback transaction. Then test:
-- 1. existing older task rows and Work history remain unmodified.
-- 2. ensure_rhythm_task_v1 => canonical_original_work_has_custody.
-- 3. insert a new old task with generated_from NULL, metadata.rhythm_state_id
--    set to the adopted source state, and planned_occurrence_id; must reject.
-- 4. insert a new planned_work_occurrences source_kind=rhythm_state
--    source_id=adopted state; must reject.
-- 5. for a non-adopted state, previous legacy task release is unaffected.
-- 6. scheduled tick does not loop on exceptions or issue alternate tasks.
-- Failure on any is a BLOCK on cutover deployment, not a green check.
