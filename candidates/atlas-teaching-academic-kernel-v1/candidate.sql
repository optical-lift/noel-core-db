-- Atlas Teaching Academic Kernel v1 candidate.
-- Gate B: Course -> immutable Course Version -> Course Offering -> Enrollment.
-- Candidate source only. Promote to supabase/migrations only with a Supabase-generated migration identity.

begin;

create table atlas.teaching_courses (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  capability_activation_id uuid not null references atlas.capability_activations(id) on delete restrict,
  course_key text not null check (btrim(course_key)<>''),
  name text not null check (btrim(name)<>''),
  status text not null default 'active' check (status in ('active','retired')),
  created_by_person_id uuid not null references atlas.people(id) on delete restrict,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (ledger_id,id),
  check ((status='active' and retired_at is null) or (status='retired' and retired_at is not null))
);
create unique index teaching_courses_ledger_key_uq on atlas.teaching_courses(ledger_id,lower(course_key));
create index teaching_courses_ledger_status_idx on atlas.teaching_courses(ledger_id,status,created_at);
alter table atlas.teaching_courses enable row level security;
revoke all on atlas.teaching_courses from public,anon,authenticated;
create trigger teaching_courses_set_updated_at before update on atlas.teaching_courses
for each row execute function atlas.set_updated_at();
comment on table atlas.teaching_courses is 'Durable academic Course identity inside a Ledger with active Teaching capability. Not a Titus-local object and not a commercial offering.';

create table atlas.teaching_course_versions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references atlas.teaching_courses(id) on delete restrict,
  version_no integer not null check (version_no>0),
  title text not null check (btrim(title)<>''),
  summary text,
  learning_outcomes text[] not null default '{}'::text[],
  published_by_person_id uuid not null references atlas.people(id) on delete restrict,
  published_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (course_id,version_no),
  unique (course_id,id)
);
create index teaching_course_versions_course_idx on atlas.teaching_course_versions(course_id,version_no);
alter table atlas.teaching_course_versions enable row level security;
revoke all on atlas.teaching_course_versions from public,anon,authenticated;
comment on table atlas.teaching_course_versions is 'Immutable published academic definition of a Course. New publication creates a new version; earlier versions never rewrite.';

