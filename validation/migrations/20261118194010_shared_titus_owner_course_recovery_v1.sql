-- Schema-clone postconditions, no data restoration or owner activation.
DO $check$
DECLARE fname text; t text;
BEGIN
 FOREACH fname IN ARRAY ARRAY[
   'public.shared_teaching_course_adopt_self_api_v1(uuid)',
   'titus.guard_adopted_customer_course_history_v1()',
   'titus.authoring_grant_current_active_v1(uuid)']
 LOOP
  IF to_regprocedure(fname) IS NULL
    OR has_function_privilege('anon',fname,'EXECUTE')
    OR has_function_privilege('service_role',fname,'EXECUTE')
  THEN RAISE EXCEPTION 'owner source custody or ACL failed'; END IF;
  IF has_function_privilege('authenticated',fname,'EXECUTE')
      IS DISTINCT FROM (fname='public.shared_teaching_course_adopt_self_api_v1(uuid)')
  THEN RAISE EXCEPTION 'owner source authenticated ACL failed'; END IF;
 END LOOP;
 FOREACH t IN ARRAY ARRAY['customer_course_drafts_v1','customer_course_material_revisions_v1',
  'customer_course_units_v1','customer_course_unit_revisions_v1']
 LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger
    WHERE tgrelid=to_regclass('titus.'||t)
    AND tgname='adopted_customer_course_history_v1' AND NOT tgisinternal AND tgenabled='O'
    AND tgfoid=to_regprocedure('titus.guard_adopted_customer_course_history_v1()'))
  THEN RAISE EXCEPTION 'historical write freeze missing'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM reality.responsibility_relations WHERE responsibility_key='titus_private_pilot_issuance')
  OR EXISTS(SELECT 1 FROM titus.course_authoring_access_grants)
  OR EXISTS(SELECT 1 FROM atlas.teaching_courses WHERE created_by_person_entity_id IS NOT NULL)
 THEN RAISE EXCEPTION 'schema-only clone unexpectedly seeded authority or Courses'; END IF;
END $check$;
