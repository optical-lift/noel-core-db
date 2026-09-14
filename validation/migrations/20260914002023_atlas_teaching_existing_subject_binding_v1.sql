-- Behavioral postconditions for Atlas Teaching Existing Subject Binding v1.
-- Run only in a disposable production-schema clone after fixture + migration.

do $proof$
declare
  root_uid constant uuid := 'a2100000-0000-4000-8000-000000000001'::uuid;
  root_ledger constant uuid := 'a2200000-0000-4000-8000-000000000001'::uuid;
  other_ledger constant uuid := 'a2200000-0000-4000-8000-000000000002'::uuid;
  source_one constant uuid := 'a2500000-0000-4000-8000-000000000001'::uuid;
  source_two constant uuid := 'a2500000-0000-4000-8000-000000000002'::uuid;
  source_other constant uuid := 'a2500000-0000-4000-8000-000000000003'::uuid;
  v_result jsonb;
  v_retry jsonb;
  v_source_activation uuid;
  v_source_activation_two uuid;
  v_ledger_activation uuid;
  v_course uuid;
  v_failed boolean;
begin
  if not exists(
    select 1 from atlas.capability_definitions d
    where d.capability_key='teaching' and d.capability_version=1 and d.status='active'
      and d.eligible_subject_kinds @> array['ledger','organization_ledger_entry']::text[]
  ) then
    raise exception 'Teaching v1 definition did not expose the proven existing-subject kind.';
  end if;

  if not atlas.capability_subject_valid_v1(
    'teaching',1,root_ledger,'organization_ledger_entry',source_one,null,null
  ) then
    raise exception 'Existing same-Ledger Organization Ledger entry was not recognized as a valid Teaching subject.';
  end if;

  if atlas.capability_subject_valid_v1(
    'teaching',1,root_ledger,'organization_ledger_entry',source_other,null,null
  ) then
    raise exception 'Organization Ledger entry was accepted under the wrong subject Ledger.';
  end if;

  if not atlas.capability_subject_governed_v1(
    root_ledger,'teaching',1,root_ledger,'organization_ledger_entry',source_one,null,null
  ) then
    raise exception 'Same-Ledger Teaching subject was not governable.';
  end if;

  if atlas.capability_subject_governed_v1(
    root_ledger,'teaching',1,other_ledger,'organization_ledger_entry',source_other,null,null
  ) then
    raise exception 'Teaching v1 accepted direct cross-Ledger subject governance.';
  end if;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);

  v_failed:=false;
  begin
    perform atlas.create_capability_activation_self_api_v1(
      root_ledger,'teaching',1,other_ledger,'organization_ledger_entry',source_other,null,null
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Cross-Ledger Teaching activation was created without correlation.'; end if;

  v_result:=atlas.create_capability_activation_self_api_v1(
    root_ledger,'teaching',1,root_ledger,'organization_ledger_entry',source_one,null,null
  );
  v_source_activation:=(v_result->>'activationId')::uuid;
  perform atlas.transition_capability_activation_self_api_v1(v_source_activation,'active','Teach this source proof');

  if not atlas.teaching_activation_active_v1(root_ledger,v_source_activation) then
    raise exception 'Teaching activation over existing subject did not become active.';
  end if;

  v_result:=atlas.create_teaching_course_from_activation_self_api_v1(
    v_source_activation,'existing-subject-course','Existing Subject Course'
  );
  v_course:=(v_result->>'courseId')::uuid;
  if v_course is null
     or (v_result->>'capabilityActivationId')::uuid<>v_source_activation
     or v_result->>'sourceSubjectKind'<>'organization_ledger_entry'
     or (v_result->>'sourceSubjectId')::uuid<>source_one
     or (v_result->>'sourceSubjectLedgerId')::uuid<>root_ledger then
    raise exception 'Course did not preserve exact Teach this source: %',v_result;
  end if;
  if not exists(
    select 1 from atlas.teaching_courses c
    where c.id=v_course and c.ledger_id=root_ledger and c.capability_activation_id=v_source_activation
  ) then
    raise exception 'Durable Course / Teaching source binding is malformed.';
  end if;

  v_retry:=atlas.create_teaching_course_from_activation_self_api_v1(
    v_source_activation,'existing-subject-course','Existing Subject Course'
  );
  if (v_retry->>'courseId')::uuid<>v_course
     or coalesce((v_retry->>'alreadyExists')::boolean,false) is not true then
    raise exception 'Exact source-bound Course retry was not idempotent.';
  end if;

  v_result:=atlas.create_capability_activation_self_api_v1(
    root_ledger,'teaching',1,root_ledger,'organization_ledger_entry',source_two,null,null
  );
  v_source_activation_two:=(v_result->>'activationId')::uuid;
  perform atlas.transition_capability_activation_self_api_v1(v_source_activation_two,'active','Second source proof');

  v_failed:=false;
  begin
    perform atlas.create_teaching_course_from_activation_self_api_v1(
      v_source_activation_two,'existing-subject-course','Existing Subject Course'
    );
  exception when sqlstate '23505' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Course key was silently rebound to a different source subject.'; end if;

  v_result:=atlas.create_teaching_course_from_activation_self_api_v1(
    v_source_activation_two,'existing-subject-course-two','Existing Subject Course Two'
  );
  if (v_result->>'capabilityActivationId')::uuid<>v_source_activation_two then
    raise exception 'Second source-bound Course did not retain its own activation.';
  end if;

  v_result:=atlas.create_capability_activation_self_api_v1(
    root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null
  );
  v_ledger_activation:=(v_result->>'activationId')::uuid;
  perform atlas.transition_capability_activation_self_api_v1(v_ledger_activation,'active','Ledger root compatibility proof');
  if not atlas.teaching_activation_active_v1(root_ledger,v_ledger_activation) then
    raise exception 'Existing Ledger-root Teaching activation compatibility broke.';
  end if;
  v_result:=atlas.create_teaching_course_self_api_v1(root_ledger,'ledger-root-course','Ledger Root Course');
  if (v_result->>'capabilityActivationId')::uuid<>v_ledger_activation then
    raise exception 'Existing Ledger-root Course API no longer selects Ledger-root Teaching.';
  end if;

  perform atlas.transition_capability_activation_self_api_v1(v_source_activation,'paused','Pause existing source proof');
  if atlas.teaching_activation_active_v1(root_ledger,v_source_activation) then
    raise exception 'Paused existing-subject Teaching activation remained active.';
  end if;
  v_failed:=false;
  begin
    perform atlas.create_teaching_course_from_activation_self_api_v1(
      v_source_activation,'paused-source-course','Paused Source Course'
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Paused source activation created a new Course.'; end if;
  if not exists(select 1 from atlas.teaching_courses where id=v_course and capability_activation_id=v_source_activation) then
    raise exception 'Pausing Teaching erased existing source-bound Course truth.';
  end if;

  if has_function_privilege('anon','atlas.create_teaching_course_from_activation_self_api_v1(uuid,text,text)','EXECUTE') then
    raise exception 'anon can execute source-bound Course creation.';
  end if;
  if not has_function_privilege('authenticated','atlas.create_teaching_course_from_activation_self_api_v1(uuid,text,text)','EXECUTE') then
    raise exception 'authenticated cannot execute bounded source-bound Course creation.';
  end if;
  if has_function_privilege('authenticated','atlas.capability_subject_governed_v1(uuid,text,integer,uuid,text,uuid,text,text)','EXECUTE') then
    raise exception 'authenticated can execute internal capability subject governance validator directly.';
  end if;
  if not has_function_privilege('service_role','atlas.capability_subject_governed_v1(uuid,text,integer,uuid,text,uuid,text,text)','EXECUTE') then
    raise exception 'service_role cannot execute capability subject governance validator.';
  end if;
end;
$proof$;
