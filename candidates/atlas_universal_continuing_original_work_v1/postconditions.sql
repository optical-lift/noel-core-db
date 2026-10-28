-- CANDIDATE postconditions: run ONLY after applying the candidate in a disposable
-- schema clone. NOT a production mutation or a signed human/worker acceptance.
DO $check$
DECLARE
  v_fn oid;
  v_acl text;
BEGIN
  SELECT p.oid INTO v_fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND p.proname='establish_continuing_original_work_internal_v1'
    AND pg_get_function_identity_arguments(p.oid)=
    'p_custody_kind text, p_custody_id uuid, p_ledger_id uuid, p_need_kind text, p_need_id uuid, p_serving_key text, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_title text, p_instructions text, p_result_contract_key text';
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'Missing exact universal continuing Work internal source contract';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR has_function_privilege('authenticated',v_fn,'EXECUTE')
     OR has_function_privilege('service_role',v_fn,'EXECUTE') THEN
    RAISE EXCEPTION 'Internal Work writer is exposed to an application credential';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_fn AND p.prosecdef
      AND 'search_path='=ANY(p.proconfig)
  ) THEN
    RAISE EXCEPTION 'Internal Work writer is missing constrained function context';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_items'::regclass
      AND c.conname='work_items_one_native_custody_v1'
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_item_context_links'::regclass
      AND c.conname='work_item_context_links_one_native_custody_v1'
  ) THEN
    RAISE EXCEPTION 'Native Household/Organization custody invariants missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='atlas' AND t.relname='household_need_occurrences_v1'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='atlas' AND t.relname='rhythm_state'
  ) THEN
    RAISE EXCEPTION 'One of two real Need source owners is unavailable';
  END IF;
  IF to_regprocedure(
      'atlas.continuing_original_work_result_continuation_internal_v1(uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION 'Missing original Work Result-to-Need continuation review';
  END IF;
  IF has_function_privilege('anon',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE')
     OR has_function_privilege('authenticated',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE')
     OR has_function_privilege('service_role',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'Cross-scope continuing-Result review is exposed to client credentials';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='atlas.continuing_original_work_result_continuation_internal_v1(uuid)'::regprocedure
      AND p.prosecdef AND p.provolatile='s'
      AND 'search_path='=ANY(p.proconfig)
  ) THEN
    RAISE EXCEPTION 'Result-to-Need review is not read-only or source-constrained';
  END IF;
  IF to_regprocedure('atlas.reality_continuation_normalize_v1(jsonb)') IS NULL
     OR to_regprocedure('atlas.household_laundry_current_self_api_v1()') IS NULL THEN
    RAISE EXCEPTION 'Existing universal continuation or Laundry source is missing';
  END IF;
  RAISE NOTICE 'Private one-serving and Result-to-Need review contracts protected; signed actual-to-next Work not yet proven';
END;
$check$;
