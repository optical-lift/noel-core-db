-- Schema-clone postconditions only. Do not use as permission to release.
DO $validation$
DECLARE
  v_read regprocedure:=to_regprocedure('public.principal_household_life_patterns_self_api_v1()');
  v_write regprocedure:=to_regprocedure('public.principal_upsert_household_life_pattern_self_api_v1(jsonb)');
  v_internal regprocedure:=to_regprocedure('atlas.principal_upsert_household_life_pattern_self_api_v1(jsonb)');
BEGIN
  IF v_read IS NULL OR v_write IS NULL OR v_internal IS NULL THEN
    RAISE EXCEPTION 'Household life-pattern source and membranes must exist.';
  END IF;
  IF has_function_privilege('anon',v_read,'EXECUTE') OR
     has_function_privilege('anon',v_write,'EXECUTE') OR
     NOT has_function_privilege('authenticated',v_read,'EXECUTE') OR
     NOT has_function_privilege('authenticated',v_write,'EXECUTE') THEN
    RAISE EXCEPTION 'Household pattern RPC roles misconfigured.';
  END IF;
  IF has_function_privilege('authenticated',v_internal,'EXECUTE') THEN
    RAISE EXCEPTION 'Internal Household writer is directly exposed.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas' AND c.relname='household_life_patterns' AND c.relrowsecurity)
    OR NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas' AND c.relname='household_life_pattern_events' AND c.relrowsecurity)
  THEN RAISE EXCEPTION 'Household pattern/event RLS is required.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=v_internal
      AND p.prosecdef AND pg_get_functiondef(p.oid) LIKE '%principal_current_household_id_v1%'
      AND pg_get_functiondef(p.oid) LIKE '%household_members%'
      AND pg_get_functiondef(p.oid) LIKE '%expectedRevision%'
      AND pg_get_functiondef(p.oid) LIKE '%sourceActionId%'
      AND pg_get_functiondef(p.oid) LIKE '%householdBasisKind%'
      AND pg_get_functiondef(p.oid) LIKE '%householdBasisDescription%') THEN
    RAISE EXCEPTION 'Writer must check active Principal, member scope, revision, idempotence.';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='atlas'
      AND table_name='household_life_patterns'
      AND column_name IN ('household_basis_kind','household_basis_description'))<>2 THEN
    RAISE EXCEPTION 'The relationship/responsibility basis must be recorded.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='atlas'
     AND table_name='household_life_patterns' AND column_name IN
       ('task_id','completed_at','overdue_at','next_due_at')) THEN
    RAISE EXCEPTION 'Household life pattern cannot become a generic recurrence task.';
  END IF;
END
$validation$;
