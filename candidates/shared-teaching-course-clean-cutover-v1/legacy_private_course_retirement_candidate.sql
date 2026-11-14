-- HELD M4: retire obsolete Titus *private* Course store and RPCs.
-- ONLY in restored disposable clone after SK101 same-ID adoption, current
-- source migration and verified private temporary manifest. Never on live.
-- Orchestrator owns transaction. No CASCADE, no second Course.
DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'protected clone required' USING ERRCODE='42501';
 END IF;
 IF to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL
 OR (SELECT count(*) FROM titus.customer_course_drafts_v1)<>1
 OR (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>1
 OR (SELECT count(*) FROM titus.customer_course_units_v1)<>2
 OR (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>3
 OR (SELECT count(*) FROM titus.customer_workspace_entitlements_v1)<>1
 OR (SELECT count(*) FROM titus.customer_workspaces_v1)<>1 THEN
  RAISE EXCEPTION 'original private Course source/manifest changed'
   USING ERRCODE='23514';
 END IF;
END
$guard$;

\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_byte_attestation.sql

-- Final cutover removes ALL old RPCs, not a shadow-read compatibility layer.
DROP FUNCTION public.titus_customer_catalog_self_api_v1() RESTRICT;
DROP FUNCTION public.titus_customer_create_course_self_api_v1(uuid,text) RESTRICT;
DROP FUNCTION public.titus_customer_start_workspace_self_api_v1(text) RESTRICT;
DROP FUNCTION public.titus_customer_material_read_self_api_v1(uuid) RESTRICT;
DROP FUNCTION public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text) RESTRICT;
DROP FUNCTION public.titus_customer_outline_read_self_api_v1(uuid) RESTRICT;
DROP FUNCTION public.titus_customer_unit_create_self_api_v1(uuid,uuid,text,text) RESTRICT;
DROP FUNCTION public.titus_customer_unit_move_self_api_v1(uuid,uuid,text) RESTRICT;
DROP FUNCTION public.titus_customer_unit_read_self_api_v1(uuid) RESTRICT;
DROP FUNCTION public.titus_customer_unit_save_self_api_v1(uuid,uuid,integer,text) RESTRICT;
DROP FUNCTION titus.customer_owned_course_for_units_v1(uuid) RESTRICT;
DROP FUNCTION titus.customer_current_auth_user_v1() RESTRICT;

-- Delete exactly the source whose immutable private copy is now adopted.
DELETE FROM titus.customer_course_unit_revisions_v1;
DELETE FROM titus.customer_course_material_revisions_v1;
DELETE FROM titus.customer_course_units_v1;
DELETE FROM titus.customer_course_drafts_v1;
DELETE FROM titus.customer_workspace_entitlements_v1;
DELETE FROM titus.customer_workspaces_v1;

DROP TABLE titus.customer_course_unit_revisions_v1 RESTRICT;
DROP TABLE titus.customer_course_material_revisions_v1 RESTRICT;
DROP TABLE titus.customer_course_units_v1 RESTRICT;
DROP TABLE titus.customer_course_drafts_v1 RESTRICT;
DROP TABLE titus.customer_workspace_entitlements_v1 RESTRICT;
DROP TABLE titus.customer_workspaces_v1 RESTRICT;

-- The independently frozen original is still available in session pg_temp,
-- even though the old Course source and workspace no longer exist.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

DO $post$
BEGIN
 IF to_regclass('titus.customer_course_drafts_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_units_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_material_revisions_v1') IS NOT NULL
 OR to_regclass('titus.customer_course_unit_revisions_v1') IS NOT NULL
 OR to_regclass('titus.customer_workspace_entitlements_v1') IS NOT NULL
 OR to_regclass('titus.customer_workspaces_v1') IS NOT NULL
 OR to_regprocedure('public.titus_customer_catalog_self_api_v1()') IS NOT NULL
 OR to_regprocedure('public.titus_customer_start_workspace_self_api_v1(text)') IS NOT NULL
 THEN
   RAISE EXCEPTION 'old Titus private Course registry or RPC survived'
    USING ERRCODE='23514';
 END IF;
END
$post$;
-- Other independent source libraries and real Work/Enrollment unaffected.
