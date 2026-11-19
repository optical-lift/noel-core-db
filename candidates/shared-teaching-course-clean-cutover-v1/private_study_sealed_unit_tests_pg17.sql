-- Held M3.17B: TWO fictional consenting students, same Course, exact
-- independently selected sealed Lesson editions. No authenticated real user.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/private_study_sealed_unit_candidate.sql
-- The disposable fixture previously modeled only anon/authenticated.
DO $acl_role$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF; END $acl_role$;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/private_study_answer_candidate.sql

DO $source_acl$
BEGIN
 IF has_table_privilege('authenticated',
  'atlas.teaching_course_private_study_unit_decisions','SELECT')
 OR has_table_privilege('authenticated',
  'atlas.teaching_course_private_study_unit_decisions','INSERT')
 OR has_function_privilege('anon','public.shared_teaching_private_study_index_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.shared_teaching_private_study_index_self_api_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid)','EXECUTE')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE
   tgrelid='atlas.teaching_course_private_study_unit_decisions'::regclass
   AND tgname='private_study_unit_decision_immutable'
   AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'private study sealed Unit source ACL failed'; END IF;
END $source_acl$;

SAVEPOINT two_private_students;
INSERT INTO auth.users(id) VALUES
 ('d9999999-9999-4999-8999-999999999991'),
 ('d9999999-9999-4999-8999-999999999992');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('59999999-9999-4999-8999-999999999991',
  'd9999999-9999-4999-8999-999999999991',NULL),
 ('59999999-9999-4999-8999-999999999992',
  'd9999999-9999-4999-8999-999999999992',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('f9999999-9999-4999-8999-999999999991','person','fictional-a'),
 ('f9999999-9999-4999-8999-999999999992','person','fictional-b');
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('d9999999-9999-4999-8999-999999999991',
  'f9999999-9999-4999-8999-999999999991','active'),
 ('d9999999-9999-4999-8999-999999999992',
  'f9999999-9999-4999-8999-999999999992','active');

-- The author seals E1 and privately invites A/B to the SAME original Course.
-- Neither sealing nor accepting is permission to read the sealed Lesson.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_seal_and_invite$
DECLARE j jsonb;a jsonb;b jsonb;
BEGIN
 PERFORM public.shared_teaching_course_composition_save_self_api_v1(
  '11111111-1111-4111-8111-111111111111',gen_random_uuid(),0,
  '[{"unitId":"32222222-2222-4222-8222-222222222222","classUnitId":"31111111-1111-4111-8111-111111111111","depth":"advanced"}]'::jsonb);
 j:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  'a9999999-9999-4999-8999-999999999991');
 IF j->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'author did not seal original private Version'; END IF;
 a:=public.shared_teaching_private_study_invite_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'f9999999-9999-4999-8999-999999999991',
  'a9999999-9999-4999-8999-999999999992',NULL);
 b:=public.shared_teaching_private_study_invite_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'f9999999-9999-4999-8999-999999999992',
  'a9999999-9999-4999-8999-999999999993',NULL);
 PERFORM set_config('app.private_e_a',a->>'invitationId',true);
 PERFORM set_config('app.private_e_b',b->>'invitationId',true);
 j:=public.shared_teaching_private_study_delivery_self_api_v1('11111111-1111-4111-8111-111111111111');
 IF jsonb_array_length(j->'invitations')<>2 OR jsonb_array_length(j->'editions')<>1
 OR j->'invitations'->0->>'state'<>'offered' OR j->'editions'->0->'units'->0 ? 'text'
 OR j->>'publicPublication'<>'false' THEN RAISE EXCEPTION 'private delivery register mismatch'; END IF;
END $author_seal_and_invite$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $a_accept_without_materials$
DECLARE denied boolean:=false;
BEGIN
 PERFORM public.shared_teaching_private_study_respond_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  'a9999999-9999-4999-8999-999999999994','accept');
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_a')::uuid,
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'mere acceptance exposed sealed content'; END IF;
 IF public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid)->'units' <> '[]'::jsonb THEN RAISE EXCEPTION 'unissued index exposed metadata'; END IF;
