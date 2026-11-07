-- SHARED TEACHING COURSE V1 — TARGET CLONE STRUCTURAL POSTCONDITIONS.
-- READ-ONLY. Intended ONLY AFTER independently reviewed full-schema clone
-- migration + private row equality proof. It is EXPECTED TO FAIL ON LIVE NOW.
-- A passing structural check alone never approves source rights or deployment.
-- No founder materials, PII, source text or private hashes are selected.

WITH expected(name,found) AS (
 VALUES
 ('canonical Course root',to_regclass('atlas.teaching_courses') IS NOT NULL),
 ('canonical manuscript revisions',to_regclass('atlas.teaching_course_manuscript_revisions') IS NOT NULL),
 ('canonical authored Units',to_regclass('atlas.teaching_course_units') IS NOT NULL),
 ('canonical authored Unit revisions',to_regclass('atlas.teaching_course_unit_revisions') IS NOT NULL),
 ('optional institutional operating standing',to_regclass('atlas.teaching_course_operating_standings') IS NOT NULL)
), retired(name,present) AS (
 VALUES
 ('legacy Titus courses',to_regclass('titus.courses') IS NOT NULL),
 ('legacy Titus course slots',to_regclass('titus.course_slots') IS NOT NULL),
 ('legacy Titus Course teacher links',to_regclass('titus.course_teachers') IS NOT NULL),
 ('legacy Titus program Courses',to_regclass('titus.program_course_placements') IS NOT NULL),
 ('legacy Titus programs',to_regclass('titus.programs') IS NOT NULL),
 ('legacy Course-only workspace',to_regclass('titus.customer_workspaces_v1') IS NOT NULL),
 ('Titus shadow Course drafts',to_regclass('titus.customer_course_drafts_v1') IS NOT NULL),
 ('Titus shadow Course manuscript revisions',to_regclass('titus.customer_course_material_revisions_v1') IS NOT NULL),
 ('Titus shadow Course Units',to_regclass('titus.customer_course_units_v1') IS NOT NULL),
 ('Titus shadow Course Unit revisions',to_regclass('titus.customer_course_unit_revisions_v1') IS NOT NULL),
 ('obsolete Titus public Courses view',to_regclass('public.titus_courses_v1') IS NOT NULL),
 ('obsolete Titus public Course slots view',to_regclass('public.titus_course_slots_v1') IS NOT NULL),
 ('obsolete Titus course path view',to_regclass('public.titus_course_path_v1') IS NOT NULL)
),
old_rpc AS (
 SELECT n.nspname||'.'||p.proname AS name
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='public' AND p.proname LIKE 'titus_customer_%')
    OR (n.nspname='atlas' AND p.proname IN
       ('create_teaching_course_self_api_v1',
        'create_teaching_course_from_activation_self_api_v1'))
),
old_fk AS (
 SELECT c.conname, c.confrelid::regclass::text AS target
 FROM pg_constraint c
 WHERE c.contype='f' AND c.conrelid=to_regclass('atlas.teaching_courses')
 AND c.confrelid IN (
    to_regclass('atlas.principals'),to_regclass('atlas.ledgers'),
    to_regclass('atlas.capability_activations'))
),
competing_course_views AS (
 SELECT schemaname||'.'||viewname AS name
 FROM pg_views
 WHERE schemaname IN ('public','titus','atlas') AND (
    definition ILIKE '%titus.customer_course_drafts_v1%'
    OR definition ILIKE '%titus.courses%'
    OR definition ILIKE '%titus.programs%')
)
SELECT 'required' AS kind,name,found AS ok FROM expected
UNION ALL SELECT 'retired',name,NOT present FROM retired
UNION ALL SELECT 'obsolete-RPC',name,FALSE FROM old_rpc
UNION ALL SELECT 'old-Principal-or-Ledger-FK',conname||'->'||target,FALSE FROM old_fk
UNION ALL SELECT 'legacy-view',name,FALSE FROM competing_course_views
ORDER BY kind,name;

-- Fails as a release proof if any row in the above result is false.
-- Additional private proof MUST compare old protected snapshot to new source
-- by all original UUIDs and row values: body bytes, request IDs, timestamps,
-- author provenance, ordering, revision sequence and source rights.
-- Sign in as author, other Person, anonymous Person and revoked former editor.
-- Verify Person-first Course creation requires no institution and a later
-- authorized institutional operation DOES NOT create another Course.
