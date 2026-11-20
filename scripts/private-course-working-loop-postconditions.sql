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
-- Run only on the disposable clone after applying candidate.sql.
DO $verify$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'atlas.require_private_course_read_grant_v1(text,uuid)',
  'atlas.read_private_course_outline_service_v1(text,uuid)',
  'atlas.read_private_course_unit_service_v1(text,uuid,uuid)',
  'public.shared_delegated_course_outline_read_service_v1(text,uuid)',
  'public.shared_delegated_course_unit_read_service_v1(text,uuid,uuid)'
 ] LOOP
  IF to_regprocedure(signature) IS NULL THEN RAISE EXCEPTION 'missing Course read function: %',signature; END IF;
  IF has_function_privilege('anon',signature,'EXECUTE')
    OR has_function_privilege('authenticated',signature,'EXECUTE') THEN
   RAISE EXCEPTION 'Course read function exposed: %',signature;
  END IF;
 END LOOP;
 FOREACH signature IN ARRAY ARRAY[
  'public.shared_delegated_course_outline_read_service_v1(text,uuid)',
  'public.shared_delegated_course_unit_read_service_v1(text,uuid,uuid)'
 ] LOOP
  IF NOT has_function_privilege('service_role',signature,'EXECUTE') THEN
   RAISE EXCEPTION 'service facade unavailable: %',signature;
  END IF;
 END LOOP;
 IF has_function_privilege('service_role','atlas.require_private_course_read_grant_v1(text,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'internal grant guard exposed to service_role';
 END IF;
END $verify$;
