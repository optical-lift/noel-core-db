-- HELD postconditions for protected disposable original current-schema clone.
-- No production use until own generated migration / full signed proof / owner approval.
DO $atlas_old_serial_branch_after$
BEGIN
 IF to_regprocedure('atlas.advance_owner_completion_gated_queue_v1()') IS NOT NULL
    OR to_regprocedure('atlas.apply_owner_completion_gated_release_effect_v1(uuid,date)') IS NOT NULL THEN
  RAISE EXCEPTION 'Obsolete owner-completion queue branch remains';
 END IF;
 IF to_regclass('atlas.task_release_queue_items') IS NULL OR to_regclass('atlas.work_items') IS NULL
   OR to_regclass('atlas.work_requirements') IS NULL THEN
  RAISE EXCEPTION 'Original historic source or canonical Work/Requirements table was removed';
 END IF;
 IF (SELECT count(*) FROM atlas.task_release_queue_items) <> 97
   OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN('active','queued'))<>0 THEN
  RAISE EXCEPTION 'Original retired queue history changed';
 END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN('atlas','public') AND p.prokind IN('f','p')
       AND pg_get_functiondef(p.oid) ILIKE '%task_release_queue_items%')<>27 THEN
  RAISE EXCEPTION 'Expected 27 remaining original queue-body consumers after two retired branch members';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
      AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
      AND NOT t.tgisinternal AND t.tgenabled='O') THEN
  RAISE EXCEPTION 'Real harvest consequence trigger removed';
 END IF;
END $atlas_old_serial_branch_after$;
