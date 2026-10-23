-- Protected-clone postconditions for source-only claim candidate.
-- Does not create a real Auth identity, Person, Ledger, invitation, or seat.
-- Signed real-user positive/negative tests and old-session replay MUST run
-- on a disposable Auth-backed clone before any production release.
DO $test$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s
 ON s.oid=p.pronamespace WHERE s.nspname='public'
 AND p.proname IN (
 'prepare_existing_person_auth_claim_self_api_v1',
 'accept_existing_person_auth_claim_self_api_v1',
 'approve_existing_person_auth_claim_self_api_v1',
 'finish_existing_person_auth_claim_self_api_v1'
 );
 IF n<>4 THEN RAISE EXCEPTION 'Claim public membrane incomplete'; END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
 WHERE s.nspname='public' AND p.proname LIKE '%existing_person_auth_claim%'
 AND (p.prosecdef OR has_function_privilege('anon',p.oid,'EXECUTE'))) THEN
  RAISE EXCEPTION 'Claim membrane must be invoker and deny anonymous';
 END IF;
 IF has_table_privilege('authenticated',
  'atlas.existing_person_auth_claim_cases','SELECT') THEN
  RAISE EXCEPTION 'Private identity cases exposed to authenticated role';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n
    ON n.oid=c.relnamespace WHERE n.nspname='atlas'
    AND c.relname='existing_person_auth_claim_cases'
    AND c.relrowsecurity) THEN
   RAISE EXCEPTION 'Private claim table RLS missing';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_indexes
   WHERE schemaname='atlas' AND tablename='person_auth_credentials'
     AND indexname='person_auth_one_active_person_shared_v1') THEN
   RAISE EXCEPTION 'Active Person credential uniqueness missing';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_indexes
   WHERE schemaname='reality' AND tablename='auth_person_bindings'
     AND indexname='reality_auth_one_active_person_shared_v1'
 ) THEN
    RAISE EXCEPTION 'Reality active Person uniqueness gate missing';
 END IF;
END $test$;
