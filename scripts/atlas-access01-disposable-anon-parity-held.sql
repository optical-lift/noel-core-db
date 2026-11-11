-- ACCESS-01 TEST ONLY: two exact PUBLIC REST wrapper anonymous grants.
-- Not a migration. Guarded local-only recovery of clone restore ACL parity.
BEGIN;
DO $access01_before$
DECLARE
  v_count int;
  v_public_anon int;
BEGIN
  IF current_setting('access01.disposable_clone',true) IS DISTINCT FROM 'true'
     OR current_database() <> 'postgres' THEN
    RAISE EXCEPTION 'REFUSE ACCESS01 ACL parity outside disposable clone';
  END IF;
  WITH exact_functions(oid, expected_definer) AS (
    VALUES
    ('atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)'::regprocedure,true),
    ('atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'::regprocedure,true),
    ('public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)'::regprocedure,false),
    ('public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'::regprocedure,false)
  ) SELECT count(*) INTO v_count
    FROM exact_functions f JOIN pg_proc p ON p.oid=f.oid
   WHERE p.proacl IS NOT NULL AND p.prosecdef=f.expected_definer
     AND p.provolatile='s' AND p.prorettype='jsonb'::regtype
     AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg IN ('search_path=""','search_path='))
     AND has_function_privilege('authenticated',f.oid,'EXECUTE')
     AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) acl
                     WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
     AND (NOT f.expected_definer OR NOT has_function_privilege('anon',f.oid,'EXECUTE'));
  IF v_count<>4 THEN
    RAISE EXCEPTION 'REFUSE ACCESS01 unexpected function or native ACL baseline';
  END IF;
  SELECT count(*) INTO v_public_anon FROM (VALUES
    ('public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)'::regprocedure),
    ('public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'::regprocedure)
  ) f(oid) WHERE has_function_privilege('anon',f.oid,'EXECUTE');
  IF v_public_anon NOT IN (0,2) THEN
    RAISE EXCEPTION 'REFUSE ACCESS01 unexpected mixed public REST anonymous ACL';
  END IF;
END
$access01_before$;

-- Only the two public wrappers; neither native function nor any GRANT touched.
-- Idempotent if this isolated clone already matches least-privilege production.
REVOKE EXECUTE ON FUNCTION public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid) FROM anon;

DO $access01_after$
DECLARE v_count integer;
BEGIN
 SELECT count(*) INTO v_count FROM (VALUES
    ('atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)'::regprocedure),
    ('atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'::regprocedure),
    ('public.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)'::regprocedure),
    ('public.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'::regprocedure)
 ) t(func_oid) JOIN pg_proc p ON p.oid=t.func_oid
 WHERE p.proacl IS NOT NULL
   AND NOT has_function_privilege('anon',t.func_oid,'EXECUTE')
   AND has_function_privilege('authenticated',t.func_oid,'EXECUTE')
   AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) acl
                   WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE');
 IF v_count<>4 THEN
   RAISE EXCEPTION 'REFUSE ACCESS01 anonymous ACL clone parity did not establish';
 END IF;
END
$access01_after$;
COMMIT;
