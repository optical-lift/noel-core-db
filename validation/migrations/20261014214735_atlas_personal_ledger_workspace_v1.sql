DO $validation$
DECLARE v_oid oid:=to_regprocedure('public.ledger_workspace_self_api_v1(uuid)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'No public Ledger workspace API'; END IF;
  IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
    OR has_function_privilege('anon',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Ledger workspace RPC role grants invalid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=v_oid AND p.prosecdef AND p.provolatile='s'
    AND 'search_path=pg_catalog'=ANY(p.proconfig)) THEN
    RAISE EXCEPTION 'Ledger public RPC must be stable SECURITY DEFINER with fixed search path';
  END IF;
  IF position('atlas.ledger_workspace_self_api_v1' in pg_get_functiondef(v_oid))=0 THEN
    RAISE EXCEPTION 'Ledger public RPC bypasses canonical workspace gate';
  END IF;
  IF position('atlas.reality_access_self_api_v1' in pg_get_functiondef(
     'atlas.ledger_workspace_self_api_v1(uuid)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'Ledger workspace does not authenticate via canonical seated read';
  END IF;
END
$validation$;