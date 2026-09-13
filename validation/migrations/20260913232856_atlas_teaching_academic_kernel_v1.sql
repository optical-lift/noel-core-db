-- Behavioral postconditions for Atlas Teaching Academic Kernel v1 candidate.
-- Run only in a disposable production-schema clone after fixture + candidate.sql + hardening.sql.

do $proof$
declare
  root_uid constant uuid := 'd1100000-0000-4000-8000-000000000001'::uuid;
  owner_uid constant uuid := 'e1100000-0000-4000-8000-000000000001'::uuid;
  learner1_uid constant uuid := 'f1100000-0000-4000-8000-000000000001'::uuid;
  learner2_uid constant uuid := 'f1200000-0000-4000-8000-000000000001'::uuid;
  learner1_person constant uuid := 'f1100000-0000-4000-8000-000000000011'::uuid;
  learner2_person constant uuid := 'f1200000-0000-4000-8000-000000000011'::uuid;
  root_ledger constant uuid := 'd1200000-0000-4000-8000-000000000001'::uuid;
  v_result jsonb;
  v_retry jsonb;
  v_capability uuid;
  v_course uuid;
  v_course2 uuid;
  v_version1 uuid;
  v_version2 uuid;
  v_other_version uuid;
  v_offering uuid;
  v_enrollment1 uuid;
  v_enrollment2 uuid;
  v_failed boolean;
  v_before bigint;
  v_after bigint;
  v_memberships_before bigint;
  v_principals_before bigint;
  v_authorities_before bigint;
  v_commercial_before bigint;
