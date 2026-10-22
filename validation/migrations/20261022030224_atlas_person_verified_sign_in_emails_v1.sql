-- Disposable schema-clone postconditions. Do not execute against live data.
DO $validation$
DECLARE
  v_read regprocedure:=to_regprocedure('public.person_sign_in_emails_self_api_v1()');
  v_sync regprocedure:=to_regprocedure('public.reconcile_person_native_sign_in_email_self_api_v1()');
  v_internal regprocedure:=to_regprocedure('atlas.reconcile_person_native_sign_in_email_self_api_v1()');
BEGIN
  IF v_read IS NULL OR v_sync IS NULL OR v_internal IS NULL THEN
    RAISE EXCEPTION 'Person multi-email read/reconciliation source missing.';
  END IF;
  IF has_function_privilege('anon',v_read,'EXECUTE')
    OR has_function_privilege('anon',v_sync,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_read,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_sync,'EXECUTE')
    OR has_function_privilege('authenticated',v_internal,'EXECUTE') THEN
    RAISE EXCEPTION 'Person email RPC is exposed across the wrong boundary.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='person_sign_in_emails' AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'Person email registry RLS required.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=v_internal
    AND p.prosecdef
    AND pg_get_functiondef(p.oid) LIKE '%auth.uid()%'
    AND pg_get_functiondef(p.oid) LIKE '%person_auth_credentials%'
    AND pg_get_functiondef(p.oid) LIKE '%email_confirmed_at%'
    AND pg_get_functiondef(p.oid) LIKE '%person_id%') THEN
    RAISE EXCEPTION 'Person/verified Auth custody insufficiently guarded.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes i
    WHERE i.schemaname='atlas' AND i.indexname='person_sign_in_one_preferred_v1')
    OR NOT EXISTS (SELECT 1 FROM pg_indexes i
    WHERE i.schemaname='atlas' AND i.indexname='person_sign_in_verified_address_unique_v1') THEN
    RAISE EXCEPTION 'Uniqueness of preferred/verified addresses is required.';
  END IF;
END
$validation$;
