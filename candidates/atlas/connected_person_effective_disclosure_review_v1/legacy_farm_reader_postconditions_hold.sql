-- Structural postconditions for legacy_farm_reader_body_containment_hold.sql.
-- NOT signed-person evidence; do not promote a passing result to privacy assurance.
BEGIN;
DO $verify$
DECLARE
 v oid;
 v_sql text;
 v_name text;
 v_sig text;
BEGIN
 FOR v_name,v_sig IN SELECT * FROM (VALUES
  ('zone_registry_source_v1','atlas.zone_registry_source_v1(uuid)'),
  ('object_crop_bed_map_v1','atlas.object_crop_bed_map_v1(uuid)'),
  ('farm_care_zone_v1','atlas.farm_care_zone_v1(uuid,text,integer)'),
  ('farm_snapshot_for_member_v1','atlas.farm_snapshot_for_member_v1(uuid)')
 ) t(name,sig) LOOP
  v := to_regprocedure(v_sig);
  IF v IS NULL THEN RAISE EXCEPTION 'Legacy reader missing: %',v_sig; END IF;
  SELECT pg_get_functiondef(v) INTO v_sql;
  IF v_sql NOT LIKE '%atlas.is_farm_owner(%'
     OR v_sql NOT LIKE '%Resource not found.%'
     OR has_function_privilege('authenticated',v,'EXECUTE')
     OR has_function_privilege('anon',v,'EXECUTE')
  THEN RAISE EXCEPTION 'Legacy reader containment missing for %',v_sig; END IF;
 END LOOP;
 v:=to_regprocedure('atlas.universal_home_v1(uuid,uuid,date,date)');
 IF v IS NULL THEN RAISE EXCEPTION 'Universal home missing'; END IF;
 SELECT pg_get_functiondef(v) INTO v_sql;
 IF (length(v_sql)-length(replace(v_sql, 'fm.role = ''owner''',''))) / length('fm.role = ''owner''') < 3
   OR NOT has_function_privilege('authenticated',v,'EXECUTE')
 THEN RAISE EXCEPTION 'Universal home owner-only legacy farm selection not proven'; END IF;
END;
$verify$;
ROLLBACK;
