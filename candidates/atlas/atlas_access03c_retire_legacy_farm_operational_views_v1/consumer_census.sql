-- ACCESS-03C consumer census: READ ONLY. Source/authority inventory, no user rows.
-- Run only to re-verify drift, not as a schema migration or deployment.
-- An occurrence in pg_get_functiondef may be an audit-list STRING, not a call.
WITH expected(signature, family, observed_source_md5) AS (
  VALUES
  ('atlas.farm_care_object_card_v1(uuid)', 'care helper', '912250a84abe2680e98890862316f1c3'),
  ('atlas.farm_care_summary_v1(uuid,integer)', 'care signed reader', '48a41b97be1f51ce7aa7a12422777bf6'),
  ('atlas.farm_care_zone_card_v1(uuid)', 'care helper', '36fe032b49403d4978385f24fb6b5822'),
  ('atlas.farm_care_zone_v1(uuid,text,integer)', 'protected care signed reader', 'd83dd57420af32defe491a3d1ece7b1b'),
  ('atlas.tending_bed_v1(uuid,text,text)', 'tending reader', 'c9311300e2b5fb0bef2e0db5f87bca2d'),
  ('atlas.tending_board_v1(uuid,text,date)', 'tending reader', '2ad9b2467a2102e86ada62eb0cc5ae39'),
  ('atlas.tending_card_json_v1(uuid,jsonb,boolean)', 'tending v1 helper', '510f783e3162b1052b6081fb8fa3271b'),
  ('atlas.tending_card_json_v2(uuid,uuid,jsonb,boolean)', 'tending v2 helper', '5621f5f54676f0310f54ea726cf7340e'),
  ('atlas.tending_task_context_v1(uuid,uuid,text)', 'tending v1 reader', '26ca1f7a3d1a16f1fc5b1aed9f2fae42'),
  ('atlas.tending_task_context_v2(uuid,uuid,text,text)', 'tending v2 reader', '48a972d24a0b168211fbde6d8e6eb5d0')
),
resolved AS (
  SELECT e.*, to_regprocedure(e.signature) AS function_oid,
         split_part(split_part(e.signature, '.', 2), '(', 1) AS function_name
  FROM expected e
)
SELECT r.signature, r.family, r.function_oid IS NOT NULL AS exists_now,
       md5(pg_get_functiondef(r.function_oid)) AS actual_source_md5,
       r.observed_source_md5,
       md5(pg_get_functiondef(r.function_oid)) = r.observed_source_md5 AS matches_observed_source,
       p.prosecdef AS security_definer,
       has_function_privilege('authenticated', r.function_oid, 'EXECUTE') AS authenticated_execute,
       has_function_privilege('anon', r.function_oid, 'EXECUTE') AS anon_execute,
       ARRAY(
         SELECT q.oid::regprocedure::text
         FROM pg_proc q JOIN pg_namespace n ON n.oid=q.pronamespace
         WHERE q.prokind='f' AND q.oid<>r.function_oid
           AND n.nspname NOT IN ('pg_catalog','information_schema')
           AND pg_get_functiondef(q.oid) LIKE ('%' || r.function_name || '%')
         ORDER BY q.oid::regprocedure::text
       ) AS textual_references_not_proven_calls
FROM resolved r LEFT JOIN pg_proc p ON p.oid=r.function_oid
ORDER BY r.signature;
