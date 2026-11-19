DO $proof$
BEGIN
 IF to_regprocedure('atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('anon','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('service_role','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR to_regclass('atlas.native_self_participation_active_v1') IS NULL
 OR to_regclass('atlas.native_self_participation_action_v1') IS NULL
 OR to_regclass('atlas.work_allocations_one_active_responsible_idx') IS NULL
 OR to_regprocedure('atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR to_regprocedure('atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='atlas.work_items'::regclass AND tgname='native_self_participation_work_terminal_v1' AND NOT tgisinternal)
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='atlas.work_allocations'::regclass AND tgname='native_self_participation_primary_release_v1' AND NOT tgisinternal)
 OR to_regprocedure('atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)','EXECUTE')
 OR to_regclass('atlas.native_direct_participation_actor_action_v1') IS NULL
 THEN RAISE EXCEPTION 'Native participation internal custody postcondition failed'; END IF;
END
$proof$;

-- Verify the exact release-candidate wrapper ACL, not a test-created adapter.
DO $rest$
DECLARE pair text; v_public oid; v_internal oid;
BEGIN
 FOREACH pair IN ARRAY ARRAY['connected_person_my_work_self_api_v2(integer,uuid)',
   'owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid)',
   'owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)',
   'native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)',
   'join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)',
   'leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)'] LOOP
   v_public:=to_regprocedure('public.'||pair); v_internal:=to_regprocedure('atlas.'||pair);
   IF v_public IS NULL OR v_internal IS NULL
     OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
     OR has_function_privilege('anon',v_public,'EXECUTE')
     OR has_function_privilege('service_role',v_public,'EXECUTE')
     OR has_function_privilege('authenticated',v_internal,'EXECUTE')
     OR has_function_privilege('anon',v_internal,'EXECUTE')
     OR has_function_privilege('service_role',v_internal,'EXECUTE')
     OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
       WHERE p.oid IN(v_public,v_internal) AND x.grantee=0 AND x.privilege_type='EXECUTE')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_public AND p.prosecdef AND ('search_path=""'=ANY(p.proconfig)))
   THEN RAISE EXCEPTION 'Shared Work REST custody differs: %',pair; END IF;
 END LOOP;
END
$rest$;