END $a_accept_without_materials$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $b_accept_without_materials$
DECLARE denied boolean:=false;
BEGIN
 PERFORM public.shared_teaching_private_study_respond_self_api_v1(
  current_setting('app.private_e_b')::uuid,
  'a9999999-9999-4999-8999-999999999995','accept');
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_b')::uuid,
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'B acceptance auto-read sealed content'; END IF;
END $b_accept_without_materials$;
RESET ROLE;

-- No student or institutional governor can make an author-only decision.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $learner_no_publish$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'a9999999-9999-4999-8999-999999999996','allow',
  current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'student signed author release'; END IF;
 denied:=false;
 BEGIN PERFORM public.shared_teaching_private_study_delivery_self_api_v1('11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'student accessed teacher delivery register'; END IF;
END $learner_no_publish$;
RESET ROLE;

-- Author explicitly releases E1 Unit1 to each Person, not Unit2 or whole Course.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_release_e1$
DECLARE a jsonb;b jsonb;c jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'a9999999-9999-4999-8999-999999999997','allow',
  current_setting('app.fictional_published_version_id')::uuid);
 b:=public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'a9999999-9999-4999-8999-999999999997','allow',
  current_setting('app.fictional_published_version_id')::uuid);
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'canReadMaterial'<>'false' OR a ? 'text' OR a ? 'curriculum' THEN
  RAISE EXCEPTION 'E1 exact grant or replay leaked material'; END IF;
 BEGIN
  PERFORM public.shared_teaching_private_study_unit_decide_self_api_v1(
   current_setting('app.private_e_b')::uuid,
   '31111111-1111-4111-8111-111111111111',
   'a9999999-9999-4999-8999-999999999997','allow',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'request ID reused for other learner'; END IF;
 c:=public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_b')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'a9999999-9999-4999-8999-999999999998','allow',
  current_setting('app.fictional_published_version_id')::uuid);
 IF c->>'alreadyExists'<>'false' THEN RAISE EXCEPTION 'B E1 grant missing'; END IF;
 c:=public.shared_teaching_private_study_delivery_self_api_v1('11111111-1111-4111-8111-111111111111');
 IF c->'invitations'->0->>'state'<>'accept' OR jsonb_array_length(c->'invitations'->0->'issued')<>1
 THEN RAISE EXCEPTION 'delivery issue or consent missing'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_private_study_unit_decide_self_api_v1(
   current_setting('app.private_e_a')::uuid,
   '99999999-9999-4999-8999-999999999999',
   'a9999999-9999-4999-8999-999999999999','allow',
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'fictional foreign Unit received grant'; END IF;
END $author_release_e1$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $a_reads_e1$
DECLARE j jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111');
 IF j->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR j->'unit'->>'text'<>'Revised class law statement.'
 OR j ? 'curriculum' OR j ? 'manuscript' OR j ? 'units'
 OR j->>'canReadManuscript'<>'false' THEN
  RAISE EXCEPTION 'A exact E1 Unit read mismatch or Course material leak'; END IF;
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_a')::uuid,
   '32222222-2222-4222-8222-222222222222');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'A read ungranted Homework Unit'; END IF;
 j:=public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid);
 IF jsonb_array_length(j->'units')<>1 OR j->'units'->0->>'unitId'<>'31111111-1111-4111-8111-111111111111'
 OR j->'units'->0 ? 'text' OR j ? 'curriculum' OR j->'units'->0->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 THEN RAISE EXCEPTION 'issued index exposed wrong edition or broader material'; END IF;
 denied:=false;
 BEGIN PERFORM public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_b')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'A could discover B index'; END IF;
END $a_reads_e1$;
RESET ROLE;

