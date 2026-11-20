-- Nested fictional test after disposition checks; preserve the outer fixture.
SAVEPOINT radio_recipient_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_subscription_recipient_candidate.sql
-- Restore operator standing only in scratch for a fresh addressed offer.
UPDATE reality.responsibility_relations SET relation_state='active',ended_at=NULL
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
SELECT set_config('app.radio_fixture_new_offer',(public.titus_radio_offer_subscription_self_api_v1(
 '77777777-7777-4777-8777-777777777777',current_setting('app.radio_fixture_station')::uuid,NULL,
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'f4000000-0000-4000-8000-000000000020')->>'offerId'),true);
DO $issuer$
BEGIN
 IF public.titus_radio_subscription_inbox_self_api_v1()->'offers' IS DISTINCT FROM '[]'::jsonb
 THEN RAISE EXCEPTION 'issuer saw another Person inbox'; END IF;
END $issuer$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient$
DECLARE r jsonb;
BEGIN
 r:=public.titus_radio_subscription_inbox_self_api_v1();
 IF r->>'personId' IS DISTINCT FROM 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
 OR jsonb_array_length(r->'offers')<>2
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'offers') x WHERE x->>'offerId'=current_setting('app.radio_fixture_new_offer'))
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'offers') x WHERE x->>'offerId' IN
 (current_setting('app.radio_fixture_offer'),current_setting('app.radio_fixture_cancel')))
 THEN RAISE EXCEPTION 'recipient inbox leaked accepted or cancelled offer or lost pending offer'; END IF;
END $recipient$;
SELECT set_config('app.radio_fixture_new_subscription',(public.titus_radio_accept_subscription_self_api_v1(
 current_setting('app.radio_fixture_new_offer')::uuid,'f4000000-0000-4000-8000-000000000021')->>'subscriptionId'),true);
RESET ROLE;
UPDATE reality.responsibility_relations SET relation_state='ended',ended_at=clock_timestamp()
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $other_end$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_end_subscription_self_api_v1(current_setting('app.radio_fixture_new_subscription')::uuid,'f4000000-0000-4000-8000-000000000022');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'other Person ended subscriber relationship'; END IF;
END $other_end$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $end$
DECLARE r jsonb; denied boolean:=false;
BEGIN
 IF public.titus_radio_subscription_inbox_self_api_v1()->'offers' IS DISTINCT FROM '[]'::jsonb
 THEN RAISE EXCEPTION 'revoked issuer offer visible'; END IF;
 PERFORM public.titus_radio_end_subscription_self_api_v1(current_setting('app.radio_fixture_new_subscription')::uuid,'f4000000-0000-4000-8000-000000000023');
 r:=public.titus_radio_end_subscription_self_api_v1(current_setting('app.radio_fixture_new_subscription')::uuid,'f4000000-0000-4000-8000-000000000023');
 IF r->>'alreadyExists' IS DISTINCT FROM 'true'
 OR jsonb_array_length(public.titus_radio_subscribed_stations_self_api_v1()->'subscriptions')<>1
 THEN RAISE EXCEPTION 'termination retry or unrelated subscription incorrect'; END IF;
 BEGIN PERFORM public.titus_radio_end_subscription_self_api_v1(current_setting('app.radio_fixture_new_subscription')::uuid,'f4000000-0000-4000-8000-000000000024');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'changed termination request accepted'; END IF;
END $end$;
RESET ROLE;
DO $counts$
BEGIN
 IF (SELECT count(*) FROM titus.radio_subscriptions_v1)<>2 OR (SELECT count(*) FROM titus.radio_subscription_endings_v1)<>1
 OR has_function_privilege('anon','public.titus_radio_subscription_inbox_self_api_v1()','EXECUTE')
 OR has_function_privilege('anon','public.titus_radio_end_subscription_self_api_v1(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'termination history or privacy incorrect'; END IF;
END $counts$;
ROLLBACK TO SAVEPOINT radio_recipient_probe;
