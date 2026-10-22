-- Postconditions for precisely eleven public, invoker-only Event RPC
-- delegates. Execute after applying the candidate in a disposable clone.
DO $gate$
DECLARE
 n text; args text; expected_vol char; x oid; inner_oid oid;
 outer_schema text; actual_def text;
 specs jsonb:='[{"n":"ledger_occurrence_shared_index_self_api_v1","types":["uuid"],"v":"stable"},{"n":"ledger_occurrence_shared_work_self_api_v1","types":["uuid","uuid","uuid"],"v":"stable"},{"n":"ledger_occurrence_work_extension_self_api_v1","types":["uuid","uuid","uuid"],"v":"stable"},{"n":"event_existing_work_choices_self_api_v1","types":["uuid","uuid","uuid","text"],"v":"stable"},{"n":"ledger_event_attention_people_self_api_v1","types":["uuid","uuid","uuid"],"v":"stable"},{"n":"link_existing_ledger_event_work_self_api_v1","types":["uuid","uuid","uuid","uuid","text"],"v":"volatile"},{"n":"direct_ledger_event_work_attention_self_api_v1","types":["uuid","uuid","uuid","uuid","uuid","boolean","text"],"v":"volatile"},{"n":"change_ledger_event_ordinary_work_self_api_v1","types":["uuid","uuid","uuid","uuid","text","text","text"],"v":"volatile"},{"n":"my_ledger_event_work_attention_self_api_v1","types":[],"v":"stable"},{"n":"create_ledger_occurrence_shared_work_self_api_v1","types":["uuid","uuid","uuid","text","text"],"v":"volatile"},{"n":"mark_ledger_occurrence_shared_work_done_self_api_v1","types":["uuid","uuid","uuid","uuid","text"],"v":"volatile"}]'::jsonb;
 item jsonb; c integer:=0;
BEGIN
 FOR item IN SELECT value FROM jsonb_array_elements(specs)
 LOOP
   n:=item->>'n';
   args:=array_to_string(ARRAY(SELECT jsonb_array_elements_text(item->'types')),',');
   expected_vol:=CASE WHEN item->>'v'='stable' THEN 's' ELSE 'v' END;
   x:=to_regprocedure('public.'||n||'('||args||')');
   inner_oid:=to_regprocedure('atlas.'||n||'('||args||')');
   IF x IS NULL OR inner_oid IS NULL THEN
     RAISE EXCEPTION 'Missing public or native Event RPC % (%)',n,args;
   END IF;
   IF NOT EXISTS (
     SELECT 1 FROM pg_proc p WHERE p.oid=x
       AND p.prorettype='jsonb'::regtype
       AND p.provolatile=expected_vol AND NOT p.prosecdef
       AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg IN ('search_path=""','search_path='))
   ) THEN RAISE EXCEPTION 'Event public wrapper has mismatched shape/security %',n; END IF;
   IF NOT has_function_privilege('authenticated',x,'EXECUTE')
       OR has_function_privilege('anon',x,'EXECUTE')
       OR EXISTS (
         SELECT 1 FROM pg_proc policy_fn
         CROSS JOIN LATERAL aclexplode(coalesce(policy_fn.proacl,
             acldefault('f',policy_fn.proowner))) perms
         WHERE policy_fn.oid=x AND perms.grantee=0
           AND perms.privilege_type='EXECUTE'
       ) THEN
     RAISE EXCEPTION 'Event public wrapper EXECUTE grant mismatch %',n;
   END IF;
   actual_def:=pg_get_functiondef(x);
   IF position('atlas.'||n||'(' IN actual_def)=0 THEN
      RAISE EXCEPTION 'Event wrapper does not forward to exact private API %',n;
   END IF;
   c:=c+1;
 END LOOP;
 IF c<>11 THEN RAISE EXCEPTION 'Expected precisely 11, got %',c; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='ledger_workspace_self_api_v1'
 ) THEN RAISE EXCEPTION 'Existing Ledger REST compatibility wrapper unexpectedly missing'; END IF;
END $gate$;
