BEGIN;
DO $check$
DECLARE v_count int;
BEGIN
 SELECT count(*)::integer INTO v_count
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='public'
    AND p.proname='existing_person_auth_transition_readiness_self_api_v1')
    OR (n.nspname='atlas'
    AND p.proname='existing_person_auth_transition_readiness_self_v1');
 IF v_count<>2 THEN
   RAISE EXCEPTION 'Expected exactly two transition readiness functions, found %',v_count;
 END IF;
 IF has_function_privilege('anon',
    'public.existing_person_auth_transition_readiness_self_api_v1(uuid,uuid)',
    'EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous account transition inspection not permitted';
 END IF;
 IF NOT has_function_privilege('authenticated',
    'public.existing_person_auth_transition_readiness_self_api_v1(uuid,uuid)',
    'EXECUTE') THEN
   RAISE EXCEPTION 'Authorized signed operator RPC not granted';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas'
   AND p.proname='existing_person_auth_transition_readiness_self_v1'
   AND p.prosecdef
 ) THEN
   RAISE EXCEPTION 'Protected owner read function missing';
 END IF;
END $check$;
COMMIT;
