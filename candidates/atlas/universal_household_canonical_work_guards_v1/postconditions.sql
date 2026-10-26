DO $test$ BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE tgname='b_guard_original_household_work_v1'
     AND tgrelid='atlas.work_items'::regclass
 ) THEN RAISE EXCEPTION 'Household Work completion source guard missing'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE tgname='z_guard_household_work_actual_v1'
     AND tgrelid='atlas.work_execution_results'::regclass
 ) THEN RAISE EXCEPTION 'Household Actual acceptance guard missing'; END IF;
 IF has_function_privilege('authenticated',
   'atlas.require_household_governor_self_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'Private Household governor helper direct invocation'; END IF;
END $test$;
-- Signed Household governor, signed member, unlinked Person and anon must be
-- tested using real sessions, as must repeat results, linked Work and cross-scope.