create table atlas.teaching_course_offerings (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null,
  course_id uuid not null,
  course_version_id uuid not null,
  state text not null default 'draft' check (state in ('draft','open','closed','retired')),
  delivery_mode text not null check (delivery_mode in ('self_paced','cohort','scheduled','live_hybrid')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by_person_id uuid not null references atlas.people(id) on delete restrict,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  opened_at timestamptz,
  closed_at timestamptz,
  retired_at timestamptz,
  foreign key (ledger_id,course_id) references atlas.teaching_courses(ledger_id,id) on delete restrict,
  foreign key (course_id,course_version_id) references atlas.teaching_course_versions(course_id,id) on delete restrict,
  unique (ledger_id,id),
  check (ends_at is null or starts_at is null or ends_at>=starts_at),
  check (
    (state='draft' and opened_at is null and closed_at is null and retired_at is null) or
    (state='open' and opened_at is not null and closed_at is null and retired_at is null) or
    (state='closed' and opened_at is not null and closed_at is not null and retired_at is null) or
    (state='retired' and retired_at is not null)
  )
);
create index teaching_course_offerings_ledger_state_idx on atlas.teaching_course_offerings(ledger_id,state,created_at);
create index teaching_course_offerings_course_idx on atlas.teaching_course_offerings(course_id,course_version_id,state);
alter table atlas.teaching_course_offerings enable row level security;
revoke all on atlas.teaching_course_offerings from public,anon,authenticated;
create trigger teaching_course_offerings_set_updated_at before update on atlas.teaching_course_offerings
for each row execute function atlas.set_updated_at();
comment on table atlas.teaching_course_offerings is 'One actual delivery of one exact immutable Teaching Course Version. Distinct from atlas.commercial_offerings.';

create table atlas.teaching_enrollments (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null,
  offering_id uuid not null,
  person_id uuid not null references atlas.people(id) on delete restrict,
  state text not null default 'active' check (state in ('active','withdrawn')),
  enrolled_by_person_id uuid not null references atlas.people(id) on delete restrict,
  enrolled_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  enrolled_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawal_reason text,
  created_at timestamptz not null default now(),
  foreign key (ledger_id,offering_id) references atlas.teaching_course_offerings(ledger_id,id) on delete restrict,
  check (
    (state='active' and withdrawn_at is null) or
    (state='withdrawn' and withdrawn_at is not null)
  )
);
create unique index teaching_enrollments_one_active_uq on atlas.teaching_enrollments(offering_id,person_id) where state='active';
create index teaching_enrollments_person_idx on atlas.teaching_enrollments(person_id,state,enrolled_at);
create index teaching_enrollments_offering_idx on atlas.teaching_enrollments(offering_id,state,enrolled_at);
alter table atlas.teaching_enrollments enable row level security;
revoke all on atlas.teaching_enrollments from public,anon,authenticated;
comment on table atlas.teaching_enrollments is 'Academic participation relation from an existing Atlas Person to a Teaching Course Offering. Enrollment is not Organization membership, Principal authority, or authentication.';

create or replace function atlas.teaching_activation_active_v1(p_ledger_id uuid,p_capability_activation_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1
    from atlas.capability_activations a
    join atlas.capability_definitions d
      on d.capability_key=a.capability_key and d.capability_version=a.capability_version
    where a.id=p_capability_activation_id
      and a.ledger_id=p_ledger_id
      and a.subject_ledger_id=p_ledger_id
      and a.subject_kind='ledger'
      and a.subject_id=p_ledger_id
      and a.subject_key is null
      and a.subject_path is null
      and a.capability_key='teaching'
      and a.capability_version=1
      and a.state='active'
      and d.status='active'
      and atlas.capability_active_for_subject_v1(p_ledger_id,'teaching',1,p_ledger_id,'ledger',p_ledger_id,null,null)
  );
$function$;
revoke all on function atlas.teaching_activation_active_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.teaching_activation_active_v1(uuid,uuid) to service_role;

create or replace function atlas.guard_teaching_course_activation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_activation atlas.capability_activations%rowtype;
begin
  select * into v_activation from atlas.capability_activations where id=new.capability_activation_id;
  if v_activation.id is null
     or v_activation.ledger_id<>new.ledger_id
     or v_activation.subject_ledger_id<>new.ledger_id
     or v_activation.subject_kind<>'ledger'
     or v_activation.subject_id is distinct from new.ledger_id
     or v_activation.subject_key is not null
     or v_activation.subject_path is not null
     or v_activation.capability_key<>'teaching'
     or v_activation.capability_version<>1 then
    raise exception 'Course must bind to Teaching v1 activation over the same Ledger.' using errcode='23514';
  end if;
  if tg_op='INSERT' and not atlas.teaching_activation_active_v1(new.ledger_id,new.capability_activation_id) then
    raise exception 'Active Teaching v1 capability required to create Course.' using errcode='23514';
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_teaching_course_activation_v1() from public,anon,authenticated;
create trigger teaching_courses_activation_guard_v1 before insert or update on atlas.teaching_courses
for each row execute function atlas.guard_teaching_course_activation_v1();

create or replace function atlas.reject_teaching_course_version_mutation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  raise exception 'Published Teaching Course Versions are immutable.' using errcode='55000';
end;
$function$;
revoke all on function atlas.reject_teaching_course_version_mutation_v1() from public,anon,authenticated;
create trigger teaching_course_versions_immutable_v1 before update or delete on atlas.teaching_course_versions
for each row execute function atlas.reject_teaching_course_version_mutation_v1();

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
  order by a.activated_at nulls last,a.created_at,a.id limit 1;
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
revoke all on function atlas.create_teaching_course_self_api_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.create_teaching_course_self_api_v1(uuid,text,text) to authenticated;

create or replace function atlas.retire_teaching_course_self_api_v1(p_course_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_course atlas.teaching_courses%rowtype; v_person uuid; v_principal uuid; v_authority uuid;
begin
  select * into v_course from atlas.teaching_courses where id=p_course_id for update;
  if v_course.id is null then raise exception 'Course not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_course.ledger_id) c;
  if v_course.status='retired' then
    return jsonb_build_object('contractVersion','teaching_course_retire_self_v1','state','ready','alreadyRetired',true,'courseId',v_course.id);
  end if;
  if exists(select 1 from atlas.teaching_course_offerings o where o.course_id=v_course.id and o.state='open') then
    raise exception 'Close or retire open Course Offerings before retiring Course.' using errcode='23514';
  end if;
  update atlas.teaching_courses set status='retired',retired_at=now() where id=v_course.id;
  return jsonb_build_object('contractVersion','teaching_course_retire_self_v1','state','ready','alreadyRetired',false,'courseId',v_course.id,'courseState','retired');
end;
$function$;
revoke all on function atlas.retire_teaching_course_self_api_v1(uuid,text) from public,anon,authenticated;
grant execute on function atlas.retire_teaching_course_self_api_v1(uuid,text) to authenticated;

create or replace function atlas.publish_teaching_course_version_self_api_v1(
  p_course_id uuid,p_title text,p_summary text default null,p_learning_outcomes text[] default '{}'::text[]
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_course atlas.teaching_courses%rowtype; v_person uuid; v_principal uuid; v_authority uuid; v_no integer; v_created atlas.teaching_course_versions%rowtype;
  v_title text:=btrim(coalesce(p_title,'')); v_outcomes text[]:=coalesce(p_learning_outcomes,'{}'::text[]);
begin
  if v_title='' then raise exception 'Course Version title is required.' using errcode='22023'; end if;
  select * into v_course from atlas.teaching_courses where id=p_course_id for update;
  if v_course.id is null then raise exception 'Course not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_course.ledger_id) c;
  if v_course.status<>'active' or not atlas.teaching_activation_active_v1(v_course.ledger_id,v_course.capability_activation_id) then
    raise exception 'Active Course and active Teaching capability required to publish.' using errcode='23514';
  end if;
  select coalesce(max(version_no),0)+1 into v_no from atlas.teaching_course_versions where course_id=v_course.id;
  insert into atlas.teaching_course_versions(
    course_id,version_no,title,summary,learning_outcomes,published_by_person_id,published_by_principal_id
  ) values (v_course.id,v_no,v_title,nullif(btrim(coalesce(p_summary,'')),''),v_outcomes,v_person,v_principal)
  returning * into v_created;
  return jsonb_build_object('contractVersion','teaching_course_version_publish_self_v1','state','ready','courseVersionId',v_created.id,
    'courseId',v_course.id,'versionNo',v_created.version_no,'publishedAt',v_created.published_at);
end;
$function$;
revoke all on function atlas.publish_teaching_course_version_self_api_v1(uuid,text,text,text[]) from public,anon,authenticated;
grant execute on function atlas.publish_teaching_course_version_self_api_v1(uuid,text,text,text[]) to authenticated;

create or replace function atlas.create_teaching_course_offering_self_api_v1(
  p_course_id uuid,p_course_version_id uuid,p_delivery_mode text,p_starts_at timestamptz default null,p_ends_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_course atlas.teaching_courses%rowtype; v_version atlas.teaching_course_versions%rowtype;
  v_person uuid; v_principal uuid; v_authority uuid; v_mode text:=btrim(coalesce(p_delivery_mode,'')); v_created atlas.teaching_course_offerings%rowtype;
begin
  if v_mode not in ('self_paced','cohort','scheduled','live_hybrid') then raise exception 'Unsupported Teaching delivery mode.' using errcode='22023'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<p_starts_at then raise exception 'Offering end cannot precede start.' using errcode='22023'; end if;
  select * into v_course from atlas.teaching_courses where id=p_course_id;
  if v_course.id is null then raise exception 'Course not found.' using errcode='P0002'; end if;
  select * into v_version from atlas.teaching_course_versions where id=p_course_version_id and course_id=p_course_id;
  if v_version.id is null then raise exception 'Course Version must belong to Course.' using errcode='23514'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_course.ledger_id) c;
  if v_course.status<>'active' or not atlas.teaching_activation_active_v1(v_course.ledger_id,v_course.capability_activation_id) then
    raise exception 'Active Course and active Teaching capability required to create Offering.' using errcode='23514';
  end if;
  insert into atlas.teaching_course_offerings(
    ledger_id,course_id,course_version_id,state,delivery_mode,starts_at,ends_at,created_by_person_id,created_by_principal_id
  ) values (v_course.ledger_id,v_course.id,v_version.id,'draft',v_mode,p_starts_at,p_ends_at,v_person,v_principal)
  returning * into v_created;
  return jsonb_build_object('contractVersion','teaching_course_offering_create_self_v1','state','ready','offeringId',v_created.id,
    'ledgerId',v_created.ledger_id,'courseId',v_created.course_id,'courseVersionId',v_created.course_version_id,'offeringState',v_created.state);
end;
$function$;
revoke all on function atlas.create_teaching_course_offering_self_api_v1(uuid,uuid,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function atlas.create_teaching_course_offering_self_api_v1(uuid,uuid,text,timestamptz,timestamptz) to authenticated;

create or replace function atlas.transition_teaching_course_offering_self_api_v1(p_offering_id uuid,p_to_state text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_offering atlas.teaching_course_offerings%rowtype; v_course atlas.teaching_courses%rowtype;
  v_person uuid; v_principal uuid; v_authority uuid; v_target text:=btrim(coalesce(p_to_state,''));
begin
  select * into v_offering from atlas.teaching_course_offerings where id=p_offering_id for update;
  if v_offering.id is null then raise exception 'Course Offering not found.' using errcode='P0002'; end if;
  select * into v_course from atlas.teaching_courses where id=v_offering.course_id;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_offering.ledger_id) c;
  if v_target=v_offering.state then
    return jsonb_build_object('contractVersion','teaching_course_offering_transition_self_v1','state','ready','alreadyInState',true,'offeringId',v_offering.id,'offeringState',v_offering.state);
  end if;
  if v_offering.state='retired' then raise exception 'Retired Course Offering is terminal.' using errcode='23514'; end if;
  if not (
    (v_offering.state='draft' and v_target in ('open','retired')) or
    (v_offering.state='open' and v_target in ('closed','retired')) or
    (v_offering.state='closed' and v_target='retired')
  ) then raise exception 'Illegal Course Offering transition.' using errcode='23514'; end if;
  if v_target='open' and (v_course.status<>'active' or not atlas.teaching_activation_active_v1(v_offering.ledger_id,v_course.capability_activation_id)) then
    raise exception 'Active Course and active Teaching capability required to open Offering.' using errcode='23514';
  end if;
  update atlas.teaching_course_offerings set
    state=v_target,
    opened_at=case when v_target='open' then coalesce(opened_at,now()) else opened_at end,
    closed_at=case when v_target='closed' then now() else closed_at end,
    retired_at=case when v_target='retired' then now() else retired_at end
  where id=v_offering.id;
  return jsonb_build_object('contractVersion','teaching_course_offering_transition_self_v1','state','ready','alreadyInState',false,
    'offeringId',v_offering.id,'fromState',v_offering.state,'offeringState',v_target);
end;
$function$;
revoke all on function atlas.transition_teaching_course_offering_self_api_v1(uuid,text) from public,anon,authenticated;
grant execute on function atlas.transition_teaching_course_offering_self_api_v1(uuid,text) to authenticated;

create or replace function atlas.enroll_person_in_teaching_offering_self_api_v1(p_offering_id uuid,p_person_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_offering atlas.teaching_course_offerings%rowtype; v_course atlas.teaching_courses%rowtype;
  v_person uuid; v_principal uuid; v_authority uuid; v_existing atlas.teaching_enrollments%rowtype; v_created atlas.teaching_enrollments%rowtype;
begin
  select * into v_offering from atlas.teaching_course_offerings where id=p_offering_id for update;
  if v_offering.id is null then raise exception 'Course Offering not found.' using errcode='P0002'; end if;
  select * into v_course from atlas.teaching_courses where id=v_offering.course_id;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_offering.ledger_id) c;
  if v_offering.state<>'open' or v_course.status<>'active' or not atlas.teaching_activation_active_v1(v_offering.ledger_id,v_course.capability_activation_id) then
    raise exception 'Open Offering under active Teaching required for new Enrollment.' using errcode='23514';
  end if;
  if not exists(select 1 from atlas.people p where p.id=p_person_id and p.status='active') then raise exception 'Active canonical Person required.' using errcode='23514'; end if;
  select * into v_existing from atlas.teaching_enrollments e where e.offering_id=p_offering_id and e.person_id=p_person_id and e.state='active' limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('contractVersion','teaching_enrollment_create_self_v1','state','ready','alreadyEnrolled',true,
      'enrollmentId',v_existing.id,'offeringId',v_existing.offering_id,'personId',v_existing.person_id,'enrollmentState',v_existing.state);
  end if;
  insert into atlas.teaching_enrollments(
    ledger_id,offering_id,person_id,state,enrolled_by_person_id,enrolled_by_principal_id
  ) values (v_offering.ledger_id,v_offering.id,p_person_id,'active',v_person,v_principal)
  returning * into v_created;
  return jsonb_build_object('contractVersion','teaching_enrollment_create_self_v1','state','ready','alreadyEnrolled',false,
    'enrollmentId',v_created.id,'offeringId',v_created.offering_id,'personId',v_created.person_id,'enrollmentState',v_created.state);
end;
$function$;
revoke all on function atlas.enroll_person_in_teaching_offering_self_api_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.enroll_person_in_teaching_offering_self_api_v1(uuid,uuid) to authenticated;

create or replace function atlas.withdraw_teaching_enrollment_self_api_v1(p_enrollment_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_enrollment atlas.teaching_enrollments%rowtype; v_person uuid; v_principal uuid; v_authority uuid;
begin
  select * into v_enrollment from atlas.teaching_enrollments where id=p_enrollment_id for update;
  if v_enrollment.id is null then raise exception 'Teaching Enrollment not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_enrollment.ledger_id) c;
  if v_enrollment.state='withdrawn' then
    return jsonb_build_object('contractVersion','teaching_enrollment_withdraw_self_v1','state','ready','alreadyWithdrawn',true,'enrollmentId',v_enrollment.id);
  end if;
  update atlas.teaching_enrollments set state='withdrawn',withdrawn_at=now(),withdrawal_reason=nullif(btrim(coalesce(p_reason,'')),'') where id=v_enrollment.id;
  return jsonb_build_object('contractVersion','teaching_enrollment_withdraw_self_v1','state','ready','alreadyWithdrawn',false,'enrollmentId',v_enrollment.id,'enrollmentState','withdrawn');
end;
$function$;
revoke all on function atlas.withdraw_teaching_enrollment_self_api_v1(uuid,text) from public,anon,authenticated;
grant execute on function atlas.withdraw_teaching_enrollment_self_api_v1(uuid,text) to authenticated;

create or replace function atlas.teaching_courses_admin_self_api_v1(p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_person uuid; v_principal uuid; v_authority uuid; v_items jsonb;
begin
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  select coalesce(jsonb_agg(jsonb_build_object(
    'courseId',t.id,'ledgerId',t.ledger_id,'courseKey',t.course_key,'name',t.name,'courseState',t.status,
    'capabilityActivationId',t.capability_activation_id,'createdAt',t.created_at,'retiredAt',t.retired_at
  ) order by t.created_at,t.id),'[]'::jsonb) into v_items
  from atlas.teaching_courses t where t.ledger_id=p_ledger_id;
  return jsonb_build_object('contractVersion','teaching_courses_admin_self_v1','state','ready','ledgerId',p_ledger_id,'items',v_items);
end;
$function$;
revoke all on function atlas.teaching_courses_admin_self_api_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.teaching_courses_admin_self_api_v1(uuid) to authenticated;

create or replace function atlas.teaching_offering_roster_admin_self_api_v1(p_offering_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_offering atlas.teaching_course_offerings%rowtype; v_person uuid; v_principal uuid; v_authority uuid; v_items jsonb;
begin
  select * into v_offering from atlas.teaching_course_offerings where id=p_offering_id;
  if v_offering.id is null then raise exception 'Course Offering not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_offering.ledger_id) c;
  select coalesce(jsonb_agg(jsonb_build_object(
    'enrollmentId',e.id,'personId',e.person_id,'enrollmentState',e.state,'enrolledAt',e.enrolled_at,'withdrawnAt',e.withdrawn_at
  ) order by e.enrolled_at,e.id),'[]'::jsonb) into v_items
  from atlas.teaching_enrollments e where e.offering_id=p_offering_id;
  return jsonb_build_object('contractVersion','teaching_offering_roster_admin_self_v1','state','ready','offeringId',p_offering_id,'items',v_items);
end;
$function$;
revoke all on function atlas.teaching_offering_roster_admin_self_api_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.teaching_offering_roster_admin_self_api_v1(uuid) to authenticated;

create or replace function atlas.teaching_enrollments_for_current_person_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_person uuid; v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person:=atlas.current_person_id_v1();
  if v_person is null then raise exception 'Canonical Person required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'enrollmentId',e.id,'ledgerId',e.ledger_id,'enrollmentState',e.state,'enrolledAt',e.enrolled_at,'withdrawnAt',e.withdrawn_at,
    'offeringId',o.id,'offeringState',o.state,'deliveryMode',o.delivery_mode,'courseId',c.id,'courseKey',c.course_key,'courseName',c.name,
    'courseVersionId',v.id,'versionNo',v.version_no,'title',v.title,'summary',v.summary,'learningOutcomes',to_jsonb(v.learning_outcomes)
  ) order by e.enrolled_at,e.id),'[]'::jsonb) into v_items
  from atlas.teaching_enrollments e
  join atlas.teaching_course_offerings o on o.id=e.offering_id and o.ledger_id=e.ledger_id
  join atlas.teaching_courses c on c.id=o.course_id and c.ledger_id=o.ledger_id
  join atlas.teaching_course_versions v on v.id=o.course_version_id and v.course_id=o.course_id
  where e.person_id=v_person;
  return jsonb_build_object('contractVersion','teaching_enrollments_current_person_v1','state','ready','personId',v_person,'items',v_items);
end;
$function$;
revoke all on function atlas.teaching_enrollments_for_current_person_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.teaching_enrollments_for_current_person_self_api_v1() to authenticated;

commit;
