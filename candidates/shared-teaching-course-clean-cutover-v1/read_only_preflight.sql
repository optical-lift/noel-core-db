-- SHARED COURSE CUTOVER V1 — READ-ONLY SOURCE/CLONE PREFLIGHT.
-- No DDL, INSERT, UPDATE, DELETE, COPY, DO or source-body output.
-- Not an executable migration; run under read-only audited credentials.
-- Counts are historical Nov 7 observations, NOT automatic approval to delete.
-- Re-run under a writer freeze; any drift blocks the proposed migration.

WITH source_counts AS (
 SELECT 'titus-private-courses' name, count(*)::bigint n FROM titus.customer_course_drafts_v1
 UNION ALL SELECT 'titus-private-workspaces',count(*) FROM titus.customer_workspaces_v1
 UNION ALL SELECT 'titus-top-level-revisions',count(*) FROM titus.customer_course_material_revisions_v1
 UNION ALL SELECT 'titus-private-units',count(*) FROM titus.customer_course_units_v1
 UNION ALL SELECT 'titus-unit-revisions',count(*) FROM titus.customer_course_unit_revisions_v1
 UNION ALL SELECT 'atlas-canonical-courses',count(*) FROM atlas.teaching_courses
 UNION ALL SELECT 'atlas-academic-versions',count(*) FROM atlas.teaching_course_versions
 UNION ALL SELECT 'atlas-course-offerings',count(*) FROM atlas.teaching_course_offerings
 UNION ALL SELECT 'atlas-course-enrollments',count(*) FROM atlas.teaching_enrollments
 UNION ALL SELECT 'legacy-titus-courses',count(*) FROM titus.courses
 UNION ALL SELECT 'legacy-programs',count(*) FROM titus.programs
 UNION ALL SELECT 'legacy-course-slots',count(*) FROM titus.course_slots
 UNION ALL SELECT 'legacy-course-teachers',count(*) FROM titus.course_teachers
 UNION ALL SELECT 'legacy-program-course-placements',count(*) FROM titus.program_course_placements
 UNION ALL SELECT 'legacy-program-canon-claims',count(*) FROM titus.canon_claims
 UNION ALL SELECT 'legacy-program-canon-structures',count(*) FROM titus.canon_structures
 UNION ALL SELECT 'legacy-program-curriculum-versions',count(*) FROM titus.curriculum_versions
 UNION ALL SELECT 'legacy-program-curriculum-findings',count(*) FROM titus.curriculum_findings
 UNION ALL SELECT 'legacy-program-curriculum-decisions',count(*) FROM titus.curriculum_decisions
 UNION ALL SELECT 'legacy-formation-units',count(*) FROM titus.formation_units
 UNION ALL SELECT 'legacy-claim-evidence',count(*) FROM titus.canon_claim_evidence
 UNION ALL SELECT 'legacy-claim-truth-links',count(*) FROM titus.canon_claim_truth_links
 UNION ALL SELECT 'legacy-structure-nodes',count(*) FROM titus.canon_structure_nodes
 UNION ALL SELECT 'legacy-structure-edges',count(*) FROM titus.canon_structure_edges
 UNION ALL SELECT 'legacy-source-adjudications',count(*) FROM titus.teacher_source_adjudications
 UNION ALL SELECT 'legacy-formation-unit-inputs',count(*) FROM titus.formation_unit_inputs
 UNION ALL SELECT 'independent-teacher-source-units',count(*) FROM titus.teacher_source_units
 UNION ALL SELECT 'independent-lesson-packets',count(*) FROM titus.lesson_packets
),
person_fitness AS (
 SELECT count(*)::int draft_count,
 count(*) FILTER (WHERE 1=(SELECT count(*) FROM reality.auth_person_bindings b
  JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person'
  WHERE b.auth_user_id=d.created_by_auth_user_id AND b.binding_state='active'))::int unique_real_person,
 count(*) FILTER (WHERE NOT EXISTS (
  SELECT 1 FROM titus.customer_workspaces_v1 w
  WHERE w.workspace_id=d.workspace_id AND w.owner_auth_user_id=d.created_by_auth_user_id
 ))::int owner_workspace_mismatch,
 count(*) FILTER (WHERE EXISTS (
  SELECT 1 FROM atlas.teaching_courses c WHERE c.id=d.course_id
 ))::int target_id_collision
 FROM titus.customer_course_drafts_v1 d
),
source_content_shape AS (
 SELECT (SELECT count(*) FROM titus.customer_course_material_revisions_v1)::int top_level_revisions,
 (SELECT coalesce(sum(char_length(body_text)),0) FROM titus.customer_course_material_revisions_v1)::int top_level_text_chars,
 (SELECT count(*) FROM titus.customer_course_units_v1 WHERE kind='lesson')::int lesson_units,
 (SELECT count(*) FROM titus.customer_course_units_v1 WHERE kind='assignment')::int homework_draft_units,
 (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)::int unit_revisions,
 (SELECT coalesce(sum(char_length(body_text)),0) FROM titus.customer_course_unit_revisions_v1)::int unit_text_chars
)
SELECT 'source-count' AS section,name,n::text AS observation
 FROM source_counts
