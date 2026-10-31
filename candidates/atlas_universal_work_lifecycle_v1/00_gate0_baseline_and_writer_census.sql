-- GATE 0 — read-only original-Work lifecycle custody and writer inventory.
-- Capture this immediately before any future production release and compare
-- after each cutover. Data is not rewritten or reclassified by this query.
SELECT
 (SELECT count(*) FROM atlas.work_items) AS canonical_original_work,
 (SELECT count(*) FROM atlas.work_items WHERE work_state='completed') AS marked_completed,
 (SELECT count(*) FROM atlas.work_execution_results) AS original_results,
 (SELECT count(*) FROM atlas.work_result_acceptances) AS original_acceptances,
 (SELECT count(*) FROM atlas.work_execution_plans) AS original_plans,
 (SELECT count(*) FROM atlas.work_execution_plan_events) AS original_plan_events,
 (SELECT count(*) FROM atlas.work_allocations) AS original_allocations,
 (SELECT count(*) FROM atlas.tasks) AS legacy_task_rows,
 (SELECT count(*) FROM atlas.task_transitions) AS legacy_task_transitions,
 (SELECT count(*) FROM atlas.task_outcome_events) AS legacy_task_outcomes,
 (SELECT count(*) FROM atlas.work_items w
  WHERE w.work_state='completed' AND NOT EXISTS(
   SELECT 1 FROM atlas.work_result_acceptances a
   WHERE a.work_item_id=w.id AND a.decision='accepted'))
  AS completed_without_accepted_result;

-- This is a *catalog-backed starting census*, not a complete proof that
-- there is no dynamic SQL or trigger-mediated writer elsewhere. Review
-- every source and transitive trigger before removing any old pathway.
SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS args,
 md5(pg_get_functiondef(p.oid)) AS source_fingerprint,
 CASE
  WHEN pg_get_functiondef(p.oid) ILIKE '%insert into atlas.work_execution_results%'
   THEN 'inserts original result'
  WHEN pg_get_functiondef(p.oid) ILIKE '%update atlas.work_items%'
   THEN 'writes Work state or fields'
  WHEN pg_get_functiondef(p.oid) ILIKE '%update atlas.work_allocations%'
   THEN 'writes responsibility or allocation'
  ELSE 'requires source review'
 END AS scan_classification
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='atlas' AND p.prokind='f'
 AND (
  pg_get_functiondef(p.oid) ILIKE '%insert into atlas.work_execution_results%'
  OR pg_get_functiondef(p.oid) ILIKE '%update atlas.work_items%'
  OR pg_get_functiondef(p.oid) ILIKE '%update atlas.work_allocations%'
 )
ORDER BY p.proname;

-- Trigger inventory includes legacy farm/task machinery: DO NOT drop it
-- merely because the new Work lifecycle begins shadow capture.
SELECT c.relname AS original_table,t.tgname AS trigger_name,
 p.proname AS function_name,pg_get_triggerdef(t.oid) AS trigger_source
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_proc p ON p.oid=t.tgfoid
WHERE n.nspname='atlas' AND NOT t.tgisinternal
 AND c.relname IN (
  'work_items','work_allocations','work_execution_plans',
  'work_execution_results','work_result_acceptances',
  'work_execution_plan_events','tasks')
ORDER BY c.relname,t.tgname;
