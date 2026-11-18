-- Production-schema-clone postconditions, not production queries.
-- No historical row data required. The new authoring surfaces must be empty,
-- and the existing Atlas institutional root and Titus historical tables kept.
DO $verify$
DECLARE rel text; proc text;
BEGIN
 FOREACH rel IN ARRAY ARRAY[
 'atlas.teaching_course_manuscript_revisions','atlas.teaching_course_units',
 'atlas.teaching_course_unit_revisions','titus.course_authoring_access_grants',
 'titus.course_authoring_access_status_events','titus.course_authoring_pilot_codes',
 'titus.course_authoring_pilot_code_claims','titus.course_authoring_pilot_code_cancellations']
 LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=to_regclass(rel) AND c.relrowsecurity)
  OR has_table_privilege('anon',rel,'SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege('authenticated',rel,'SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege('service_role',rel,'SELECT,INSERT,UPDATE,DELETE')
  THEN RAISE EXCEPTION 'private authoring table absent or overly exposed: %',rel; END IF;
 END LOOP;
 FOREACH proc IN ARRAY ARRAY[
 'public.titus_authoring_access_self_api_v1()',
 'public.shared_teaching_course_create_self_api_v1(uuid,text)',
 'public.shared_teaching_course_catalog_self_api_v1()',
 'public.shared_teaching_course_material_read_self_api_v1(uuid)',
 'public.shared_teaching_course_material_save_self_api_v1(uuid,uuid,integer,text)',
 'public.shared_teaching_course_outline_read_self_api_v1(uuid)',
 'public.shared_teaching_course_unit_create_self_api_v1(uuid,uuid,text,text)',
 'public.shared_teaching_course_unit_move_self_api_v1(uuid,uuid,text)',
 'public.shared_teaching_course_unit_read_self_api_v1(uuid)',
 'public.shared_teaching_course_unit_save_self_api_v1(uuid,uuid,integer,text)',
 'public.titus_private_pilot_code_issue_self_api_v1(uuid)',
 'public.titus_private_pilot_code_claim_self_api_v1(text,uuid)',
 'public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid)',
 'public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)']
 LOOP
  IF to_regprocedure(proc) IS NULL
  OR has_function_privilege('anon',proc,'EXECUTE')
  OR has_function_privilege('service_role',proc,'EXECUTE')
  OR NOT has_function_privilege('authenticated',proc,'EXECUTE')
  THEN RAISE EXCEPTION 'authoring RPC ACL mismatch: %',proc; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='atlas.teaching_courses'::regclass
  AND conname='teaching_courses_complete_origin_v1' AND convalidated)
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.teaching_courses'::regclass
  AND tgname='teaching_courses_activation_guard_v1' AND tgqual IS NOT NULL AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.teaching_courses'::regclass
  AND tgname='teaching_courses_identity_immutable_v1' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.teaching_courses'::regclass
  AND tgname='teaching_courses_person_identity_immutable_v1' AND tgenabled='O')
 THEN RAISE EXCEPTION 'Course origin guard missing'; END IF;
 FOREACH rel IN ARRAY ARRAY['titus.customer_course_drafts_v1',
 'titus.customer_course_material_revisions_v1','titus.customer_course_units_v1',
 'titus.customer_course_unit_revisions_v1','titus.customer_workspace_entitlements_v1',
 'atlas.teaching_courses'] LOOP
  IF to_regclass(rel) IS NULL THEN RAISE EXCEPTION 'existing Course relation lost: %',rel; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM atlas.teaching_courses WHERE created_by_person_entity_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_manuscript_revisions)
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_units)
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_access_grants)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_access_status_events)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_pilot_codes)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_claims)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_cancellations)
 THEN RAISE EXCEPTION 'schema install seeded new authoring records'; END IF;
END $verify$;
