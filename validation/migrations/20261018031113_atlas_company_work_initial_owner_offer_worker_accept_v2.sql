DO $verify$
BEGIN
 IF to_regclass('atlas.company_work_initial_responsibility_offers') IS NULL
    THEN RAISE EXCEPTION 'Missing institution-owned initial offer table'; END IF;
 IF has_table_privilege('authenticated','atlas.company_work_initial_responsibility_offers','INSERT')
    OR has_table_privilege('authenticated','atlas.company_work_initial_responsibility_offers','SELECT')
    OR has_table_privilege('anon','atlas.company_work_initial_responsibility_offers','SELECT')
    THEN RAISE EXCEPTION 'Raw offer table improperly exposed'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.proname IN ('offer_unallocated_company_work_self_api_v1',
     'respond_unallocated_company_work_self_api_v1','company_work_initial_offers_self_api_v1',
     'withdraw_unallocated_company_work_offer_self_api_v1')
     AND n.nspname='public' AND NOT p.prosecdef)<>4
   THEN RAISE EXCEPTION 'All public transports must be invoker'; END IF;
 IF has_function_privilege('anon','public.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('anon','public.respond_unallocated_company_work_self_api_v1(uuid,text)','EXECUTE')
 OR has_function_privilege('anon','public.company_work_initial_offers_self_api_v1()','EXECUTE') OR has_function_privilege('anon','public.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Anon invocation not allowed'; END IF;
 IF NOT has_function_privilege('authenticated','public.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.respond_unallocated_company_work_self_api_v1(uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.company_work_initial_offers_self_api_v1()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Authenticated offer/response transport missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND indexname='company_work_initial_responsibility_one_pending_v1')
 THEN RAISE EXCEPTION 'Duplicate pending offer protection missing'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Native Ledger root authorization missing'; END IF;
 IF position('seat.ended_at IS NULL' IN
   pg_get_functiondef('atlas.company_work_initial_offers_self_api_v1()'::regprocedure))=0
 THEN RAISE EXCEPTION 'Worker offer read lacks active employee seat revocation guard'; END IF;
 IF position('withdrawn' IN
   pg_get_functiondef('atlas.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner must be able to withdraw an unanswered offer'; END IF;
 IF position('self_adoption' IN
   pg_get_functiondef('atlas.respond_unallocated_company_work_self_api_v1(uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Receiver-established allocation provenance missing'; END IF;
END
$verify$;
