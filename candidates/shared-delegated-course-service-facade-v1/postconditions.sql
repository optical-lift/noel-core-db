DO $acl$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['public.shared_delegated_course_prepare_service_v1(text,uuid,jsonb)','public.shared_delegated_course_apply_service_v1(text,uuid,jsonb)'] LOOP
  IF to_regprocedure(f) IS NULL OR NOT has_function_privilege('service_role',f,'EXECUTE')
   OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
   OR (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(f))
  THEN RAISE EXCEPTION 'service facade ACL or invoker contract mismatch: %',f; END IF;
 END LOOP;
END $acl$;

DO $signed_acl$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['public.shared_private_atlas_carrier_status_self_api_v1()',
  'public.shared_private_atlas_carrier_enroll_self_api_v1(uuid,timestamptz)','public.shared_private_atlas_carrier_revoke_self_api_v1(uuid)']
 LOOP
  IF to_regprocedure(f) IS NULL OR NOT has_function_privilege('authenticated',f,'EXECUTE')
    OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('service_role',f,'EXECUTE')
  THEN RAISE EXCEPTION 'signed private carrier ACL mismatch: %',f; END IF;
 END LOOP;
END $signed_acl$;
