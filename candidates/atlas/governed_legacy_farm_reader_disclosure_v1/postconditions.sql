-- Postconditions on a disposable production-shaped schema clone.
DO $check$
DECLARE v_name text; v_def text;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['zone_registry_source_v1','object_crop_bed_map_v1','farm_care_zone_v1','farm_care_object_v1','farm_care_summary_v1','farm_snapshot_for_member_v1']) LOOP
   SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname=v_name LIMIT 1;
   IF v_def IS NULL OR position('require_governed_farm_full_disclosure_self_v1' IN v_def)=0 THEN
     RAISE EXCEPTION 'Legacy disclosure reader not guarded: %',v_name;
   END IF;
   IF position('atlas.is_farm_member' IN v_def)>0
      OR position('atlas.current_farm_role' IN v_def)>0
      OR position('atlas.farm_memberships' IN v_def)>0 THEN
     RAISE EXCEPTION 'Legacy membership bypass persists: %',v_name;
   END IF;
 END LOOP;
 IF has_function_privilege('authenticated',
    'atlas.require_governed_farm_full_disclosure_self_v1(uuid)', 'EXECUTE') THEN
   RAISE EXCEPTION 'Internal authorization helper must not be callable directly';
 END IF;
END
$check$;
-- Signed owner/connected Person/outsider/anon direct-RPC denial is still
-- mandatory; static clone assertions alone do not establish effective access.
