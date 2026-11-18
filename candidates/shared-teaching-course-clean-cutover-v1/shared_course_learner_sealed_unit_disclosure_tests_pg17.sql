-- M3.16B: one original source-issued learner Enrollment may receive one
-- separately authored sealed Unit read, NOT whole Version or classroom.
-- Executed inside the M3.15B signed and fictional original Enrollment fixture,
-- before M3.15C withdrawal and parent savepoint rollback.
DO $learner_unit_acl$
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.shared_course_learner_unit_disclosure_decisions','SELECT')
 OR has_table_privilege('authenticated',
   'atlas.shared_course_learner_unit_disclosure_decisions','INSERT')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR has_function_privilege('anon',
   'public.shared_teaching_learner_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
   'public.shared_teaching_learner_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE
   tgrelid='atlas.shared_course_learner_unit_disclosure_decisions'::regclass
   AND tgname='shared_learner_unit_disclosure_immutable' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'private original learner sealed Unit ACL missing'; END IF;
END $learner_unit_acl$;

SELECT set_config('app.m316b_unit_id',u.unit_id::text,true)
 FROM atlas.teaching_course_units u
 JOIN atlas.teaching_course_offerings o ON o.course_id=u.course_id
 WHERE o.id=current_setting('app.fictional_teacher_offering_id')::uuid
 ORDER BY u.display_position,u.unit_id LIMIT 1;

-- The learner accepted invitation and is actually enrolled on the original
-- carrier. Neither administrative fact exposes any sealed Unit by itself.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $learner_enrollment_not_materials$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'original Enrollment auto-released sealed Unit'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid,
   'b3160000-0000-4000-8000-000000000001','allow_learner_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner impersonated original author'; END IF;
END $learner_enrollment_not_materials$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_not_original_author$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid,
   'b3160000-0000-4000-8000-000000000002','allow_learner_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'institution governor signed author Unit release'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor impersonated enrolled learner'; END IF;
END $governor_not_original_author$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $original_author_releases_single_learner_unit$
DECLARE a jsonb;b jsonb; denied boolean:=false;
BEGIN
 a:=public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
  current_setting('app.fictional_learner_enrollment_id')::uuid,
  current_setting('app.m316b_unit_id')::uuid,
  'b3160000-0000-4000-8000-000000000003','allow_learner_sealed_unit');
 b:=public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
  current_setting('app.fictional_learner_enrollment_id')::uuid,
  current_setting('app.m316b_unit_id')::uuid,
  'b3160000-0000-4000-8000-000000000003','allow_learner_sealed_unit');
 IF a->>'contractVersion'<>'shared_learner_unit_disclosure_author_v1'
 OR a->>'enrollmentId'<>current_setting('app.fictional_learner_enrollment_id')
 OR a->>'unitId'<>current_setting('app.m316b_unit_id')
 OR a->>'decision'<>'allow_learner_sealed_unit'
 OR a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'canReadCurriculum'<>'false' OR a->>'canParticipate'<>'false'
 OR a->>'canSubmit'<>'false' OR a->>'canAssignWork'<>'false'
 OR a->>'canTeach'<>'false' THEN
  RAISE EXCEPTION 'exact separate original-author Unit permission incorrect'; END IF;
 BEGIN
  PERFORM public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid,
   'b3160000-0000-4000-8000-000000000003','withhold_learner_sealed_unit');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'exact original author request changed on replay'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   '99999999-9999-4999-8999-999999999999',
   'b3160000-0000-4000-8000-000000000004','allow_learner_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'unsealed or foreign Unit could be released'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author impersonated recipient learner'; END IF;
