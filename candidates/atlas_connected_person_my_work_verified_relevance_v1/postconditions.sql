-- ACCESS-02 POSTCONDITIONS — disposable verification only; never install as
-- a production migration. These checks cannot substitute for signed actor tests.
DO $access02_postconditions$
DECLARE
  v_fn oid;
  v_wrapper oid;
  v_src text;
  v_guard int;
  v_original int;
  v_scope int;
  v_page int;
BEGIN
  v_fn := to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)');
  v_wrapper := to_regprocedure('public.connected_person_my_work_self_api_v1(integer,uuid)');
  IF v_fn IS NULL OR v_wrapper IS NULL THEN
    RAISE EXCEPTION 'ACCESS-02 native or REST Work reader missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_fn
    AND p.prosecdef AND p.provolatile='s'
    AND p.prorettype='jsonb'::regtype
    AND ('search_path=""'=ANY(p.proconfig))
  ) THEN
    RAISE EXCEPTION 'ACCESS-02 native Work source shape changed';
  END IF;
  v_src := pg_get_functiondef(v_fn);
  v_guard := position('AND coalesce(relevance.has_relevance,false)' IN v_src);
  v_original := position('AND atlas.person_original_work_identity_disclosed_self_v1(' IN v_src);
  v_scope := position('AND atlas.person_has_native_ledger_connection_v1(' IN v_src);
  v_page := position('LIMIT p_limit+1' IN v_src);
  IF v_guard=0 OR v_original<=v_guard OR v_scope<=v_original OR v_page<=v_scope
    OR position('AND w.work_state=''open''' IN v_src)=0
    OR position('x.evidence_kind IN (''owner_attested'',''participant_attested'')' IN v_src)=0
    OR position('company_work_native_ledger_exact_source_v1' IN v_src)=0
    OR position('a.assignee_canonical_person_id=v_self' IN v_src)=0
    OR position('''instructions'',r.instructions' IN v_src)=0
    OR position('IF auth.uid() IS NULL OR v_self IS NULL' IN v_src)=0 THEN
    RAISE EXCEPTION 'ACCESS-02 relevance, identity, source or pagination guard missing';
  END IF;
  IF md5(pg_get_functiondef(v_wrapper))
      IS DISTINCT FROM 'c47a7961a04f6b834b65a851253990da' THEN
    RAISE EXCEPTION 'ACCESS-02 public Work wrapper unexpectedly changed';
  END IF;
  IF NOT has_function_privilege('authenticated',v_wrapper,'EXECUTE')
    OR has_function_privilege('anon',v_wrapper,'EXECUTE')
    OR EXISTS (SELECT 1 FROM aclexplode(
        coalesce((SELECT p.proacl FROM pg_proc p WHERE p.oid=v_wrapper),
                 acldefault('f',(SELECT p.proowner FROM pg_proc p WHERE p.oid=v_wrapper)))
       ) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'ACCESS-02 REST Work wrapper execution ACL differs from release baseline';
  END IF;
  RAISE NOTICE 'PASS ACCESS-02 static current source postconditions; independent signed actors still required';
END;
$access02_postconditions$;
