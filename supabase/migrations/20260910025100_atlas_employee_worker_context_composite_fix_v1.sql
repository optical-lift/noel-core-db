begin;

-- Keep replayed schema aligned with the production Gate 2 function. Resolve
-- appointment and position as separate composite rows rather than relying on
-- expansion of two table records into two PL/pgSQL targets.
create or replace function atlas.organization_employee_worker_context_self_v1(
  p_farm_id uuid,
  p_delivery_membership_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_farm atlas.farms%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_seat atlas.organization_employee_seats%rowtype;
  v_position atlas.organization_positions%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
  v_timezone text:='America/Chicago';
  v_today date;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','authentication_required'); end if;
  if p_farm_id is null or p_delivery_membership_id is null then return jsonb_build_object('ok',false,'reason','worker_context_required'); end if;

  select * into v_farm from atlas.farms f where f.id=p_farm_id;
  if v_farm.id is null or v_farm.organization_id is null or v_farm.organization_unit_id is null then
    return jsonb_build_object('ok',false,'reason','institutional_farm_context_required');
  end if;

  v_timezone:=coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='America/Chicago'; end if;
  v_today:=(now() at time zone v_timezone)::date;

  select * into v_farm_member
  from atlas.farm_memberships fm
  where fm.id=p_delivery_membership_id and fm.farm_id=p_farm_id and fm.user_id=v_uid
    and fm.active=true and fm.role='farm_hand' and fm.identity_subject_id is not null;
  if v_farm_member.id is null then return jsonb_build_object('ok',false,'reason','active_worker_membership_required'); end if;
  if not atlas.farm_membership_eligible_on_date_v1(v_farm_member.id,p_farm_id,v_today) then
    return jsonb_build_object('ok',false,'reason','worker_membership_not_eligible');
  end if;

  select * into v_org_member
  from atlas.organization_memberships m
  where m.organization_id=v_farm.organization_id and m.user_id=v_uid
    and m.identity_subject_id=v_farm_member.identity_subject_id and m.active=true and m.role='member'
  order by m.created_at limit 1;
  if v_org_member.id is null then return jsonb_build_object('ok',false,'reason','employee_organization_membership_required'); end if;
  if not atlas.organization_membership_eligible_on_date_v1(v_org_member.id,v_farm.organization_id,v_today) then
    return jsonb_build_object('ok',false,'reason','employee_organization_membership_not_eligible');
  end if;

  select * into v_seat
  from atlas.organization_employee_seats s
  where s.organization_id=v_farm.organization_id and s.organization_membership_id=v_org_member.id
    and s.identity_subject_id=v_org_member.identity_subject_id and s.seat_class='employee'
    and s.status='active' and s.billing_state in ('active','waived') limit 1;
  if v_seat.id is null then return jsonb_build_object('ok',false,'reason','active_employee_seat_required'); end if;

  if not exists(
    select 1 from atlas.organization_member_credentials c
    where c.organization_id=v_farm.organization_id and c.organization_membership_id=v_org_member.id
      and c.employee_seat_id=v_seat.id and c.identity_subject_id=v_org_member.identity_subject_id
      and c.credential_kind='auth_user' and c.auth_user_id=v_uid and c.status='active'
      and (c.expires_at is null or c.expires_at>now())
  ) then return jsonb_build_object('ok',false,'reason','active_employee_credential_required'); end if;

  select a into v_appointment
  from atlas.organization_position_appointments a
  join atlas.organization_positions p on p.id=a.position_id and p.organization_id=a.organization_id and p.status='active'
  where a.organization_id=v_farm.organization_id and a.organization_membership_id=v_org_member.id
    and a.identity_subject_id=v_org_member.identity_subject_id and a.status='active'
    and a.begins_at<=now() and (a.ends_at is null or a.ends_at>now())
    and p.organization_unit_id=v_farm.organization_unit_id
  order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id limit 1;
  if v_appointment.id is null then return jsonb_build_object('ok',false,'reason','active_worker_appointment_required'); end if;

  select * into v_position from atlas.organization_positions p
  where p.id=v_appointment.position_id and p.organization_id=v_farm.organization_id
    and p.organization_unit_id=v_farm.organization_unit_id and p.status='active';
  if v_position.id is null then return jsonb_build_object('ok',false,'reason','active_worker_position_required'); end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','organization_employee_worker_context_v1',
    'organizationId',v_farm.organization_id,'organizationUnitId',v_farm.organization_unit_id,
    'organizationMembershipId',v_org_member.id,'deliveryMembershipId',v_farm_member.id,
    'identitySubjectId',v_org_member.identity_subject_id,'employeeSeatId',v_seat.id,
    'appointmentId',v_appointment.id,'positionId',v_position.id,'positionKey',v_position.stable_key,
    'positionTitle',v_position.display_title,'serviceDate',v_today
  );
end;
$function$;

commit;
