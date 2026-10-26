-- Clone-only postconditions for the existing all-date Person Today reader.
-- Not proof of signed session isolation, full disclosure, or release readiness.
BEGIN;
DO $check$
DECLARE
  v_fn oid:=to_regprocedure('atlas.connected_person_company_work_today_self_api_v1(integer)');
  v_public oid:=to_regprocedure('public.connected_person_company_work_today_self_api_v1(integer)');
  v_definition text;
BEGIN
  IF v_fn IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Existing connected Person Today SQL API missing';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_fn)
     OR has_function_privilege('anon',v_fn,'EXECUTE')
     OR has_function_privilege('anon',v_public,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Existing Today RPC ACL envelope invalid';
  END IF;
  v_definition:=pg_get_functiondef(v_fn);
  IF v_definition NOT LIKE '%reality_access_self_api_v1%'
     OR v_definition NOT LIKE '%person_has_native_ledger_connection_v1%'
     OR v_definition NOT LIKE '%company_work_native_ledger_relevance%'
     OR v_definition NOT LIKE '%company_work_native_ledger_exact_source_v1%'
     OR v_definition NOT LIKE '%rel.attribution_state=%'
     OR v_definition NOT LIKE '%a.assignee_membership_id IS NULL%'
     OR v_definition NOT LIKE '%NULL::text AS instructions%'
     OR v_definition NOT LIKE '%NULL::text AS source_type%'
     OR v_definition NOT LIKE '%NULL::uuid AS source_id%'
     OR v_definition NOT LIKE '%connected_person_company_work_today_v1%'
  THEN
    RAISE EXCEPTION 'Today source not restricted by current Person, exact Ledger and original Work attribution';
  END IF;
  IF v_definition LIKE '%w.title,w.instructions%'
      OR v_definition LIKE '%w.source_object_type source_type%'
  THEN
    RAISE EXCEPTION 'Existing Today read still exposes unapproved source fields';
  END IF;
END;
$check$;
ROLLBACK;
