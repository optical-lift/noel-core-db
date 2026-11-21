-- UNI-OPS-01 P3/U2C original writer/legacy successor CENSUS.
-- READ ONLY. Intended for a new source review or ephemeral clone.
-- No private Work contents, People, roster, farm details or task rows returned.
-- Caution: source-text match is not proof of ALL dynamic or indirect DML.
SELECT n.nspname AS owning_schema,
 p.proname AS source_function,
 pg_catalog.pg_get_function_identity_arguments(p.oid) AS signature,
 pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS exact_source_md5,
 CASE
  WHEN p.prosrc ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
   THEN 'direct_canonical_original_insert'
  WHEN p.prosrc ~* 'UPDATE[[:space:]]+atlas[.]work_items'
   THEN 'canonical_original_update'
  ELSE 'canonical_original_caller_to_reconcile'
 END AS type
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('atlas','public')
 AND (
 p.prosrc ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
 OR p.prosrc ~* 'UPDATE[[:space:]]+atlas[.]work_items'
 OR p.prosrc ~* 'establish_continuing_original_work_internal_v1'
 OR p.prosrc ~* 'governor_approve_rhythm_opportunity_self_api_v1'
 )
ORDER BY type,owning_schema,source_function;

-- Explicit old work/task/occurrence producers and one-step dispatchers:
SELECT p.proname AS source_function,
 pg_catalog.pg_get_function_identity_arguments(p.oid) AS signature,
 pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS source_md5,
 (p.prosrc ~* 'release_eligible_work_v1') AS calls_old_release_sweep,
 (p.prosrc ~* 'apply_[[:alnum:]_]+_release_effect_v1') AS calls_serial_release_effect,
 (p.prosrc ~* 'signal_work_occurrence_v1') AS releases_planned_occurrence,
 (p.prosrc ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]tasks') AS inserts_old_task,
 (p.prosrc ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]planned_work_occurrences') AS inserts_old_occurrence
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='atlas'
 AND p.prosrc ~* 'release_eligible_work_v1|apply_[[:alnum:]_]+_release_effect_v1|signal_work_occurrence_v1'
ORDER BY p.proname;

-- The actual current trigger attachments; a matched PL/pgSQL body alone
-- does not establish a trigger is attached or enabled.
SELECT c.relname AS table_name,t.tgname AS trigger_name,
 t.tgenabled AS trigger_enabled,p.proname AS implementing_source,
 pg_catalog.pg_get_triggerdef(t.oid) AS source_attachment
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
WHERE NOT t.tgisinternal
 AND n.nspname='atlas'
 AND c.relname IN (
  'work_items','tasks','planned_work_occurrences',
  'rhythm_state','work_execution_results','work_result_acceptances')
ORDER BY c.relname,t.tgname;

-- Competing potential Future-Work source transports:
SELECT n.nspname AS owning_schema,p.proname,
 pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
 pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) AS def_md5
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('atlas','public')
 AND (p.proname ~* 'rhythm|governed|prework|task.*release|original.*work')
ORDER BY n.nspname,p.proname;
