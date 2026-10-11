DO $proof$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM information_schema.tables
   WHERE table_schema='atlas' AND table_name='titus_constellation_viewer_grants')
 THEN RAISE EXCEPTION 'Missing Atlas-owned research viewer permission store'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.titus_constellation_viewer_grants'::regclass)
 THEN RAISE EXCEPTION 'Missing grant-table RLS'; END IF;
 IF has_table_privilege('anon','atlas.titus_constellation_viewer_grants','SELECT')
   OR has_table_privilege('authenticated','atlas.titus_constellation_viewer_grants','SELECT')
   OR has_table_privilege('anon','atlas.titus_constellation_viewer_grants','INSERT')
   OR has_table_privilege('authenticated','atlas.titus_constellation_viewer_grants','INSERT')
 THEN RAISE EXCEPTION 'Browser privileges granted on private Atlas research grants'; END IF;
 IF has_function_privilege('anon','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
   OR NOT has_function_privilege('service_role','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Research authorization API role boundary failed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.titus_constellation_viewer_grants)
 THEN RAISE EXCEPTION 'Candidate unexpectedly inserted user research access grants'; END IF;
 IF public.titus_constellation_viewer_allowed_v1(gen_random_uuid(),gen_random_uuid(),gen_random_uuid())
 THEN RAISE EXCEPTION 'Foreign unrelated identity/session gained research access'; END IF;
 IF public.titus_constellation_viewer_allowed_v1(NULL,NULL,NULL)
 THEN RAISE EXCEPTION 'Null identity/session gained research access'; END IF;
END $proof$;
