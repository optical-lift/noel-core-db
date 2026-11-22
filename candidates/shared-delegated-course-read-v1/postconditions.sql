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
