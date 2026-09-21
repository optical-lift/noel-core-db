begin;

do $validation$
declare
  v_org uuid:=gen_random_uuid();
  v_org_other uuid:=gen_random_uuid();
  v_person uuid:=gen_random_uuid();
  v_person_other uuid:=gen_random_uuid();
  v_record uuid;
  v_record_other uuid;
  v_unit uuid:=gen_random_uuid();
  v_position uuid:=gen_random_uuid();
  v_appointment uuid;
  v_seat uuid;
  v_user uuid:=gen_random_uuid();
  v_membership uuid;
  v_membership_person uuid;
  v_membership_record uuid;
begin
  if to_regclass('atlas.institutional_person_records') is null then
    raise exception 'Institutional Person Record table is missing.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_position_appointments'
      and column_name='institutional_person_record_id' and is_nullable='NO'
  ) then
    raise exception 'Position Appointment is not canonically bound to Institutional Person Record.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_employee_seats'
      and column_name='institutional_person_record_id' and is_nullable='NO'
  ) then
    raise exception 'Employee seat is not canonically bound to Institutional Person Record.';
  end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_position_appointments'
      and column_name='organization_membership_id' and is_nullable='NO'
  ) then
    raise exception 'Position Appointment still requires authenticated Organization Membership.';
  end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='organization_employee_seats'
      and column_name='organization_membership_id' and is_nullable='NO'
  ) then
    raise exception 'Employee seat still requires authenticated Organization Membership.';
  end if;

  if exists(
    select 1
    from atlas.organization_memberships m
    where m.person_id is not null
      and m.institutional_person_record_id is null
  ) then
    raise exception 'Existing Organization Membership with canonical Person was not bridged.';
  end if;

  if exists(
    select 1
    from atlas.organization_position_appointments a
    where a.organization_membership_id is not null
      and a.institutional_person_record_id is null
  ) then
    raise exception 'Existing Position Appointment was not bridged.';
  end if;

  if exists(
    select 1
    from atlas.organization_employee_seats s
    where s.organization_membership_id is not null
      and s.institutional_person_record_id is null
  ) then
    raise exception 'Existing employee seat was not bridged.';
  end if;

  if exists(
    select 1
    from atlas.work_allocations wa
    where wa.assignee_membership_id is not null
      and wa.assignee_institutional_person_record_id is null
  ) then
    raise exception 'Existing Work responsibility lacks Institutional Person bridge.';
  end if;

  if has_table_privilege('anon','atlas.institutional_person_records','SELECT')
     or has_table_privilege('authenticated','atlas.institutional_person_records','SELECT')
     or has_table_privilege('anon','atlas.institutional_person_records','INSERT')
     or has_table_privilege('authenticated','atlas.institutional_person_records','INSERT') then
    raise exception 'Institutional Person Record widened direct browser table authority.';
  end if;

  insert into atlas.organizations(id,stable_key,name)
  values
    (v_org,'ipr-proof-'||substr(v_org::text,1,8),'Institutional Person Proof'),
    (v_org_other,'ipr-proof-'||substr(v_org_other::text,1,8),'Institutional Person Other Proof');

  insert into atlas.people(id,display_name,status,metadata)
  values
    (v_person,'Accountless Worker','active','{"proof":"institutional_person_record_v1"}'::jsonb),
    (v_person_other,'Other Accountless Worker','active','{"proof":"institutional_person_record_v1"}'::jsonb);

  insert into atlas.institutional_person_records(
    organization_id,person_id,status,establishment_basis
  ) values(
    v_org,v_person,'active',
    '{"contractVersion":"institutional_person_record_v1","basisKind":"validation_accountless_human"}'::jsonb
  ) returning id into v_record;

  insert into atlas.institutional_person_records(
    organization_id,person_id,status,establishment_basis
  ) values(
    v_org_other,v_person_other,'active',
    '{"contractVersion":"institutional_person_record_v1","basisKind":"validation_other_human"}'::jsonb
  ) returning id into v_record_other;

  if exists(
    select 1 from atlas.person_auth_credentials c
    where c.person_id=v_person and c.status='active'
  ) then
    raise exception 'Accountless Institutional Person unexpectedly acquired an auth credential.';
  end if;

  if exists(
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_org and m.person_id=v_person
  ) then
    raise exception 'Accountless Institutional Person unexpectedly acquired Organization Membership.';
  end if;

  insert into atlas.organization_units(
    id,organization_id,stable_key,name,unit_kind,status,metadata
  ) values(
    v_unit,v_org,'proof_unit','Proof Unit','operating_unit','active','{}'::jsonb
  );

  insert into atlas.organization_positions(
    id,organization_id,organization_unit_id,stable_key,display_title,position_kind,status,metadata
  ) values(
    v_position,v_org,v_unit,'proof_worker','Proof Worker','staff','active','{}'::jsonb
  );

  insert into atlas.organization_position_appointments(
    organization_id,position_id,institutional_person_record_id,
    organization_membership_id,identity_subject_id,
    appointment_kind,status,begins_at,metadata
  ) values(
    v_org,v_position,v_record,
    null,null,
    'primary','active',now(),
    '{"proof":"accountless_position_appointment"}'::jsonb
  ) returning id into v_appointment;

  if not exists(
    select 1 from atlas.organization_position_appointments a
    where a.id=v_appointment
      and a.institutional_person_record_id=v_record
      and a.organization_membership_id is null
      and a.identity_subject_id is null
  ) then
    raise exception 'Accountless Position Appointment was not preserved.';
  end if;

  insert into atlas.organization_employee_seats(
    organization_id,institutional_person_record_id,
    organization_membership_id,identity_subject_id,
    seat_class,status,billing_state,billing_unit_price_cents,metadata
  ) values(
    v_org,v_record,
    null,null,
    'employee','active','active',700,
    '{"proof":"accountless_employee_seat"}'::jsonb
  ) returning id into v_seat;

  if not exists(
    select 1 from atlas.organization_employee_seats s
    where s.id=v_seat
      and s.institutional_person_record_id=v_record
      and s.organization_membership_id is null
      and s.identity_subject_id is null
      and s.billing_unit_price_cents=700
  ) then
    raise exception 'Accountless $7 employee seat was not established independently of login.';
  end if;

  -- A record from another Organization cannot be used as local appointment identity.
  begin
    insert into atlas.organization_position_appointments(
      organization_id,position_id,institutional_person_record_id,
      appointment_kind,status,begins_at,metadata
    ) values(
      v_org,v_position,v_record_other,
      'primary','active',now(),
      '{"proof":"cross_org_invalid"}'::jsonb
    );
    raise exception 'Cross-Organization Institutional Person appointment unexpectedly succeeded.';
  exception when foreign_key_violation or check_violation then
    null;
  end;

  -- Existing login-backed membership creation still creates/bridges a canonical
  -- Person, then bridges that Person to one Institutional Person Record.
  insert into auth.users(id,email,created_at,updated_at)
  values(
    v_user,
    'ipr-proof-'||substr(v_user::text,1,8)||'@example.test',
    now(),now()
  );

  insert into atlas.organization_memberships(
    organization_id,user_id,role,active
  ) values(
    v_org,v_user,'member',true
  ) returning id,person_id into v_membership,v_membership_person;

  select institutional_person_record_id
  into v_membership_record
  from atlas.organization_memberships
  where id=v_membership;

  if v_membership_person is null or v_membership_record is null then
    raise exception 'Authenticated Organization Membership did not bridge through Person to Institutional Person Record.';
  end if;

  if not exists(
    select 1 from atlas.institutional_person_records ipr
    where ipr.id=v_membership_record
      and ipr.organization_id=v_org
      and ipr.person_id=v_membership_person
      and ipr.status='active'
  ) then
    raise exception 'Organization Membership bridge resolved to the wrong institutional human.';
  end if;

  -- A seat cannot combine one Institutional Person with another Membership.
  begin
    update atlas.organization_employee_seats
    set organization_membership_id=v_membership
    where id=v_seat;
    raise exception 'Employee seat accepted a Membership belonging to another institutional human.';
  exception when check_violation then
    null;
  end;

  if not exists(
    select 1
    from atlas.architecture_truth_authorities
    where authority_key='institutional_person_record'
      and authority_status='canonical'
      and authority_owner='atlas.institutional_person_records'
  ) then
    raise exception 'Institutional Person Record truth authority registration is missing.';
  end if;
end;
$validation$;

rollback;
