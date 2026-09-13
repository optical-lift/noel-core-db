-- Hardening overlay for Atlas Teaching Academic Kernel v1 candidate.
-- Concatenate after candidate.sql when promoting to the single governed migration.

begin;

-- Correct the active Teaching activation lookup to use fields Gate A actually owns.
create or replace function atlas.create_teaching_course_self_api_v1(p_ledger_id uuid,p_course_key text,p_name text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_person uuid; v_principal uuid; v_authority uuid; v_key text:=lower(btrim(coalesce(p_course_key,''))); v_name text:=btrim(coalesce(p_name,''));
  v_activation atlas.capability_activations%rowtype; v_existing atlas.teaching_courses%rowtype; v_created atlas.teaching_courses%rowtype;
begin
  if v_key='' or v_name='' then raise exception 'Course key and name are required.' using errcode='22023'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  select * into v_activation from atlas.capability_activations a
  where a.ledger_id=p_ledger_id and a.subject_ledger_id=p_ledger_id and a.subject_kind='ledger'
    and a.subject_id=p_ledger_id and a.subject_key is null and a.subject_path is null
    and a.capability_key='teaching' and a.capability_version=1 and a.state='active'
  order by a.created_at,a.id limit 1;
  if v_activation.id is null or not atlas.teaching_activation_active_v1(p_ledger_id,v_activation.id) then
    raise exception 'Active Teaching v1 capability required.' using errcode='23514';
  end if;
  select * into v_existing from atlas.teaching_courses t
  where t.ledger_id=p_ledger_id and lower(t.course_key)=v_key limit 1;
  if v_existing.id is not null then
    if v_existing.name<>v_name then raise exception 'Course key already identifies a different Course name.' using errcode='23505'; end if;
    return jsonb_build_object('contractVersion','teaching_course_create_self_v1','state','ready','alreadyExists',true,
      'courseId',v_existing.id,'ledgerId',v_existing.ledger_id,'courseState',v_existing.status,'capabilityActivationId',v_existing.capability_activation_id);
  end if;
  insert into atlas.teaching_courses(
    ledger_id,capability_activation_id,course_key,name,status,created_by_person_id,created_by_principal_id
  ) values (p_ledger_id,v_activation.id,v_key,v_name,'active',v_person,v_principal)
  returning * into v_created;
  return jsonb_build_object('contractVersion','teaching_course_create_self_v1','state','ready','alreadyExists',false,
    'courseId',v_created.id,'ledgerId',v_created.ledger_id,'courseState',v_created.status,'capabilityActivationId',v_created.capability_activation_id);
end;
$function$;

create or replace function atlas.guard_teaching_course_identity_update_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  if old.ledger_id is distinct from new.ledger_id
     or old.capability_activation_id is distinct from new.capability_activation_id
     or old.course_key is distinct from new.course_key
     or old.created_by_person_id is distinct from new.created_by_person_id
     or old.created_by_principal_id is distinct from new.created_by_principal_id
     or old.created_at is distinct from new.created_at then
    raise exception 'Teaching Course identity/custody fields are immutable.' using errcode='55000';
  end if;
  if old.status='retired' and new.status<>'retired' then
    raise exception 'Retired Teaching Course is terminal.' using errcode='55000';
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_teaching_course_identity_update_v1() from public,anon,authenticated;
create trigger teaching_courses_identity_immutable_v1 before update on atlas.teaching_courses
for each row execute function atlas.guard_teaching_course_identity_update_v1();

create or replace function atlas.guard_teaching_course_offering_update_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_course atlas.teaching_courses%rowtype;
begin
  if old.ledger_id is distinct from new.ledger_id
     or old.course_id is distinct from new.course_id
     or old.course_version_id is distinct from new.course_version_id
     or old.created_by_person_id is distinct from new.created_by_person_id
     or old.created_by_principal_id is distinct from new.created_by_principal_id
     or old.created_at is distinct from new.created_at then
    raise exception 'Teaching Course Offering identity/version custody is immutable.' using errcode='55000';
  end if;
  if old.state='retired' and new.state<>'retired' then
    raise exception 'Retired Teaching Course Offering is terminal.' using errcode='55000';
  end if;
  if old.state<>new.state and not (
    (old.state='draft' and new.state in ('open','retired')) or
    (old.state='open' and new.state in ('closed','retired')) or
    (old.state='closed' and new.state='retired')
  ) then
    raise exception 'Illegal Teaching Course Offering state transition.' using errcode='23514';
  end if;
  if old.state<>new.state and new.state='open' then
    select * into v_course from atlas.teaching_courses where id=new.course_id;
    if v_course.id is null or v_course.status<>'active' or not atlas.teaching_activation_active_v1(new.ledger_id,v_course.capability_activation_id) then
      raise exception 'Active Course and active Teaching capability required to open Offering.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_teaching_course_offering_update_v1() from public,anon,authenticated;
create trigger teaching_course_offerings_update_guard_v1 before update on atlas.teaching_course_offerings
for each row execute function atlas.guard_teaching_course_offering_update_v1();

create or replace function atlas.guard_teaching_enrollment_update_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  if old.ledger_id is distinct from new.ledger_id
     or old.offering_id is distinct from new.offering_id
     or old.person_id is distinct from new.person_id
     or old.enrolled_by_person_id is distinct from new.enrolled_by_person_id
     or old.enrolled_by_principal_id is distinct from new.enrolled_by_principal_id
     or old.enrolled_at is distinct from new.enrolled_at
     or old.created_at is distinct from new.created_at then
    raise exception 'Teaching Enrollment identity/custody fields are immutable.' using errcode='55000';
  end if;
  if old.state='withdrawn' then
    if new is distinct from old then
      raise exception 'Withdrawn Teaching Enrollment is terminal and immutable.' using errcode='55000';
    end if;
    return new;
  end if;
  if old.state<>new.state and not (old.state='active' and new.state='withdrawn') then
    raise exception 'Illegal Teaching Enrollment state transition.' using errcode='23514';
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_teaching_enrollment_update_v1() from public,anon,authenticated;
create trigger teaching_enrollments_update_guard_v1 before update on atlas.teaching_enrollments
for each row execute function atlas.guard_teaching_enrollment_update_v1();

commit;
