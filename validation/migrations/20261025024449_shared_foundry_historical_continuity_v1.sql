-- SOURCE ONLY: execute after both historical continuity SQL candidates in
-- a disposable production-schema clone. This file must never write customer
-- history or forge real founder/signed session receipts.
DO $audit$
DECLARE
 f text;
 decl text;
 row_cnt integer;
BEGIN
 IF to_regprocedure('atlas.foundry_historical_eligible_self_v1(text,uuid)') IS NULL
   OR to_regprocedure('public.list_foundry_historical_recovery_candidates_self_api_v1()') IS NULL
   OR to_regprocedure('public.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean)') IS NULL
   OR to_regprocedure('public.list_foundry_workspace_history_self_api_v1(text,bigint,integer)') IS NULL
   OR to_regprocedure('public.get_foundry_workspace_event_self_api_v1(text,text)') IS NULL
   OR to_regprocedure('public.get_foundry_existing_implementation_context_self_api_v1(text)') IS NULL
   OR to_regprocedure('public.identify_foundry_as_personal_implementation_source_self_api_v1(text)') IS NULL
 THEN RAISE EXCEPTION 'Historical Foundry continuity RPC missing'; END IF;

 FOREACH f IN ARRAY ARRAY[
   'list_foundry_historical_recovery_candidates_self_api_v1()',
   'recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean)',
   'list_foundry_workspace_history_self_api_v1(text,bigint,integer)',
   'get_foundry_workspace_event_self_api_v1(text,text)',
   'get_foundry_existing_implementation_context_self_api_v1(text)',
   'identify_foundry_as_personal_implementation_source_self_api_v1(text)'
 ] LOOP
   IF has_function_privilege('anon','public.'||f,'EXECUTE')
     OR has_function_privilege('service_role','public.'||f,'EXECUTE')
     OR NOT has_function_privilege('authenticated','public.'||f,'EXECUTE')
   THEN RAISE EXCEPTION 'Forbidden or missing Foundry HTTP function privilege: %',f; END IF;
 END LOOP;
 SELECT pg_get_functiondef('atlas.foundry_historical_eligible_self_v1(text,uuid)'::regprocedure) INTO decl;
 IF decl NOT ILIKE '%every%' AND decl NOT ILIKE '%NOT EXISTS%' THEN
   RAISE EXCEPTION 'Historical Ledger coverage condition missing'; END IF;
 IF decl NOT ILIKE '%another.principal_id<>p_principal_id%'
 THEN RAISE EXCEPTION 'Missing exclusive-root private source protection'; END IF;

 SELECT pg_get_functiondef('atlas.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean)'::regprocedure) INTO decl;
 IF decl NOT ILIKE '%foundry_current_signed_principal_v1%'
    OR decl NOT ILIKE '%p_confirm_original_history IS DISTINCT FROM true%'
    OR decl NOT ILIKE '%foundry.append_event%'
    OR decl NOT ILIKE '%creation_request_id=p_request_id%'
 THEN RAISE EXCEPTION 'Unsigned or non-idempotent recovery command'; END IF;

 SELECT pg_get_functiondef('atlas.list_foundry_workspace_history_self_api_v1(text,bigint,integer)'::regprocedure) INTO decl;
 IF decl NOT ILIKE '%owner_principal_id=actor%'
    OR decl NOT ILIKE '%LEAST(25%'
 THEN RAISE EXCEPTION 'History is not owner-scoped and bounded'; END IF;

 SELECT pg_get_functiondef(
 'atlas.identify_foundry_as_personal_implementation_source_self_api_v1(text)'::regprocedure)
 INTO decl;
 IF decl NOT ILIKE '%owner_principal_id=actor%'
    OR decl NOT ILIKE '%personal_atlas%'
    OR decl NOT ILIKE '%sourceReadAuthorized%'
    OR decl NOT ILIKE '%source_state%'
 THEN RAISE EXCEPTION 'Foundry personal source registration bypasses ownership or source-only state'; END IF;

 SELECT count(*) INTO row_cnt FROM foundry.events;
 IF row_cnt<0 THEN RAISE EXCEPTION 'Impossible source custody baseline'; END IF;
END $audit$;

-- Unsigned RPCs are always denied. Real successful owner/outsider/worker
-- HTTP, revocation and exact-original-event tests require a separate signed
-- GoTrue fixture on a disposable clone; never claim these static tests do it.
DO $audit$
BEGIN
 BEGIN
   PERFORM atlas.list_foundry_historical_recovery_candidates_self_api_v1();
   RAISE EXCEPTION 'Unsigned candidate lookup unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
   PERFORM atlas.list_foundry_workspace_history_self_api_v1('synthetic-missing-workspace',0,20);
   RAISE EXCEPTION 'Unsigned historic read unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $audit$;
