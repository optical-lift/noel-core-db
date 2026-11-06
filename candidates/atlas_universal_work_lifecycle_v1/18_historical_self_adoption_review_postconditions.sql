-- HELD disposable-clone postconditions, never a production write.
DO $checks$
DECLARE v_oid oid; v_sql text; v_rls record;
BEGIN
 SELECT c.relrowsecurity,c.relforcerowsecurity INTO v_rls
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='atlas' AND c.relname='historical_self_adoption_review_events_v1';
 IF v_rls IS NULL OR NOT v_rls.relrowsecurity OR NOT v_rls.relforcerowsecurity THEN
  RAISE EXCEPTION 'Historical evidence table must be RLS-forced' USING ERRCODE='42501';
 END IF;
 IF has_table_privilege('anon','atlas.historical_self_adoption_review_events_v1','SELECT')
   OR has_table_privilege('authenticated','atlas.historical_self_adoption_review_events_v1','SELECT')
   OR has_table_privilege('authenticated','atlas.historical_self_adoption_review_events_v1','INSERT')
   OR has_table_privilege('authenticated','atlas.historical_self_adoption_review_events_v1','UPDATE')
   OR has_table_privilege('authenticated','atlas.historical_self_adoption_review_events_v1','DELETE')
 THEN RAISE EXCEPTION 'Raw historical source leaked to app role' USING ERRCODE='42501'; END IF;
 FOR v_oid IN SELECT unnest(ARRAY[
  to_regprocedure('atlas.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)'),
  to_regprocedure('atlas.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)'),
  to_regprocedure('atlas.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)'),
  to_regprocedure('atlas.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)')
 ]::regprocedure[])::oid LOOP
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Missing exact historical API'; END IF;
  IF has_function_privilege('anon',v_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
  THEN RAISE EXCEPTION 'Historical API wrong call authority' USING ERRCODE='42501'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_sql;
  IF position('organization_memberships' in v_sql)>0
     OR position('employee_seats' in v_sql)>0 THEN
    RAISE EXCEPTION 'Legacy membership reintroduced in historical API' USING ERRCODE='42501';
  END IF;
 END LOOP;
 FOR v_oid IN SELECT unnest(ARRAY[
  to_regprocedure('public.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)'),
  to_regprocedure('public.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)'),
  to_regprocedure('public.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)'),
  to_regprocedure('public.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)')
 ]::regprocedure[])::oid LOOP
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Missing historical public REST wrapper'; END IF;
  IF has_function_privilege('anon',v_oid,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
  THEN RAISE EXCEPTION 'Historical REST wrapper wrong call authority' USING ERRCODE='42501'; END IF;
 END LOOP;
 IF to_regprocedure('atlas.reject_historical_review_mutation_v1()') IS NULL
   OR NOT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      WHERE c.oid='atlas.historical_self_adoption_review_events_v1'::regclass
        AND t.tgname='reject_historical_review_mutation_v1' AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'Historical review immutability not enforced' USING ERRCODE='42501'; END IF;
 RAISE NOTICE 'PASS structural native historical review; real signed negative tests remain required';
END; $checks$;
