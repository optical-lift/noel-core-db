-- Cross-draft ONLY: compile after #2368 shadow + single transition and
-- #2362 release_candidate (without COMMIT) + 10 care cutover.
-- Protected production-schema clone in one transaction; always ROLLBACK.
-- Structural checks do NOT prove signed positive worker authorization.
DO $care_single_done$
DECLARE
  v_done regprocedure:=to_regprocedure(
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)');
  v_actual regprocedure:=to_regprocedure(
    'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)');
  v_done_sql text;
  v_actual_sql text;
  v_rejected boolean:=false;
BEGIN
  IF v_done IS NULL OR v_actual IS NULL
     OR to_regclass('atlas.work_lifecycle_events_v1') IS NULL THEN
    RAISE EXCEPTION 'One original lifecycle source and care writer must be compiled first';
  END IF;
  IF has_function_privilege('anon',v_done,'EXECUTE')
     OR has_function_privilege('authenticated',v_done,'EXECUTE')
     OR has_function_privilege('service_role',v_done,'EXECUTE')
     OR has_function_privilege('anon',v_actual,'EXECUTE')
     OR has_function_privilege('authenticated',v_actual,'EXECUTE')
     OR has_function_privilege('service_role',v_actual,'EXECUTE') THEN
    RAISE EXCEPTION 'Pre-release source writer unexpectedly executable from client';
  END IF;
  -- PostgreSQL records SET search_path TO '' in pg_proc.proconfig
  -- as the exact text search_path="" (not search_path=).
  -- Require the empty pinned path AND SECURITY DEFINER for BOTH functions;
  -- this is not a relaxation to accept any schema or mutable caller path.
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_done
       AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig)) THEN
    RAISE EXCEPTION 'Universal lifecycle authority lacks SECURITY DEFINER with empty pinned search_path';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_actual
       AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig)) THEN
    RAISE EXCEPTION 'Physical care writer lacks SECURITY DEFINER with empty pinned search_path';
  END IF;
  v_done_sql:=pg_get_functiondef(v_done);
  v_actual_sql:=pg_get_functiondef(v_actual);
  IF position('continuing_care_actual_v1' in v_done_sql)=0
     OR position('source_qualified_physical_actual' in v_done_sql)=0
     OR position('rhythm_satisfactions' in v_done_sql)=0
     OR position('atlas.apply_work_lifecycle_transition_internal_v1' in v_actual_sql)=0
     OR position('work_lifecycle_events_v1' in v_actual_sql)=0 THEN
    RAISE EXCEPTION 'Care evidence and single terminal source are not connected';
  END IF;
  IF v_actual_sql ~* 'UPDATE[[:space:]]+atlas[.]work_items[[:space:]]+SET[[:space:]]+work_state'
     OR v_actual_sql ~* 'UPDATE[[:space:]]+atlas[.]work_allocations[[:space:]]+SET[[:space:]]+state' THEN
    RAISE EXCEPTION 'Physical domain writer still has an independent Done mutation';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class c
     WHERE c.oid='atlas.work_lifecycle_events_v1'::regclass AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'Canonical lifecycle event source is not RLS protected';
  END IF;
  -- A nonexistent original cannot be completed even by the test's elevated
  -- SQL runner. This does not substitute for signed GoTrue/PostgREST tests.
  BEGIN
    PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
      '00000000-0000-4000-8000-000000000090'::uuid,'complete',
      '00000000-0000-4000-8000-000000000091'::uuid,'unknown-physical-care');
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unknown physical-care transition failed to deny';
  END IF;
  RAISE NOTICE 'One draft Done path structurally linked and denied for unknown Work; signed actor and physical Result acceptance remain outstanding';
END;
$care_single_done$;
