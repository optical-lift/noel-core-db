-- Run only on the approved disposable production-schema clone.
DO $verify$
BEGIN
  IF to_regprocedure('public.connected_person_my_work_self_api_v1(integer,uuid)') IS NULL
    OR to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)') IS NULL
  THEN RAISE EXCEPTION 'Canonical My Work reader missing'; END IF;
  IF NOT has_function_privilege('authenticated',
    'public.connected_person_my_work_self_api_v1(integer,uuid)','EXECUTE')
    OR has_function_privilege('anon',
    'public.connected_person_my_work_self_api_v1(integer,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'Person-only grants not enforced'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas' AND p.proname='connected_person_my_work_self_api_v1'
      AND p.prosecdef AND p.provolatile='s'
  ) THEN RAISE EXCEPTION 'Internal reader is not stable guarded source'; END IF;
END
$verify$;
-- Authenticated acceptance probes (separate from this schema-only fixture):
-- 1. User A reads their own verified canonical Person allocation(s); User B cannot.
-- 2. Work scheduled Friday is 'scheduled' when selecting Wednesday.
-- 3. Withdrawing the active plan makes the original Work 'unscheduled' (same IDs).
-- 4. Needs-replan, duplicate active plans and malformed dates do not become
--    falsely declared unscheduled tasks.
-- 5. A page cursor yields all rows without duplicates and no optional offers.