UNION ALL SELECT 'person-fitness','source-drafts',draft_count::text FROM person_fitness
UNION ALL SELECT 'person-fitness','unique-active-canonical-people',unique_real_person::text FROM person_fitness
UNION ALL SELECT 'person-fitness','owner-workspace-mismatches',owner_workspace_mismatch::text FROM person_fitness
UNION ALL SELECT 'person-fitness','target-course-id-collisions',target_id_collision::text FROM person_fitness
UNION ALL SELECT 'content-shape','top-level-revisions',top_level_revisions::text FROM source_content_shape
UNION ALL SELECT 'content-shape','top-level-characters',top_level_text_chars::text FROM source_content_shape
UNION ALL SELECT 'content-shape','lesson-units',lesson_units::text FROM source_content_shape
UNION ALL SELECT 'content-shape','homework-draft-units',homework_draft_units::text FROM source_content_shape
UNION ALL SELECT 'content-shape','unit-revisions',unit_revisions::text FROM source_content_shape
UNION ALL SELECT 'content-shape','unit-characters',unit_text_chars::text FROM source_content_shape
ORDER BY section,name;

-- Recursive deletion graph: inspect every child BEFORE selecting its rows.
WITH RECURSIVE root AS (
 SELECT 'titus.courses'::regclass AS oid
 UNION ALL SELECT 'titus.programs'::regclass
 UNION ALL SELECT 'titus.customer_course_drafts_v1'::regclass
 UNION ALL SELECT 'titus.customer_workspaces_v1'::regclass
), graph(root,object,depth,path) AS (
 SELECT oid,oid,0,ARRAY[oid]::oid[] FROM root
 UNION ALL
 SELECT g.root,c.conrelid,g.depth+1,g.path||c.conrelid
 FROM graph g JOIN pg_constraint c ON c.contype='f' AND c.confrelid=g.object
 WHERE NOT c.conrelid=ANY(g.path) AND g.depth<12
)
SELECT root::regclass::text AS source_root,object::regclass::text AS dependent,
 min(depth) AS shortest_fk_distance
 FROM graph GROUP BY root,object
 ORDER BY source_root,shortest_fk_distance,dependent;

-- Public/table/view and RPC consumers require explicit retirement, no CASCADE.
SELECT schemaname AS schema_name,viewname AS object_name
FROM pg_views
WHERE schemaname IN ('public','titus','atlas') AND (
 definition ILIKE '%titus.courses%'
 OR definition ILIKE '%titus.programs%'
 OR definition ILIKE '%titus.customer_course_drafts_v1%'
 OR definition ILIKE '%titus.customer_course_units_v1%'
 OR definition ILIKE '%atlas.teaching_courses%')
ORDER BY schema_name,object_name;

SELECT n.nspname AS schema_name,p.proname AS function_name,
 pg_get_function_identity_arguments(p.oid) AS exact_args
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','titus','atlas') AND (
 pg_get_functiondef(p.oid) ILIKE '%titus.customer_course_drafts_v1%'
 OR pg_get_functiondef(p.oid) ILIKE '%titus.customer_course_units_v1%'
 OR pg_get_functiondef(p.oid) ILIKE '%titus.customer_workspaces_v1%'
 OR pg_get_functiondef(p.oid) ILIKE '%titus.courses%'
 OR pg_get_functiondef(p.oid) ILIKE '%titus.programs%'
 OR pg_get_functiondef(p.oid) ILIKE '%atlas.teaching_courses%')
ORDER BY schema_name,function_name,exact_args;
