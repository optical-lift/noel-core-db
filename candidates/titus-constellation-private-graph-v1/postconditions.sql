-- Test against the schema-only protected production clone; do not add fake research rows.
DO $test$
DECLARE v jsonb;
BEGIN
 SELECT public.titus_constellation_private_snapshot_v1() INTO v;
 IF v->>'sourceMode' IS DISTINCT FROM 'live'
 OR jsonb_typeof(v->'nodes') <> 'array'
 OR jsonb_typeof(v->'edges') <> 'array'
 OR jsonb_typeof(v->'omissions') <> 'array'
 THEN RAISE EXCEPTION 'Invalid private Constellation graph contract'; END IF;
 IF has_function_privilege('anon','public.titus_constellation_private_snapshot_v1()','EXECUTE')
 OR has_function_privilege('authenticated','public.titus_constellation_private_snapshot_v1()','EXECUTE')
 OR NOT has_function_privilege('service_role','public.titus_constellation_private_snapshot_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'The graph RPC must allow service-role transport only'; END IF;
 IF EXISTS (
  SELECT 1 FROM jsonb_array_elements(v->'edges') e
  WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'nodes') n WHERE n->>'id'=e->>'from')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'nodes') n WHERE n->>'id'=e->>'to')
 ) THEN RAISE EXCEPTION 'Rendered relationship with absent endpoint'; END IF;
END $test$;
