-- Build 4 public transport must remain a thin authenticated-only mirror
-- of the already-released Atlas owner-authorized source contracts.
DO $validation$
DECLARE v_name text; v_signature text; v_function oid;
BEGIN
  FOR v_name,v_signature IN
    SELECT * FROM (VALUES
      ('company_work_accountability_native_ledger_self_api_v1','uuid,uuid,text,integer,uuid'),
      ('company_people_native_ledger_scope_self_api_v1','uuid,uuid,integer,uuid'),
      ('establish_company_work_native_ledger_relevance_self_api_v1','uuid,uuid,jsonb')
    ) signatures(function_name,arg_types)
  LOOP
    v_function := to_regprocedure('public.'||v_name||'('||v_signature||')');
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'Missing notebook transport: %',v_name;
    END IF;
    IF NOT has_function_privilege('authenticated',v_function,'EXECUTE')
      OR has_function_privilege('anon',v_function,'EXECUTE')
    THEN
      RAISE EXCEPTION 'Unsafe notebook transport grants: %',v_name;
    END IF;
    IF (SELECT prosecdef FROM pg_proc WHERE oid=v_function) THEN
      RAISE EXCEPTION 'Transport must remain invoker: %',v_name;
    END IF;
  END LOOP;
END;
$validation$;
