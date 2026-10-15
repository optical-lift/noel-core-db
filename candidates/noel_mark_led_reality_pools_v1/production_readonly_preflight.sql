-- NOEL MARK-LED REALITY POOLS — PRODUCTION READ-ONLY PREFLIGHT
-- Snapshot date: 2026-10-15; target: zirqkouammpwxlqfbsvf (noel-core).
-- Only SELECT statements: safe for inspecting existing production evidence.
-- No DDL, DML, transaction writes, temp objects, researcher payloads or founder content.
-- THIS DOES NOT VALIDATE EXECUTION OF registry_candidate.sql OR ITS POSTCONDITIONS.
-- It proves source counts, transformation reproducibility, label multiplicity,
-- and the inherited-pool reconciliation workload before a governed release.

-- 1. Source inventory and projection admissibility.
WITH src AS (
 SELECT source_token_id, hebrew_surface,
 regexp_replace(replace(hebrew_surface,'/',''), '[֑-ׇֽֿׁׂׅׄ]', '', 'g') AS projected
 FROM draft.ot_canonical_tokens_stage
)
SELECT count(*) AS source_occurrences,
 count(DISTINCT source_token_id) AS distinct_occurrence_ids,
 count(DISTINCT hebrew_surface) AS distinct_exact_surfaces,
 count(DISTINCT projected) AS distinct_r2_consonantal_projections,
 count(*) FILTER (WHERE hebrew_surface IS NULL OR hebrew_surface='') AS invalid_source_surfaces,
 count(*) FILTER (WHERE projected = '' OR projected !~ '^[א-ת]+$') AS invalid_projections,
 count(*) FILTER (WHERE hebrew_surface LIKE '%/%') AS editorial_slash_occurrences
FROM src;

-- 2. Check the EXACT NMF hashing formula generates no colliding IDs
-- over the actual distinct MT source forms.
WITH forms AS (SELECT DISTINCT hebrew_surface AS surface FROM draft.ot_canonical_tokens_stage),
hashed AS (
 SELECT 'NMF-'||encode(sha256(convert_to(
   'NMF1'||chr(31)||'Hebr'||chr(31)||'R2'||chr(31)||
   'mt_noel_current_exact_surface_v1'||chr(31)||surface,'UTF8')),'hex') AS form_id
 FROM forms
)
SELECT count(*) AS exact_surfaces, count(DISTINCT form_id) AS distinct_nmf_ids
FROM hashed;

-- 3. How many projected marks relate to multiple inherited source labels?
WITH pairs AS (
 SELECT DISTINCT
  regexp_replace(replace(hebrew_surface,'/',''), '[֑-ׇֽֿׁׂׅׄ]', '', 'g') AS mark,
  strong_id
 FROM draft.ot_canonical_tokens_stage WHERE strong_id IS NOT NULL
), per_mark AS (
 SELECT mark,count(DISTINCT strong_id) AS labels FROM pairs GROUP BY mark
)
SELECT count(*) AS source_labeled_marks,
 count(*) FILTER (WHERE labels>1) AS marks_with_multiple_strongs,
 max(labels) AS maximum_strongs_per_mark FROM per_mark;

-- 4. How many existing lexical pools would require explicit collision review?
-- Only summary counts appear; private pool definitions and identity assignments
-- are NOT emitted to public CI or GitHub artifacts.
WITH pairs AS (
 SELECT DISTINCT
  regexp_replace(replace(t.hebrew_surface,'/',''), '[֑-ׇֽֿׁׂׅׄ]', '', 'g') AS mark,
  a.node_id
 FROM draft.ot_canonical_tokens_stage t
 JOIN draft.noel_reality_aliases a ON a.alias_kind='strongs'
  AND a.alias_value='H'||lpad(substring(t.strong_id FROM '[0-9]+'),4,'0')
 WHERE t.strong_id LIKE 'H%'
), grouped AS (
 SELECT mark,count(DISTINCT node_id) AS legacy_pools FROM pairs GROUP BY mark
)
SELECT count(*) AS marks_with_existing_pool_aliases,
 count(*) FILTER (WHERE legacy_pools>1) AS marks_needing_collision_review,
 max(legacy_pools) AS max_legacy_pools_per_mark FROM grouped;

-- 5. Protection and scope: pre-release mark schema absent; existing pool
-- totals and migration history unchanged. Count-only, no researcher text.
SELECT
 (SELECT count(*) FROM information_schema.tables WHERE table_schema='draft'
  AND table_name LIKE 'noel_mark_%') AS live_mark_registry_tables,
 (SELECT count(*) FROM draft.noel_reality_nodes WHERE node_kind='lexical_pool')
  AS live_lexical_pools,
 (SELECT count(*) FROM supabase_migrations.schema_migrations) AS live_migration_rows;

-- Expected preflight results as observed on production 2026-10-15:
-- #1 306785 / 306785 / 112067 / 39956 / 0 / 0 / 146751
-- #2 112067 / 112067
-- #3 39931 / 4335 / 40
-- #4 6789 / 132 / 3
-- #5 0 / 287 / 3063
-- When rerunning, reconcile changes instead of forcing these counts to match.
