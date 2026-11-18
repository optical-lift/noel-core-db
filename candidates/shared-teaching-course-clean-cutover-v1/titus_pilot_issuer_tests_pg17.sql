-- HELD M1.1 fictional issuer + recipient; no paid customer, no
-- actually established Reality product-issuer, no live issuer authorization.
-- Run inside existing isolated generic zero-legacy source journey.
SAVEPOINT titus_private_pilot_probe;
-- The full shared Reality substrate exists in production. This intentionally
-- SMALL fictional counterpart gives the candidate a verifiable responsibility
-- predicate without inserting into a real Reality ledger or issuing authority.
CREATE TABLE reality.responsibility_relations(
 id uuid PRIMARY KEY,
 carrier_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 responsibility_key text NOT NULL,
 jurisdiction_kind text NOT NULL,
 jurisdiction_domain text,
 relation_state text NOT NULL,
 permitted_operations text[] NOT NULL,
 began_at timestamptz NOT NULL,
 ended_at timestamptz
);
\i /source/candidates/shared-teaching-course-clean-cutover-v1/titus_pilot_issuer_candidate.sql
DO $pilot_acl$
BEGIN
 IF has_table_privilege('authenticated','titus.course_authoring_pilot_offers','SELECT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_offers','INSERT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_responses','SELECT')
 OR has_table_privilege('authenticated','titus.course_authoring_pilot_responses','INSERT')
 OR has_table_privilege('anon','titus.course_authoring_pilot_offers','SELECT')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_offer_self_api_v1(uuid,uuid,timestamptz,timestamptz)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_offer_read_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.titus_private_pilot_respond_self_api_v1(uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.titus_private_pilot_offer_self_api_v1(uuid,uuid,timestamptz,timestamptz)','EXECUTE')
 OR has_function_privilege('authenticated',
  'titus.require_current_pilot_issuer_self_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'untrusted pilot audience has direct write/read/issuer privileges';
 END IF;
END $pilot_acl$;
SELECT set_config('app.fictional_pilot_deadline',
 (clock_timestamp()+interval '7 days')::text,true);
SELECT set_config('app.fictional_pilot_access_until',
 (clock_timestamp()+interval '30 days')::text,true);

-- No Reality product-issuer standing yet: even the course's original author
-- cannot invite a new Titus customer just because they own a Course.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $no_automatic_issuer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_offer_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000001',
  current_setting('app.fictional_pilot_deadline')::timestamptz,
  current_setting('app.fictional_pilot_access_until')::timestamptz);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'login or Course authorship minted product grants'; END IF;
END $no_automatic_issuer$;
RESET ROLE;

-- Fictional Reality owner explicitly establishes a scoped pilot-issuer
-- responsibility in scratch only. Actual issuance of such responsibility is
-- not implemented here, and no production standing is conferred.
INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_domain,relation_state,permitted_operations,began_at,ended_at)
VALUES('c0000000-0000-4000-8000-000000000040',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_private_pilot_issuance','domain','titus','active',
 ARRAY['issue_pilot_offer']::text[],clock_timestamp()-interval '1 day',NULL);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient_cannot_issue$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_offer_self_api_v1(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'c0000000-0000-4000-8000-000000000002',
  current_setting('app.fictional_pilot_deadline')::timestamptz,
  current_setting('app.fictional_pilot_access_until')::timestamptz);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'recipient minted another Person pilot'; END IF;
END $recipient_cannot_issue$;
RESET ROLE;

-- Only separately signed issuer A can propose this first pilot for B.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issuer_offer$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.titus_private_pilot_offer_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000003',
  current_setting('app.fictional_pilot_deadline')::timestamptz,
  current_setting('app.fictional_pilot_access_until')::timestamptz);
 b:=public.titus_private_pilot_offer_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000003',
  current_setting('app.fictional_pilot_deadline')::timestamptz,
  current_setting('app.fictional_pilot_access_until')::timestamptz);
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'offerId'<>b->>'offerId' OR a->>'grantActive'<>'false' THEN
  RAISE EXCEPTION 'pilot issuer did not preserve one immutable offer';
 END IF;
 PERFORM set_config('app.fictional_pilot_offer_id',a->>'offerId',true);
 BEGIN
 PERFORM public.titus_private_pilot_offer_self_api_v1(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'c0000000-0000-4000-8000-000000000003',
  current_setting('app.fictional_pilot_deadline')::timestamptz+interval '1 day',
  current_setting('app.fictional_pilot_access_until')::timestamptz);
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'changed original offer replay admitted'; END IF;
 denied:=false;
 BEGIN
 PERFORM public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000004','accept');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'issuer accepted recipient pilot'; END IF;
END $issuer_offer$;
RESET ROLE;

-- Recipient B can inspect own narrow pilot, but no Course/license yet.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $not_yet_licensed$
DECLARE j jsonb;
BEGIN
 j:=public.titus_private_pilot_offer_read_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid);
 IF j->>'state'<>'offered' OR j->>'grantActive'<>'false'
 OR (j->>'acceptBy')::timestamptz
    <>current_setting('app.fictional_pilot_deadline')::timestamptz
 OR (j->>'grantValidUntil')::timestamptz
    <>current_setting('app.fictional_pilot_access_until')::timestamptz
 OR j ? 'course' OR j ? 'student' OR j ? 'research' THEN
  RAISE EXCEPTION 'merely offered pilot activated a Course or grant'; END IF;
