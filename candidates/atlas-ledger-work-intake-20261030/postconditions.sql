-- STRUCTURAL postconditions only. Signed clone required for authority/privacy.
DO $check$
DECLARE total integer; submit_source text;
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
 -- PostgREST named-argument routing must match the actual signed caller
 -- payload. A function present in pg_proc but with unnamed arguments yields
 -- PGRST202 instead of executing the source permission gate (not 42501).
 IF NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='submit_ledger_work_self_api_v1'
     AND p.proargnames=ARRAY['p_ledger_id','p_title','p_attention_date_proposal','p_source_action_id']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ledger_work_inbox_root_self_api_v1'
     AND p.proargnames=ARRAY['p_ledger_id','p_limit']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ledger_work_submission_status_self_api_v1'
     AND p.proargnames=ARRAY['p_intake_id']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decide_ledger_work_intake_root_self_api_v1'
     AND p.proargnames=ARRAY['p_intake_id','p_decision','p_expected_revision','p_reason']::text[]
 ) THEN RAISE EXCEPTION 'Native Ledger intake named RPC arguments mismatch REST caller';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname='ledger_work_intakes' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Private intake must be RLS-enabled';END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname IN ('ledger_work_intakes','ledger_work_intake_decisions')
     AND has_table_privilege('authenticated',c.oid,'SELECT'))
 THEN RAISE EXCEPTION 'No direct employee table access';END IF;
 -- General original Work must not duplicate the submitter's Person identifier,
 -- raw action key, or Ledger identity in freeform metadata. Restricted intake
 -- and exact native Ledger relevance remain the only identity-bearing custody.
 submit_source:=pg_get_functiondef('atlas.submit_ledger_work_self_api_v1(uuid,text,date,text)'::regprocedure);
 IF position('''submittedByPersonId''' IN submit_source)>0
    OR position('''sourceActionId''' IN submit_source)>0
    OR position('''nativeLedgerId''' IN submit_source)>0
 THEN RAISE EXCEPTION 'Sensitive identity copied into original Work metadata';END IF;
END;
$check$;
