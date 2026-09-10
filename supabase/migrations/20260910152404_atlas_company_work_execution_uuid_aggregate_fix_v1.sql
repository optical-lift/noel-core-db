begin;

-- PostgreSQL has no built-in min(uuid) aggregate. The execution eligibility
-- check only needs the matching farm membership id when exactly one match
-- exists, so aggregate its text representation and cast that single value
-- back to uuid.
create or replace function atlas.company_work_execution_membership_check_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_seat atlas.organization_employee_seats%rowtype;
  v_farm_id uuid;
  v_count integer:=0;
  v_farm_membership_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return jsonb_build_object('allowed',false,'state','missing_work'); end if;

  if not atlas.organization_membership_eligible_on_date_v1(p_assignee_membership_id,v_work.organization_id,p_service_date) then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_eligible');
  end if;

  select * into v_org_member
  from atlas.organization_memberships
  where id=p_assignee_membership_id and organization_id=v_work.organization_id;

  if v_org_member.id is null then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_found');
  end if;

  if v_org_member.role='member' then
    select * into v_seat
    from atlas.organization_employee_seats s
    where s.organization_id=v_work.organization_id
      and s.organization_membership_id=v_org_member.id
      and s.identity_subject_id=v_org_member.identity_subject_id
      and s.seat_class='employee'
      and s.status='active'
      and s.billing_state in ('active','waived')
    limit 1;

    if v_seat.id is null then
      return jsonb_build_object(
        'allowed',false,
        'state','active_employee_seat_required',
        'organizationMembershipId',v_org_member.id
      );
    end if;

    if not exists (
      select 1
      from atlas.organization_member_credentials c
      where c.organization_id=v_work.organization_id
        and c.organization_membership_id=v_org_member.id
        and c.employee_seat_id=v_seat.id
        and c.identity_subject_id=v_org_member.identity_subject_id
        and c.status='active'
        and (c.expires_at is null or c.expires_at>now())
    ) then
      return jsonb_build_object(
        'allowed',false,
        'state','active_employee_credential_required',
        'organizationMembershipId',v_org_member.id,
        'employeeSeatId',v_seat.id
      );
    end if;
  end if;

  select pwo.farm_id into v_farm_id
  from atlas.work_execution_adapters a
  join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id and a.state='active'
  order by a.created_at limit 1;

  if v_farm_id is null then
    return jsonb_strip_nulls(jsonb_build_object(
      'allowed',true,
      'state','no_farm_execution_carrier',
      'organizationMembershipId',p_assignee_membership_id,
      'employeeSeatId',v_seat.id
    ));
  end if;

  select count(*),min(fm.id::text)::uuid into v_count,v_farm_membership_id
  from atlas.farm_memberships fm
  where fm.farm_id=v_farm_id
    and fm.user_id=v_org_member.user_id
    and fm.role='farm_hand'
    and atlas.farm_membership_eligible_on_date_v1(fm.id,v_farm_id,p_service_date);

  return jsonb_strip_nulls(jsonb_build_object(
    'allowed',v_count=1,
    'state',case
      when v_count=1 then 'eligible_worker'
      when v_count=0 then 'no_eligible_worker_membership'
      else 'ambiguous_worker_membership'
    end,
    'farmId',v_farm_id,
    'organizationMembershipId',p_assignee_membership_id,
    'employeeSeatId',v_seat.id,
    'farmMembershipId',case when v_count=1 then v_farm_membership_id else null end,
    'matchingWorkerMemberships',v_count,
    'workerRole','farm_hand'
  ));
end;
$function$;

commit;