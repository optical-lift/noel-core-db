-- HELD P3 harvest-output successor issuer cutover, exact live
-- pg_get_functiondef MD5 b2425633eefe7bee95221be6f96079a8, source only, not a migration.
-- A harvest-output Result may establish physical inventory evidence,
-- but does not authorize the next preparation Work. Existing source
-- observation inserts and pre-existing Work are unchanged.
BEGIN;
DO $pin$
BEGIN
 IF (SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
     FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas'
       AND p.proname='queue_flower_preparation_after_harvest_v1')
     IS DISTINCT FROM 'b2425633eefe7bee95221be6f96079a8' THEN
  RAISE EXCEPTION 'Harvest-output task-trigger source drift';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
     AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
     AND t.tgenabled<>'D'
 ) THEN
  RAISE EXCEPTION 'Actual harvest-output trigger attachment changed';
 END IF;
END;
$pin$;

CREATE OR REPLACE FUNCTION atlas.queue_flower_preparation_after_harvest_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_task_series_key text;
begin
  select t.task_series_key
  into v_task_series_key
  from atlas.tasks t
  where t.id = new.task_id;

  if v_task_series_key = 'anna_harvest_thursday_weekly' then
    return new;
  end if;

  -- Nov 4 6A. A firsthand harvested-output observation is durable
  -- source evidence, not a standing grant for downstream Work.
  -- No automatic preparation Task, planned occurrence, Person allocation
  -- or Clock. Separate owner source-authorized Work is still required.
  -- Retain historical existing preparation Task/occurrence untouched.
  NULL;

  return new;
end;
$function$
COMMIT;
