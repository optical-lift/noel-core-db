-- ACCESS-01 postconditions. Execute ONLY after the candidate on a
-- production-shaped disposable clone; this is not signed actor acceptance.
-- No new grant, API or source Object may be inferred from a green test.
DO $audit$
DECLARE
 v_signature text;
 v_name text;
 v_native oid;
 v_public oid;
 v_def text;
 v_public_def text;
 v_guard integer;
 v_list integer;
BEGIN
 IF to_regprocedure('atlas.capability_root_authority_context_self_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)') IS NULL THEN
   RAISE EXCEPTION 'ACCESS-01 existing Event and root authority helpers required';
 END IF;
 FOR v_signature IN SELECT unnest(ARRAY[
   'event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)',
   'ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'
 ]) LOOP
   v_name := split_part(v_signature,'(',1);
   v_native := to_regprocedure('atlas.' || v_signature)::oid;
   v_public := to_regprocedure('public.' || v_signature)::oid;
   IF v_native IS NULL OR v_public IS NULL THEN
     RAISE EXCEPTION 'ACCESS-01 native or original REST wrapper missing';
   END IF;
   IF NOT EXISTS (
     SELECT 1 FROM pg_proc p
     WHERE p.oid=v_native AND p.prosecdef AND p.provolatile='s'
       AND p.prorettype='jsonb'::regtype
       AND EXISTS(SELECT 1 FROM unnest(p.proconfig) cfg
                  WHERE cfg IN ('search_path=""','search_path='))
   ) THEN RAISE EXCEPTION 'ACCESS-01 native function shape/security mismatch'; END IF;
   IF NOT EXISTS (
     SELECT 1 FROM pg_proc p
     WHERE p.oid=v_public AND NOT p.prosecdef AND p.provolatile='s'
       AND p.prorettype='jsonb'::regtype
       AND EXISTS(SELECT 1 FROM unnest(p.proconfig) cfg
                  WHERE cfg IN ('search_path=""','search_path='))
   ) THEN RAISE EXCEPTION 'ACCESS-01 REST delegate shape/security mismatch'; END IF;
   IF has_function_privilege('anon',v_native,'EXECUTE')
      OR NOT has_function_privilege('authenticated',v_native,'EXECUTE')
      OR has_function_privilege('anon',v_public,'EXECUTE')
      OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        WHERE p.oid IN (v_native,v_public) AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
      ) THEN
      RAISE EXCEPTION 'ACCESS-01 native or REST RPC role grants incorrect';
   END IF;
   v_def := pg_get_functiondef(v_native);
   v_public_def := pg_get_functiondef(v_public);
   v_guard := position('PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id)' in v_def);
   v_list := position('SELECT coalesce(jsonb_agg' in v_def);
   IF position('atlas.ledger_occurrence_shared_work_actor_self_v1' in v_def)=0
      OR v_guard=0 OR v_list=0 OR v_guard>v_list
      OR position('USING errcode=''42501''' in lower(v_def))=0
      OR position('atlas.' || v_name || '(' in v_public_def)=0
   THEN
     RAISE EXCEPTION 'ACCESS-01 source guard, denial, order or public forwarding missing';
   END IF;
 END LOOP;
END
$audit$;
