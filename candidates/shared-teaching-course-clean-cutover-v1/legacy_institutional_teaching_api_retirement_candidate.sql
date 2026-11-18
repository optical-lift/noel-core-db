-- HELD M4.1 — retire ALL obsolete institution-first Atlas Course/
-- Version/Offering/Roster/Enrollment API entrypoints with exact DROP RESTRICT.
-- This is an executable protected-clone candidate ONLY, not production.
-- Requires the separately verified SK101 adoption, full old content lineage
-- backup/restore and old Titus Course/Program/Customer source retirement.
-- Independent source-issued author, governor, teacher and learner rights
-- remain on the SAME original Course; this script never deletes data.
DO $gate$
DECLARE
 v_missing text;
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL
 OR to_regclass('titus.customer_course_drafts_v1') IS NOT NULL
 OR to_regclass('titus.courses') IS NOT NULL
 OR EXISTS(SELECT 1 FROM titus.programs)
 OR to_regclass('atlas.teaching_courses') IS NULL
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1 THEN
  RAISE EXCEPTION 'protected same-ID adoption and ALL old Course roots retirement required'
   USING ERRCODE='23514';
 END IF;
 WITH required(r) AS (VALUES
  ('public.shared_teaching_course_create_self_api_v1(uuid,text)'::text),
  ('public.shared_teaching_course_catalog_self_api_v1()'),
  ('public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])'),
  ('public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)'),
  ('public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)'),
  ('public.shared_teaching_teacher_offer_self_api_v1(uuid,uuid,uuid)'),
  ('public.shared_teaching_teacher_respond_self_api_v1(uuid,uuid,text)')
 )
 SELECT string_agg(r,', ' ORDER BY r) INTO v_missing
 FROM required WHERE to_regprocedure(r) IS NULL;
 IF v_missing IS NOT NULL THEN
  RAISE EXCEPTION 'current independently governed canonical Course sources absent: %',v_missing
   USING ERRCODE='23514';
 END IF;
END $gate$;

-- Retire the original Course makers AND ALL privileged old direct readers,
-- immutable Version minting, open/close transitions, learner shortcuts and
-- roster/retirement operations. New shared Course APIs remain untouched.
-- No DROP CASCADE: an unknown view/function dependency blocks the entire
-- protected transaction. No anonymous or authenticated compatibility shell.
DROP FUNCTION IF EXISTS atlas.create_teaching_course_self_api_v1(uuid,text,text) RESTRICT;
DROP FUNCTION IF EXISTS atlas.create_teaching_course_from_activation_self_api_v1(uuid,text,text) RESTRICT;
DROP FUNCTION IF EXISTS atlas.teaching_courses_admin_self_api_v1(uuid) RESTRICT;
DROP FUNCTION IF EXISTS atlas.teaching_course_admin_self_api_v1(uuid) RESTRICT;
DROP FUNCTION IF EXISTS atlas.retire_teaching_course_self_api_v1(uuid,text) RESTRICT;
DROP FUNCTION IF EXISTS atlas.publish_teaching_course_version_self_api_v1(uuid,text,text,text[]) RESTRICT;
DROP FUNCTION IF EXISTS atlas.create_teaching_course_offering_self_api_v1(
 uuid,uuid,text,timestamptz,timestamptz) RESTRICT;
DROP FUNCTION IF EXISTS atlas.transition_teaching_course_offering_self_api_v1(uuid,text) RESTRICT;
DROP FUNCTION IF EXISTS atlas.teaching_offering_roster_admin_self_api_v1(uuid) RESTRICT;
DROP FUNCTION IF EXISTS atlas.enroll_person_in_teaching_offering_self_api_v1(uuid,uuid) RESTRICT;
DROP FUNCTION IF EXISTS atlas.withdraw_teaching_enrollment_self_api_v1(uuid,text) RESTRICT;
DROP FUNCTION IF EXISTS atlas.teaching_enrollments_for_current_person_self_api_v1() RESTRICT;

-- PostgreSQL catalog functional end-state assertion. A function with the
-- exact obsolete name in atlas (including unknown overloads) is a FAIL,
-- never a best-effort partial cutover. This is deliberately stricter than
-- the curated DROP signatures above and prevents old RPCs from surviving
-- under a different argument list.
DO $no_legacy_teaching_rpc$
DECLARE v_remaining text;
BEGIN
 SELECT string_agg(p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
   '; ' ORDER BY p.proname) INTO v_remaining
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname IN (
  'create_teaching_course_self_api_v1',
  'create_teaching_course_from_activation_self_api_v1',
  'teaching_courses_admin_self_api_v1',
  'teaching_course_admin_self_api_v1',
  'retire_teaching_course_self_api_v1',
  'publish_teaching_course_version_self_api_v1',
  'create_teaching_course_offering_self_api_v1',
  'transition_teaching_course_offering_self_api_v1',
  'teaching_offering_roster_admin_self_api_v1',
  'enroll_person_in_teaching_offering_self_api_v1',
  'withdraw_teaching_enrollment_self_api_v1',
  'teaching_enrollments_for_current_person_self_api_v1');
 IF v_remaining IS NOT NULL THEN
  RAISE EXCEPTION 'old institutional Teaching RPCs still exist: %',v_remaining
   USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_courses
   WHERE created_by_person_entity_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Person-founded same Course was lost during retirement'
   USING ERRCODE='23514';
 END IF;
END $no_legacy_teaching_rpc$;
