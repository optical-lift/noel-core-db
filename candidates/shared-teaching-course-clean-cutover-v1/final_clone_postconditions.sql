-- SHARED TEACHING COURSE V1 — TARGET CLONE STRUCTURAL POSTCONDITIONS.
-- READ-ONLY. Intended ONLY AFTER independently reviewed full-schema clone
-- migration + private row equality proof. It is EXPECTED TO FAIL ON LIVE NOW.
-- A passing structural check alone never approves source rights or deployment.
-- No founder materials, PII, source text or private hashes are selected.

DO $final_release$
DECLARE v_failures text;
BEGIN
WITH expected(name,found) AS (
 VALUES
 ('canonical Course root',to_regclass('atlas.teaching_courses') IS NOT NULL),
 ('canonical manuscript revisions',to_regclass('atlas.teaching_course_manuscript_revisions') IS NOT NULL),
 ('canonical authored Units',to_regclass('atlas.teaching_course_units') IS NOT NULL),
 ('canonical authored Unit revisions',to_regclass('atlas.teaching_course_unit_revisions') IS NOT NULL),
 ('optional institutional operating standing',to_regclass('atlas.teaching_course_operating_standings') IS NOT NULL),
 ('source-issued Person-scoped Titus access',to_regclass('titus.course_authoring_access_grants') IS NOT NULL),
 -- The old McMillan program's exclusive rows must be gone, but the shared
 -- Program and teacher-link table DEFINITIONS remain reusable source schema.
 ('reusable Program table retained',to_regclass('titus.programs') IS NOT NULL),
 ('reusable Program-teacher relation retained',to_regclass('titus.program_teachers') IS NOT NULL),
 ('old Program rows deleted',NOT EXISTS (SELECT 1 FROM titus.programs)),
 ('old Program teacher links deleted',NOT EXISTS (SELECT 1 FROM titus.program_teachers)),
 ('Titus private author access self API',to_regprocedure('public.titus_authoring_access_self_api_v1()') IS NOT NULL),
 ('canonical author-signed teacher offer',to_regprocedure('public.shared_teaching_teacher_offer_self_api_v1(uuid,uuid,uuid)') IS NOT NULL),
 ('canonical teacher signed answer',to_regprocedure('public.shared_teaching_teacher_respond_self_api_v1(uuid,uuid,text)') IS NOT NULL),
 ('original author exact teacher sealed Unit permission',to_regprocedure('public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text)') IS NOT NULL),
 ('teacher single sealed Unit self reader',to_regprocedure('public.shared_teaching_teacher_sealed_unit_read_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('original author exact learner sealed Unit permission',to_regprocedure('public.shared_teaching_learner_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text)') IS NOT NULL),
 ('learner single sealed Unit self reader',to_regprocedure('public.shared_teaching_learner_sealed_unit_read_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('private immutable learner Unit disclosure author events',to_regclass('atlas.shared_course_learner_unit_disclosure_decisions') IS NOT NULL),
 ('immutable learner Unit disclosure trigger',EXISTS (
   SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid=to_regclass('atlas.shared_course_learner_unit_disclosure_decisions')
    AND t.tgname='shared_learner_unit_disclosure_immutable' AND NOT t.tgisinternal)),
 ('private immutable teacher Unit disclosure author events',to_regclass('atlas.shared_course_teacher_unit_disclosure_decisions') IS NOT NULL),
 ('immutable teacher Unit disclosure trigger',EXISTS (
   SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid=to_regclass('atlas.shared_course_teacher_unit_disclosure_decisions')
    AND t.tgname='shared_teacher_unit_disclosure_immutable' AND NOT t.tgisinternal)),
 ('source-specific learner invitation author permission',to_regprocedure('public.shared_teaching_learner_invitation_decide_self_api_v1(uuid,uuid,text)') IS NOT NULL),
 ('exact canonical learner invitation offer',to_regprocedure('public.shared_teaching_learner_offer_self_api_v1(uuid,uuid,uuid)') IS NOT NULL),
 ('private own learner invitation reader',to_regprocedure('public.shared_teaching_learner_offer_read_self_api_v1(uuid)') IS NOT NULL),
 ('independent learner consent response',to_regprocedure('public.shared_teaching_learner_respond_self_api_v1(uuid,uuid,text)') IS NOT NULL),
 ('governor learner invitation withdrawal',to_regprocedure('public.shared_teaching_learner_withdraw_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('original Enrollment carrier retained',to_regclass('atlas.teaching_enrollments') IS NOT NULL),
 ('source-issued Enrollment gate still active',to_regprocedure('atlas.guard_shared_course_enrollment_pending_v1()') IS NOT NULL),
 ('separate signed original author Enrollment permission',to_regprocedure('public.shared_teaching_learner_enrollment_decide_self_api_v1(uuid,uuid,text)') IS NOT NULL),
 ('current governed canonical Enrollment issuance',to_regprocedure('public.shared_teaching_learner_enrollment_issue_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('learner own original Enrollment read',to_regprocedure('public.shared_teaching_learner_enrollment_read_self_api_v1(uuid)') IS NOT NULL),
 ('learner source-issued terminal original withdrawal',to_regprocedure('public.shared_teaching_learner_enrollment_withdraw_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('immutable original learner withdrawal receipt',to_regclass('atlas.shared_course_enrollment_withdrawal_issuances') IS NOT NULL),
 ('original Enrollment withdrawal receipt trigger',EXISTS(
   SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid=to_regclass('atlas.shared_course_enrollment_withdrawal_issuances')
   AND t.tgname='shared_enrollment_withdrawal_immutable'
   AND NOT t.tgisinternal)),
 ('private immutable original Enrollment issuance receipts',to_regclass('atlas.shared_course_enrollment_issuances') IS NOT NULL),
 ('private immutable author Enrollment scope',to_regclass('atlas.shared_course_learner_enrollment_author_decisions') IS NOT NULL),
 ('canonical Reality learner identity on SAME original Enrollment',EXISTS(
   SELECT 1 FROM pg_attribute a WHERE a.attrelid=to_regclass('atlas.teaching_enrollments')
   AND a.attname='person_entity_id' AND a.attnum>0 AND NOT a.attisdropped)),
 ('canonical original Enrollment provenance constraint',EXISTS(
   SELECT 1 FROM pg_constraint c WHERE c.conrelid=to_regclass('atlas.teaching_enrollments')
   AND c.conname='shared_course_enrollment_provenance_v1' AND c.contype='c')),
 ('original Enrollment source trigger retained',EXISTS(
   SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass('atlas.teaching_enrollments')
   AND t.tgname='shared_course_enrollment_pending_v1' AND NOT t.tgisinternal)),
 ('canonical exact governor open source',to_regprocedure('public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)') IS NOT NULL),
 ('private original Course seal',to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NOT NULL)
), retired(name,present) AS (
 VALUES
 ('legacy Titus courses',to_regclass('titus.courses') IS NOT NULL),
 ('legacy Titus course slots',to_regclass('titus.course_slots') IS NOT NULL),
 ('legacy Titus Course teacher links',to_regclass('titus.course_teachers') IS NOT NULL),
 ('legacy Titus lesson placements',to_regclass('titus.course_lesson_placements') IS NOT NULL),
 ('legacy Titus lesson prerequisites',to_regclass('titus.course_lesson_prerequisites') IS NOT NULL),
 ('legacy Titus Course-slot activity log',to_regclass('titus.course_slot_activity_log') IS NOT NULL),
 ('legacy Titus program Courses',to_regclass('titus.program_course_placements') IS NOT NULL),

 ('legacy Course-only workspace',to_regclass('titus.customer_workspaces_v1') IS NOT NULL),
 ('old Auth-owned Titus product entitlements',to_regclass('titus.customer_workspace_entitlements_v1') IS NOT NULL),
 ('Titus shadow Course drafts',to_regclass('titus.customer_course_drafts_v1') IS NOT NULL),
 ('Titus shadow Course manuscript revisions',to_regclass('titus.customer_course_material_revisions_v1') IS NOT NULL),
 ('Titus shadow Course Units',to_regclass('titus.customer_course_units_v1') IS NOT NULL),
 ('Titus shadow Course Unit revisions',to_regclass('titus.customer_course_unit_revisions_v1') IS NOT NULL),
 ('obsolete Titus public Courses view',to_regclass('public.titus_courses_v1') IS NOT NULL),
 ('obsolete Titus public Course slots view',to_regclass('public.titus_course_slots_v1') IS NOT NULL),
 ('obsolete Titus course path view',to_regclass('public.titus_course_path_v1') IS NOT NULL),
 ('obsolete Titus Course preview path view',to_regclass('public.titus_course_preview_path_v1') IS NOT NULL)
),
old_rpc AS (
 SELECT n.nspname||'.'||p.proname AS name
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='public' AND p.proname LIKE 'titus_customer_%')
    OR (n.nspname='atlas' AND p.proname IN
       ('create_teaching_course_self_api_v1',
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
        'teaching_enrollments_for_current_person_self_api_v1'))
    OR (n.nspname='titus' AND p.proname IN
       ('customer_current_auth_user_v1',
        'customer_owned_course_for_units_v1',
        'link_lesson_packet_to_course_slot',
        'mark_course_slot_in_sandbox',
        'mark_course_slot_packet_ready',
        'start_course_slot_deep_dive'))
),
old_fk AS (
 SELECT c.conname, c.confrelid::regclass::text AS target
 FROM pg_constraint c
 WHERE c.contype='f' AND c.conrelid=to_regclass('atlas.teaching_courses')
 AND c.confrelid IN (
    to_regclass('atlas.principals'),to_regclass('atlas.ledgers'),
    to_regclass('atlas.capability_activations'))
),
old_institutional_columns AS (
 SELECT n.nspname||'.'||c.relname||'.'||a.attname AS name
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='atlas' AND a.attnum>0 AND NOT a.attisdropped
 AND (
  (c.relname='teaching_courses' AND a.attname IN
   ('ledger_id','capability_activation_id','created_by_person_id','created_by_principal_id'))
  OR (c.relname='teaching_course_versions' AND a.attname IN
   ('published_by_person_id','published_by_principal_id'))
  OR (c.relname='teaching_course_offerings' AND a.attname IN
   ('created_by_person_id','created_by_principal_id'))
 )
),
obsolete_offering_guard AS (
 SELECT n.nspname||'.'||p.proname AS name
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname='guard_teaching_course_offering_update_v1'
 UNION ALL
 SELECT n.nspname||'.'||t.tgname
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='atlas' AND t.tgname='teaching_course_offerings_update_guard_v1'
   AND NOT t.tgisinternal
),
competing_course_views AS (
 SELECT schemaname||'.'||viewname AS name
 FROM pg_views
 WHERE schemaname IN ('public','titus','atlas') AND (
    definition ILIKE '%titus.customer_course_drafts_v1%'
    OR definition ILIKE '%titus.courses%'
    OR definition ILIKE '%titus.programs%')
),
violations AS (
 SELECT 'required' AS kind,expected.name,expected.found AS ok FROM expected
 UNION ALL SELECT 'retired',name,NOT present FROM retired
 UNION ALL SELECT 'obsolete-RPC',name,FALSE FROM old_rpc
 UNION ALL SELECT 'old-Principal-or-Ledger-FK',conname||'->'||target,FALSE FROM old_fk
 UNION ALL SELECT 'obsolete-institutional-identity-column',name,FALSE FROM old_institutional_columns
 UNION ALL SELECT 'obsolete-Offering-guard',name,FALSE FROM obsolete_offering_guard
 UNION ALL SELECT 'legacy-view',name,FALSE FROM competing_course_views
)
SELECT string_agg(kind||':'||name,'; ' ORDER BY kind,name)
  INTO v_failures FROM violations WHERE NOT ok;
IF v_failures IS NOT NULL THEN
 RAISE EXCEPTION 'shared Course cutover has unresolved legacy/source requirements: %',
  v_failures USING ERRCODE='23514';
END IF;
END
$final_release$;

-- This is a hard-fail end-state structural proof, EXPECTED to fail on live.
-- Its passing never constitutes authority to release.
-- Additional private proof MUST compare old protected snapshot to new source
-- by all original UUIDs and row values: body bytes, request IDs, timestamps,
-- author provenance, ordering, revision sequence and source rights.
-- Sign in as author, other Person, anonymous Person and revoked former editor.
-- Verify Person-first Course creation requires no institution and a later
-- authorized institutional operation DOES NOT create another Course.
