-- Behavioral postconditions for Atlas Teaching Course Detail Read v1.
-- Run only in a disposable production-schema clone after the fixture and candidate migration.

do $proof$
declare
  root_uid constant uuid := 'd2100000-0000-4000-8000-000000000001'::uuid;
  learner_uid constant uuid := 'f2100000-0000-4000-8000-000000000001'::uuid;
  learner_person constant uuid := 'f2100000-0000-4000-8000-000000000011'::uuid;
  root_ledger constant uuid := 'd2200000-0000-4000-8000-000000000001'::uuid;
  v_result jsonb;
  v_capability uuid;
  v_course uuid;
  v_version1 uuid;
  v_version2 uuid;
  v_offering uuid;
  v_enrollment uuid;
  v_failed boolean;
  v_before bigint;
  v_after bigint;
begin
  perform set_config('request.jwt.claim.sub',root_uid::text,true);

  -- Establish the ordinary Gate A/B truth that this read projection must expose.
  v_result:=atlas.create_capability_activation_self_api_v1(
    root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null
  );
  v_capability:=(v_result->>'activationId')::uuid;
  perform atlas.transition_capability_activation_self_api_v1(v_capability,'active','Teaching detail read proof');

  v_result:=atlas.create_teaching_course_self_api_v1(root_ledger,'detail-proof-course','Detail Proof Course');
  v_course:=(v_result->>'courseId')::uuid;

  v_result:=atlas.publish_teaching_course_version_self_api_v1(
    v_course,'Detail Proof Course','First immutable definition',array['first outcome']::text[]
  );
  v_version1:=(v_result->>'courseVersionId')::uuid;

  v_result:=atlas.publish_teaching_course_version_self_api_v1(
    v_course,'Detail Proof Course v2','Second immutable definition',array['first outcome','second outcome']::text[]
  );
  v_version2:=(v_result->>'courseVersionId')::uuid;

  v_result:=atlas.create_teaching_course_offering_self_api_v1(v_course,v_version2,'self_paced',null,null);
  v_offering:=(v_result->>'offeringId')::uuid;
  perform atlas.transition_teaching_course_offering_self_api_v1(v_offering,'open');

  v_result:=atlas.enroll_person_in_teaching_offering_self_api_v1(v_offering,learner_person);
  v_enrollment:=(v_result->>'enrollmentId')::uuid;

  select count(*) into v_before from atlas.teaching_course_versions where course_id=v_course;
  v_before:=v_before + (select count(*) from atlas.teaching_course_offerings where course_id=v_course);

  -- 1. Root-governing Teaching view returns the exact Course and its durable source custody.
  v_result:=atlas.teaching_course_admin_self_api_v1(v_course);
  if (v_result->>'courseId')::uuid<>v_course
     or (v_result->>'ledgerId')::uuid<>root_ledger
     or v_result->>'courseKey'<>'detail-proof-course'
     or v_result->>'name'<>'Detail Proof Course'
     or v_result->>'courseState'<>'active'
     or (v_result->>'capabilityActivationId')::uuid<>v_capability
     or v_result->>'activationState'<>'active'
     or (v_result->>'sourceSubjectLedgerId')::uuid<>root_ledger
     or v_result->>'sourceSubjectKind'<>'ledger'
     or (v_result->>'sourceSubjectId')::uuid<>root_ledger then
    raise exception 'Teaching Course detail identity/custody projection malformed: %',v_result;
  end if;

  -- 2. Published Versions are complete, immutable-history ordered, and distinguish exact definitions.
  if jsonb_array_length(v_result->'versions')<>2
     or (v_result->'versions'->0->>'courseVersionId')::uuid<>v_version1
     or (v_result->'versions'->0->>'versionNo')::integer<>1
     or v_result->'versions'->0->>'title'<>'Detail Proof Course'
     or v_result->'versions'->0->>'summary'<>'First immutable definition'
     or (v_result->'versions'->1->>'courseVersionId')::uuid<>v_version2
     or (v_result->'versions'->1->>'versionNo')::integer<>2
     or v_result->'versions'->1->>'title'<>'Detail Proof Course v2'
     or jsonb_array_length(v_result->'versions'->1->'learningOutcomes')<>2 then
    raise exception 'Teaching Course Version projection malformed or unordered: %',v_result->'versions';
  end if;

  -- 3. Offerings preserve exact Version custody and governed lifecycle state.
  if jsonb_array_length(v_result->'offerings')<>1
     or (v_result->'offerings'->0->>'offeringId')::uuid<>v_offering
     or (v_result->'offerings'->0->>'courseVersionId')::uuid<>v_version2
     or v_result->'offerings'->0->>'offeringState'<>'open'
     or v_result->'offerings'->0->>'deliveryMode'<>'self_paced'
     or v_result->'offerings'->0->>'openedAt' is null then
    raise exception 'Teaching Course Offering projection malformed: %',v_result->'offerings';
  end if;

  -- 4. Reading is observational only.
  select count(*) into v_after from atlas.teaching_course_versions where course_id=v_course;
  v_after:=v_after + (select count(*) from atlas.teaching_course_offerings where course_id=v_course);
  if v_after<>v_before then raise exception 'Course detail read mutated academic truth.'; end if;

  -- 5. A learner enrollment does not confer Teaching-side administrative read authority.
  perform set_config('request.jwt.claim.sub',learner_uid::text,true);
  v_failed:=false;
  begin
    perform atlas.teaching_course_admin_self_api_v1(v_course);
  exception when sqlstate '42501' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Learner read Teaching-side Course administration without root Ledger authority.'; end if;

  -- Existing learner projection remains independent and Person-scoped.
  v_result:=atlas.teaching_enrollments_for_current_person_self_api_v1();
  if (v_result->>'personId')::uuid<>learner_person
     or jsonb_array_length(v_result->'items')<>1
     or (v_result->'items'->0->>'enrollmentId')::uuid<>v_enrollment then
    raise exception 'Learner projection was disturbed by Teaching Course detail read: %',v_result;
  end if;

  -- 6. Pausing Teaching blocks new commitments but does not erase the governing read of established history.
  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  perform atlas.transition_capability_activation_self_api_v1(v_capability,'paused','Teaching detail historical read proof');
  v_result:=atlas.teaching_course_admin_self_api_v1(v_course);
  if v_result->>'activationState'<>'paused'
     or jsonb_array_length(v_result->'versions')<>2
     or jsonb_array_length(v_result->'offerings')<>1 then
    raise exception 'Paused Teaching erased or hid established Course history: %',v_result;
  end if;

  -- 7. Unknown Course IDs fail closed rather than returning an empty cross-tenant shape.
  v_failed:=false;
  begin
    perform atlas.teaching_course_admin_self_api_v1('ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid);
  exception when sqlstate 'P0002' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Unknown Course ID did not fail closed.'; end if;

  -- 8. Browser membrane: bounded API only, no direct academic-table read grant.
  if not has_function_privilege('authenticated','atlas.teaching_course_admin_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role cannot execute Teaching Course detail API.';
  end if;
  if has_function_privilege('anon','atlas.teaching_course_admin_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Anon role can execute Teaching Course detail API.';
  end if;
  if has_table_privilege('authenticated','atlas.teaching_courses','SELECT')
     or has_table_privilege('authenticated','atlas.teaching_course_versions','SELECT')
     or has_table_privilege('authenticated','atlas.teaching_course_offerings','SELECT') then
    raise exception 'Teaching Course detail migration reopened direct authenticated table reads.';
  end if;
end;
$proof$;