END $not_yet_licensed$;
RESET ROLE;

-- Separate source-only alternative: the named recipient may deliberately
-- DECLINE. The same receipt is idempotent; a later accept is forbidden.
-- Roll back this fictional choice to exercise acceptance separately below.
SAVEPOINT pilot_decline_trial;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $recipient_declines$
DECLARE a jsonb;b jsonb;view_self jsonb;denied boolean:=false;
BEGIN
 a:=public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000030','decline');
 b:=public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000030','decline');
 view_self:=public.titus_private_pilot_offer_read_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid);
 IF a->>'grantActive'<>'false' OR b->>'alreadyExists'<>'true'
 OR view_self->>'state'<>'decline' OR view_self->>'grantActive'<>'false' THEN
  RAISE EXCEPTION 'private-pilot decline created access or lost history';
 END IF;
 BEGIN
  PERFORM public.titus_private_pilot_respond_self_api_v1(
   current_setting('app.fictional_pilot_offer_id')::uuid,
   'c0000000-0000-4000-8000-000000000031','accept');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'declined pilot could later be accepted'; END IF;
END $recipient_declines$;
RESET ROLE;
ROLLBACK TO SAVEPOINT pilot_decline_trial;

-- Scratch owner pauses issuer standing after the offer was issued. A stale
-- responsibility cannot activate someone else's access via later acceptance.
UPDATE reality.responsibility_relations SET relation_state='paused'
 WHERE id='c0000000-0000-4000-8000-000000000040';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $lost_issuer_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000005','accept');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'lost issuer standing still activated grant'; END IF;
END $lost_issuer_denied$;
RESET ROLE;

UPDATE reality.responsibility_relations SET relation_state='active'
 WHERE id='c0000000-0000-4000-8000-000000000040';

-- An issuer's archived/revoked Person Auth binding is not current standing.
-- Pausing and restoring a separate Responsibility row alone is insufficient.
SAVEPOINT revoked_pilot_issuer_auth;
UPDATE reality.auth_person_bindings SET binding_state='revoked'
 WHERE auth_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $issuer_auth_revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.titus_private_pilot_respond_self_api_v1(
   current_setting('app.fictional_pilot_offer_id')::uuid,
   'c0000000-0000-4000-8000-000000000050','accept');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN
  RAISE EXCEPTION 'recipient accepted from a revoked pilot issuer binding'; END IF;
END $issuer_auth_revoked$;
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_pilot_issuer_auth;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $independent_acceptance$
DECLARE a jsonb;b jsonb;catalog jsonb;denied boolean:=false;
BEGIN
 a:=public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000006','accept');
 b:=public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000006','accept');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'grantActive'<>'true' OR b->>'grantActive'<>'true' THEN
  RAISE EXCEPTION 'recipient independent pilot acceptance not current';
 END IF;
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF catalog->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'accepted Titus pilot automatically created a Course'; END IF;
 BEGIN
 PERFORM public.titus_private_pilot_respond_self_api_v1(
  current_setting('app.fictional_pilot_offer_id')::uuid,
  'c0000000-0000-4000-8000-000000000007','decline');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot response was not terminal'; END IF;
END $independent_acceptance$;
RESET ROLE;

DO $pilot_originals$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM titus.course_authoring_pilot_offers o
    WHERE o.offer_id=current_setting('app.fictional_pilot_offer_id')::uuid
     AND o.accept_by::text<>o.grant_valid_until::text)<>1 THEN
  RAISE EXCEPTION 'pilot accept deadline and access expiry were conflated'; END IF;
 IF (SELECT count(*) FROM titus.course_authoring_access_grants g
   WHERE g.person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    AND g.valid_until=current_setting('app.fictional_pilot_access_until')::timestamptz)<>1 THEN
  RAISE EXCEPTION 'accepted grant inherited wrong expiry'; END IF;
 IF (SELECT count(*) FROM titus.course_authoring_pilot_offers)<>1 OR
 (SELECT count(*) FROM titus.course_authoring_pilot_responses
  WHERE decision='accept')<>1 OR
 (SELECT count(*) FROM titus.course_authoring_access_grants
  WHERE person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
   AND grant_source_receipt='pilot:'||current_setting('app.fictional_pilot_offer_id')
   AND grant_kind='private_pilot')<>1 THEN
  RAISE EXCEPTION 'pilot receipt/Person/source original mismatch'; END IF;
 BEGIN
 DELETE FROM titus.course_authoring_pilot_responses;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot acceptance was erasable'; END IF;
 denied:=false;
 BEGIN
 UPDATE titus.course_authoring_pilot_offers SET grant_valid_until=clock_timestamp()+interval '1 year';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'pilot offer could be extended by mutation'; END IF;
END $pilot_originals$;

-- No pilot issuer, customer, Role, Source, Course or data survives.
ROLLBACK TO SAVEPOINT titus_private_pilot_probe;
DO $pilot_rolled_back$
BEGIN
 IF to_regclass('reality.responsibility_relations') IS NOT NULL
 OR to_regclass('titus.course_authoring_pilot_offers') IS NOT NULL
 OR to_regclass('titus.course_authoring_pilot_responses') IS NOT NULL
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0 OR
 (SELECT count(*) FROM atlas.teaching_courses)<>0 THEN
  RAISE EXCEPTION 'pilot probe leaked fictional product/source originals'; END IF;
END $pilot_rolled_back$;
