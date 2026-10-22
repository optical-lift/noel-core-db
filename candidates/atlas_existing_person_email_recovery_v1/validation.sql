-- Postconditions for disposable schema-clone validation.
DO $checks$
DECLARE
  v_begin regprocedure := to_regprocedure('atlas.service_begin_person_email_recovery_v1(uuid,uuid,text,text,text)');
  v_verify regprocedure := to_regprocedure('atlas.service_verify_person_email_recovery_v1(uuid,text)');
  v_approve regprocedure := to_regprocedure('atlas.service_approve_person_email_recovery_v1(uuid,uuid,text,text)');
  v_finish regprocedure := to_regprocedure('atlas.service_finish_person_email_recovery_v1(uuid)');
BEGIN
  IF v_begin IS NULL OR v_verify IS NULL OR v_approve IS NULL OR v_finish IS NULL THEN
    RAISE EXCEPTION 'Missing governed recovery source routines.';
  END IF;
  IF has_function_privilege('anon',v_begin,'EXECUTE')
    OR has_function_privilege('authenticated',v_begin,'EXECUTE')
    OR has_function_privilege('anon',v_verify,'EXECUTE')
    OR has_function_privilege('authenticated',v_verify,'EXECUTE')
    OR has_function_privilege('anon',v_approve,'EXECUTE')
    OR has_function_privilege('authenticated',v_approve,'EXECUTE') THEN
    RAISE EXCEPTION 'Recovery service must not be available to browser roles.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='person_email_recovery_cases' AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Recovery cases require row security.';
  END IF;
END
$checks$;
