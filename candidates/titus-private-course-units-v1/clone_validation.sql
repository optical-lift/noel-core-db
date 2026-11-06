-- READ-ONLY structural checks on the disposable PG17 scratch database.
-- No real customers, no production writes, and no seeded courses.
DO $v$ DECLARE f text;
BEGIN
 IF (SELECT count(*) FROM titus.customer_course_units_v1)<>0 OR
    (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>0 THEN
  RAISE EXCEPTION 'Unit candidate seeded data';
 END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='titus.customer_course_units_v1'::regclass) OR
    NOT (SELECT relrowsecurity FROM pg_class WHERE oid='titus.customer_course_unit_revisions_v1'::regclass) THEN
  RAISE EXCEPTION 'Unit table RLS missing';
 END IF;
 FOREACH f IN ARRAY ARRAY[
   'public.titus_customer_outline_read_self_api_v1(uuid)',
   'public.titus_customer_unit_create_self_api_v1(uuid,uuid,text,text)',
   'public.titus_customer_unit_move_self_api_v1(uuid,uuid,text)',
   'public.titus_customer_unit_read_self_api_v1(uuid)',
   'public.titus_customer_unit_save_self_api_v1(uuid,uuid,integer,text)']
 LOOP
  IF to_regprocedure(f) IS NULL OR
   NOT has_function_privilege('authenticated',f,'EXECUTE') OR
   has_function_privilege('anon',f,'EXECUTE') OR
   has_function_privilege('service_role',f,'EXECUTE') THEN
   RAISE EXCEPTION 'Unexpected guarded Unit RPC privileges: %',f;
  END IF;
 END LOOP;
 IF has_function_privilege('authenticated','titus.customer_owned_course_for_units_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'Internal helper exposed';
 END IF;
 IF has_table_privilege('authenticated','titus.customer_course_units_v1','SELECT') OR
    has_table_privilege('authenticated','titus.customer_course_unit_revisions_v1','INSERT') OR
    has_table_privilege('anon','titus.customer_course_units_v1','SELECT') OR
    has_table_privilege('service_role','titus.customer_course_unit_revisions_v1','SELECT') THEN
  RAISE EXCEPTION 'Direct private Unit table access exposed';
 END IF;
END $v$;
SELECT 'PASS: units candidate closed, unseeded, authenticated-only guarded RPCs' AS result;
