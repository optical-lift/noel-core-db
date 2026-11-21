-- Disposable clone only, after candidate.sql.
DO $verify$
BEGIN
 IF to_regprocedure('atlas.private_atlas_carrier_standing_grant_current_v1(uuid)') IS NULL
  OR to_regprocedure('public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid)') IS NULL THEN
  RAISE EXCEPTION 'standing grant source missing';
 END IF;
 IF has_function_privilege('anon','public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid)','EXECUTE')
  OR has_function_privilege('service_role','public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'standing enrollment ACL mismatch';
 END IF;
 IF has_function_privilege('anon','atlas.private_atlas_carrier_standing_grant_current_v1(uuid)','EXECUTE')
  OR has_function_privilege('authenticated','atlas.private_atlas_carrier_standing_grant_current_v1(uuid)','EXECUTE')
  OR has_function_privilege('service_role','atlas.private_atlas_carrier_standing_grant_current_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'internal standing predicate exposed';
 END IF;
END $verify$;
