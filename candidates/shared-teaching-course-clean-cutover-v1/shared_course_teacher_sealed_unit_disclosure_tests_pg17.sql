-- HELD M3.16A: fictional separate author-approved exact SEALED Unit disclosure.
-- Runs AFTER two independently signed teacher decisions on one Course/Offering
-- but BEFORE existing teacher appointment/Teaching permission revocation tests.
-- No student, Work, class or whole Course manuscript access.
DO $m316_source_acl$
BEGIN
 IF has_table_privilege('authenticated',
    'atlas.shared_course_teacher_unit_disclosure_decisions','SELECT')
 OR has_table_privilege('authenticated',
    'atlas.shared_course_teacher_unit_disclosure_decisions','INSERT')
 OR has_function_privilege('anon',
    'public.shared_teaching_teacher_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
    'public.shared_teaching_teacher_sealed_unit_read_self_api_v1(uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
    'public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger
  WHERE tgrelid='atlas.shared_course_teacher_unit_disclosure_decisions'::regclass
  AND tgname='shared_teacher_unit_disclosure_immutable' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'teacher sealed Unit source or grants are not private'; END IF;
END $m316_source_acl$;
SELECT set_config('app.m316_unit_id',u.unit_id::text,true)
 FROM atlas.teaching_course_units u
 WHERE u.course_id='11111111-1111-4111-8111-111111111111'
 ORDER BY u.display_position,u.unit_id LIMIT 1;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $m316_acceptance_is_not_materials$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'accepted teacher acquired sealed Unit without author approval'; END IF;
END $m316_acceptance_is_not_materials$;
RESET ROLE;

-- The authored exact Unit is selected from the existing immutable Version.
-- Only the original author can grant disclosure on ONE accepted offer+Unit.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m316_author_grants_exact_teacher_unit$
DECLARE a jsonb;b jsonb; denied boolean:=false;
BEGIN
 a:=public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid,
  'a3160000-0000-4000-8000-000000000001','allow_teacher_sealed_unit');
 b:=public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid,
  'a3160000-0000-4000-8000-000000000001','allow_teacher_sealed_unit');
 IF a->>'contractVersion'<>'shared_teacher_unit_disclosure_author_v1'
 OR a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'teacherOfferId'<>current_setting('app.teacher_accept_offer_id')
 OR a->>'unitId'<>current_setting('app.m316_unit_id')
 OR a->>'canReadCurriculum'<>'false' OR a->>'canTeach'<>'false'
 OR a->>'canReadOthers'<>'false' THEN
  RAISE EXCEPTION 'separate author grant returned imprecise Unit scope'; END IF;
 BEGIN
  PERFORM public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid,
   'a3160000-0000-4000-8000-000000000001','withhold_teacher_sealed_unit');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'replayed source grant could change to withhold'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid,
   'a3160000-0000-4000-8000-000000000002','allow_teacher_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author granted sealed Unit to declined teacher'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   '99999999-9999-4999-8999-999999999999',
   'a3160000-0000-4000-8000-000000000003','allow_teacher_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'author granted unseen, unsealed phantom Unit'; END IF;
END $m316_author_grants_exact_teacher_unit$;
RESET ROLE;

-- Institution governor did not become a personal teacher; Course author did
-- not become teacher; declining teacher cannot access accepted teacher data.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $m316_governor_cannot_read_named_teacher_unit$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor read private individual teacher Unit'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid,
   'a3160000-0000-4000-8000-000000000004','allow_teacher_sealed_unit');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor authorized Unit as original Course author'; END IF;
