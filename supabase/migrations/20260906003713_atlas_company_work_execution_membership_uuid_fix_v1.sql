create or replace function atlas.company_work_execution_membership_check_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_farm_id uuid;
  v_count integer:=0;
  v_farm_membership_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return jsonb_build_object('allowed',false,'state','missing_work'); end if;
  if not atlas.organization_membership_eligible_on_date_v1(p_assignee_membership_id,v_work.organization_id,p_service_date) then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_eligible');
  end if;
  select * into v_org_member from atlas.organization_memberships
  where id=p_assignee_membership_id and organization_id=v_work.organization_id;

  select pwo.farm_id into v_farm_id
  from atlas.work_execution_adapters a
  join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id and a.state='active'
  order by a.created_at limit 1;

  if v_farm_id is null then
    return jsonb_build_object(
      'allowed',true,
      'state','no_farm_execution_carrier',
      'organizationMembershipId',p_assignee_membership_id
    );
  end if;

  select count(*)::integer into v_count
  from atlas.farm_memberships fm
  where fm.farm_id=v_farm_id
    and fm.user_id=v_org_member.user_id
    and fm.role='farm_hand'
    and atlas.farm_membership_eligible_on_date_v1(fm.id,v_farm_id,p_service_date);

  if v_count=1 then
    select fm.id into v_farm_membership_id
    from atlas.farm_memberships fm
    where fm.farm_id=v_farm_id
      and fm.user_id=v_org_member.user_id
      and fm.role='farm_hand'
      and atlas.farm_membership_eligible_on_date_v1(fm.id,v_farm_id,p_service_date)
    order by fm.created_at,fm.id
    limit 1;
  end if;

  return jsonb_build_object(
    'allowed',v_count=1,
    'state',case
      when v_count=1 then 'eligible_worker'
      when v_count=0 then 'no_eligible_worker_membership'
      else 'ambiguous_worker_membership'
    end,
    'farmId',v_farm_id,
    'organizationMembershipId',p_assignee_membership_id,
    'farmMembershipId',case when v_count=1 then v_farm_membership_id else null end,
    'matchingWorkerMemberships',v_count,
    'workerRole','farm_hand'
  );
end;
$$;