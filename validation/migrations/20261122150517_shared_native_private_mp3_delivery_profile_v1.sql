-- Held source postconditions for the protected disposable production-schema
-- clone and the already existing isolated listening proof. READ-ONLY.
-- This is not a signed-user admission test or release approval.
DO $private_mp3_post$
DECLARE v_function oid; v_definition text;
BEGIN
  v_function:=to_regprocedure('public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)');
  IF v_function IS NULL THEN
    RAISE EXCEPTION 'Fixed private MP3 profile operation missing'; END IF;
  SELECT pg_get_functiondef(v_function) INTO v_definition;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_function)
    OR (SELECT proconfig FROM pg_proc WHERE oid=v_function)
       IS DISTINCT FROM ARRAY['search_path=pg_catalog']
    OR v_definition NOT LIKE '%auth.uid()%'
    OR v_definition NOT LIKE '%auth.jwt()%'
    OR v_definition NOT LIKE '%auth.sessions%'
    OR v_definition NOT LIKE '%workspace_memberships%'
    OR v_definition NOT LIKE '%private_audiobook_mp3%'
    OR v_definition NOT LIKE '%native_private_mp3_v1%'
    OR v_definition NOT LIKE '%publication_approved%'
  THEN RAISE EXCEPTION 'Fixed profile source or identity boundary changed'; END IF;
  IF NOT has_function_privilege('authenticated',v_function,'EXECUTE')
    OR has_function_privilege('anon',v_function,'EXECUTE')
    OR has_function_privilege('service_role',v_function,'EXECUTE')
  THEN RAISE EXCEPTION 'Unexpected private MP3 profile RPC grant'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='transcript_core.delivery_profiles'::regclass)
    OR has_table_privilege('authenticated','transcript_core.delivery_profiles','SELECT')
    OR has_table_privilege('authenticated','transcript_core.delivery_profiles','INSERT')
    OR has_table_privilege('service_role','transcript_core.delivery_profiles','SELECT')
    OR has_table_privilege('service_role','transcript_core.delivery_profiles','INSERT')
  THEN RAISE EXCEPTION 'Private delivery profile table exposure'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='transcript_core.delivery_profiles'::regclass
    AND c.contype='u' AND pg_get_constraintdef(c.oid)
      LIKE 'UNIQUE (workspace_id, profile_key, rule_version)%'
  ) THEN RAISE EXCEPTION 'Native profile version uniqueness missing'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='transcript_core_private_mp3_profile_self_api_v1')<>1
  THEN RAISE EXCEPTION 'Ambiguous fixed private profile overload'; END IF;
END $private_mp3_post$;
SELECT 'PASS held exact private MP3 profile source, grants and native table boundary' AS result;
