-- Disposable clone postconditions only.
DO $verify$
DECLARE sig text;
BEGIN
 IF to_regprocedure('atlas.require_private_course_management_v1(text,uuid,text,boolean)') IS NULL
  OR to_regprocedure('public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)') IS NULL
  OR to_regprocedure('public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'SK101 management facade missing'; END IF;
 FOREACH sig IN ARRAY ARRAY[
  'public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)',
  'public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)'
 ] LOOP
  IF has_function_privilege('anon',sig,'EXECUTE')
   OR has_function_privilege('authenticated',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'management facade exposed: %',sig; END IF;
 END LOOP;
 IF NOT has_function_privilege('service_role','public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)','EXECUTE')
  OR NOT has_function_privilege('service_role','public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'service facade ACL missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.agent_command_definitions WHERE command_key='teaching.course.management.read' AND status='active')
  OR NOT EXISTS(SELECT 1 FROM atlas.agent_command_definitions WHERE command_key='teaching.course.management.write' AND status='active')
 THEN RAISE EXCEPTION 'management command admission missing'; END IF;
END $verify$;
