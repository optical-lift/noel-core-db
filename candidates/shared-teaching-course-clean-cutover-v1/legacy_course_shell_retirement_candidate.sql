-- HELD M4: delete and retire ONLY obsolete Titus Course/slot shell family.
-- Real execution: owner-controlled isolated restored clone ONLY, after M1-M3
-- same-id SK101 adoption and private manifest preservation succeed.
-- NOT A LIVE PRODUCTION MIGRATION. Orchestrator owns transaction/rollback.
-- Independent source units, packets, Song objects, claims and research remain.
-- Explicit operations throughout. Never CASCADE.

DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
   RAISE EXCEPTION 'protected clone required' USING ERRCODE='42501';
 END IF;
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_units)<>2
 OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>3
 OR to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL THEN
   RAISE EXCEPTION 'SK101 source preservation has not been established'
   USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.courses)<>15
 OR (SELECT count(*) FROM titus.course_slots)<>33
 OR (SELECT count(*) FROM titus.course_teachers)<>9
 OR (SELECT count(*) FROM titus.course_lesson_placements)<>1
 OR (SELECT count(*) FROM titus.course_lesson_prerequisites)<>0
 OR (SELECT count(*) FROM titus.program_course_placements)<>18
 OR (SELECT count(*) FROM titus.curriculum_slot_placements)<>30
 OR (SELECT count(*) FROM titus.slot_canon_briefs)<>4
 OR (SELECT count(*) FROM titus.slot_song_scopes)<>15
 OR (SELECT count(*) FROM titus.canon_brief_items)<>60
 OR (SELECT count(*) FROM titus.slot_teacher_source_candidates)<>0
 OR (SELECT count(*) FROM titus.course_slot_activity_log)<>0
 OR (SELECT count(*) FROM titus.workspace_state)<>1 THEN
  RAISE EXCEPTION 'legacy Course/slot scope drift: refuse deletion'
  USING ERRCODE='23514';
 END IF;
 -- Neither the canonical Course ID nor its authoring original belongs to
 -- these obsolete Course slugs. Legacy Course-shell and canonical IDs are
 -- independent types; there is NO slug -> UUID migration.
END
$preflight$;

-- Retire old public/worker Course projections before the underlying tables.
-- These are old Course views, not the new canonical source projection.
DROP VIEW IF EXISTS public.titus_course_preview_path_v1 RESTRICT;
DROP VIEW IF EXISTS public.titus_course_path_v1 RESTRICT;
DROP VIEW IF EXISTS public.titus_course_word_lesson_live_v1 RESTRICT;
DROP VIEW IF EXISTS public.titus_course_slots_v1 RESTRICT;
DROP VIEW IF EXISTS public.titus_courses_v1 RESTRICT;
DROP VIEW IF EXISTS titus.v_slot_workbench_v2 RESTRICT;
DROP VIEW IF EXISTS titus.v_curriculum_workspace_v2 RESTRICT;
DROP VIEW IF EXISTS titus.v_program_curriculum_map_v2 RESTRICT;
DROP VIEW IF EXISTS titus.noel_deep_dive_queue_v1 RESTRICT;
DROP VIEW IF EXISTS titus.ready_to_promote_queue_v1 RESTRICT;
DROP VIEW IF EXISTS titus.course_build_board_v1 RESTRICT;
DROP VIEW IF EXISTS titus.course_slots_admin_v1 RESTRICT;

-- Old slot-specific RPCs. Do not drop teacher's independent lesson packets.
DROP FUNCTION IF EXISTS public.get_titus_course_preview_packet_by_slug(text) RESTRICT;
DROP FUNCTION IF EXISTS titus.link_lesson_packet_to_course_slot(text,text,text,text,text,text) RESTRICT;
DROP FUNCTION IF EXISTS titus.mark_course_slot_in_sandbox(text,text,text) RESTRICT;
DROP FUNCTION IF EXISTS titus.mark_course_slot_packet_ready(text,text,text) RESTRICT;
DROP FUNCTION IF EXISTS titus.start_course_slot_deep_dive(text,text,text,text) RESTRICT;
DROP FUNCTION IF EXISTS titus.get_lesson_packet_template_for_slot(text,text,text) RESTRICT;

-- Drop old workspace state, which is one legacy Program/Course pointer,
-- not a canonical Person, Course, Institution, or Notebook original.
-- If other views or functions need it, RESTRICT fails and blocks cutover.
DELETE FROM titus.workspace_state;
DROP TABLE titus.workspace_state RESTRICT;

-- Remove Course-only descendants explicitly from leaves to roots. On all
-- rows the FK closure is still the previously inventoried set of 15 old
-- shell Courses (any unknown row triggers the preflight count drift check).
DELETE FROM titus.slot_song_scopes;
DELETE FROM titus.canon_brief_items;
DELETE FROM titus.slot_teacher_source_candidates;
DELETE FROM titus.slot_canon_briefs;
DELETE FROM titus.course_slot_activity_log;
DELETE FROM titus.curriculum_slot_placements;
DELETE FROM titus.program_course_placements;
DELETE FROM titus.course_lesson_prerequisites;
DELETE FROM titus.course_lesson_placements;
DELETE FROM titus.course_teachers;
DELETE FROM titus.course_slots;
DELETE FROM titus.courses;

-- These tables are solely legacy Course shell/slot storage, NOT the
-- independent research originals and NOT the new atlas.teaching_courses.
DROP TABLE titus.slot_song_scopes RESTRICT;
DROP TABLE titus.canon_brief_items RESTRICT;
DROP TABLE titus.slot_teacher_source_candidates RESTRICT;
DROP TABLE titus.slot_canon_briefs RESTRICT;
DROP TABLE titus.course_slot_activity_log RESTRICT;
DROP TABLE titus.curriculum_slot_placements RESTRICT;
DROP TABLE titus.program_course_placements RESTRICT;
DROP TABLE titus.course_lesson_prerequisites RESTRICT;
DROP TABLE titus.course_lesson_placements RESTRICT;
DROP TABLE titus.course_teachers RESTRICT;
DROP TABLE titus.course_slots RESTRICT;
DROP TABLE titus.courses RESTRICT;

-- Requires the original source bytes to remain in pg_temp. The independent
-- canonical Course/Unit manuscript comparison never sees deleted text.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

DO $post$
BEGIN
 IF to_regclass('titus.courses') IS NOT NULL
 OR to_regclass('titus.course_slots') IS NOT NULL
 OR to_regclass('titus.program_course_placements') IS NOT NULL
 OR to_regclass('titus.workspace_state') IS NOT NULL
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1
 THEN
  RAISE EXCEPTION 'Course-shell retirement not complete' USING ERRCODE='23514';
 END IF;
END
$post$;
-- The OLD McMillan Program/Formation/research original family is a distinct
-- retirement tranche; this script never deletes it or source libraries.
