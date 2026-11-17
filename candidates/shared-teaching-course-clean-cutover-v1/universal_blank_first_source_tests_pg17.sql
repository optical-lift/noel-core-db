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
DECLARE v_grant jsonb;catalog jsonb;
BEGIN
 v_grant:=public.titus_authoring_access_self_api_v1();
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF v_grant->>'canUseTitus'<>'false'
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
DECLARE v_grant jsonb;catalog jsonb;created jsonb;again jsonb;v_course_id uuid;
BEGIN
 v_grant:=public.titus_authoring_access_self_api_v1();
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF v_grant->>'canUseTitus'<>'true' OR catalog->'courses'<>'[]'::jsonb THEN
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
 -- No privileged table reads inside an authenticated Person session.
 -- Source readback above is the user's only entitlement path.
 PERFORM set_config('app.fictional_blank_course_id',v_course_id::text,true);
END $create_first_empty_original$;
RESET ROLE;
-- Independent privileged aggregate: only the explicitly created Course root,
-- no Course contents, institution or implicit student records.
DO $blank_first_original_postconditions$
DECLARE v_course_id uuid:=current_setting('app.fictional_blank_course_id')::uuid;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses c WHERE c.id=v_course_id)<>1
 OR (SELECT count(*) FROM atlas.teaching_courses c WHERE c.id=v_course_id
  AND (c.ledger_id IS NOT NULL OR c.capability_activation_id IS NOT NULL
   OR c.created_by_principal_id IS NOT NULL))<>0
 OR (SELECT count(*) FROM atlas.teaching_course_units)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>0 THEN
  RAISE EXCEPTION 'first Course fabricated institution, Unit or manuscript';
 END IF;
END $blank_first_original_postconditions$;

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
   current_setting('app.fictional_blank_course_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'other Person read owner Course'; END IF;
END $outsider_blank$;
RESET ROLE;

-- Two INDEPENDENT new customers must not inherit a global Course, or
-- each other's permission through a duplicate request ID / same title.
-- Access source is simulated as independently verified by the synthetic
-- test owner; **no payment, self-grant, onboarding or live issuer is asserted**.
DO $no_self_grants$
BEGIN
 IF has_table_privilege('authenticated',
   'titus.course_authoring_access_grants','SELECT')
 OR has_table_privilege('authenticated',
   'titus.course_authoring_access_grants','INSERT')
 OR has_table_privilege('authenticated',
   'titus.course_authoring_access_grants','UPDATE')
 OR has_table_privilege('authenticated',
   'titus.course_authoring_access_grants','DELETE')
 OR has_table_privilege('anon',
   'titus.course_authoring_access_grants','SELECT')
 THEN RAISE EXCEPTION 'client can read or mint Titus access'; END IF;
END $no_self_grants$;

-- Expired receipt is not a Titus entitlement, even for a current Person.
SAVEPOINT expired_second_buyer;
INSERT INTO titus.course_authoring_access_grants(
 person_entity_id,grant_source_auth_user_id,grant_kind,grant_source_receipt,
 state,granted_at,valid_until)
VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','purchase',
 'fictional-expired-second-receipt','active',
 clock_timestamp()-interval '3 days',clock_timestamp()-interval '1 day');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $expired_buyer$
DECLARE p jsonb;c jsonb;
BEGIN
 p:=public.titus_authoring_access_self_api_v1();
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF p->>'canUseTitus'<>'false'
 OR c->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'expired receipt enabled Titus or inherited another Course';
 END IF;
END $expired_buyer$;
RESET ROLE;
ROLLBACK TO SAVEPOINT expired_second_buyer;

-- A second explicit grant DOES NOT COPY the first buyer's Course.
-- It is a test-only insert: actual grant issuance still needs a lawful
-- verified source and authorized operator, which is NOT implemented.
INSERT INTO titus.course_authoring_access_grants(
 person_entity_id,grant_source_auth_user_id,grant_kind,grant_source_receipt,
 state,granted_at,valid_until)
VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','private_pilot',
 'fictional-independent-second-buyer','active',clock_timestamp(),NULL);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $second_buyer_own_course$
DECLARE p jsonb;c jsonb;root jsonb;own uuid;reading jsonb;outline jsonb;
 denied boolean:=false;
BEGIN
 p:=public.titus_authoring_access_self_api_v1();
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF p->>'canUseTitus'<>'true'
 OR c->'courses'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'second independently authorized buyer was not empty';
 END IF;
 -- Even a matching requestId and title belong to a different Person.
 root:=public.shared_teaching_course_create_self_api_v1(
  'be000000-0000-4000-8000-000000000001','Untitled field notes');
 own:=(root->>'courseId')::uuid;
 IF own=current_setting('app.fictional_blank_course_id')::uuid OR
  root->>'alreadyExists'<>'false' THEN
  RAISE EXCEPTION 'two buyers collided at original Course creation';
 END IF;
 PERFORM set_config('app.fictional_blank_course_id_b',own::text,true);
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF jsonb_array_length(c->'courses')<>1
 OR c->'courses'->0->>'courseId'<>own::text THEN
  RAISE EXCEPTION 'second buyer Course list does not contain exactly own Course';
 END IF;
 reading:=public.shared_teaching_course_material_read_self_api_v1(own);
 outline:=public.shared_teaching_course_outline_read_self_api_v1(own);
 IF reading->'material'<>'null'::jsonb
 OR outline->'units'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'second buyer new Course was prepopulated';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   current_setting('app.fictional_blank_course_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'second buyer read first buyer Course'; END IF;
END $second_buyer_own_course$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $first_buyer_remains_isolated$
DECLARE c jsonb;denied boolean:=false;
BEGIN
 c:=public.shared_teaching_course_catalog_self_api_v1();
 IF jsonb_array_length(c->'courses')<>1 OR
 c->'courses'->0->>'courseId'<>current_setting('app.fictional_blank_course_id') THEN
  RAISE EXCEPTION 'first buyer inherited second buyer Course';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_material_read_self_api_v1(
   current_setting('app.fictional_blank_course_id_b')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'first buyer read second buyer Course'; END IF;
END $first_buyer_remains_isolated$;
RESET ROLE;

-- Revoking Titus product access instantly changes only its current grant;
-- it never erases or overwrites the Course original. Shared source Course
-- custody is separately governed, and Titus adapter checks grant on each call.
UPDATE titus.course_authoring_access_grants
 SET state='revoked'
 WHERE person_entity_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $revoked_product_grant$
DECLARE access jsonb;catalog jsonb;
BEGIN
 access:=public.titus_authoring_access_self_api_v1();
 catalog:=public.shared_teaching_course_catalog_self_api_v1();
 IF access->>'canUseTitus'<>'false' OR
 jsonb_array_length(catalog->'courses')<>1 OR
 catalog->'courses'->0->>'courseId'<>current_setting('app.fictional_blank_course_id_b')
 THEN RAISE EXCEPTION 'product grant and canonical Course custody conflated'; END IF;
END $revoked_product_grant$;
RESET ROLE;

DO $two_buyer_aggregate$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>2
 OR (SELECT count(*) FROM titus.course_authoring_access_grants)<>2
 OR (SELECT count(*) FROM atlas.teaching_course_units)<>0
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>0
 OR EXISTS(SELECT 1 FROM atlas.teaching_courses
    WHERE ledger_id IS NOT NULL OR created_by_principal_id IS NOT NULL)
 THEN
  RAISE EXCEPTION 'two independent empty buyers seeded unrelated sources';
 END IF;
END $two_buyer_aggregate$;

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