-- Both issued siblings from exactly one sealed composition; withholding a
-- parent may never disclose it. Roll back these extra decisions for later fixtures.
SAVEPOINT composition_projection;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
SELECT public.shared_teaching_private_study_unit_decide_self_api_v1(current_setting('app.private_e_a')::uuid,
 '32222222-2222-4222-8222-222222222222',gen_random_uuid(),'allow',current_setting('app.fictional_published_version_id')::uuid);
SELECT public.shared_teaching_course_composition_save_self_api_v1('11111111-1111-4111-8111-111111111111',gen_random_uuid(),1,'[]'::jsonb);
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $projection$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid);
 IF jsonb_array_length(j->'units')<>2 OR j->'units'->1->>'classUnitId' IS DISTINCT FROM '31111111-1111-4111-8111-111111111111'
 OR j->'units'->1->>'depth' IS DISTINCT FROM 'advanced' THEN RAISE EXCEPTION 'sealed membership lost after working change'; END IF;
END $projection$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
SELECT public.shared_teaching_private_study_unit_decide_self_api_v1(current_setting('app.private_e_a')::uuid,
 '31111111-1111-4111-8111-111111111111',gen_random_uuid(),'withhold',NULL);
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $hidden_parent$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid);
 IF jsonb_array_length(j->'units')<>1 OR j->'units'->0->>'classUnitId' IS NOT NULL OR j->'units'->0->>'depth' IS NOT NULL
 THEN RAISE EXCEPTION 'withheld parent disclosed'; END IF;
END $hidden_parent$;
RESET ROLE;
ROLLBACK TO SAVEPOINT composition_projection;

-- Author edits working Class, publishes and seals E2 without rewriting E1.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_e2$
DECLARE j jsonb;v jsonb;s jsonb;
BEGIN
 j:=public.shared_teaching_course_unit_save_self_api_v1(
  '31111111-1111-4111-8111-111111111111',
  'b9999999-9999-4999-8999-999999999991',2,
  E'Fictional E2 lesson\r\nNew observation\r\n\r\n## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\r\n\r\nWhat changed?');
 IF j->'material'->>'revisionNumber'<>'3' THEN
  RAISE EXCEPTION 'author E2 working Unit did not advance'; END IF;
 v:=public.shared_teaching_private_study_prepare_edition_self_api_v1(
  '11111111-1111-4111-8111-111111111111','b9999999-9999-4999-8999-999999999992','Fictional E2 definition');
 s:=v;
 IF s->>'snapshotId' IS NULL OR s->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'author E2 seal missing'; END IF;
 PERFORM set_config('app.private_version_e2',v->>'courseVersionId',true);
 s:=public.shared_teaching_private_study_prepare_edition_self_api_v1(
  '11111111-1111-4111-8111-111111111111','b9999999-9999-4999-8999-999999999992','Fictional E2 definition');
 IF s->>'alreadyExists'<>'true' OR s->>'snapshotId'<>v->>'snapshotId' THEN RAISE EXCEPTION 'edition retry changed original'; END IF;
 j:=public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_b')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'b9999999-9999-4999-8999-999999999994','allow',
  (v->>'courseVersionId')::uuid);
 IF j->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'author did not choose E2 for B'; END IF;
END $author_e2$;
RESET ROLE;

-- Choice 5C: A stays on E1; B sees E2. Both may navigate Unit1
-- (choice 6A: navigation is NOT gated on completing other released Units).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $a_stays_e1$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111');
 IF j->'unit'->>'text'<>'Revised class law statement.'
 OR j->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 THEN RAISE EXCEPTION 'A was silently advanced to E2'; END IF;
 IF public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid)->'units'->0->>'courseVersionId'<>current_setting('app.fictional_published_version_id') THEN RAISE EXCEPTION 'A index advanced to E2'; END IF;
