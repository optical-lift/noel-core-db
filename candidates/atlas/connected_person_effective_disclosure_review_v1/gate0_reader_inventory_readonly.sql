-- Gate 0 read-only replay inventory; run against CURRENT target SQL catalog.
-- This is metadata only, never a replacement for signed PostgREST sessions.
-- Never describe authenticated SQL EXECUTE as proof of HTTP reachability.
WITH functions AS (
  SELECT n.nspname AS schema_name,
    p.proname AS function_name,
    p.oid::regprocedure::text AS signature,
    p.prosecdef AS security_definer,
    has_schema_privilege('authenticated',n.oid,'USAGE') AS schema_usage_auth,
    has_function_privilege('authenticated',p.oid,'EXECUTE') AS sql_execute_auth,
    has_function_privilege('anon',p.oid,'EXECUTE') AS sql_execute_anon,
    pg_get_functiondef(p.oid) AS source_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('atlas','public')
),
farm_function_inventory AS (
  SELECT schema_name,function_name,signature,security_definer,
    schema_usage_auth,sql_execute_auth,sql_execute_anon,
    CASE
      WHEN source_body ILIKE '%atlas.is_farm_owner(%'
        OR source_body ILIKE '%atlas.is_farm_manager_or_owner(%'
        THEN 'legacy_farm_owner_or_manager_check_present'
      WHEN source_body ILIKE '%atlas.is_farm_member(%'
        OR source_body ILIKE '%atlas.current_farm_role(%'
        OR source_body ILIKE '%atlas.farm_memberships%'
        THEN 'farm_membership_or_role_check_present'
      ELSE 'no_recognized_farm_gate_in_body'
    END AS detected_gate_hint,
    (source_body ILIKE '%atlas.zones%'
     OR source_body ILIKE '%atlas.growing_objects%'
     OR source_body ILIKE '%atlas.crop_cycles%'
     OR source_body ILIKE '%atlas.crop_observations%'
     OR source_body ILIKE '%atlas.object_contents%'
     OR source_body ILIKE '%atlas.care_state_history%') AS reads_farm_subject_source,
    (source_body ILIKE '%farm_snapshot_for_member_v1%') AS references_farm_snapshot,
    (source_body ILIKE '%zone_registry_source_v1%'
     OR source_body ILIKE '%object_crop_bed_map_v1%'
     OR source_body ILIKE '%farm_care_zone_v1%') AS references_three_priority_readers
  FROM functions
)
SELECT *
FROM farm_function_inventory
WHERE security_definer
  AND (
    (reads_farm_subject_source
      AND detected_gate_hint<>'no_recognized_farm_gate_in_body')
    OR references_farm_snapshot
    OR references_three_priority_readers
  )
ORDER BY sql_execute_auth DESC,schema_name,function_name,signature;

-- Direct table exposure is a distinct source path; inspect ACL and RLS separately.
SELECT n.nspname AS schema_name,c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  has_table_privilege('authenticated',c.oid,'SELECT') AS authenticated_select,
  has_table_privilege('anon',c.oid,'SELECT') AS anon_select
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='atlas'
  AND c.relkind IN ('r','p','v','m')
  AND c.relname IN
    ('zones','growing_objects','crop_cycles','crop_observations',
     'object_contents','care_state_history','object_activity_events',
     'work_items','work_item_context_links','work_allocations')
ORDER BY c.relname;

-- Catalog findings show SQL-level privileges and implementation hints only.
-- PostgREST exposure, application server routes, storage, cache and search
-- must be inventoried independently; no signed-user guarantee is inferred.
