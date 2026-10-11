-- Production-shaped schema-only clone validation. No invented Bible or founder research fixture rows.
DO $proof$
DECLARE v jsonb;
BEGIN
 SELECT public.titus_constellation_private_chapter_v1('Psa',147) INTO v;
 IF v->>'book' IS DISTINCT FROM 'Psa'
    OR v->>'chapter' IS DISTINCT FROM '147'
    OR jsonb_typeof(v->'english') <> 'array'
    OR jsonb_typeof(v->'original') <> 'array'
 THEN RAISE EXCEPTION 'Scripture chapter witness payload contract invalid'; END IF;

 IF public.titus_constellation_private_chapter_v1('Psa',0) IS NOT NULL
    OR public.titus_constellation_private_chapter_v1('Psa',151) IS NOT NULL
    OR public.titus_constellation_private_chapter_v1('malformed',147) IS NOT NULL
 THEN RAISE EXCEPTION 'Unbounded Scripture chapter coordinate'; END IF;

 IF has_function_privilege('anon','public.titus_constellation_private_chapter_v1(text,integer)','EXECUTE')
    OR has_function_privilege('authenticated','public.titus_constellation_private_chapter_v1(text,integer)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.titus_constellation_private_chapter_v1(text,integer)','EXECUTE')
 THEN RAISE EXCEPTION 'Chapter witness private transport ACL failed'; END IF;

 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(v->'original') AS verse,
                 jsonb_array_elements(verse->'tokens') AS token,
                 jsonb_array_elements_text(token->'poolIds') AS pool_id
   WHERE pool_id NOT LIKE 'pool:%'
 ) THEN RAISE EXCEPTION 'Chapter surfaced a non-pool token anchor'; END IF;
END $proof$;
