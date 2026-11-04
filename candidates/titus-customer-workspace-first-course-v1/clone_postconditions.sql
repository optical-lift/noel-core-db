-- TITUS PRIVATE CUSTOMER COURSE V1: PRODUCTION-SHAPED CLONE VALIDATION ONLY.
-- May run only AFTER the candidate DDL has been applied to a disposable
-- schema/role clone. No fake Auth users, claims, purchases or entitlements.
-- This is NOT the scratch-only fixture.sql or postconditions.sql.
-- This file reads schema metadata and the new (empty) candidate tables;
-- it does not change persistent data or issue authorization.
DO $titus_customer_clone_v1$
DECLARE v_call_denied boolean:=false;
BEGIN
 IF to_regclass('titus.customer_workspaces_v1') IS NULL OR
    to_regclass('titus.customer_course_drafts_v1') IS NULL OR
    to_regclass('titus.customer_workspace_entitlements_v1') IS NULL THEN
   RAISE EXCEPTION 'Titus customer source tables missing';
 END IF;

 IF NOT EXISTS (
   SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='titus' AND c.relname='customer_workspaces_v1'
      AND c.relrowsecurity
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='titus' AND c.relname='customer_course_drafts_v1'
      AND c.relrowsecurity
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='titus' AND c.relname='customer_workspace_entitlements_v1'
      AND c.relrowsecurity
 ) THEN RAISE EXCEPTION 'Titus customer private RLS missing';
 END IF;

 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint k
   WHERE k.conrelid='titus.customer_course_drafts_v1'::regclass
     AND k.contype='u' AND k.conname='customer_course_request_scoped_v1'
 ) THEN RAISE EXCEPTION 'Workspace-scoped request uniqueness missing';
 END IF;

 IF NOT has_function_privilege('authenticated',
    'public.titus_customer_catalog_self_api_v1()','EXECUTE') OR
    NOT has_function_privilege('authenticated',
    'public.titus_customer_start_workspace_self_api_v1(text)','EXECUTE') OR
    NOT has_function_privilege('authenticated',
    'public.titus_customer_create_course_self_api_v1(uuid,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Required exact authenticated-only RPC grants missing';
 END IF;

 IF has_function_privilege('anon',
    'public.titus_customer_catalog_self_api_v1()','EXECUTE') OR
    has_function_privilege('anon',
    'public.titus_customer_start_workspace_self_api_v1(text)','EXECUTE') OR
    has_function_privilege('anon',
    'public.titus_customer_create_course_self_api_v1(uuid,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous Titus customer RPC execute leak';
 END IF;

 IF has_table_privilege('authenticated',
    'titus.customer_workspaces_v1','SELECT') OR
    has_table_privilege('authenticated',
    'titus.customer_course_drafts_v1','INSERT') OR
    has_table_privilege('authenticated',
    'titus.customer_workspace_entitlements_v1','SELECT') OR
    has_table_privilege('service_role',
    'titus.customer_workspace_entitlements_v1','INSERT') THEN
   RAISE EXCEPTION 'Titus customer private table privilege leak';
 END IF;

 IF EXISTS(SELECT 1 FROM titus.customer_workspaces_v1) OR
    EXISTS(SELECT 1 FROM titus.customer_course_drafts_v1) OR
    EXISTS(SELECT 1 FROM titus.customer_workspace_entitlements_v1) THEN
   RAISE EXCEPTION 'Source unexpectedly seeded customer, course, or entitlement';
 END IF;

 -- The DB administrator has no incoming signed Auth session. The public
 -- SECURITY DEFINER read must nevertheless deny access at source.
 BEGIN
   PERFORM public.titus_customer_catalog_self_api_v1();
 EXCEPTION WHEN insufficient_privilege THEN
   v_call_denied:=true;
 END;
 IF NOT v_call_denied THEN
   RAISE EXCEPTION 'No-session customer catalog call was not denied';
 END IF;
END $titus_customer_clone_v1$;
