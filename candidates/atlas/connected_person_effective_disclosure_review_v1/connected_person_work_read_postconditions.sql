-- Structural checks for connected_person_work_read_candidate.sql.
-- Do not count a passing SQL assertion as signed HTTP authorization proof.
BEGIN;
DO $test$
DECLARE
  v_internal oid;
  v_bridge oid;
  v_body text;
BEGIN
  v_internal:=to_regprocedure('atlas.connected_person_authorized_ledger_work_self_api_v1(uuid,integer,uuid)');
  v_bridge:=to_regprocedure('public.connected_person_authorized_ledger_work_self_api_v1(uuid,integer,uuid)');
  IF v_internal IS NULL OR v_bridge IS NULL THEN
    RAISE EXCEPTION 'Exact Ledger individual Work API missing';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_internal)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_bridge)
     OR has_function_privilege('authenticated',v_internal,'EXECUTE')
     OR has_function_privilege('anon',v_internal,'EXECUTE')
     OR has_function_privilege('anon',v_bridge,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_bridge,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Individual Work source ACL invalid';
  END IF;
  v_body:=pg_get_functiondef(v_internal);
  IF v_body NOT LIKE '%reality_access_self_api_v1%'
     OR v_body NOT LIKE '%person_has_native_ledger_connection_v1%'
     OR v_body NOT LIKE '%company_work_native_ledger_relevance%'
     OR v_body NOT LIKE '%company_work_native_ledger_exact_source_v1%'
     OR v_body NOT LIKE '%a.establishment_basis%'
     OR v_body NOT LIKE '%s.ended_at IS NULL%'
     OR v_body NOT LIKE '%permissionAuditComplete%'
  THEN
    RAISE EXCEPTION 'Individual Work source authority check missing';
  END IF;
  IF v_body LIKE '%w.instructions%'
    OR v_body LIKE '%w.metadata%'
    OR v_body LIKE '%work_item_context_links%'
    OR v_body LIKE '%growing_objects%'
    OR v_body LIKE '%crop_cycles%'
    OR v_body LIKE '%care_state_history%'
  THEN
    RAISE EXCEPTION 'Individual Work read includes unauthorized institutional source fields';
  END IF;
END;
$test$;
ROLLBACK;
