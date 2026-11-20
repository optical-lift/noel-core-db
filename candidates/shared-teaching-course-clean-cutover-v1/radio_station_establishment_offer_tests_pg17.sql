-- Nested fictional U1 probe. No real consent or live records.
SAVEPOINT radio_operator_commands_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_subscribed_station_collection_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_station_establishment_offer_candidate.sql
SET LOCAL ROLE authenticated;
DO $publish_not_establish$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',NULL,'Fictional station','f4000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'publish authority implicitly established station'; END IF;
END $publish_not_establish$;
RESET ROLE;
-- Grant only inside fixture; no actual issuer exists.
UPDATE reality.responsibility_relations SET permitted_operations=ARRAY['publish','establish_station','establish_program','offer_subscription']
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
DO $commands$
DECLARE a jsonb; b jsonb; p jsonb; o jsonb; retry jsonb; denied boolean:=false;
BEGIN
 a:=public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',NULL,'Fictional station','f4000000-0000-4000-8000-000000000001');
 b:=public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',NULL,'Fictional station','f4000000-0000-4000-8000-000000000001');
 IF a->>'stationId' IS DISTINCT FROM b->>'stationId' OR b->>'alreadyExists' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'station replay mismatch'; END IF;
 BEGIN PERFORM public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',NULL,'Changed title','f4000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'changed station intent accepted'; END IF;
 p:=public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',(a->>'stationId')::uuid,'Fictional program','f4000000-0000-4000-8000-000000000002');
 IF p->>'programId' IS NULL OR p->>'stationId' IS DISTINCT FROM a->>'stationId' THEN RAISE EXCEPTION 'program establishment mismatch'; END IF;
 o:=public.titus_radio_offer_subscription_self_api_v1('77777777-7777-4777-8777-777777777777',(a->>'stationId')::uuid,(p->>'programId')::uuid,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000003');
 retry:=public.titus_radio_offer_subscription_self_api_v1('77777777-7777-4777-8777-777777777777',(a->>'stationId')::uuid,(p->>'programId')::uuid,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000003');
 IF o->>'offerId' IS DISTINCT FROM retry->>'offerId' OR retry->>'alreadyExists' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'offer replay mismatch'; END IF;
 denied:=false;
 BEGIN PERFORM public.titus_radio_offer_subscription_self_api_v1('77777777-7777-4777-8777-777777777777',(a->>'stationId')::uuid,NULL,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000003');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'changed offer intent accepted'; END IF;
END $commands$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient$
DECLARE denied boolean:=false;
BEGIN
 IF public.titus_radio_subscribed_stations_self_api_v1()->'subscriptions' IS DISTINCT FROM '[]'::jsonb
 THEN RAISE EXCEPTION 'unaccepted offer created cover'; END IF;
 BEGIN PERFORM public.titus_radio_establish_self_api_v1('77777777-7777-4777-8777-777777777777',NULL,'Unauthorized station','f4000000-0000-4000-8000-000000000004');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'recipient created station'; END IF;
END $recipient$;
RESET ROLE;
DO $counts$
BEGIN
 IF (SELECT count(*) FROM titus.radio_stations_v1)<>1 OR (SELECT count(*) FROM titus.radio_programs_v1)<>1
 OR (SELECT count(*) FROM titus.radio_subscription_offers_v1)<>1
 OR EXISTS(SELECT FROM titus.radio_subscriptions_v1)
 OR EXISTS(SELECT FROM titus.radio_subscription_acceptances_v1)
 OR has_table_privilege('authenticated','titus.radio_subscription_offers_v1','SELECT')
 THEN RAISE EXCEPTION 'Radio original counts or privacy incorrect'; END IF;
END $counts$;
ROLLBACK TO SAVEPOINT radio_operator_commands_probe;
