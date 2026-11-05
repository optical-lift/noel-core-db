-- READ-ONLY structural validation for a newly applied Titus material migration.
-- SAFE ON A PRODUCTION-SHAPED CLONE; NO fixture users, grants, sample Courses,
-- entitlement rows, or manuscript edits. This is not an authorization smoke.
-- Synthetic signed-shaped behavior remains isolated in postconditions.sql.
DO $titus_material_clone_validate$
DECLARE
 v_class oid;
 v_read oid;
 v_save oid;
 v_role text;
 v_priv text;
BEGIN
 v_class:=to_regclass('titus.customer_course_material_revisions_v1');
 IF v_class IS NULL THEN
  RAISE EXCEPTION 'Titus material revisions table is missing';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_class WHERE oid=v_class
   AND relrowsecurity AND relkind='r'
 ) THEN
  RAISE EXCEPTION 'Titus private material RLS/table contract missing';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>0 THEN
  RAISE EXCEPTION 'A new Titus material migration must not seed authoring data';
 END IF;

 v_read:=to_regprocedure('public.titus_customer_material_read_self_api_v1(uuid)');
 v_save:=to_regprocedure('public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)');
 IF v_read IS NULL OR v_save IS NULL THEN
  RAISE EXCEPTION 'Source-guarded Titus authoring functions are missing';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_proc WHERE oid=v_read
    AND prosecdef AND provolatile='v'
 ) OR NOT EXISTS(
  SELECT 1 FROM pg_proc WHERE oid=v_save
    AND prosecdef AND provolatile='v'
 ) THEN
  RAISE EXCEPTION 'Material functions must preserve reviewed guarded signatures';
 END IF;
 IF NOT has_function_privilege('authenticated',v_read,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_save,'EXECUTE') THEN
  RAISE EXCEPTION 'Authenticated actor lacks guarded material function access';
 END IF;
 IF has_function_privilege('anon',v_read,'EXECUTE')
    OR has_function_privilege('anon',v_save,'EXECUTE') THEN
  RAISE EXCEPTION 'Anonymous actor may call private material function';
 END IF;
 IF has_function_privilege('service_role',v_read,'EXECUTE')
    OR has_function_privilege('service_role',v_save,'EXECUTE') THEN
  RAISE EXCEPTION 'Service-role transport may call private signed-user material function';
 END IF;
 FOR v_role IN SELECT rolname FROM pg_roles
   WHERE rolname IN ('authenticated','anon','service_role')
 LOOP
  FOREACH v_priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
   IF has_table_privilege(v_role,'titus.customer_course_material_revisions_v1',v_priv) THEN
    RAISE EXCEPTION 'Role % has direct % on private Titus material',v_role,v_priv;
   END IF;
  END LOOP;
 END LOOP;
END;
$titus_material_clone_validate$;
