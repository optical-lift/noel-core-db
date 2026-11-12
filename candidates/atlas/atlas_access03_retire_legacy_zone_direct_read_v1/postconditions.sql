-- ACCESS-03A required postconditions; read only.
DO $access03_post$
BEGIN
  IF has_table_privilege('authenticated','atlas.zones','SELECT')
    OR has_table_privilege('authenticated','atlas.v_crop_cycle_registry','SELECT')
    OR has_table_privilege('anon','atlas.zones','SELECT')
    OR has_table_privilege('anon','atlas.v_crop_cycle_registry','SELECT')
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_policies
      WHERE schemaname='atlas' AND tablename='zones'
        AND cmd IN ('SELECT','ALL')) THEN
    RAISE EXCEPTION 'ACCESS03 legacy direct SELECT still reachable';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
      WHERE c.oid='atlas.zones'::regclass AND c.relrowsecurity)
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
      WHERE c.oid='atlas.v_crop_cycle_registry'::regclass
        AND 'security_invoker=true'=ANY(c.reloptions)) THEN
    RAISE EXCEPTION 'ACCESS03 source table or invoker view missing';
  END IF;
  IF md5(pg_catalog.pg_get_functiondef(
    'atlas.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)'::regprocedure
  )) <> '3c3268893122b8d3a118c06103766d87'
    OR md5(pg_catalog.pg_get_functiondef(
    'atlas.zone_registry_source_v1(uuid)'::regprocedure
  )) <> '9ffe4ddb1e8ab84f532ba599986536ef' THEN
    RAISE EXCEPTION 'ACCESS03 canonical source reader changed';
  END IF;
END
$access03_post$;
