-- HELD synthetic source projection only; fixture owner creates invented
-- originals. Never treat these as genuine consent, issuer or signed proof.
SAVEPOINT radio_collection_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_subscribed_station_collection_candidate.sql
DO $blank$
DECLARE n text;
BEGIN
 FOREACH n IN ARRAY ARRAY['radio_stations_v1','radio_programs_v1','library_memberships_v1',
 'library_membership_endings_v1','radio_subscriptions_v1','radio_subscription_endings_v1'] LOOP
  IF has_table_privilege('anon','titus.'||n,'SELECT')
  OR has_table_privilege('authenticated','titus.'||n,'SELECT')
  OR has_table_privilege('authenticated','titus.'||n,'INSERT')
  OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('titus.'||n))
  THEN RAISE EXCEPTION 'Radio private original ACL widened'; END IF;
 END LOOP;
 IF EXISTS(SELECT FROM titus.radio_stations_v1) OR EXISTS(SELECT FROM titus.radio_subscriptions_v1)
 OR EXISTS(SELECT FROM titus.library_memberships_v1)
 OR has_function_privilege('anon','public.titus_radio_subscribed_stations_self_api_v1()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.titus_radio_subscribed_stations_self_api_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'Radio source zero-seed/ACL violation'; END IF;
END $blank$;

INSERT INTO titus.radio_stations_v1(station_id,ledger_id,title,established_at)
VALUES
 ('f3000000-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777777','Fictional station',clock_timestamp()-interval '1 day'),
 ('f3000000-0000-4000-8000-000000000002','77777777-7777-4777-8777-777777777777','Fictional station',clock_timestamp()-interval '1 day');
INSERT INTO titus.radio_programs_v1(program_id,station_id,title,established_at)
VALUES
 ('f3000000-0000-4000-8000-000000000003','f3000000-0000-4000-8000-000000000001','First fictional program',clock_timestamp()-interval '1 day'),
 ('f3000000-0000-4000-8000-000000000004','f3000000-0000-4000-8000-000000000001','Second fictional program',clock_timestamp()-interval '1 day');
INSERT INTO titus.library_memberships_v1(membership_id,ledger_id,person_id,issuer_person_id,source_receipt,accepted_at)
VALUES('f3000000-0000-4000-8000-000000000005','77777777-7777-4777-8777-777777777777',
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'fictional-membership-1',clock_timestamp()-interval '1 hour');
INSERT INTO titus.radio_subscriptions_v1(subscription_id,station_id,ledger_id,program_id,person_id,membership_id,issuer_person_id,source_receipt,accepted_at)
VALUES
 ('f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777777','f3000000-0000-4000-8000-000000000003','dddddddd-dddd-4ddd-8ddd-dddddddddddd','f3000000-0000-4000-8000-000000000005','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-subscription-1',clock_timestamp()-interval '30 minutes'),
 ('f3000000-0000-4000-8000-000000000012','f3000000-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777777','f3000000-0000-4000-8000-000000000004','dddddddd-dddd-4ddd-8ddd-dddddddddddd','f3000000-0000-4000-8000-000000000005','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-subscription-2',clock_timestamp()-interval '30 minutes'),
 ('f3000000-0000-4000-8000-000000000013','f3000000-0000-4000-8000-000000000002','77777777-7777-4777-8777-777777777777',NULL,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-subscription-3',clock_timestamp()-interval '30 minutes');
-- Expired independent subscription must not reappear as a cover.
INSERT INTO titus.radio_subscriptions_v1(subscription_id,station_id,ledger_id,person_id,issuer_person_id,source_receipt,accepted_at,valid_until)
VALUES('f3000000-0000-4000-8000-000000000014','f3000000-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777777','dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-expired-subscription',clock_timestamp()-interval '2 hours',clock_timestamp()-interval '1 hour');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $subscriber$
DECLARE r jsonb;
BEGIN
 r:=public.titus_radio_subscribed_stations_self_api_v1();
 IF r->>'personId' IS DISTINCT FROM 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
 OR r->>'contractVersion' IS DISTINCT FROM 'titus_radio_subscribed_stations_v1'
 OR jsonb_array_length(r->'subscriptions')<>3
 OR r->'subscriptions'->0->>'stationId' IS DISTINCT FROM 'f3000000-0000-4000-8000-000000000001'
 OR r->'subscriptions'->2->>'stationId' IS DISTINCT FROM 'f3000000-0000-4000-8000-000000000002'
 OR r->'subscriptions'->2->'programId' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'subscription projection missing or mixed station originals'; END IF;
END $subscriber$;
-- The Course author and membership issuer gets no subscriptions by those facts.
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $other$
BEGIN
 IF public.titus_radio_subscribed_stations_self_api_v1()->'subscriptions' IS DISTINCT FROM '[]'::jsonb
 THEN RAISE EXCEPTION 'other Person received subscriber catalog'; END IF;
END $other$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $bad_session$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_subscribed_stations_self_api_v1();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'wrong session obtained station source'; END IF;
END $bad_session$;
RESET ROLE;

DO $foreign_keys$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  INSERT INTO titus.radio_subscriptions_v1(station_id,ledger_id,program_id,person_id,issuer_person_id,source_receipt,accepted_at)
  VALUES('f3000000-0000-4000-8000-000000000002','77777777-7777-4777-8777-777777777777',
  'f3000000-0000-4000-8000-000000000003','dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-invalid-program',clock_timestamp());
 EXCEPTION WHEN foreign_key_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'cross-station program accepted'; END IF;
 denied:=false;
 BEGIN
  INSERT INTO titus.radio_subscriptions_v1(station_id,ledger_id,person_id,membership_id,issuer_person_id,source_receipt,accepted_at)
  VALUES('f3000000-0000-4000-8000-000000000001','77777777-7777-4777-8777-777777777777',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','f3000000-0000-4000-8000-000000000005',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-invalid-member',clock_timestamp());
 EXCEPTION WHEN foreign_key_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'another Person borrowed membership'; END IF;
 denied:=false;
 BEGIN
  UPDATE titus.radio_subscriptions_v1 SET program_id=NULL WHERE subscription_id='f3000000-0000-4000-8000-000000000011';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'subscription original rewritten'; END IF;
END $foreign_keys$;

INSERT INTO titus.library_membership_endings_v1 VALUES(
 'f3000000-0000-4000-8000-000000000005','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fictional-membership-ending',clock_timestamp());
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $membership_end$
DECLARE r jsonb;
BEGIN
 r:=public.titus_radio_subscribed_stations_self_api_v1();
 IF jsonb_array_length(r->'subscriptions')<>1
 OR r->'subscriptions'->0->>'subscriptionId' IS DISTINCT FROM 'f3000000-0000-4000-8000-000000000013'
 THEN RAISE EXCEPTION 'ended membership affected unrelated subscription or retained included programs'; END IF;
END $membership_end$;
RESET ROLE;
INSERT INTO titus.radio_subscription_endings_v1 VALUES(
 'f3000000-0000-4000-8000-000000000013','dddddddd-dddd-4ddd-8ddd-dddddddddddd','fictional-subscription-ending',clock_timestamp());
SET LOCAL ROLE authenticated;
DO $subscription_end$
BEGIN
 IF public.titus_radio_subscribed_stations_self_api_v1()->'subscriptions' IS DISTINCT FROM '[]'::jsonb
 THEN RAISE EXCEPTION 'ended subscriber still received station'; END IF;
END $subscription_end$;
RESET ROLE;
ROLLBACK TO SAVEPOINT radio_collection_probe;
