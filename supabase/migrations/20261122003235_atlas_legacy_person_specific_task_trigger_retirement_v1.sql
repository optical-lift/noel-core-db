-- HELD SOURCE CANDIDATE ONLY: physically retire two superseded
-- person/site-specific automatic policies attached to LEGACY atlas.tasks.
-- This is not a canonical Work/Person/Need authorization change and does
-- not delete or rewrite ANY historical Task, queue, Work or evidence row.
-- Owner's direction: no hardcoded Anna/Lex/Elm policy in universal Atlas.
-- Test in protected current-schema signed PostgreSQL clone; require
-- canonical generated version and separate exact owner production approval.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $atlas_legacy_person_task_before$
DECLARE
  v_rec record;
  v_tg_oid oid;
  v_source_mentions integer;
BEGIN
  IF to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'Legacy Task, original Work/Requirements/queue or scheduler missing; stop';
  END IF;

  -- No currently open/blocked old Task qualifies for the exact implicit
  -- Anna maintenance assignment rule. Historical Anna-tagged Tasks are not
  -- presumed native Work; the original rows are preserved.
  IF EXISTS (
    SELECT 1 FROM atlas.tasks t
    WHERE t.status IN ('open','blocked')
      AND lower(coalesce(t.metadata->>'owner_task','false')) NOT IN ('true','yes','1')
      AND lower(coalesce(t.metadata->>'mowing_owner_handoff','false')) NOT IN ('true','yes','1')
      AND lower(coalesce(t.metadata->>'owner_problem_handoff_open','false')) NOT IN ('true','yes','1')
      AND (
        (t.metadata->>'work_collection_key'='weeding'
         AND lower(coalesce(t.metadata->>'canonical_maintenance_delivery','false')) IN ('true','yes','1'))
        OR
        (t.metadata->>'work_collection_key'='mowing'
         AND lower(coalesce(t.metadata->>'canonical_collection_task','false')) IN ('true','yes','1'))
      )
  ) THEN
    RAISE EXCEPTION 'Unresolved open maintenance Task still qualifies for implicit Anna assignment; stop';
  END IF;

  FOR v_rec IN SELECT * FROM (VALUES
    ('assign_anna_maintenance_collection_task_v1'::text,
     to_regprocedure('atlas.assign_anna_maintenance_collection_task_v1()')::oid,
     '7ddeea2f1c26535f6d0122aeac6fb603'::text,
     'trg_assign_anna_maintenance_collection_task_v1'::text,
     '5be7ad3385ea4b0c6b5ccd4e6f3af00c'::text),
    ('enforce_no_sunday_task_due_date'::text,
     to_regprocedure('atlas.enforce_no_sunday_task_due_date()')::oid,
     '8cb6d7f377ac8c7d9e444f50f86b299b'::text,
     'trg_enforce_no_sunday_task_due_date'::text,
     '63f44cca6ce872b461b9fa9ab9121ead'::text)
  ) AS expected(function_name,function_oid,source_md5,trigger_name,trigger_md5)
  LOOP
    IF v_rec.function_oid IS NULL
       OR md5(pg_get_functiondef(v_rec.function_oid)) IS DISTINCT FROM v_rec.source_md5 THEN
      RAISE EXCEPTION 'Exact historical Task trigger-function source drifted; stop';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=v_rec.function_oid
        AND p.proowner='postgres'::regrole AND p.prosecdef
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'Trigger-function owner/privileges drifted; stop';
    END IF;
    SELECT t.oid INTO v_tg_oid
    FROM pg_trigger t
    WHERE t.tgrelid='atlas.tasks'::regclass
      AND t.tgname=v_rec.trigger_name
      AND t.tgfoid=v_rec.function_oid
      AND NOT t.tgisinternal AND t.tgenabled='O';
    IF v_tg_oid IS NULL
       OR md5(pg_get_triggerdef(v_tg_oid)) IS DISTINCT FROM v_rec.trigger_md5 THEN
      RAISE EXCEPTION 'Exact enabled historical Task trigger binding drifted; stop';
    END IF;
    IF (SELECT count(*) FROM pg_trigger t
        WHERE t.tgfoid=v_rec.function_oid AND NOT t.tgisinternal)<>1
       OR (SELECT count(*) FROM pg_depend d
        WHERE d.refobjid=v_rec.function_oid AND d.deptype='n')<>1
       OR NOT EXISTS (SELECT 1 FROM pg_depend d
        WHERE d.refobjid=v_rec.function_oid AND d.deptype='n'
          AND d.classid='pg_trigger'::regclass AND d.objid=v_tg_oid) THEN
      RAISE EXCEPTION 'Unexpected catalog dependent on historical Task trigger-function; stop';
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job j
      WHERE position(v_rec.function_name IN lower(j.command))>0) THEN
      RAISE EXCEPTION 'Scheduled job references historical Task trigger-function; stop';
    END IF;
    SELECT count(*) INTO v_source_mentions
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_rec.function_oid AND p.prokind IN ('f','p')
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND position(v_rec.function_name IN lower(pg_get_functiondef(p.oid)))>0;
    IF v_source_mentions<>0 THEN
      RAISE EXCEPTION 'Another installed function calls historical Task trigger-function; stop';
    END IF;
  END LOOP;

  PERFORM set_config('atlas.old_task_rows_before',
    (SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.old_task_anna_tag_before',
    (SELECT count(*)::text FROM atlas.tasks WHERE metadata->>'anna_task'='true'),true);
  PERFORM set_config('atlas.old_task_sunday_history_before',
    (SELECT count(*)::text FROM atlas.tasks WHERE metadata->>'sunday_guardrail_applied'='true'),true);
  PERFORM set_config('atlas.old_task_trigger_count_before',
    (SELECT count(*)::text FROM pg_trigger WHERE tgrelid='atlas.tasks'::regclass AND NOT tgisinternal),true);
  PERFORM set_config('atlas.old_task_work_before',
    (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.old_task_requirements_before',
    (SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.old_task_queue_before',
    (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
END $atlas_legacy_person_task_before$;

-- These are the only DDL actions. Do NOT CASCADE.
DROP TRIGGER trg_assign_anna_maintenance_collection_task_v1 ON atlas.tasks RESTRICT;
DROP TRIGGER trg_enforce_no_sunday_task_due_date ON atlas.tasks RESTRICT;
DROP FUNCTION atlas.assign_anna_maintenance_collection_task_v1() RESTRICT;
DROP FUNCTION atlas.enforce_no_sunday_task_due_date() RESTRICT;

DO $atlas_legacy_person_task_after$
BEGIN
  IF to_regprocedure('atlas.assign_anna_maintenance_collection_task_v1()') IS NOT NULL
     OR to_regprocedure('atlas.enforce_no_sunday_task_due_date()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.tasks'::regclass
        AND tgname IN ('trg_assign_anna_maintenance_collection_task_v1',
                       'trg_enforce_no_sunday_task_due_date')
     ) THEN
    RAISE EXCEPTION 'Exact historical Task hardcoded policy survived; stop';
  END IF;
  IF (SELECT count(*)::text FROM atlas.tasks)
      IS DISTINCT FROM current_setting('atlas.old_task_rows_before')
     OR (SELECT count(*)::text FROM atlas.tasks WHERE metadata->>'anna_task'='true')
      IS DISTINCT FROM current_setting('atlas.old_task_anna_tag_before')
     OR (SELECT count(*)::text FROM atlas.tasks WHERE metadata->>'sunday_guardrail_applied'='true')
      IS DISTINCT FROM current_setting('atlas.old_task_sunday_history_before')
     OR (SELECT count(*)::text FROM atlas.work_items)
      IS DISTINCT FROM current_setting('atlas.old_task_work_before')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
      IS DISTINCT FROM current_setting('atlas.old_task_requirements_before')
     OR (SELECT count(*)::text FROM atlas.task_release_queue_items)
      IS DISTINCT FROM current_setting('atlas.old_task_queue_before') THEN
    RAISE EXCEPTION 'Original Task/history or canonical Work/Requirements/queue changed; stop';
  END IF;
  IF (SELECT count(*) FROM pg_trigger
       WHERE tgrelid='atlas.tasks'::regclass AND NOT tgisinternal)
     <>current_setting('atlas.old_task_trigger_count_before')::integer-2 THEN
    RAISE EXCEPTION 'Unrelated atlas.tasks trigger changed; stop';
  END IF;
  IF to_regprocedure('atlas.accept_membership_invite_v1(uuid)') IS NULL
     OR to_regprocedure('atlas.living_day_base_v1(uuid,date)') IS NULL
     OR to_regprocedure('atlas.refresh_elm_public_calendar_from_purpose_context_v1()') IS NULL
     OR to_regprocedure('atlas.refresh_elm_public_calendar_from_purpose_membership_v1()') IS NULL THEN
    RAISE EXCEPTION 'Unrelated still-unadjudicated source was touched; stop';
  END IF;
END $atlas_legacy_person_task_after$;
COMMIT;