END $m316_governor_cannot_read_named_teacher_unit$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeed","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeed"}';
DO $m316_declining_teacher_cannot_read_other_teacher$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'other teacher saw a specific teacher sealed Unit'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
   current_setting('app.teacher_decline_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'declined teacher acquired material without consent/grant'; END IF;
END $m316_declining_teacher_cannot_read_other_teacher$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $m316_teacher_reads_exact_one_sealed_unit$
DECLARE j jsonb; denied boolean:=false;
BEGIN
 j:=public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid);
 IF j->>'contractVersion'<>'shared_teacher_sealed_unit_read_v1'
 OR j->>'teacherOfferId'<>current_setting('app.teacher_accept_offer_id')
 OR j->>'offeringId'<>current_setting('app.fictional_teacher_offering_id')
 OR j->>'unitId'<>current_setting('app.m316_unit_id')
 OR j->>'courseVersionId'<>current_setting('app.fictional_published_version_id')
 OR j->'unit' IS NULL
 OR j->>'scope'<>'one_author_approved_sealed_unit_to_appointed_teacher_only'
 OR j->>'canTeach'<>'false' OR j->>'canReadOtherUnits'<>'false'
 OR j->>'canReadManuscript'<>'false' OR j->>'canShareWithLearners'<>'false'
 OR j->>'canAssignWork'<>'false' OR j->>'canEnroll'<>'false'
 OR j ? 'manuscript' OR j ? 'curriculum' OR j ? 'units' OR j ? 'roster'
 OR j ? 'otherTeachers' OR j ? 'learners' OR j ? 'courseText' THEN
  RAISE EXCEPTION 'Unit read was not exact single Unit and negative rights'; END IF;
 -- Test transport only, with fully fictional bytes: the signed teacher
 -- cannot SELECT private snapshot tables. Scratch owner checks fidelity.
 PERFORM set_config('app.m316_read_unit', (j->'unit')::text,true);
 BEGIN
  PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
    current_setting('app.teacher_accept_offer_id')::uuid,
    '99999999-9999-4999-8999-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'teacher enumerated another Unit without author scope'; END IF;
END $m316_teacher_reads_exact_one_sealed_unit$;
RESET ROLE;
DO $m316_scratch_owner_bytes_equal_sealed_source$
DECLARE sealed_unit jsonb; observed jsonb;
BEGIN
 SELECT x.unit INTO sealed_unit
 FROM atlas.teaching_course_version_curriculum_snapshots s
 CROSS JOIN LATERAL jsonb_array_elements(s.curriculum_payload->'units') x(unit)
 WHERE s.course_id='11111111-1111-4111-8111-111111111111'
  AND s.course_version_id=current_setting('app.fictional_published_version_id')::uuid
  AND x.unit->>'unitId'=current_setting('app.m316_unit_id');
 observed:=current_setting('app.m316_read_unit')::jsonb;
 IF sealed_unit IS NULL OR observed IS DISTINCT FROM sealed_unit THEN
  RAISE EXCEPTION 'specific authorized Unit does not match immutable sealed source';
 END IF;
END $m316_scratch_owner_bytes_equal_sealed_source$;

-- After author revokes THIS UNIT only, previously accepted appointment and
-- invitation remain historic but future reads are denied.
SAVEPOINT m316_author_unit_revoked;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $m316_author_withholds_unit$
BEGIN
 PERFORM public.shared_teaching_teacher_unit_disclose_decide_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid,
  'a3160000-0000-4000-8000-000000000005','withhold_teacher_sealed_unit');
END $m316_author_withholds_unit$;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $m316_revoked_teacher_cannot_read_unit$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked author Unit scope kept teacher materials live'; END IF;
END $m316_revoked_teacher_cannot_read_unit$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316_author_unit_revoked;

-- Independently revoked source Teaching entitlement denies material read,
-- even with current author Unit allow, accepted teacher consent, open Offering.
SAVEPOINT m316_teaching_revoked;
UPDATE atlas.fictional_teaching_entitlement SET state='revoked';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"5eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
DO $m316_teaching_entitlement_revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
   current_setting('app.teacher_accept_offer_id')::uuid,
   current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked institution Teaching grant kept private teacher Unit'; END IF;
END $m316_teaching_entitlement_revoked$;
RESET ROLE;
ROLLBACK TO SAVEPOINT m316_teaching_revoked;

-- The signed user binding and session must both be current.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","session_id":"50000000-0000-4000-8000-000000000000"}';
DO $m316_fake_teacher_session_denied$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_teacher_sealed_unit_read_self_api_v1(
  current_setting('app.teacher_accept_offer_id')::uuid,
  current_setting('app.m316_unit_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'nonexistent teacher session read sealed material'; END IF;
END $m316_fake_teacher_session_denied$;
RESET ROLE;

DO $m316_unchanged_originals$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_offerings
    WHERE operating_proposal_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots)<>1
 OR (SELECT count(*) FROM atlas.shared_course_teacher_unit_disclosure_decisions)<>1
 OR EXISTS(SELECT 1 FROM atlas.teaching_enrollments)
 THEN RAISE EXCEPTION 'teacher sealed Unit read modified Course/Offering/student originals'; END IF;
 BEGIN
  UPDATE atlas.shared_course_teacher_unit_disclosure_decisions
   SET decision='withhold_teacher_sealed_unit';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'source author sealed Unit grant was rewritten'; END IF;
END $m316_unchanged_originals$;
-- Existing M3.14 teacher revocation and M3.15 learner test still follow.
