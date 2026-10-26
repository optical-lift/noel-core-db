BEGIN;
DO $checks$
DECLARE v int;
BEGIN
 SELECT count(*) INTO v FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN (
 'prepare_existing_person_auth_replacement_self_api_v1',
 'consent_existing_person_auth_replacement_old_self_api_v1',
 'plan_existing_person_auth_replacement_self_api_v1',
 'finish_existing_person_auth_replacement_self_api_v1');
 IF v<>4 THEN RAISE EXCEPTION 'Replacement RPC count incorrect: %',v; END IF;
 IF has_function_privilege('anon',
   'public.finish_existing_person_auth_replacement_self_api_v1(uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous replacement permitted'; END IF;
 IF NOT has_function_privilege('authenticated',
   'public.finish_existing_person_auth_replacement_self_api_v1(uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Authenticated wrapper missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name='existing_person_auth_claim_cases'
     AND column_name='old_account_consented_session_id')
 THEN RAISE EXCEPTION 'Old user signed consent proof missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_indexes
   WHERE schemaname='reality' AND tablename='auth_person_bindings'
     AND indexname='reality_auth_one_active_person_shared_v1')
 THEN RAISE EXCEPTION 'Competing active Person uniqueness not present'; END IF;
END $checks$;
COMMIT;
