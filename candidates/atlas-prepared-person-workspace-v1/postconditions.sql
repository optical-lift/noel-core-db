-- Run in an authorized disposable clone *after* applying candidate.sql.
-- These verify only structural boundaries; signed actors remain separate tests.
DO $check$
BEGIN
 IF EXISTS (
   SELECT 1 FROM information_schema.role_table_grants
   WHERE table_schema='atlas'
     AND table_name IN ('prepared_person_cases','prepared_person_items',
                        'prepared_person_decision_receipts',
                        'prepared_person_operator_grants')
     AND grantee IN ('anon','authenticated','PUBLIC')
 ) THEN
   RAISE EXCEPTION 'Direct table access must remain revoked';
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='atlas'
       AND c.relname IN ('prepared_person_cases','prepared_person_items',
                        'prepared_person_decision_receipts',
                        'prepared_person_operator_grants') AND c.relrowsecurity) <> 4 THEN
   RAISE EXCEPTION 'RLS must cover all prepared Person custody tables';
 END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas' AND p.proname LIKE 'prepared_person_%self_api_v1') <> 11 THEN
   RAISE EXCEPTION 'Prepared Person RPC surface incomplete';
 END IF;
END $check$;
