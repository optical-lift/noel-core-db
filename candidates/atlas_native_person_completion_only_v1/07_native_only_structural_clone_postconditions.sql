-- HELD disposable clone postconditions ONLY. Never execute on live production.
-- Run after the exact source-pinned completion-only SQL and the original P1
-- structural postconditions, before signed GoTrue/PostgREST acceptance.
DO $native_only_check$
DECLARE
  v_function text;
  v_check text;
BEGIN
  IF current_database() IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'Refusing non-disposable native completion verification';
  END IF;
  IF to_regclass('atlas.historical_self_adoption_review_events_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'Historical review source must not be introduced by completion-only release';
  END IF;
  IF to_regprocedure('public.governor_retire_historical_work_self_api_v1(uuid,uuid,uuid,text,uuid)')
    IS NOT NULL OR
    to_regprocedure('public.governor_historical_retirement_preflight_self_api_v1(uuid,uuid,uuid)')
    IS NOT NULL THEN
    RAISE EXCEPTION 'Historical cancellation or preflight transport must remain uninstalled';
  END IF;
  SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_function
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='apply_work_lifecycle_transition_internal_v1'
    AND p.pronargs=4;
  IF v_function IS NULL
    OR v_function NOT LIKE '%p_transition_kind IS DISTINCT FROM ''complete''%'
    OR v_function NOT LIKE '%Historical self-adopted responsibility requires native reconciliation%'
    OR v_function NOT LIKE '%Current native responsible Person required%'
    OR v_function LIKE '%IF p_transition_kind=''cancel'' THEN%' THEN
    RAISE EXCEPTION 'Single private native-Person completion guard missing or cancellation still executable';
  END IF;
  SELECT pg_catalog.pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='atlas' AND t.relname='work_lifecycle_events_v1'
    AND c.conname='work_lifecycle_events_v1_source_table_check';
  IF v_check IS NULL
     OR v_check LIKE '%historical_self_adoption_review_events_v1%' THEN
    RAISE EXCEPTION 'Historical event source still admitted to native-only lifecycle';
  END IF;
  RAISE NOTICE 'PASS completion-only source: native Person, one private transition and no historical cancellation functions';
END
$native_only_check$;
