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

-- Signed C1 + original fictional Farm/member fixture must already be loaded by
-- Noel's existing local protected clone harness. PostgreSQL output test only;
-- all names/IDs below are disposable and never access production records.
DO $atlas_worker_day_future_projection_behavior$
DECLARE v_future jsonb; v_today jsonb; v_input jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM atlas.farms f
               WHERE f.id='e5200000-0000-4000-8000-000000000851'::uuid
                 AND f.stable_key='held-retirement-farm-a')
 OR NOT EXISTS(SELECT 1 FROM atlas.farm_memberships fm
               WHERE fm.id='e5200000-0000-4000-8000-000000000862'::uuid
                 AND fm.farm_id='e5200000-0000-4000-8000-000000000851'::uuid
                 AND fm.active AND fm.role='farm_hand')
 THEN RAISE EXCEPTION 'Missing trusted original synthetic farm/worker fixture'; END IF;

 v_input:=jsonb_build_object(
   'availableWorkerDay',true,
   'automaticWork',jsonb_build_array(
     jsonb_build_object('sourceKind','queue','sourceId',
        'e5200000-0000-4000-8000-000000000888','expectedActiveMinutes',43),
     jsonb_build_object('sourceKind','trusted_nonqueue_future',
        'sourceId','e5200000-0000-4000-8000-000000000889','expectedActiveMinutes',12)
   )
 );
 v_future:=atlas.worker_day_selection_overlay_live_v1(
   'e5200000-0000-4000-8000-000000000851'::uuid,
   'e5200000-0000-4000-8000-000000000862'::uuid,
   CURRENT_DATE+7, v_input);
 IF coalesce(jsonb_typeof(v_future->'automaticWork'),'')<>'array'
    OR jsonb_array_length(v_future->'automaticWork')<>1
    OR v_future->'automaticWork'->0->>'sourceKind' IS DISTINCT FROM 'trusted_nonqueue_future'
    OR (v_future->>'automaticPaidMinutes')::integer IS DISTINCT FROM 12
    OR coalesce(jsonb_typeof(v_future->'realWork'),'')<>'array'
    OR coalesce(jsonb_typeof(v_future->'nextUp'),'')<>'array'
 THEN RAISE EXCEPTION 'Future Worker Day projected old queue or lost nonqueue native work'; END IF;

 v_today:=atlas.worker_day_selection_overlay_live_v1(
   'e5200000-0000-4000-8000-000000000851'::uuid,
   'e5200000-0000-4000-8000-000000000862'::uuid,
   CURRENT_DATE, v_input);
 IF coalesce(jsonb_typeof(v_today->'automaticWork'),'')<>'array'
    OR jsonb_array_length(v_today->'automaticWork')<>0
 THEN RAISE EXCEPTION 'Today Worker Day automatic queue suppression changed'; END IF;
END $atlas_worker_day_future_projection_behavior$;
