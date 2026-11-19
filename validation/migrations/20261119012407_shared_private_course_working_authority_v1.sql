DO $contracts$
DECLARE f text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM atlas.agent_command_definitions WHERE command_key='teaching.course.authoring.apply_proposal' AND command_version=1
    AND confirmation_requirement='principal_explicit' AND execution_class='commit') OR
  NOT EXISTS(SELECT 1 FROM atlas.agent_command_definitions WHERE command_key='teaching.course.authoring.save_draft' AND command_version=1
    AND confirmation_requirement='none' AND execution_class='commit' AND scope_kind='personal')
 THEN RAISE EXCEPTION 'distinct working and reviewed command contract missing';END IF;
 f:='public.shared_delegated_course_save_draft_service_v1(text,uuid,jsonb)';
 IF NOT has_function_privilege('service_role',f,'EXECUTE') OR has_function_privilege('anon',f,'EXECUTE')
   OR has_function_privilege('authenticated',f,'EXECUTE') OR (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(f))
 THEN RAISE EXCEPTION 'working service facade ACL mismatch'; END IF;
 f:='atlas.execute_private_course_authoring_v2(text,uuid,jsonb,text)';
 IF has_function_privilege('service_role',f,'EXECUTE') OR has_function_privilege('anon',f,'EXECUTE')
   OR has_function_privilege('authenticated',f,'EXECUTE') THEN RAISE EXCEPTION 'shared writer exposed';END IF;
 FOREACH f IN ARRAY ARRAY['public.shared_private_atlas_carrier_enroll_working_self_api_v1(uuid,timestamptz)',
  'public.shared_private_atlas_carrier_status_self_api_v2()','public.shared_private_atlas_carrier_revoke_self_api_v2(uuid)'] LOOP
  IF NOT has_function_privilege('authenticated',f,'EXECUTE') OR has_function_privilege('anon',f,'EXECUTE')
   OR has_function_privilege('service_role',f,'EXECUTE') THEN RAISE EXCEPTION 'working signed boundary mismatch';END IF;
 END LOOP;
END $contracts$;
