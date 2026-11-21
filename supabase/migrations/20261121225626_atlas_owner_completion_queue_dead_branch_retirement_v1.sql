-- HELD SOURCE CANDIDATE ONLY: remove one orphaned legacy owner-completion
-- queue branch after its original progression trigger was separately released.
-- This is NOT a migration, does not retire the queue table, and must not run in
-- production without original protected signed/full-Atlas no-loss clone,
-- canonical version generation, and exact owner release authorization.
-- Source: Atlas UNI-OPS-01 #532, verified original queue status cleanup
-- 20261121204646, five-consumer cutover 20261121211411,
-- and original six-trigger retirement 20261121154334.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $atlas_owner_old_serial_branch_guard$
DECLARE
  v_root oid := to_regprocedure('atlas.advance_owner_completion_gated_queue_v1()');
  v_effect oid := to_regprocedure('atlas.apply_owner_completion_gated_release_effect_v1(uuid,date)');
  v_rec record;
  v_mention_count integer;
BEGIN
  IF v_root IS NULL OR v_effect IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'Exact source routines, historic queue, canonical Work/Requirements, or scheduled-job catalog missing; stop';
  END IF;
  IF EXISTS (SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
     OR (SELECT count(*) FROM atlas.task_release_queue_items) <> 97 THEN
    RAISE EXCEPTION 'The owner-adjudicated historical 97-row queue is not the verified retired source; stop';
  END IF;
  IF (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')<>82
     OR (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')<>15 THEN
    RAISE EXCEPTION 'Historical queue state distribution drifted; stop';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND (t.tgfoid IN (v_root,v_effect)
       OR (t.tgrelid='atlas.tasks'::regclass AND t.tgname='advance_owner_completion_gated_queue_v1'))
  ) THEN
    RAISE EXCEPTION 'Legacy owner completion queue remains installed as a trigger; stop';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
      AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) THEN
    RAISE EXCEPTION 'Original physical harvest consequence trigger missing; stop';
  END IF;
  FOR v_rec IN SELECT * FROM (VALUES
    (v_root, '2d4c93888e82f00f3a1af150827d1bcc'::text),
    (v_effect, '625d90abe259db0f8edaf42900ac722d'::text)
  ) AS expected(function_oid,expected_source_md5)
  LOOP
    IF (SELECT md5(pg_get_functiondef(v_rec.function_oid)))
         IS DISTINCT FROM v_rec.expected_source_md5 THEN
      RAISE EXCEPTION 'Original legacy branch source drifted; stop';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=v_rec.function_oid
        AND p.proowner='postgres'::regrole AND p.prosecdef
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'Function owner/privilege/identity differs from source-approved held orphan; stop';
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.refobjid=v_rec.function_oid AND d.objid<>v_rec.function_oid
        AND d.deptype='n'
    ) THEN
      RAISE EXCEPTION 'Found direct catalog dependent on old serial function; stop';
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM cron.job j
    WHERE position('advance_owner_completion_gated_queue_v1' IN lower(j.command))>0
       OR position('apply_owner_completion_gated_release_effect_v1' IN lower(j.command))>0
  ) THEN
    RAISE EXCEPTION 'A scheduled job still mentions the original queue branch; stop';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_root AND p.prokind IN ('f','p')
      AND n.nspname<>'information_schema' AND n.nspname<>'pg_catalog'
      AND n.nspname NOT LIKE 'pg_toast%'
      AND position('advance_owner_completion_gated_queue_v1' IN lower(pg_get_functiondef(p.oid)))>0
  ) THEN
    RAISE EXCEPTION 'Root old queue function has a newly discovered caller; stop';
  END IF;
  SELECT count(*) INTO v_mention_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_effect AND p.prokind IN('f','p')
      AND n.nspname<>'information_schema' AND n.nspname<>'pg_catalog'
      AND n.nspname NOT LIKE 'pg_toast%'
      AND position('apply_owner_completion_gated_release_effect_v1' IN lower(pg_get_functiondef(p.oid)))>0;
  IF v_mention_count<>1 OR
     position('apply_owner_completion_gated_release_effect_v1' IN
       lower(pg_get_functiondef(v_root)))=0 THEN
    RAISE EXCEPTION 'Old queue leaf is not the sole source caller of its old effect; stop';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname IN('atlas','public') AND p.prokind IN('f','p')
        AND pg_get_functiondef(p.oid) ILIKE '%task_release_queue_items%')<>29 THEN
    RAISE EXCEPTION 'Expected exact 29 queue-source references before bounded legacy branch removal; stop';
  END IF;
  PERFORM set_config('atlas.held_owner_legacy_queue_before',(SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.held_owner_work_before',(SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.held_owner_requirement_before',(SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.held_owner_task_before',(SELECT count(*)::text FROM atlas.tasks),true);
END $atlas_owner_old_serial_branch_guard$;

DROP FUNCTION atlas.advance_owner_completion_gated_queue_v1() RESTRICT;
DROP FUNCTION atlas.apply_owner_completion_gated_release_effect_v1(uuid,date) RESTRICT;

DO $atlas_owner_old_serial_branch_preserve$
BEGIN
 IF to_regprocedure('atlas.advance_owner_completion_gated_queue_v1()') IS NOT NULL
    OR to_regprocedure('atlas.apply_owner_completion_gated_release_effect_v1(uuid,date)') IS NOT NULL THEN
  RAISE EXCEPTION 'Exact deprecated functions survived RESTRICT drop; stop';
 END IF;
 IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
       IS DISTINCT FROM current_setting('atlas.held_owner_legacy_queue_before')
 OR (SELECT count(*)::text FROM atlas.work_items)
       IS DISTINCT FROM current_setting('atlas.held_owner_work_before')
 OR (SELECT count(*)::text FROM atlas.work_requirements)
       IS DISTINCT FROM current_setting('atlas.held_owner_requirement_before')
 OR (SELECT count(*)::text FROM atlas.tasks)
       IS DISTINCT FROM current_setting('atlas.held_owner_task_before') THEN
  RAISE EXCEPTION 'Original source or canonical Work/Requirements/Tasks changed; stop';
 END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN('atlas','public') AND p.prokind IN('f','p')
       AND pg_get_functiondef(p.oid) ILIKE '%task_release_queue_items%')<>27 THEN
  RAISE EXCEPTION 'Unexpected queue reference count after exact two-function DROP RESTRICT; stop';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
   AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
   AND NOT t.tgisinternal AND t.tgenabled='O'
 ) THEN
   RAISE EXCEPTION 'Original harvest preparation trigger changed; stop';
 END IF;
END $atlas_owner_old_serial_branch_preserve$;
COMMIT;
