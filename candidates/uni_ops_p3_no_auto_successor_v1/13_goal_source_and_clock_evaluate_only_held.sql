-- HELD P3 / Nov 4 6A: Goal STATE evaluation never grants automatic
-- Work issuance from a trigger/clock. Preserve goal state transitions,
-- distinct owner review, historical source evaluation and explicit
-- standalone issuance source. Exact current live function snapshots.
-- This does NOT replace or disable explicit goal original Work mechanisms.
-- Do not install without real source-owner and operational review.
BEGIN;
DO $source$
BEGIN
 IF (SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='goal_clock_tick_v1') IS DISTINCT FROM '4ab780c4ae1215b505112ffebb7f99ec' THEN RAISE EXCEPTION 'P3 Goal source drift: goal_clock_tick_v1'; END IF;
 IF (SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='goal_source_changed_v1') IS DISTINCT FROM '233a3c244aba968bc930ba73c5a346f3' THEN RAISE EXCEPTION 'P3 Goal source drift: goal_source_changed_v1'; END IF;
END;
$source$;

-- Live goal_clock_tick_v1 original MD5 4ab780c4ae1215b505112ffebb7f99ec. Only p_release flag differs.
CREATE OR REPLACE FUNCTION atlas.goal_clock_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_farm record; v_results jsonb:='[]'::jsonb;
begin
  for v_farm in select distinct farm_id from atlas.goals where active loop
    v_results:=v_results||jsonb_build_array(atlas.evaluate_goal_unlocks_v1(v_farm.farm_id,(now() at time zone 'America/Chicago')::date,false));
  end loop;
  return jsonb_build_object('evaluatedAt',now(),'farms',v_results);
end;
$function$


-- Live goal_source_changed_v1 original MD5 233a3c244aba968bc930ba73c5a346f3. Only p_release flag differs.
CREATE OR REPLACE FUNCTION atlas.goal_source_changed_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_farm_id uuid;
begin
  if pg_trigger_depth()>1 then return coalesce(new,old); end if;
  v_farm_id:=coalesce((to_jsonb(new)->>'farm_id')::uuid,(to_jsonb(old)->>'farm_id')::uuid);
  if v_farm_id is not null and exists(select 1 from atlas.goals where farm_id=v_farm_id and active) then
    perform atlas.evaluate_goal_unlocks_v1(v_farm_id,(now() at time zone 'America/Chicago')::date,false);
  end if;
  return coalesce(new,old);
end;
$function$

COMMIT;
