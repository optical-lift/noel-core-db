-- ACCESS-03A guarded legacy DIRECT SELECT retirement; candidate only.
BEGIN;
DO $access03_preflight$
BEGIN
  IF (SELECT count(*) FROM pg_catalog.pg_policies
      WHERE schemaname='atlas' AND tablename='zones') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname='atlas' AND tablename='zones'
         AND policyname='zones_read_operations'
         AND cmd='SELECT' AND roles::text='{authenticated}'
         AND qual='atlas.can_read_farm_operations(farm_id)'
     ) THEN
    RAISE EXCEPTION 'ACCESS03 legacy zone policy changed';
  END IF;
  IF NOT has_table_privilege('authenticated','atlas.zones','SELECT')
    OR NOT has_table_privilege('authenticated','atlas.v_crop_cycle_registry','SELECT')
    OR has_table_privilege('anon','atlas.zones','SELECT')
    OR has_table_privilege('anon','atlas.v_crop_cycle_registry','SELECT') THEN
    RAISE EXCEPTION 'ACCESS03 direct ACL baseline changed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid='atlas.zones'::regclass AND c.relrowsecurity
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid='atlas.v_crop_cycle_registry'::regclass
      AND 'security_invoker=true'=ANY(c.reloptions)
  ) THEN
    RAISE EXCEPTION 'ACCESS03 source RLS or invoker view changed';
  END IF;
  IF md5(pg_catalog.pg_get_functiondef(
    'atlas.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)'::regprocedure
  )) <> '3c3268893122b8d3a118c06103766d87'
  OR md5(pg_catalog.pg_get_functiondef(
    'atlas.zone_registry_source_v1(uuid)'::regprocedure
  )) <> '9ffe4ddb1e8ab84f532ba599986536ef' THEN
    RAISE EXCEPTION 'ACCESS03 current governed source changed';
  END IF;
END
$access03_preflight$;
DROP POLICY zones_read_operations ON atlas.zones;
REVOKE SELECT ON TABLE atlas.zones FROM authenticated;
REVOKE SELECT ON TABLE atlas.v_crop_cycle_registry FROM authenticated;
COMMIT;
