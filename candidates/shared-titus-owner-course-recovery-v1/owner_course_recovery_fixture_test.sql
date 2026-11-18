-- Fictional PG17 proof; run after the previous fixture setup and released SQL.
-- No actual owner identity, manuscript, production token or student.
BEGIN;
INSERT INTO reality.responsibility_relations VALUES(
 '89999999-9999-4999-8999-999999999999','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_private_pilot_issuance','domain','titus','active',
 ARRAY['issue_pilot_code','revoke_pilot_code','end_pilot_access'],now(),NULL);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $test$
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'false' THEN
  RAISE EXCEPTION 'issuer alone gained authoring'; END IF;
 BEGIN PERFORM public.shared_teaching_course_adopt_self_api_v1('11111111-1111-4111-8111-111111111111');
 RAISE EXCEPTION 'issuer-only recovery allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
RESET ROLE;
UPDATE reality.responsibility_relations SET permitted_operations=array_append(permitted_operations,'author_course_as_owner')
 WHERE id='89999999-9999-4999-8999-999999999999';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $test$
DECLARE j jsonb;
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'true' THEN
  RAISE EXCEPTION 'owner lacks authoring'; END IF;
 j:=public.shared_teaching_course_adopt_self_api_v1('11111111-1111-4111-8111-111111111111');
 IF j->>'alreadyExists'<>'false' OR j->>'courseId'<>'11111111-1111-4111-8111-111111111111'
  OR j->>'manuscriptRevisions'<>'1' OR j->>'units'<>'2' OR j->>'unitRevisions'<>'3' THEN
  RAISE EXCEPTION 'recovery receipt mismatch'; END IF;
 IF public.shared_teaching_course_adopt_self_api_v1('11111111-1111-4111-8111-111111111111')->>'alreadyExists'<>'true'
 THEN RAISE EXCEPTION 'retry failed'; END IF;
 IF jsonb_array_length(public.shared_teaching_course_catalog_self_api_v1()->'courses')<>1 THEN
 RAISE EXCEPTION 'same Course missing from owner library'; END IF;
 IF public.shared_teaching_course_material_read_self_api_v1('11111111-1111-4111-8111-111111111111')->'material'->>'text'
 IS DISTINCT FROM E'Teaching source\n\nObservation: \u05d0\n' THEN RAISE EXCEPTION 'recovered source differs'; END IF;
END $test$;
RESET ROLE;
DO $test$
BEGIN
 IF EXISTS(SELECT 1 FROM titus.course_authoring_access_grants) THEN RAISE EXCEPTION 'fabricated license'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_courses)<>2 THEN RAISE EXCEPTION 'duplicate or missing Course'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_course_units)<>2 OR
    (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>3 THEN RAISE EXCEPTION 'lost Units'; END IF;
 BEGIN UPDATE titus.customer_course_material_revisions_v1 SET body_text='changed';
 RAISE EXCEPTION 'historical secondary writer active'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 BEGIN UPDATE titus.customer_course_units_v1 SET title='changed';
 RAISE EXCEPTION 'historical Unit writer active'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 BEGIN UPDATE titus.customer_course_unit_revisions_v1 SET body_text='changed';
 RAISE EXCEPTION 'historical Unit revision writer active'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 BEGIN UPDATE titus.customer_course_drafts_v1 SET title='changed';
 RAISE EXCEPTION 'historical Course writer active'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 IF has_function_privilege('anon','public.shared_teaching_course_adopt_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('service_role','public.shared_teaching_course_adopt_self_api_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'unsigned recovery exposed'; END IF;
END $test$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $test$
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'false' THEN RAISE EXCEPTION 'outsider authoring'; END IF;
 BEGIN PERFORM public.shared_teaching_course_adopt_self_api_v1('11111111-1111-4111-8111-111111111111');
 RAISE EXCEPTION 'outsider adoption allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.shared_teaching_course_material_read_self_api_v1('11111111-1111-4111-8111-111111111111');
 RAISE EXCEPTION 'outsider read allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
RESET ROLE;
UPDATE reality.responsibility_relations SET relation_state='ended',ended_at=clock_timestamp()
 WHERE id='89999999-9999-4999-8999-999999999999';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $test$
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'false' THEN RAISE EXCEPTION 'ended authority still authoring'; END IF;
 BEGIN PERFORM public.shared_teaching_course_create_self_api_v1(gen_random_uuid(),'Denied');
 RAISE EXCEPTION 'ended owner can write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
RESET ROLE;
ROLLBACK;
\echo PASS owner access, same-ID recovery, historical freeze, outsider denial, ended access
