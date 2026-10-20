-- API transport postconditions on a disposable production-schema clone.
-- These assertions create no source tasks, reviews, allocations, or canonical Work.
DO $verify$
DECLARE
  v_name text;
  v_read regprocedure := to_regprocedure(
    'public.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)');
  v_write regprocedure := to_regprocedure(
    'public.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)');
BEGIN
  IF v_read IS NULL OR v_write IS NULL THEN
    RAISE EXCEPTION 'Missing public Venue backlog transport function';
  END IF;
  IF to_regprocedure('atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)') IS NULL
    OR to_regprocedure('atlas.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Missing internal owner-gated Venue backlog authority';
  END IF;
  FOREACH v_name IN ARRAY ARRAY[
    'company_work_legacy_backlog_owner_self_api_v1',
    'decide_company_work_legacy_backlog_owner_self_api_v1'
  ] LOOP
    IF NOT EXISTS(
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=v_name
        AND NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'Public transport missing invoker/authenticated-only restriction: %',v_name;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='atlas' AND p.proname=v_name
        AND p.prosecdef
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'Owner-gated internal authority permission missing: %',v_name;
    END IF;
  END LOOP;
  IF (SELECT p.provolatile FROM pg_proc p WHERE p.oid=v_read::oid)<>'s'
    OR (SELECT p.provolatile FROM pg_proc p WHERE p.oid=v_write::oid)<>'v' THEN
    RAISE EXCEPTION 'Public read/write volatility mismatch';
  END IF;
  IF position('atlas.company_work_legacy_backlog_owner_self_api_v1' IN
      pg_get_functiondef(v_read::oid))=0
    OR position('atlas.decide_company_work_legacy_backlog_owner_self_api_v1' IN
      pg_get_functiondef(v_write::oid))=0 THEN
    RAISE EXCEPTION 'Public transport must delegate to the existing guarded authority';
  END IF;
END
$verify$;
