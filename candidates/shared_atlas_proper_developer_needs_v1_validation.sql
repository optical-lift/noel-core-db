-- Bounded structural postconditions for local production-schema clone.
DO $test$
DECLARE body text;
BEGIN
 IF to_regclass('atlas.implementation_discovery_needs_v1') IS NULL
    OR to_regclass('atlas.implementation_discovery_need_activity_v1') IS NULL
    OR to_regprocedure('public.implementation_discovery_subject_work_self_api_v1(uuid)') IS NULL
    OR to_regprocedure('public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text)') IS NULL
    OR to_regprocedure('public.record_implementation_discovery_activity_self_api_v1(uuid,uuid,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'Atlas Proper actionable Discovery source incomplete'; END IF;
 IF has_table_privilege('anon','atlas.implementation_discovery_needs_v1','SELECT')
    OR has_table_privilege('authenticated','atlas.implementation_discovery_needs_v1','SELECT')
    OR has_table_privilege('service_role','atlas.implementation_discovery_needs_v1','INSERT')
 THEN RAISE EXCEPTION 'Developer work table rights leaked'; END IF;
 IF has_function_privilege('anon','public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Developer work RPC grants are unsafe'; END IF;
 SELECT pg_get_functiondef('atlas.implementation_discovery_subject_guard_self_v1(uuid)'::regprocedure) INTO body;
 IF body NOT ILIKE '%implementation_foundry_discovery_inventory_self_api_v1%'
 THEN RAISE EXCEPTION 'Independent practitioner/canonical source guard missing'; END IF;
 BEGIN
  PERFORM atlas.implementation_discovery_subject_work_self_api_v1('f1900000-0000-4000-8000-000000000499'::uuid);
  RAISE EXCEPTION 'Unsigned caller unexpectedly opened developer workspace';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
