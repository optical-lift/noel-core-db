-- Run against isolated source/schema clone only, not live writes.
DO $proof$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY[
 'atlas.prepare_course_authoring_proposal_service_v1(text,uuid,jsonb)',
 'atlas.apply_course_authoring_proposal_service_v1(text,uuid,jsonb)',
 'atlas.validate_course_authoring_proposal_v1(jsonb,uuid)',
 'atlas.course_authoring_receipt_v1(uuid)']
 LOOP
  IF to_regprocedure(f) IS NULL OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
   OR has_function_privilege('service_role',f,'EXECUTE') IS DISTINCT FROM (f LIKE '%_service_v1(%') THEN
   RAISE EXCEPTION 'delegated Course function ACL mismatch: %',f; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM atlas.agent_command_definitions WHERE command_key='teaching.course.authoring.apply_proposal'
  AND command_version=1 AND scope_kind='personal' AND execution_class='commit' AND confirmation_requirement='principal_explicit'
  AND target_contract='{"kind":"teaching_course"}'::jsonb) THEN RAISE EXCEPTION 'missing command definition';END IF;
 IF EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations WHERE 'teaching.course.authoring.apply_proposal'=ANY(allowed_command_keys))
 THEN RAISE EXCEPTION 'candidate must not issue grants'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_units WHERE created_by_agent_invocation_id IS NOT NULL)
  OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id IS NOT NULL)
 THEN RAISE EXCEPTION 'candidate must not populate Course'; END IF;
END $proof$;
