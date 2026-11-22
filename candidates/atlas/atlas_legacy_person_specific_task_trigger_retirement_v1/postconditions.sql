-- HELD postcondition in independent protected PostgreSQL clone, not a
-- production request. Full source-row no-loss is separately checked by
-- Noel's original per-table row-identity/content fingerprint validator.
DO $atlas_person_policy_postconditions$
BEGIN
  IF to_regprocedure('atlas.assign_anna_maintenance_collection_task_v1()') IS NOT NULL
     OR to_regprocedure('atlas.enforce_no_sunday_task_due_date()') IS NOT NULL THEN
    RAISE EXCEPTION 'Old Anna/Elm automatic Task policy function remains';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.tasks'::regclass
      AND tgname IN ('trg_assign_anna_maintenance_collection_task_v1',
                     'trg_enforce_no_sunday_task_due_date')) THEN
    RAISE EXCEPTION 'Old person/site-specific Task triggers remain';
  END IF;
  IF to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL THEN
    RAISE EXCEPTION 'Original Task evidence or native Work/Requirements/queue missing';
  END IF;
  IF to_regprocedure('atlas.accept_membership_invite_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.living_day_base_v1(uuid,date)') IS NULL
     OR to_regprocedure('atlas.refresh_elm_public_calendar_from_purpose_context_v1()') IS NULL
     OR to_regprocedure('atlas.refresh_elm_public_calendar_from_purpose_membership_v1()') IS NULL THEN
    RAISE EXCEPTION 'Unrelated original integration machinery was removed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM atlas.work_items) THEN
    RAISE EXCEPTION 'Original fictional C1 Work source disappeared';
  END IF;
END $atlas_person_policy_postconditions$;
