-- Isolated U1 fixture only; no production data or actual signed bearer.
SAVEPOINT radio_publishing_standing_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/shared_institution_publishing_standing_probe_candidate.sql

-- Invoker helper remains inaccessible to browser roles.
DO $acl$
BEGIN
 IF has_function_privilege('authenticated','titus.require_current_institution_publisher_self_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon','titus.require_current_institution_publisher_self_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'publishing standing probe exposed'; END IF;
END $acl$;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $no_admission$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'publisher entered without admission'; END IF;
END $no_admission$;
INSERT INTO titus.institution_account_admissions_v1(
 admission_id,person_entity_id,institution_entity_id,ledger_id,
 issued_by_person_entity_id,issue_receipt,acceptance_receipt,issued_at,accepted_at)
VALUES('f2000000-0000-4000-8000-000000000001',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444',
 '77777777-7777-4777-8777-777777777777','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'fictional-radio-issue','fictional-radio-accept',clock_timestamp()-interval '1 hour',clock_timestamp()-interval '30 minutes');
-- Even admitted manager standing does not include publishing.
INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_entity_id,relation_state,permitted_operations,began_at,scope)
VALUES('f2000000-0000-4000-8000-000000000002','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_institution_account_management','entity','44444444-4444-4444-8444-444444444444',
 'active',ARRAY['invite','withdraw','cancel'],clock_timestamp()-interval '1 day',
 '{"ledgerId":"77777777-7777-4777-8777-777777777777"}');
DO $manager_not_publisher$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'manager inherited publishing standing'; END IF;
END $manager_not_publisher$;
INSERT INTO reality.responsibility_relations(
 id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
 jurisdiction_entity_id,relation_state,permitted_operations,began_at,scope)
VALUES('f2000000-0000-4000-8000-000000000003','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'institution_publication_management','entity','44444444-4444-4444-8444-444444444444',
 'active',ARRAY['publish'],clock_timestamp()-interval '1 day',
 '{"ledgerId":"77777777-7777-4777-8777-777777777777"}');
DO $publisher$
DECLARE r jsonb; denied boolean:=false;
BEGIN
 r:=titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-777777777777');
 IF r->>'responsibilityId' IS DISTINCT FROM 'f2000000-0000-4000-8000-000000000003'
 OR r->>'publicationApproved' IS DISTINCT FROM 'false' THEN
  RAISE EXCEPTION 'standing receipt false or implied approval'; END IF;
 BEGIN
  PERFORM titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'wrong Ledger inherited authority'; END IF;
END $publisher$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $outsider$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'other Person borrowed publisher authority'; END IF;
END $outsider$;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
UPDATE reality.responsibility_relations SET relation_state='ended',ended_at=clock_timestamp()
WHERE id='f2000000-0000-4000-8000-000000000003';
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM titus.require_current_institution_publisher_self_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked publishing standing reused'; END IF;
END $revoked$;
ROLLBACK TO SAVEPOINT radio_publishing_standing_probe;
