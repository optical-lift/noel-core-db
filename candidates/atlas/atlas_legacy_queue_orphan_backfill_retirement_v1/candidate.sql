-- HELD: Atlas SRC-RETIRE-01 A, retire one source-catalog orphan
-- SOURCE ONLY. This is NOT a production migration or deletion approval.
-- This function is an older administrator-only legacy Task release-queue
-- backfill. No table, queue row, Work, privilege, policy or trigger changes.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $atlas_legacy_backfill_retirement_guard$
DECLARE
  v_func oid;
BEGIN
  v_func := to_regprocedure('atlas.backfill_active_task_release_gates_v1()')::oid;
  IF v_func IS NULL THEN
    RAISE EXCEPTION 'legacy backfill identity changed; stop';
  END IF;

  -- Read-only 2026-11-16 current-source fingerprint. A changed function
  -- must be independently reviewed; never drop an unknown definition.
  IF (SELECT md5(pg_catalog.pg_get_functiondef(p.oid))
      FROM pg_catalog.pg_proc p WHERE p.oid=v_func)
        IS DISTINCT FROM '623f52a2ff3ae732cdc62e459be8bfca' THEN
    RAISE EXCEPTION 'legacy backfill function source drift; stop';
  END IF;

  -- Never retire anything with known native or source-text consumers.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_depend d
    WHERE d.refobjid=v_func AND d.deptype NOT IN ('i','e','p')
  ) THEN
    RAISE EXCEPTION 'legacy backfill has tracked dependents; stop';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgfoid=v_func AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'legacy backfill trigger reference found; stop';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE p.oid<>v_func AND p.prokind IN ('f','p')
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND strpos(lower(pg_catalog.pg_get_functiondef(p.oid)),
                 'backfill_active_task_release_gates_v1')>0
  ) THEN
    RAISE EXCEPTION 'legacy backfill function caller found; stop';
  END IF;

  IF has_function_privilege('anon',v_func,'EXECUTE')
     OR has_function_privilege('authenticated',v_func,'EXECUTE')
     OR has_function_privilege('service_role',v_func,'EXECUTE') THEN
    RAISE EXCEPTION 'legacy backfill has unexpected API execute permission; stop';
  END IF;

  IF to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'scheduler catalog absent; cannot check jobs; stop';
  END IF;
  IF EXISTS (
    SELECT 1 FROM cron.job
    WHERE command ILIKE '%backfill_active_task_release_gates_v1%'
  ) THEN
    RAISE EXCEPTION 'legacy backfill scheduled caller found; stop';
  END IF;

  -- If external / historical administrative use is discovered during
  -- release review, HOLD even if this catalog check passes.
END
$atlas_legacy_backfill_retirement_guard$;

DROP FUNCTION atlas.backfill_active_task_release_gates_v1() RESTRICT;

DO $atlas_legacy_backfill_retirement_postcheck$
BEGIN
  IF to_regprocedure('atlas.backfill_active_task_release_gates_v1()') IS NOT NULL THEN
    RAISE EXCEPTION 'legacy function survived guarded retirement';
  END IF;
  IF to_regclass('atlas.task_release_queue_items') IS NULL
     OR to_regclass('atlas.work_items') IS NULL THEN
    RAISE EXCEPTION 'unrelated legacy queue or canonical Work missing; stop';
  END IF;
END
$atlas_legacy_backfill_retirement_postcheck$;
COMMIT;