END $a_stays_e1$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $b_moves_e2$
DECLARE j jsonb;denied boolean:=false;
BEGIN
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
  current_setting('app.private_e_b')::uuid,
  '31111111-1111-4111-8111-111111111111');
 IF j->'unit'->>'text' IS DISTINCT FROM E'Fictional E2 lesson\r\nNew observation\r\n\r\n## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\r\n\r\nWhat changed?'
 OR j->>'courseVersionId'<>current_setting('app.private_version_e2')
 THEN RAISE EXCEPTION 'B did not receive exact authorized E2'; END IF;
 IF public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_b')::uuid)->'units'->0->>'courseVersionId'<>current_setting('app.private_version_e2') THEN RAISE EXCEPTION 'B index did not receive E2'; END IF;
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_a')::uuid,
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'B read A invitation'; END IF;
END $b_moves_e2$;
RESET ROLE;

\i /source/candidates/shared-teaching-course-clean-cutover-v1/private_study_answer_tests_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/private_study_submission_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/private_study_submission_tests_pg17.sql

-- Author withholds A Unit after E1 without destroying prior decisions.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withhold_a$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_private_study_unit_decide_self_api_v1(
  current_setting('app.private_e_a')::uuid,
  '31111111-1111-4111-8111-111111111111',
  'b9999999-9999-4999-8999-999999999995','withhold',NULL);
 IF j->>'decision'<>'withhold' THEN RAISE EXCEPTION 'A withhold not recorded'; END IF;
END $author_withhold_a$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $a_withheld$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_a')::uuid,
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'author withdrawn Unit still disclosed'; END IF;
 IF public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_a')::uuid)->'units'<>'[]'::jsonb THEN RAISE EXCEPTION 'withheld Unit still in index'; END IF;
END $a_withheld$;
RESET ROLE;

-- B withdraws accepted study; its exact E2 read immediately fails.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $b_withdrawn$
DECLARE denied boolean:=false;
BEGIN
 PERFORM public.shared_teaching_private_study_withdraw_self_api_v1(
  current_setting('app.private_e_b')::uuid,
  'b9999999-9999-4999-8999-999999999996');
 BEGIN
  PERFORM public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
   current_setting('app.private_e_b')::uuid,
   '31111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn B still reads E2'; END IF;
 denied:=false;
 BEGIN PERFORM public.shared_teaching_private_study_index_self_api_v1(current_setting('app.private_e_b')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn B still has index'; END IF;
 denied:=false;
 BEGIN PERFORM public.shared_teaching_private_study_answer_save_self_api_v1(current_setting('app.private_e_b')::uuid,
 '31111111-1111-4111-8111-111111111111',current_setting('app.t4_snapshot')::uuid,current_setting('app.t4_revision')::uuid,'12345678-1234-4234-8234-123456789abc',gen_random_uuid(),2,'After withdrawal');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn learner wrote answer';END IF;
END $b_withdrawn$;
RESET ROLE;

DO $end_state$
DECLARE v_enrollments bigint:=0;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions)<>4
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions
  WHERE decision='allow')<>3
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions
  WHERE decision='withhold')<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots)<>2
 THEN RAISE EXCEPTION 'one Course/two immutable editions/source fixture altered: courses %, total %, allow %, withhold %, snapshots %, enrollment table %',
  (SELECT count(*) FROM atlas.teaching_courses),
  (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions),
  (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions WHERE decision='allow'),
  (SELECT count(*) FROM atlas.teaching_course_private_study_unit_decisions WHERE decision='withhold'),
  (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots),
  to_regclass('atlas.teaching_enrollments'); END IF;
 -- Institutional Enrollment stays at zero even after two direct learners.
 -- Institutional Enrollment is introduced later in this synthetic journey.
 -- If absent here, the private source has not materialized it. If present,
 -- it must remain empty: never create an institutional original as a shortcut.
 IF to_regclass('atlas.teaching_enrollments') IS NOT NULL THEN
  EXECUTE 'SELECT count(*) FROM atlas.teaching_enrollments' INTO v_enrollments;
  IF v_enrollments<>0 THEN
   RAISE EXCEPTION 'private read minted institutional Enrollment';
  END IF;
 END IF;
END $end_state$;
ROLLBACK TO SAVEPOINT two_private_students;
