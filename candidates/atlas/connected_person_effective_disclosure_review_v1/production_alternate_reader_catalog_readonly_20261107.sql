-- Noel #2255 / Atlas #437: 2026-11-07 CURRENT production checkpoint.
-- READ ONLY. No SQL payload from this file is an authorization proof or
-- a substitute for signed independent GoTrue/PostgREST sessions.
-- The old farm-atlas Vercel project has been deleted. Removing that HTTP
-- carrier does NOT remove SQL functions, privileges or alternate clients.
--
-- 1. Named native/public alternate-reader inventory (catalog metadata only).
-- Named functions can be reachable by dependent SECURITY DEFINER functions
-- even without a directly callable public wrapper.
WITH targeted(name) AS (
 VALUES
 ('zone_registry_source_v1'), ('object_crop_bed_map_v1'),
 ('farm_care_zone_v1'), ('farm_snapshot_for_member_v1'),
 ('farm_care_summary_v1'), ('farm_care_object_v1'),
 ('object_workbench_v1'), ('grow_room_state_v1'), ('universal_home_v1'),
 ('connected_person_my_work_self_api_v1'),
 ('connected_person_company_work_today_self_api_v1'),
 ('connected_person_company_work_day_self_api_v1'),
 ('company_work_worker_day_self_api_v1'),
 ('company_work_worker_day_refresh_self_api_v1'),
 ('worker_report_company_work_projection_self_api_v1'),
 ('company_work_employee_home_self_api_v1'),
 ('connected_person_work_approved_fields_self_api_v1'),
 ('governor_decide_connected_person_work_field_self_api_v1'),
 ('connected_person_authorized_ledger_work_self_api_v1')
), source_functions AS (
 SELECT p.oid,n.nspname AS schema_name,p.proname,p.prosecdef,
        pg_get_functiondef(p.oid) AS body
 FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('atlas','public')
)
SELECT t.name,s.schema_name,s.oid::regprocedure::text AS signature,
       s.prosecdef AS security_definer,
       CASE WHEN s.oid IS NOT NULL
         THEN has_schema_privilege('authenticated',
                to_regnamespace(s.schema_name),'USAGE') END
         AS authenticated_schema_usage,
       CASE WHEN s.oid IS NOT NULL
         THEN has_function_privilege('authenticated',s.oid,'EXECUTE') END
         AS authenticated_execute,
       CASE WHEN s.oid IS NOT NULL
         THEN has_function_privilege('anon',s.oid,'EXECUTE') END
         AS anonymous_execute,
       (s.body ILIKE '%person_has_native_ledger_connection_v1%')
         AS mentions_native_connection,
       (s.body ILIKE '%company_work_native_ledger_exact_source_v1%')
         AS mentions_exact_work_source,
       (s.body ILIKE '%company_work_native_ledger_relevance%')
         AS mentions_work_relevance,
       (s.body ILIKE '%principal_has_ledger_authority_v1%')
         AS mentions_ledger_governing_authority,
       (s.body ILIKE '%instructions%') AS mentions_instructions
FROM targeted t
LEFT JOIN source_functions s ON s.proname=t.name
ORDER BY t.name,s.schema_name,s.oid::regprocedure::text;

-- 2. Table SELECT privileges and RLS are distinct from definer/function reads.
SELECT n.nspname AS schema_name,c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       has_table_privilege('authenticated',c.oid,'SELECT')
         AS authenticated_select,
       has_table_privilege('anon',c.oid,'SELECT') AS anonymous_select
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='atlas' AND c.relkind IN ('r','p','v','m')
  AND c.relname IN ('zones','growing_objects','crop_cycles',
     'crop_observations','object_contents','care_state_history',
     'object_activity_events','work_items','work_item_context_links',
     'work_allocations')
ORDER BY c.relname;

-- 3. Required candidate remains held. This records existence, not safe access.
SELECT
 to_regclass('atlas.connected_person_work_field_decision_events_v1')::text
   AS held_decision_table,
 to_regprocedure('public.connected_person_work_approved_fields_self_api_v1(uuid,uuid)')::text
   AS held_approved_fields_reader,
 to_regprocedure('public.governor_decide_connected_person_work_field_self_api_v1(uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)')::text
   AS held_governor_writer,
 EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261026010327'
 ) AS existing_farm_crop_custody_migration_recorded;

-- 4. Current original Work state aggregate only, no Person or Work titles.
SELECT w.work_state,
       COUNT(DISTINCT w.id) AS original_work_count,
       COUNT(DISTINCT a.id) FILTER (WHERE a.state='active')
         AS current_responsibility_allocations
FROM atlas.work_items w
LEFT JOIN atlas.work_allocations a ON a.work_item_id=w.id
WHERE w.source_object_type='legacy_task_slice'
GROUP BY w.work_state
ORDER BY w.work_state;

-- SQL metadata alone cannot certify PostgREST schema exposure, HTTP
-- reachability, revoked JWT behavior, privacy, field-level rights or
-- correctness of a legacy worker's positive Work experience.
