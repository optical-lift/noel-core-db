-- HELD M3.10 end-to-end on fictional source. Not a live migration.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/same_course_offering_draft_fixture_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/same_course_offering_draft_candidate.sql

DO $shape_guard$
DECLARE n integer;
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_course_offerings','INSERT')
 OR has_table_privilege('authenticated','atlas.teaching_course_version_use_decision_events','SELECT')
 OR has_function_privilege('anon',
   'public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_course_version_use_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Offering source ACL changed'; END IF;
 IF EXISTS(SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.teaching_course_offerings'::regclass
    AND conname='teaching_course_offerings_ledger_id_course_id_fkey') THEN
  RAISE EXCEPTION 'old institution-owned Course ID composite FK survived';
 END IF;
 SELECT count(*) INTO n FROM pg_constraint
 WHERE conrelid='atlas.teaching_course_offerings'::regclass
 AND conname IN ('shared_course_offering_native_ledger_fkey',
   'shared_course_offering_course_root_fkey',
   'teaching_course_offerings_course_id_course_version_id_fkey');
 IF n<>3 THEN
  RAISE EXCEPTION 'new exact separate FK and immutable Version relation absent';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger
 WHERE tgrelid='atlas.teaching_course_offerings'::regclass
 AND tgname='shared_course_offerings_exact_identity_v1') THEN
  RAISE EXCEPTION 'held Offering draft identity guard missing';
 END IF;
END $shape_guard$;

SAVEPOINT same_course_offering_test;
-- A new fictional proposal avoids the historical withdrawn invitations.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_proposes_shared_version$
DECLARE p jsonb;
BEGIN
 p:=public.shared_teaching_course_operating_propose_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '77777777-7777-4777-8777-777777777777',
  'c9999999-9999-4999-8999-999999999999');
 IF p->>'state'<>'proposed' THEN
  RAISE EXCEPTION 'author cannot propose canonical Course operation'; END IF;
END $author_proposes_shared_version$;
RESET ROLE;

-- Fictional test-only invitation handle; not a second identity or issuer.
UPDATE atlas.teaching_course_operating_standings
 SET id='e8888888-8888-4888-8888-888888888888'
 WHERE request_id='c9999999-9999-4999-8999-999999999999';
DO $initial_shape$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1 THEN
  RAISE EXCEPTION 'fictional shared Course/Version original not unique';
 END IF;
END $initial_shape$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $cannot_create_from_proposal$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'proposal alone created Offering'; END IF;
END $cannot_create_from_proposal$;
DO $governor_accepts_exact_course$
DECLARE result jsonb;
BEGIN
 result:=public.shared_teaching_course_operating_accept_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   'a7777777-7777-4777-8777-777777777777',
   'f8888888-8888-4888-8888-888888888888');
 IF result->>'state'<>'accepted' THEN
  RAISE EXCEPTION 'independent governor acceptance failed';
 END IF;
END $governor_accepts_exact_course$;
DO $cannot_create_from_acceptance$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'acceptance alone created Offering'; END IF;
END $cannot_create_from_acceptance$;
RESET ROLE;

-- Course title and Version use are distinct, independently authored acts.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_title_allow$
BEGIN
 PERFORM public.shared_teaching_course_operating_title_decide_self_api_v1(
  'e8888888-8888-4888-8888-888888888888',
  'd8888888-8888-4888-8888-888888888888','allow_title');
END $author_title_allow$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $title_is_not_version_use$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'title grant became Version use authority'; END IF;
END $title_is_not_version_use$;

DO $operator_not_version_author$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'd8888888-8888-4888-8888-888888888885',
   'allow_draft_offering');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor self-authorized Version use'; END IF;
END $operator_not_version_author$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_exact_version_use$
DECLARE x jsonb;y jsonb;denied boolean:=false;
BEGIN
 x:=public.shared_teaching_course_version_use_decide_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'd8888888-8888-4888-8888-888888888886','allow_draft_offering');
 y:=public.shared_teaching_course_version_use_decide_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'd8888888-8888-4888-8888-888888888886','allow_draft_offering');
 IF x->>'alreadyExists'<>'false' OR y->>'alreadyExists'<>'true'
 OR x->>'eventSequence'<>y->>'eventSequence'
 OR x->>'canOpenOffering'<>'false' THEN
  RAISE EXCEPTION 'Version-use author consent replay failed';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'd8888888-8888-4888-8888-888888888886','withhold_draft_offering');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'changed immutable Version-use decision replay passed';
 END IF;
END $author_exact_version_use$;

-- Author can permit use but not assume signed institution governor identity.
DO $author_cannot_create_institution_offer$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author impersonated institutional root Offering issuer'; END IF;
END $author_cannot_create_institution_offer$;

SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_draft_only$
DECLARE a jsonb;b jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 b:=public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'cohort',NULL,NULL);
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'offeringId'<>b->>'offeringId'
 OR a->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR a->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR a->>'ledgerId'<>'77777777-7777-4777-8777-777777777777'
 OR a->>'offeringState'<>'draft' OR a->>'canOpen'<>'false' THEN
  RAISE EXCEPTION 'canonical same-Course draft Offering or replay failed';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888888',
   'scheduled',NULL,NULL);
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed Offering create request admitted'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   '11111111-1111-4111-8111-111111111111');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'draft Offering leaked private manuscript'; END IF;
END $governor_draft_only$;
RESET ROLE;

DO $exact_shared_structure$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings)<>1
 OR NOT EXISTS (SELECT 1 FROM atlas.teaching_course_offerings o
 JOIN atlas.teaching_course_versions v
 ON o.course_id=v.course_id AND o.course_version_id=v.id
 WHERE o.course_id='11111111-1111-4111-8111-111111111111'
   AND o.ledger_id='77777777-7777-4777-8777-777777777777'
   AND o.created_by_person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
   AND o.created_by_person_id IS NULL AND o.created_by_principal_id IS NULL
   AND o.state='draft' AND o.opened_at IS NULL
   AND v.publication_scope='definition_metadata_only'
 ) THEN RAISE EXCEPTION 'Offering duplicated original or bypassed exact Version FK'; END IF;
 BEGIN
  UPDATE atlas.teaching_course_offerings SET state='open';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'unreleased open operation bypassed'; END IF;
 denied:=false;
 BEGIN DELETE FROM atlas.teaching_course_offerings;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'unreleased Offering deletion bypassed'; END IF;
END $exact_shared_structure$;

-- Changed current author approval must stop NEW draft creation, even while
-- an earlier draft remains historical. Draft has no open/enroll access.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $withdraw_version_use$
BEGIN
 PERFORM public.shared_teaching_course_version_use_decide_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'd8888888-8888-4888-8888-888888888887','withhold_draft_offering');
END $withdraw_version_use$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $withdrawn_use_denies_new_offering$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_offering_draft_create_self_api_v1(
   'e8888888-8888-4888-8888-888888888888',
   current_setting('app.fictional_published_version_id')::uuid,
   'a8888888-8888-4888-8888-888888888889',
   'cohort',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Version-use still created draft'; END IF;
END $withdrawn_use_denies_new_offering$;
RESET ROLE;

ROLLBACK TO SAVEPOINT same_course_offering_test;
