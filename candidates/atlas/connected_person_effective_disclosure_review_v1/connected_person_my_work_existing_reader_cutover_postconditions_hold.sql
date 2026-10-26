-- Structural postconditions for the HELD cutover of existing My Work.
-- Run only on a protected full-schema disposable clone after the held SQL.
-- Not a signed HTTP test; no live production change or release claim.
BEGIN;
DO $guard$
DECLARE
  v_internal oid := to_regprocedure(
    'atlas.connected_person_my_work_self_api_v1(integer,uuid)');
  v_public oid := to_regprocedure(
    'public.connected_person_my_work_self_api_v1(integer,uuid)');
  v_body text;
  v_wrapper text;
BEGIN
  IF v_internal IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Original My Work source and existing public API must both exist';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_internal)
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_public)
    OR has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_public,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Original My Work RPC privilege envelope changed unexpectedly';
  END IF;
  v_wrapper:=pg_get_functiondef(v_public);
  IF v_wrapper NOT LIKE '%atlas.connected_person_my_work_self_api_v1%'
  THEN
    RAISE EXCEPTION 'Original My Work wrapper no longer delegates to checked source';
  END IF;
  v_body:=pg_get_functiondef(v_internal);
  IF v_body NOT LIKE '%reality_access_self_api_v1%'
    OR v_body NOT LIKE '%current_person_id_v1%'
    OR v_body NOT LIKE '%person_has_native_ledger_connection_v1%'
    OR v_body NOT LIKE '%company_work_native_ledger_relevance%'
    OR v_body NOT LIKE '%company_work_native_ledger_exact_source_v1%'
    OR v_body NOT LIKE '%relevance.has_relevance IS TRUE%'
    OR v_body NOT LIKE '%connected_person_work_field_currently_approved_v1%'
    OR v_body NOT LIKE '%connected_person_my_work_v1%'
    OR v_body NOT LIKE '%scheduleReadAcrossAllDates%'
    OR v_body NOT LIKE '%optionalRequestsExcluded%'
  THEN
    RAISE EXCEPTION 'Existing My Work reader remains overbroad or lost its original contract';
  END IF;
  -- Projection may keep a NULL-compatible field slot, but may not source
  -- instructions from the institutional Work row before a distinct
  -- approved exact-Work instruction disclosure policy is installed.
  IF v_body LIKE '%w.title,w.instructions,w.result_contract_key%'
    OR v_body LIKE '%''instructions'',w.instructions%'
    OR v_body LIKE '%''instructions'',r.source_instructions%'
  THEN
    RAISE EXCEPTION 'Existing My Work still exposes unreviewed instructions';
  END IF;
END;
$guard$;
ROLLBACK;