begin
  -- Baseline: Gate A exists live in the production-shaped clone and no academic tables are browser-writable.
  if not exists(select 1 from atlas.capability_definitions where capability_key='teaching' and capability_version=1 and status='active') then
    raise exception 'Gate A Teaching v1 definition is missing.';
  end if;

  select count(*) into v_commercial_before from atlas.commercial_offerings;
  select count(*) into v_memberships_before from atlas.organization_memberships where person_id=learner1_person;
  select count(*) into v_principals_before from atlas.principals where person_id=learner1_person;
  select count(*) into v_authorities_before
  from atlas.principal_ledger_authorities a join atlas.principals p on p.id=a.principal_id
  where p.person_id=learner1_person;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);

  -- 1/2. Teaching capability is required. Root authority alone cannot manufacture a Course.
  v_failed:=false;
  begin perform atlas.create_teaching_course_self_api_v1(root_ledger,'song-method-i','Song Method I');
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Course creation succeeded without active Teaching capability.'; end if;

  -- Activate Teaching through Gate A itself.
  v_result:=atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  v_capability:=(v_result->>'activationId')::uuid;
  perform atlas.transition_capability_activation_self_api_v1(v_capability,'active','Gate B proof');
  if not atlas.teaching_activation_active_v1(root_ledger,v_capability) then raise exception 'Teaching activation did not become usable by Gate B.'; end if;

  -- 3/4. Root authority creates; Organization ownership without Ledger root authority does not.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_failed:=false;
  begin perform atlas.create_teaching_course_self_api_v1(root_ledger,'owner-illegal-course','Owner Illegal Course');
  exception when sqlstate '42501' then v_failed:=true; end;
  if not v_failed then raise exception 'Organization owner without root Ledger authority created Course.'; end if;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  v_result:=atlas.create_teaching_course_self_api_v1(root_ledger,'song-method-i','Song Method I');
  v_course:=(v_result->>'courseId')::uuid;
  if v_course is null or v_result->>'courseState'<>'active' or (v_result->>'capabilityActivationId')::uuid<>v_capability then
    raise exception 'Root-authorized Course creation malformed: %',v_result;
  end if;

  -- 5. Exact Course retry is idempotent and Course is bound to exact Ledger/Teaching activation.
  v_retry:=atlas.create_teaching_course_self_api_v1(root_ledger,'song-method-i','Song Method I');
  if (v_retry->>'courseId')::uuid<>v_course or coalesce((v_retry->>'alreadyExists')::boolean,false) is not true then
    raise exception 'Exact Course retry was not idempotent.';
  end if;
  if not exists(select 1 from atlas.teaching_courses where id=v_course and ledger_id=root_ledger and capability_activation_id=v_capability and course_key='song-method-i') then
    raise exception 'Course durable Ledger/capability binding is malformed.';
  end if;

  -- 6/7/8. Publish immutable Version 1, then Version 2 without rewriting Version 1.
  v_result:=atlas.publish_teaching_course_version_self_api_v1(v_course,'Song Method I','First published definition',array['recognize form','map sections']::text[]);
  v_version1:=(v_result->>'courseVersionId')::uuid;
  if (v_result->>'versionNo')::integer<>1 then raise exception 'First Course Version did not receive version 1.'; end if;
  v_failed:=false;
  begin update atlas.teaching_course_versions set title='Illegal rewrite' where id=v_version1;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Published Course Version was mutable.'; end if;

  v_result:=atlas.publish_teaching_course_version_self_api_v1(v_course,'Song Method I Revised','Second published definition',array['recognize form','map sections','teach back']::text[]);
  v_version2:=(v_result->>'courseVersionId')::uuid;
  if (v_result->>'versionNo')::integer<>2 or v_version2=v_version1 then raise exception 'Second Course Version sequencing failed.'; end if;
  if not exists(select 1 from atlas.teaching_course_versions where id=v_version1 and version_no=1 and title='Song Method I' and summary='First published definition') then
    raise exception 'Publishing Version 2 rewrote Version 1.';
  end if;

  -- Create another Course/Version solely to prove cross-course version attachment fails.
  v_result:=atlas.create_teaching_course_self_api_v1(root_ledger,'other-course','Other Course');
  v_course2:=(v_result->>'courseId')::uuid;
  v_result:=atlas.publish_teaching_course_version_self_api_v1(v_course2,'Other Course','Other definition','{}'::text[]);
  v_other_version:=(v_result->>'courseVersionId')::uuid;

  -- 9/10. Offering binds one exact Version and cannot borrow another Course's Version.
  v_failed:=false;
  begin perform atlas.create_teaching_course_offering_self_api_v1(v_course,v_other_version,'self_paced',null,null);
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Offering accepted a Course Version from another Course.'; end if;

  v_result:=atlas.create_teaching_course_offering_self_api_v1(v_course,v_version1,'self_paced',null,null);
  v_offering:=(v_result->>'offeringId')::uuid;
  if v_offering is null or (v_result->>'courseVersionId')::uuid<>v_version1 or v_result->>'offeringState'<>'draft' then
    raise exception 'Course Offering creation malformed: %',v_result;
  end if;
  v_failed:=false;
  begin update atlas.teaching_course_offerings set course_version_id=v_version2 where id=v_offering;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Course Offering exact Version custody was mutable.'; end if;

  -- 11. Organization owner cannot open Offering; root Principal can.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_failed:=false;
  begin perform atlas.transition_teaching_course_offering_self_api_v1(v_offering,'open');
  exception when sqlstate '42501' then v_failed:=true; end;
  if not v_failed then raise exception 'Non-root Organization owner opened Course Offering.'; end if;
  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  v_result:=atlas.transition_teaching_course_offering_self_api_v1(v_offering,'open');
  if v_result->>'offeringState'<>'open' then raise exception 'Root Principal could not open Offering.'; end if;

  -- 12-16. Enrollment requires open Offering/active Teaching, points to Person directly, creates no Atlas authority/membership, and retries idempotently.
  v_result:=atlas.enroll_person_in_teaching_offering_self_api_v1(v_offering,learner1_person);
  v_enrollment1:=(v_result->>'enrollmentId')::uuid;
  if v_enrollment1 is null or (v_result->>'personId')::uuid<>learner1_person or v_result->>'enrollmentState'<>'active' then
    raise exception 'Learner Enrollment creation malformed: %',v_result;
  end if;
  v_retry:=atlas.enroll_person_in_teaching_offering_self_api_v1(v_offering,learner1_person);
  if (v_retry->>'enrollmentId')::uuid<>v_enrollment1 or coalesce((v_retry->>'alreadyEnrolled')::boolean,false) is not true then
    raise exception 'Exact active Enrollment retry was not idempotent.';
  end if;
  select count(*) into v_after from atlas.organization_memberships where person_id=learner1_person;
  if v_after<>v_memberships_before then raise exception 'Enrollment manufactured Organization membership.'; end if;
  select count(*) into v_after from atlas.principals where person_id=learner1_person;
  if v_after<>v_principals_before then raise exception 'Enrollment manufactured Principal identity.'; end if;
  select count(*) into v_after
  from atlas.principal_ledger_authorities a join atlas.principals p on p.id=a.principal_id
  where p.person_id=learner1_person;
  if v_after<>v_authorities_before then raise exception 'Enrollment manufactured Principal/Ledger authority.'; end if;

  -- 17. Learner self-read is Person-scoped and does not leak to another Person.
  perform set_config('request.jwt.claim.sub',learner1_uid::text,true);
  v_result:=atlas.teaching_enrollments_for_current_person_self_api_v1();
  if (v_result->>'personId')::uuid<>learner1_person or jsonb_array_length(v_result->'items')<>1
     or (v_result->'items'->0->>'enrollmentId')::uuid<>v_enrollment1 then
    raise exception 'Learner self-read did not return own Enrollment: %',v_result;
  end if;
  perform set_config('request.jwt.claim.sub',learner2_uid::text,true);
  v_result:=atlas.teaching_enrollments_for_current_person_self_api_v1();
  if (v_result->>'personId')::uuid<>learner2_person or jsonb_array_length(v_result->'items')<>0 then
    raise exception 'Learner self-read leaked another Person Enrollment: %',v_result;
  end if;

  -- 18/19. Withdrawal is terminal history; re-enrollment creates a new row.
  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  perform atlas.withdraw_teaching_enrollment_self_api_v1(v_enrollment1,'proof withdrawal');
  if not exists(select 1 from atlas.teaching_enrollments where id=v_enrollment1 and state='withdrawn' and withdrawn_at is not null) then
    raise exception 'Enrollment withdrawal did not preserve terminal history.';
  end if;
  v_failed:=false;
  begin update atlas.teaching_enrollments set state='active',withdrawn_at=null where id=v_enrollment1;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Withdrawn Enrollment was resurrected.'; end if;
  v_result:=atlas.enroll_person_in_teaching_offering_self_api_v1(v_offering,learner1_person);
  v_enrollment2:=(v_result->>'enrollmentId')::uuid;
  if v_enrollment2 is null or v_enrollment2=v_enrollment1
     or not exists(select 1 from atlas.teaching_enrollments where id=v_enrollment1 and state='withdrawn') then
    raise exception 'Re-enrollment did not preserve prior withdrawn row.';
  end if;

  -- 20. Pausing Teaching blocks new commitments but preserves governance closure/withdrawal and historical learner reads.
  perform atlas.transition_capability_activation_self_api_v1(v_capability,'paused','Gate B pause proof');
  v_failed:=false;
  begin perform atlas.create_teaching_course_self_api_v1(root_ledger,'paused-illegal','Paused Illegal');
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Paused Teaching allowed new Course.'; end if;
  v_failed:=false;
  begin perform atlas.publish_teaching_course_version_self_api_v1(v_course,'Paused Illegal Version',null,'{}'::text[]);
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Paused Teaching allowed new Course Version publication.'; end if;
  v_failed:=false;
  begin perform atlas.create_teaching_course_offering_self_api_v1(v_course,v_version2,'self_paced',null,null);
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Paused Teaching allowed new Offering.'; end if;
  v_failed:=false;
  begin perform atlas.enroll_person_in_teaching_offering_self_api_v1(v_offering,learner2_person);
  exception when sqlstate '23514' then v_failed:=true; end;
  if not v_failed then raise exception 'Paused Teaching allowed new Enrollment.'; end if;

  perform set_config('request.jwt.claim.sub',learner1_uid::text,true);
  v_result:=atlas.teaching_enrollments_for_current_person_self_api_v1();
  if jsonb_array_length(v_result->'items')<>2 then raise exception 'Paused Teaching erased learner history.'; end if;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  v_result:=atlas.transition_teaching_course_offering_self_api_v1(v_offering,'closed');
  if v_result->>'offeringState'<>'closed' then raise exception 'Paused Teaching prevented governance closure of existing Offering.'; end if;
  perform atlas.withdraw_teaching_enrollment_self_api_v1(v_enrollment2,'closeout while paused');
  if not exists(select 1 from atlas.teaching_enrollments where id=v_enrollment2 and state='withdrawn') then
    raise exception 'Paused Teaching prevented governance withdrawal.';
  end if;

  -- Retire Offering and Course while capability remains paused; historical truth must persist.
  perform atlas.transition_teaching_course_offering_self_api_v1(v_offering,'retired');
  perform atlas.retire_teaching_course_self_api_v1(v_course,'Gate B proof retirement');
  v_failed:=false;
  begin update atlas.teaching_courses set status='active',retired_at=null where id=v_course;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Retired Course was resurrected.'; end if;
  v_failed:=false;
  begin update atlas.teaching_course_offerings set state='open',retired_at=null where id=v_offering;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Retired Offering was resurrected.'; end if;

  perform set_config('request.jwt.claim.sub',learner1_uid::text,true);
  v_result:=atlas.teaching_enrollments_for_current_person_self_api_v1();
  if jsonb_array_length(v_result->'items')<>2 then raise exception 'Retirement erased learner history.'; end if;

  -- 21. Academic Offering never touches commerce truth.
  select count(*) into v_after from atlas.commercial_offerings;
  if v_after<>v_commercial_before then raise exception 'Academic Course Offering mutated atlas.commercial_offerings.'; end if;

  -- 22/23. Browser privilege membrane stays closed; only bounded authenticated APIs are exposed.
  if has_table_privilege('authenticated','atlas.teaching_courses','SELECT')
     or has_table_privilege('authenticated','atlas.teaching_courses','INSERT')
     or has_table_privilege('authenticated','atlas.teaching_course_versions','SELECT')
     or has_table_privilege('authenticated','atlas.teaching_course_offerings','SELECT')
     or has_table_privilege('authenticated','atlas.teaching_enrollments','SELECT')
     or has_table_privilege('anon','atlas.teaching_enrollments','SELECT') then
    raise exception 'Teaching academic tables are directly exposed to browser roles.';
  end if;
  if not has_function_privilege('authenticated','atlas.create_teaching_course_self_api_v1(uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.publish_teaching_course_version_self_api_v1(uuid,text,text,text[])','EXECUTE')
     or not has_function_privilege('authenticated','atlas.create_teaching_course_offering_self_api_v1(uuid,uuid,text,timestamp with time zone,timestamp with time zone)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.enroll_person_in_teaching_offering_self_api_v1(uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.teaching_enrollments_for_current_person_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.teaching_enrollments_for_current_person_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.create_teaching_course_self_api_v1(uuid,text,text)','EXECUTE') then
    raise exception 'Teaching academic API privilege membrane is incorrect.';
  end if;
end;
$proof$;
