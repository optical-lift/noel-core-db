-- Schema-only disposable clone and release postconditions for five exact live consumers.
DO $atlas_legacy_consumer_postconditions$
DECLARE r record; src text; body_count integer;
BEGIN
 IF to_regclass('atlas.task_release_queue_items') IS NULL
    OR to_regclass('atlas.work_items') IS NULL
    OR to_regclass('atlas.work_requirements') IS NULL THEN
  RAISE EXCEPTION 'Source, current Work or Requirements lost';
 END IF;
 FOR r IN SELECT * FROM (VALUES
   ('atlas.capture_deferred_task_v1()'),
   ('atlas.deal_next_paid_work_v1(uuid,uuid,date,boolean)'),
   ('atlas.defer_existing_task_to_occurrence_v1(uuid,text)'),
   ('atlas.floating_paid_work_candidates_v1(uuid,uuid,date)'),
   ('atlas.worker_future_day_projection_source_v1(uuid,uuid,date,date)')
 ) AS expected(signature)
 LOOP
   IF to_regprocedure(r.signature) IS NULL THEN RAISE EXCEPTION 'Required live function % removed',r.signature; END IF;
   src:=pg_get_functiondef(to_regprocedure(r.signature)::oid);
   IF strpos(lower(src),'task_release_queue_items')>0 THEN
     RAISE EXCEPTION 'Old queue table still referenced by %',r.signature;
   END IF;
 END LOOP;
 IF position('release_queue_key' IN pg_get_functiondef('atlas.floating_paid_work_candidates_v1(uuid,uuid,date)'::regprocedure))=0
 OR position('release_queue_key' IN pg_get_functiondef('atlas.deal_next_paid_work_v1(uuid,uuid,date,boolean)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'Obsolete queue-origin task exclusion lost';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger t WHERE t.tgrelid='atlas.tasks'::regclass
   AND t.tgname='zz_capture_deferred_task_v1' AND NOT t.tgisinternal
 ) THEN RAISE EXCEPTION 'Deferred-task original preservation trigger removed'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger t WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
   AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
   AND NOT t.tgisinternal
 ) THEN RAISE EXCEPTION 'Real harvest preparation trigger lost'; END IF;
 SELECT count(*)::integer INTO body_count FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('atlas','public') AND p.prokind IN ('f','p')
   AND pg_get_functiondef(p.oid) ILIKE '%task_release_queue_items%';
 IF body_count<>29 THEN
   RAISE EXCEPTION 'Expected only five of 34 live source consumers retired, got % remaining',body_count;
 END IF;
END $atlas_legacy_consumer_postconditions$;
