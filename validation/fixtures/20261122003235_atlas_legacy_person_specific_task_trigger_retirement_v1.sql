-- HELD disposable current-schema clone only. Trusted signed C1 Work identity
-- is installed separately through the ORIGINAL Noel protected validator before
-- this fixture. Do not insert live or invented legacy Tasks or copy old rows.
SELECT 1/(CASE WHEN
  to_regprocedure('atlas.assign_anna_maintenance_collection_task_v1()') IS NOT NULL
  AND to_regprocedure('atlas.enforce_no_sunday_task_due_date()') IS NOT NULL
  AND (SELECT count(*) FROM pg_trigger WHERE tgrelid='atlas.tasks'::regclass
    AND NOT tgisinternal AND tgname IN
       ('trg_assign_anna_maintenance_collection_task_v1',
        'trg_enforce_no_sunday_task_due_date'))=2
  AND EXISTS (SELECT 1 FROM atlas.organizations
    WHERE id='e5200000-0000-4000-8000-000000000801'::uuid)
  AND EXISTS (SELECT 1 FROM atlas.work_items)
  THEN 1 ELSE 0 END
) AS exact_two_original_task_trigger_positive_fixture;
