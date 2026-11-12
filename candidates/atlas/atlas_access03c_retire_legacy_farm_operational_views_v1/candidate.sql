-- ACCESS-03C SOURCE ONLY: retire obsolete selected-farm-first reader VIEWS.
-- NOT production authorization; no row deletion, no base table alteration.
-- Requires ACCESS-03B governed two-table RLS to be independently released FIRST.
-- Atlas universal Person/Principal/Organization/Ledger source RPCs stay intact.
BEGIN;
DO $access03c_preflight$
DECLARE
  v record;
  observed_dependents text[];
BEGIN
  -- The two direct farm table readers must be governed before any legacy
  -- view is removed. A source-only 03B draft is NOT a deployed prerequisite.
  IF to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NULL
     OR (SELECT count(*) FROM pg_catalog.pg_policies
         WHERE schemaname='atlas' AND
           ((tablename='growing_objects' AND policyname='growing_objects_read_operations')
           OR (tablename='crop_cycles' AND policyname='crop_cycles_read_operations'))
           AND cmd='SELECT'
           AND qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)') <> 2
     OR has_table_privilege('authenticated','atlas.zones','SELECT')
  THEN
    RAISE EXCEPTION 'ACCESS03C requires released governed 03B and retired ACCESS03A zone reader';
  END IF;

  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='atlas' AND c.relname IN (
          'farm_care_object_state_v1','farm_care_object_projection_v1',
          'tending_task_track_v1','v_farm_object_operational_state')
          AND c.relkind='v' AND 'security_invoker=true'=ANY(c.reloptions)) <> 4
  THEN RAISE EXCEPTION 'ACCESS03C obsolete view family inventory drift'; END IF;

  FOR v IN SELECT * FROM (VALUES
     ('farm_care_object_state_v1'::text,'d541cb041506c3fdd3594cf8f47a8e8d'::text,true),
     ('farm_care_object_projection_v1','1134b7267249ac92a60176f4da23f6a3',false),
     ('tending_task_track_v1','518463fd12aeb5f3465998833808606b',false),
     ('v_farm_object_operational_state','5cd80e07b501999dc4f64fd4601e4300',true)
   ) t(view_name,expected_md5,expected_authenticated_select)
  LOOP
    IF md5(pg_get_viewdef(format('atlas.%I',v.view_name)::regclass,true)) <> v.expected_md5
       OR has_table_privilege('authenticated',
            format('atlas.%I',v.view_name),'SELECT') IS DISTINCT FROM v.expected_authenticated_select
       OR has_table_privilege('anon',format('atlas.%I',v.view_name),'SELECT')
    THEN
      RAISE EXCEPTION 'ACCESS03C view definition/ACL drift: %',v.view_name;
    END IF;
  END LOOP;

  -- Explicitly account for both dependent views instead of silently CASCADE
  -- deleting any unknown downstream object.
  SELECT coalesce(array_agg(DISTINCT n.nspname||'.'||c.relname
      ORDER BY n.nspname||'.'||c.relname),ARRAY[]::text[])
    INTO observed_dependents
  FROM pg_depend d JOIN pg_rewrite rw ON rw.oid=d.objid
    JOIN pg_class c ON c.oid=rw.ev_class
    JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE d.refobjid='atlas.farm_care_object_state_v1'::regclass
    AND c.oid<>'atlas.farm_care_object_state_v1'::regclass
    AND c.relkind IN ('v','m');
  IF observed_dependents<>ARRAY[
      'atlas.farm_care_object_projection_v1',
      'atlas.tending_task_track_v1']::text[]
  THEN RAISE EXCEPTION 'ACCESS03C unexpected downstream view dependency';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_depend d JOIN pg_rewrite rw ON rw.oid=d.objid
      JOIN pg_class c ON c.oid=rw.ev_class
    WHERE d.refobjid=ANY(ARRAY[
      'atlas.farm_care_object_projection_v1'::regclass,
      'atlas.tending_task_track_v1'::regclass,
      'atlas.v_farm_object_operational_state'::regclass])
      AND c.oid<>d.refobjid AND c.relkind IN ('v','m')
  ) THEN RAISE EXCEPTION 'ACCESS03C unreviewed view family dependents'; END IF;

  -- Replacing a farm-only projection must not remove universal current
  -- source APIs. No legacy farm role, membership, or owner task privilege
  -- may become an alternate path.
  IF to_regprocedure(
       'atlas.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)') IS NULL
    OR to_regprocedure('atlas.governor_farm_current_inventory_options_self_api_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.zone_registry_source_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.object_crop_bed_map_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.farm_care_zone_v1(uuid,text,integer)') IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C canonical source API prerequisite absent'; END IF;
END
$access03c_preflight$;

-- Dependency-safe order; every DROP explicitly RESTRICT.
-- If a new function/view/constraint depends on these, fail transactionally.
DROP VIEW atlas.farm_care_object_projection_v1 RESTRICT;
DROP VIEW atlas.tending_task_track_v1 RESTRICT;
DROP VIEW atlas.farm_care_object_state_v1 RESTRICT;
DROP VIEW atlas.v_farm_object_operational_state RESTRICT;
COMMIT;
