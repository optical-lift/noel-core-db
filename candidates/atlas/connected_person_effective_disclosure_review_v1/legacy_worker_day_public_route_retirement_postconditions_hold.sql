-- Protected-clone-only ACL check for coordinated legacy Worker Day cutover.
-- Passing this does NOT establish no other definer, Vercel or farm GET pathway.
-- Run only after native Person owner+worker success/reader parity is established.
BEGIN;
DO $guard$
DECLARE
 v_name text;
 v_public oid;
 v_internal oid;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY[
    'company_work_worker_day_self_api_v1(date,integer)',
    'company_work_worker_day_refresh_self_api_v1(date,integer)',
    'worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb)',
    'company_work_employee_home_self_api_v1()'
  ]::text[]) LOOP
   v_public:=to_regprocedure('public.'||v_name);
   v_internal:=to_regprocedure('atlas.'||v_name);
   IF v_public IS NULL OR v_internal IS NULL THEN
     RAISE EXCEPTION 'Legacy source contract absent: %',v_name;
   END IF;
   IF has_function_privilege('authenticated',v_public,'EXECUTE')
      OR has_function_privilege('anon',v_public,'EXECUTE')
      OR has_function_privilege('authenticated',v_internal,'EXECUTE')
      OR has_function_privilege('anon',v_internal,'EXECUTE')
   THEN
     RAISE EXCEPTION 'Legacy Worker Day independently executable under original role: %',v_name;
   END IF;
 END LOOP;
END;
$guard$;
ROLLBACK;
