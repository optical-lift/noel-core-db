-- ACCESS-03C read-only postconditions; run only on disposable clone before release.
DO $access03c_postconditions$
BEGIN
  IF to_regclass('atlas.farm_care_object_state_v1') IS NOT NULL
     OR to_regclass('atlas.farm_care_object_projection_v1') IS NOT NULL
     OR to_regclass('atlas.tending_task_track_v1') IS NOT NULL
     OR to_regclass('atlas.v_farm_object_operational_state') IS NOT NULL
  THEN RAISE EXCEPTION 'ACCESS03C obsolete farm view still exists'; END IF;

  IF to_regclass('atlas.zones') IS NULL
     OR to_regclass('atlas.growing_objects') IS NULL
     OR to_regclass('atlas.crop_cycles') IS NULL
     OR to_regclass('atlas.farm_memberships') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_class c
           WHERE c.oid='atlas.growing_objects'::regclass AND c.relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class c
           WHERE c.oid='atlas.crop_cycles'::regclass AND c.relrowsecurity)
  THEN RAISE EXCEPTION 'ACCESS03C retained canonical tables / RLS missing'; END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_policies
       WHERE schemaname='atlas'
         AND ((tablename='growing_objects' AND policyname='growing_objects_read_operations')
             OR (tablename='crop_cycles' AND policyname='crop_cycles_read_operations'))
         AND cmd='SELECT'
         AND qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)')<>2
    OR has_table_privilege('authenticated','atlas.zones','SELECT')
  THEN RAISE EXCEPTION 'ACCESS03C released 03A/03B security postconditions not preserved'; END IF;

  IF to_regprocedure(
       'atlas.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)') IS NULL
    OR to_regprocedure('atlas.governor_farm_current_inventory_options_self_api_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.zone_registry_source_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.object_crop_bed_map_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.farm_care_zone_v1(uuid,text,integer)') IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C universal native source API removed'; END IF;
END
$access03c_postconditions$;
