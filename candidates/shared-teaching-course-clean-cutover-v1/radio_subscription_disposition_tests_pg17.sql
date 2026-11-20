-- Nested disposition proof uses the station already established in the outer fixture.
SAVEPOINT radio_disposition_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_subscription_disposition_candidate.sql
-- Keep exact IDs in scratch-only session settings, not browser-visible reads.
SELECT set_config('app.radio_fixture_offer',(SELECT offer_id::text FROM titus.radio_subscription_offers_v1),true);
SELECT set_config('app.radio_fixture_station',(SELECT station_id::text FROM titus.radio_stations_v1),true);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issuer_cannot_accept$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_offer')::uuid,'f4000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'issuer fabricated recipient consent'; END IF;
END $issuer_cannot_accept$;
SELECT set_config('app.radio_fixture_cancel',(public.titus_radio_offer_subscription_self_api_v1(
 '77777777-7777-4777-8777-777777777777',current_setting('app.radio_fixture_station')::uuid,NULL,
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000011')->>'offerId'),true);
DO $cancel$
DECLARE r jsonb;
BEGIN
 PERFORM public.titus_radio_cancel_subscription_offer_self_api_v1(current_setting('app.radio_fixture_cancel')::uuid,'f4000000-0000-4000-8000-000000000012');
 r:=public.titus_radio_cancel_subscription_offer_self_api_v1(current_setting('app.radio_fixture_cancel')::uuid,'f4000000-0000-4000-8000-000000000012');
 IF r->>'alreadyExists' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'cancellation replay not stable'; END IF;
END $cancel$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $accept$
DECLARE a jsonb;b jsonb;denied boolean:=false; r jsonb;
BEGIN
 BEGIN PERFORM public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_cancel')::uuid,'f4000000-0000-4000-8000-000000000013');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'cancelled offer was accepted'; END IF;
 a:=public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_offer')::uuid,'f4000000-0000-4000-8000-000000000014');
 b:=public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_offer')::uuid,'f4000000-0000-4000-8000-000000000014');
 r:=public.titus_radio_subscribed_stations_self_api_v1();
 IF a->>'subscriptionId' IS DISTINCT FROM b->>'subscriptionId' OR b->>'alreadyExists' IS DISTINCT FROM 'true'
 OR jsonb_array_length(r->'subscriptions')<>1 OR r->'subscriptions'->0->>'subscriptionId' IS DISTINCT FROM a->>'subscriptionId'
 THEN RAISE EXCEPTION 'accepted subscription did not project exact station'; END IF;
 denied:=false;
 BEGIN PERFORM public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_offer')::uuid,'f4000000-0000-4000-8000-000000000015');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'changed acceptance request accepted'; END IF;
END $accept$;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $accepted_cannot_cancel$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_cancel_subscription_offer_self_api_v1(current_setting('app.radio_fixture_offer')::uuid,'f4000000-0000-4000-8000-000000000016');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'accepted offer cancelled'; END IF;
END $accepted_cannot_cancel$;
SELECT set_config('app.radio_fixture_revoked',(public.titus_radio_offer_subscription_self_api_v1(
 '77777777-7777-4777-8777-777777777777',current_setting('app.radio_fixture_station')::uuid,NULL,
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000017')->>'offerId'),true);
RESET ROLE;
UPDATE reality.responsibility_relations SET relation_state='ended',ended_at=clock_timestamp()
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_accept_subscription_self_api_v1(current_setting('app.radio_fixture_revoked')::uuid,'f4000000-0000-4000-8000-000000000018');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked issuer offer accepted'; END IF;
END $revoked$;
RESET ROLE;
DO $counts$
BEGIN
 IF (SELECT count(*) FROM titus.radio_subscriptions_v1)<>1 OR (SELECT count(*) FROM titus.radio_subscription_acceptances_v1)<>1
 OR (SELECT count(*) FROM titus.radio_subscription_offer_cancellations_v1)<>1
 OR has_table_privilege('authenticated','titus.radio_subscription_offer_cancellations_v1','SELECT')
 OR has_function_privilege('anon','public.titus_radio_accept_subscription_self_api_v1(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'disposition original or privacy incorrect'; END IF;
END $counts$;
ROLLBACK TO SAVEPOINT radio_disposition_probe;
