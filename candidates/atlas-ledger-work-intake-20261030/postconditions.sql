-- STRUCTURAL postconditions only. Signed clone required for authority/privacy.
DO $check$
DECLARE total integer;
BEGIN
 SELECT count(*) INTO total FROM information_schema.tables
 WHERE table_schema='atlas' AND table_name IN
 ('ledger_work_intakes','ledger_work_intake_decisions');
 IF total<>2 THEN RAISE EXCEPTION 'Missing native intake source tables';END IF;
 SELECT count(*) INTO total FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('submit_ledger_work_self_api_v1','ledger_work_inbox_root_self_api_v1',
  'ledger_work_submission_status_self_api_v1','decide_ledger_work_intake_root_self_api_v1');
 IF total<>4 THEN RAISE EXCEPTION 'Native Ledger intake public facades missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname='ledger_work_intakes' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Private intake must be RLS-enabled';END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname IN ('ledger_work_intakes','ledger_work_intake_decisions')
     AND has_table_privilege('authenticated',c.oid,'SELECT'))
 THEN RAISE EXCEPTION 'No direct employee table access';END IF;
END;
$check$;
