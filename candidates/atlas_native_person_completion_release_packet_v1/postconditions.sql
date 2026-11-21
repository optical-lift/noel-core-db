-- HELD ATLAS native-Person-only completion postconditions, read-only checks.
-- Run ONLY on a disposable current-schema clone after candidate.sql and
-- preserve its output with a signed-actor matrix and canonical source receipt.
-- This file is NOT a production migration, fixture, repair or release approval.
DO $native_release_check$
DECLARE
  v_transition text;
  v_worker text;
  v_legacy text;
  v_event text;
  v_evt_count bigint;
  v_work_count bigint;
  v_source_constraint text;
BEGIN
  IF to_regclass('atlas.work_lifecycle_events_v1') IS NULL
     OR to_regprocedure('atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'Canonical single lifecycle source absent'; END IF;

  SELECT pg_catalog.pg_get_functiondef(p.oid)
  INTO v_transition FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='apply_work_lifecycle_transition_internal_v1'
    AND p.pronargs=4;
  IF v_transition IS NULL
    OR v_transition NOT LIKE '%p_transition_kind IS DISTINCT FROM ''complete''%'
    OR v_transition NOT LIKE '%Historical self-adopted responsibility requires native reconciliation%'
    OR v_transition NOT LIKE '%Current native responsible Person required%'
    OR v_transition NOT LIKE '%Existing accepted source evidence required%'
    OR v_transition NOT LIKE '%source_qualified_physical_actual%'
    OR v_transition NOT LIKE '%pg_advisory_xact_lock%'
    OR v_transition LIKE '%IF p_transition_kind=''cancel'' THEN%'
    OR v_transition LIKE '%SET work_state=''cancelled''%'
  THEN RAISE EXCEPTION 'Private source authority is not the exact native completion-only rule'; END IF;

  IF has_function_privilege('anon',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
    OR has_function_privilege('authenticated',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
    OR has_function_privilege('service_role',
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','EXECUTE')
  THEN RAISE EXCEPTION 'Client may call internal Done transition directly'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='work_lifecycle_events_v1'
      AND c.relrowsecurity AND c.relforcerowsecurity
  ) THEN RAISE EXCEPTION 'Work lifecycle must have forced RLS'; END IF;
  IF has_table_privilege('anon','atlas.work_lifecycle_events_v1','SELECT')
    OR has_table_privilege('authenticated','atlas.work_lifecycle_events_v1','SELECT')
    OR has_table_privilege('service_role','atlas.work_lifecycle_events_v1','SELECT')
  THEN RAISE EXCEPTION 'Lifecycle source table exposed to browser or service role'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='atlas.work_lifecycle_events_v1'::regclass
      AND t.tgname='work_lifecycle_event_append_only_v1'
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='atlas.work_lifecycle_events_v1'::regclass
      AND t.tgname='work_lifecycle_event_no_truncate_v1'
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) THEN RAISE EXCEPTION 'Immutable lifecycle history mutation guard absent'; END IF;

  SELECT pg_catalog.pg_get_constraintdef(c.oid)
    INTO v_source_constraint FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='atlas.work_lifecycle_events_v1'::regclass
    AND c.conname='work_lifecycle_events_v1_source_table_check';
  IF v_source_constraint IS NULL OR v_source_constraint LIKE '%historical_self_adoption_review_events_v1%'
  THEN RAISE EXCEPTION 'History review source must not be newly admitted'; END IF;
  IF to_regclass('atlas.historical_self_adoption_review_events_v1') IS NOT NULL
    OR to_regprocedure('public.governor_retire_historical_work_self_api_v1(uuid,uuid,uuid,text,uuid)') IS NOT NULL
  THEN RAISE EXCEPTION 'Historical review/retirement remains outside this source cohort'; END IF;

  SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_worker
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='report_connected_person_company_work_internal_v1'
    AND p.pronargs=7;
  SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_legacy
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='report_self_responsible_company_work_self_api_v1'
    AND p.pronargs=4;
  SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_event
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='mark_ledger_occurrence_shared_work_done_self_api_v1'
    AND p.pronargs=5;
  IF v_worker IS NULL OR v_legacy IS NULL OR v_event IS NULL
    OR v_worker NOT LIKE '%lifecycleContractVersion%'
    OR v_worker NOT LIKE '%apply_work_lifecycle_transition_internal_v1%'
    OR v_event NOT LIKE '%apply_work_lifecycle_transition_internal_v1%'
    OR v_event NOT LIKE '%personalPerformanceNotClaimed%'
    OR v_event NOT LIKE '%eventReceipt%'
    OR v_event NOT LIKE '%physicalPerformerAsserted%'
    OR v_event NOT LIKE '%historicalRecordedCompletion%'
    OR v_event NOT LIKE '%e.event_kind=''work_transition_applied''%'
    OR v_event NOT LIKE '%e.to_state=''completed''%'
    OR v_event NOT LIKE '%Completed Event Work has no qualifying historical Done or authoritative lifecycle event%'
    OR v_legacy NOT LIKE '%Historical self-adopted Work is reference only%'
  THEN RAISE EXCEPTION 'Existing original-Work writer cutovers incomplete or reauthorized legacy'; END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='atlas.work_items'::regclass
      AND t.tgname='work_items_shadow_lifecycle_state_v1' AND NOT t.tgisinternal)
  THEN RAISE EXCEPTION 'Original Work state observer missing'; END IF;
  SELECT count(*) INTO v_work_count FROM atlas.work_items;
  SELECT count(DISTINCT work_item_id) INTO v_evt_count
    FROM atlas.work_lifecycle_events_v1
    WHERE event_kind='historical_state_snapshot';
  IF v_evt_count IS DISTINCT FROM v_work_count THEN
    RAISE EXCEPTION 'Original Work baseline not complete, Work: %, baseline: %',
      v_work_count,v_evt_count;
  END IF;
  RAISE NOTICE 'PASS native completion-only source: single Work writer, Person authority, old writer cutover, historical cancel held; baseline Work: %',
    v_work_count;
END
$native_release_check$;