END $original_author_releases_single_learner_unit$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666662","session_id":"56666666-6666-4666-8666-666666666662"}';
DO $declining_second_learner_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'declining different learner read original enrolled learner material'; END IF;
END $declining_second_learner_denied$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $accepted_teacher_not_learner$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'teacher read named learner private material as learner'; END IF;
END $accepted_teacher_not_learner$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $signed_learner_sees_exact_sealed_unit_only$
DECLARE j jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_learner_sealed_unit_read_self_api_v1(
  current_setting('app.fictional_learner_enrollment_id')::uuid,
  current_setting('app.m316b_unit_id')::uuid);
 IF j->>'contractVersion'<>'shared_learner_sealed_unit_read_v1'
 OR j->>'enrollmentId'<>current_setting('app.fictional_learner_enrollment_id')
 OR j->>'offeringId'<>current_setting('app.fictional_teacher_offering_id')
 OR j->>'unitId'<>current_setting('app.m316b_unit_id')
 OR j->>'learnerPersonEntityId'<>'f6666666-6666-4666-8666-666666666661'
 OR j->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR j->'unit'->>'unitId'<>current_setting('app.m316b_unit_id')
 OR j->>'scope'<>'one_author_approved_sealed_unit_to_enrolled_learner_only'
 OR j->>'canReadCurriculum'<>'false' OR j->>'canReadOtherUnits'<>'false'
 OR j->>'canReadManuscript'<>'false' OR j->>'canParticipate'<>'false'
 OR j->>'canSubmit'<>'false' OR j->>'canAssignWork'<>'false'
 OR j->>'canTeach'<>'false' OR j->>'canEnroll'<>'false'
 OR j ? 'curriculum' OR j ? 'units' OR j ? 'manuscript'
 OR j ? 'roster' OR j ? 'otherLearners' OR j ? 'work' OR j ? 'classroom'
 THEN RAISE EXCEPTION 'enrolled learner received improper sealed Unit or class rights'; END IF;
 -- Signed learner cannot SELECT private snapshot; the detached scratch
 -- owner verifies bytes without expanding that recipient's table privileges.
 PERFORM set_config('app.m316b_read_unit',(j->'unit')::text,true);
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   '99999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner could enumerate Unit outside exact author scope'; END IF;
END $signed_learner_sees_exact_sealed_unit_only$;
RESET ROLE;
DO $isolated_owner_compares_immutable_unit_bytes$
DECLARE sealed_unit jsonb; read_unit jsonb;
BEGIN
 SELECT x.unit INTO sealed_unit
 FROM atlas.teaching_course_version_curriculum_snapshots s
 CROSS JOIN LATERAL jsonb_array_elements(s.curriculum_payload->'units') x(unit)
 WHERE s.course_version_id=current_setting('app.fictional_published_version_id')::uuid
  AND x.unit->>'unitId'=current_setting('app.m316b_unit_id');
 read_unit:=current_setting('app.m316b_read_unit')::jsonb;
 IF sealed_unit IS NULL OR read_unit IS DISTINCT FROM sealed_unit THEN
  RAISE EXCEPTION 'learner sealed Unit content not byte-equivalent to original snapshot'; END IF;
END $isolated_owner_compares_immutable_unit_bytes$;

-- A forged session with the right canonical user SUB is not authorization.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"59999999-9999-4999-8999-999999999999"}';
DO $invalid_learner_session_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'invalid learner session leaked original sealed Unit'; END IF;
END $invalid_learner_session_denied$;
RESET ROLE;

-- Author withdraws THIS single Unit permission with immutable new event.
SAVEPOINT m316b_author_revokes_specific_unit;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $original_author_withholds_one_unit$
BEGIN
 PERFORM public.shared_teaching_learner_unit_disclose_decide_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid,
   'b3160000-0000-4000-8000-000000000005','withhold_learner_sealed_unit');
END $original_author_withholds_one_unit$;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $unit_revocation_stops_future_learner_read$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author revoked learner Unit scope but reading remained live'; END IF;
END $unit_revocation_stops_future_learner_read$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316b_author_revokes_specific_unit;

