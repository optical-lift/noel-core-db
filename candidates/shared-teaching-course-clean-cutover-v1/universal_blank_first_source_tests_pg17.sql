-- UNIVERAL EMPTY-FIRST M1/M3 SOURCE PROOF: network-isolated fictional PG17.
-- Runs BEFORE historic SK101 adoption. The legacy draft is temporarily
-- removed ONLY inside a savepoint of a synthetic database, restored by
-- ROLLBACK; absolutely no production data, migration or actual learner.
SAVEPOINT universal_blank_first_source;
DELETE FROM titus.customer_course_unit_revisions_v1;
DELETE FROM titus.customer_course_units_v1;
DELETE FROM titus.customer_course_material_revisions_v1;
DELETE FROM titus.customer_course_drafts_v1;
DELETE FROM titus.customer_workspace_entitlements_v1;

-- Baseline Course source must be installable without a single named
-- legacy manuscript/Unit/Student/Offering.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_first_candidate.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/canonical_authoring_candidate.sql
DO $zero_after_source_setup$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_units)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>0
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>0
 OR (SELECT count(*) FROM titus.customer_course_drafts_v1)<>0
 OR to_regclass('atlas.teaching_course_offerings') IS NOT NULL
 OR to_regclass('atlas.teaching_enrollments') IS NOT NULL
 THEN
  RAISE EXCEPTION 'universal Course schema seeded a Course, Unit, entitlement or institution';
 END IF;
END $zero_after_source_setup$;

-- A live session/Person is NOT a purchase grant or a Course original.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $blank_person$
DECLARE grant jsonb;catalog jsonb;
BEGIN
 grant:=public.titus_authoring_access_self_api_v1();
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF grant->>'canUseTitus'<>'false'
 OR catalog->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'login silently licensed author or created a Course';
 END IF;
END $blank_person$;
RESET ROLE;

-- Fictional grant explicitly conferred, not implied from Person/auth alone.
INSERT INTO titus.course_authoring_access_grants(
 person_entity_id,grant_source_auth_user_id,grant_kind,grant_source_receipt,
 state,granted_at,valid_until)
VALUES('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','private_pilot',
 'fictional-generic-blank-first-grant','active',now(),NULL);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $create_first_empty_original$
DECLARE grant jsonb;catalog jsonb;created jsonb;again jsonb;v_course_id uuid;
BEGIN
 grant:=public.titus_authoring_access_self_api_v1();
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF grant->>'canUseTitus'<>'true' OR catalog->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'explicit Titus grant populated a default Course';
 END IF;
 created:=public.shared_teaching_course_create_self_api_v1(
  'be000000-0000-4000-8000-000000000001','Untitled field notes');
 again:=public.shared_teaching_course_create_self_api_v1(
  'be000000-0000-4000-8000-000000000001','Untitled field notes');
 v_course_id:=(created->>'courseId')::uuid;
 IF created->>'alreadyExists'<>'false'
 OR again->>'alreadyExists'<>'true'
 OR again->>'courseId'<>created->>'courseId' THEN
  RAISE EXCEPTION 'first Course created duplicate original';
 END IF;
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF jsonb_array_length(catalog->'courses')<>1
 OR catalog->'courses'->0->>'title'<>'Untitled field notes'
 OR catalog->'courses'->0->>'courseId'<>v_course_id::text
 THEN RAISE EXCEPTION 'first created Course not source-confirmed'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_courses c WHERE c.id=v_course_id)<>1 THEN
  RAISE EXCEPTION 'first Course missing'; END IF;
 IF (SELECT count(*) FROM atlas.teaching_courses c WHERE c.id=v_course_id
  AND (c.ledger_id IS NOT NULL OR c.capability_activation_id IS NOT NULL
   OR c.created_by_principal_id IS NOT NULL))<>0
 OR (SELECT count(*) FROM atlas.teaching_course_units)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>0 THEN
  RAISE EXCEPTION 'creating Course fabricated institution, Unit or manuscript';
 END IF;
END $create_first_empty_original$;
RESET ROLE;

-- Another current Person never sees the new author's Course, even without
-- needing a second institution, a Song permission, or a matching title.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $outsider_blank$
DECLARE c jsonb;denied boolean:=false;
BEGIN
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF c->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'other Person inherited first buyer Course';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   (SELECT id FROM atlas.teaching_courses LIMIT 1));
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'other Person read owner Course'; END IF;
END $outsider_blank$;
RESET ROLE;

-- Restore ALL synthetic legacy rows exactly before historic migration
-- attestation. The generic schema objects/first Course also rollback.
ROLLBACK TO SAVEPOINT universal_blank_first_source;
DO $recovered_prior_source$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>0
 OR (SELECT count(*) FROM titus.customer_course_drafts_v1)<>1
 OR (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>1
 OR (SELECT count(*) FROM titus.customer_course_units_v1)<>2
 OR (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>3
 OR to_regprocedure('public.shared_teaching_course_create_self_api_v1(uuid,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'blank-first probe disturbed independent historical source'; END IF;
END $recovered_prior_source$;
