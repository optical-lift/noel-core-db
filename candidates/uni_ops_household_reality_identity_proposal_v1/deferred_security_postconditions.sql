-- DEFERRED. Use only on a disposable current-schema Postgres clone after
-- assembly of the six HELD source candidate files in README order.
-- This is source for the later collected structural acceptance, NOT a run.
DO $post$
DECLARE
  v_table_name text;
  v_function_name text;
  v_table regclass;
  v_function regprocedure;
  v_role text;
  v_def boolean;
  v_search_path text;
BEGIN
  FOREACH v_table_name IN ARRAY ARRAY[
    'atlas.uni_ops_household_reality_identity_proposals_v1',
    'atlas.uni_ops_household_disclosure_decision_events_v1',
    'atlas.uni_ops_household_reality_identity_reviews_v1'
  ] LOOP
    v_table:=to_regclass(v_table_name);
    IF v_table IS NULL THEN
      RAISE EXCEPTION 'HELD source carrier missing: %',v_table_name;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=v_table
      AND c.relrowsecurity=true
    ) THEN
      RAISE EXCEPTION 'HELD private source must have RLS: %',v_table_name;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=v_table
        AND t.tgisinternal=false
        AND (t.tgtype::int & 2)=2
        AND (t.tgtype::int & 8)=8
        AND (t.tgtype::int & 16)=16
    ) THEN
      RAISE EXCEPTION 'HELD source event history not append-only: %',v_table_name;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF pg_catalog.has_table_privilege(v_role,v_table,'SELECT')
         OR pg_catalog.has_table_privilege(v_role,v_table,'INSERT')
         OR pg_catalog.has_table_privilege(v_role,v_table,'UPDATE')
         OR pg_catalog.has_table_privilege(v_role,v_table,'DELETE') THEN
        RAISE EXCEPTION 'HELD table public to role: % / %',
          v_table_name,v_role;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_function_name IN ARRAY ARRAY[
    'atlas.uni_ops_propose_household_reality_identity_internal_v1(uuid,uuid,uuid,uuid,text)',
    'atlas.uni_ops_decide_household_disclosure_internal_v1(uuid,uuid,uuid,text,text,uuid,text)',
    'atlas.uni_ops_household_disclosure_current_self_internal_v1(uuid,uuid,text)',
    'atlas.uni_ops_review_household_reality_identity_internal_v1(uuid,text,uuid,text,text,uuid)',
    'atlas.uni_ops_resolve_household_reality_identity_internal_v1(uuid,uuid,uuid)',
    'atlas.uni_ops_household_identity_review_queue_internal_v1(integer,timestamptz,uuid)',
    'atlas.uni_ops_household_source_composition_internal_v1(uuid,uuid,uuid)',
    'atlas.uni_ops_original_household_need_receipt_internal_v1(uuid,uuid,uuid)',
    'atlas.uni_ops_household_typed_requirement_source_packet_internal_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    v_function:=to_regprocedure(v_function_name);
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'HELD source function missing: %',v_function_name;
    END IF;
    SELECT p.prosecdef,array_to_string(p.proconfig,',')
      INTO v_def,v_search_path
    FROM pg_catalog.pg_proc p WHERE p.oid=v_function;
    IF v_def IS DISTINCT FROM true
       OR v_search_path NOT LIKE '%search_path=%' THEN
      RAISE EXCEPTION 'Source invoker or function search_path drift: %',
        v_function_name;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF pg_catalog.has_function_privilege(v_role,v_function,'EXECUTE') THEN
        RAISE EXCEPTION 'Private writer/reader callable by %: %',
          v_role,v_function_name;
      END IF;
    END LOOP;
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
      ) a
      WHERE p.oid=v_function AND a.grantee=0
        AND a.privilege_type='EXECUTE'
    ) THEN
      RAISE EXCEPTION 'PUBLIC function grant persisted: %',v_function_name;
    END IF;
  END LOOP;

  IF to_regprocedure('public.uni_ops_review_household_reality_identity_internal_v1(uuid,text,uuid,text,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.uni_ops_household_disclosure_current_self_internal_v1(uuid,uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'Unauthorized public source mirror';
  END IF;

  RAISE NOTICE 'HELD source structures satisfy private append-only contract; does NOT approve signed actors or a release';
END;
$post$;