-- Native institution Teaching entitlement must remain CURRENT after grant.
SAVEPOINT m316b_native_teaching_revoked;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $revoked_source_entitlement_ends_learner_read$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked Teaching entitlement kept student materials open'; END IF;
END $revoked_source_entitlement_ends_learner_read$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316b_native_teaching_revoked;

-- Learner owns the right to exit an already-issued Enrollment; that
-- independent terminal withdrawal immediately ends Unit read, retaining
-- the original sealed source plus the immutable author decision history.
SAVEPOINT m316b_learner_self_withdraw;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $learner_withdrawal_closes_material_not_history$
DECLARE denied boolean:=false; j jsonb;
BEGIN
 j:=public.shared_teaching_learner_enrollment_withdraw_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   'b3160000-0000-4000-8000-000000000006');
 IF j->>'enrollmentState'<>'withdrawn' THEN
  RAISE EXCEPTION 'signed learner own withdrawal not terminal'; END IF;
 BEGIN PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'withdrawn learner retained sealed Unit access'; END IF;
END $learner_withdrawal_closes_material_not_history$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316b_learner_self_withdraw;

-- Governor's separate historical invitation withdrawal ends further
-- material reading even though it does not silently rewrite Enrollment.
SAVEPOINT m316b_invitation_withdrawn;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_withdraws_original_learner_invitation$
BEGIN
 PERFORM public.shared_teaching_learner_withdraw_self_api_v1(
   current_setting('app.fictional_learner_accept_offer_id')::uuid,
   'b3160000-0000-4000-8000-000000000007');
END $governor_withdraws_original_learner_invitation$;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $withdrawn_invitation_revokes_future_learner_material$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked original invitation kept learner Unit access'; END IF;
END $withdrawn_invitation_revokes_future_learner_material$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316b_invitation_withdrawn;

-- Independent author Enrollment withdrawal also closes future material read.
SAVEPOINT m316b_author_enrollment_scope_withheld;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_withholds_enrollment_scope$
BEGIN
 PERFORM public.shared_teaching_learner_enrollment_decide_self_api_v1(
   current_setting('app.fictional_teacher_offering_id')::uuid,
   'b3160000-0000-4000-8000-000000000008','withhold_learner_enrollment');
END $author_withholds_enrollment_scope$;
SET LOCAL request.jwt.claims='{"sub":"d6666666-6666-4666-8666-666666666661","session_id":"56666666-6666-4666-8666-666666666661"}';
DO $author_revoked_enrollment_closes_materials$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_learner_sealed_unit_read_self_api_v1(
   current_setting('app.fictional_learner_enrollment_id')::uuid,
   current_setting('app.m316b_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked author Enrollment scope kept learner source read'; END IF;
END $author_revoked_enrollment_closes_materials$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316b_author_enrollment_scope_withheld;

DO $m316b_private_original_unmodified$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings
    WHERE operating_proposal_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots)<>1
 OR (SELECT count(*) FROM atlas.teaching_enrollments)<>1
 OR (SELECT count(*) FROM atlas.shared_course_enrollment_issuances)<>1
 OR (SELECT count(*) FROM atlas.shared_course_learner_unit_disclosure_decisions)<>1
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_enrollments
   WHERE id=current_setting('app.fictional_learner_enrollment_id')::uuid
    AND state='active' AND withdrawn_at IS NULL)
 THEN RAISE EXCEPTION 'learner sealed Unit disclosure forged or changed Course/Enrollment'; END IF;
 BEGIN
  UPDATE atlas.shared_course_learner_unit_disclosure_decisions
   SET decision='withhold_learner_sealed_unit';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner Unit author permission receipt mutated'; END IF;
 denied:=false;
 BEGIN
  DELETE FROM atlas.shared_course_learner_unit_disclosure_decisions;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'learner Unit author permission receipt erased'; END IF;
END $m316b_private_original_unmodified$;
-- M3.15C own history/withdraw tests follow using active original Enrollment.
