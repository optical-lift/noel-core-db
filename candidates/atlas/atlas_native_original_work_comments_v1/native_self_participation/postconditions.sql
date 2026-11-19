DO $proof$
BEGIN
 IF to_regprocedure('atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('anon','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('service_role','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR to_regclass('atlas.native_self_participation_active_v1') IS NULL
 OR to_regclass('atlas.native_self_participation_action_v1') IS NULL
 OR to_regclass('atlas.work_allocations_one_active_responsible_idx') IS NULL
 THEN RAISE EXCEPTION 'Native participation internal custody postcondition failed'; END IF;
END
$proof$;
