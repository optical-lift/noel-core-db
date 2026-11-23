-- HELD: additional disposable clone-only postconditions for original Worker Day reader.
-- Companion to test-only source candidate, not authorization for live release.
DO $atlas_worker_day_projection_post$
DECLARE v_body text;
BEGIN
 v_body:=pg_get_functiondef('atlas.worker_day_selection_overlay_live_v1(uuid,uuid,date,jsonb)'::regprocedure);
 IF position('task_release_queue_items' IN lower(v_body))>0
 OR position('v_queue_task' IN lower(v_body))>0
 OR position('worker_week_day_capacity_v1' IN v_body)=0
 OR position('presented_work_selection_rows_v1' IN v_body)=0
 OR position('sourceKind' IN v_body)=0
 OR NOT EXISTS(
    SELECT 1 FROM pg_proc p WHERE p.oid='atlas.worker_day_selection_overlay_live_v1(uuid,uuid,date,jsonb)'::regprocedure
    AND p.proowner='postgres'::regrole AND p.prosecdef
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
 )
 THEN RAISE EXCEPTION 'Worker Day future queue cutover postconditions failed'; END IF;
 IF to_regclass('atlas.task_release_queue_items') IS NULL
    OR to_regclass('atlas.work_items') IS NULL
    OR to_regclass('atlas.work_allocations') IS NULL
    OR to_regclass('atlas.work_execution_plans') IS NULL
 THEN RAISE EXCEPTION 'Historical/canonical Work evidence lost'; END IF;
END $atlas_worker_day_projection_post$;
