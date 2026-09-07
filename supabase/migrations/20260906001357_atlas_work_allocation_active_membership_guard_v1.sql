create or replace function atlas.validate_active_work_allocation_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.state='active' then
    if not exists(
      select 1
      from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id
        and om.active
    ) then
      raise exception 'Active Work responsibility requires an active Organization Membership.' using errcode='23514';
    end if;

    if new.assigned_by_membership_id is not null
       and (tg_op='INSERT'
            or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
            or old.state is distinct from new.state
            or old.organization_id is distinct from new.organization_id)
       and not exists(
         select 1
         from atlas.organization_memberships om
         where om.id=new.assigned_by_membership_id
           and om.organization_id=new.organization_id
           and om.active
       ) then
      raise exception 'A new active Work allocation cannot name an inactive assigning membership.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function atlas.validate_active_work_allocation_membership_v1() from public,anon,authenticated;
grant execute on function atlas.validate_active_work_allocation_membership_v1() to postgres,service_role;

drop trigger if exists work_allocations_validate_active_membership_v1 on atlas.work_allocations;
create trigger work_allocations_validate_active_membership_v1
before insert or update of state,assignee_membership_id,assigned_by_membership_id,organization_id
on atlas.work_allocations
for each row execute function atlas.validate_active_work_allocation_membership_v1();

create or replace function atlas.release_work_allocations_for_inactive_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if old.active=true and new.active=false then
    update atlas.work_allocations wa
    set state='released',
        released_at=coalesce(wa.released_at,now()),
        release_reason='assignee_organization_membership_inactive',
        metadata=coalesce(wa.metadata,'{}'::jsonb)||jsonb_build_object(
          'responsibilityReleasedBy','organization_membership_deactivation',
          'inactiveOrganizationMembershipId',new.id,
          'responsibilityReleasedAt',now()
        ),
        updated_at=now()
    where wa.organization_id=new.organization_id
      and wa.assignee_membership_id=new.id
      and wa.state='active';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.release_work_allocations_for_inactive_membership_v1() from public,anon,authenticated;
grant execute on function atlas.release_work_allocations_for_inactive_membership_v1() to postgres,service_role;

drop trigger if exists organization_memberships_release_work_allocations_v1 on atlas.organization_memberships;
create trigger organization_memberships_release_work_allocations_v1
after update of active on atlas.organization_memberships
for each row
when (old.active is distinct from new.active)
execute function atlas.release_work_allocations_for_inactive_membership_v1();

-- Existing rows predate the invariant. They cannot remain active responsibility
-- after the assignee's Organization Membership has become inactive. Releasing
-- Responsibility does not close, complete, cancel, or reassign the underlying Work.
update atlas.work_allocations wa
set state='released',
    released_at=coalesce(wa.released_at,now()),
    release_reason='assignee_organization_membership_inactive',
    metadata=coalesce(wa.metadata,'{}'::jsonb)||jsonb_build_object(
      'responsibilityReleasedBy','active_membership_invariant_backfill_v1',
      'inactiveOrganizationMembershipId',wa.assignee_membership_id,
      'responsibilityReleasedAt',now()
    ),
    updated_at=now()
from atlas.organization_memberships om
where om.id=wa.assignee_membership_id
  and om.organization_id=wa.organization_id
  and wa.state='active'
  and not om.active;

comment on function atlas.validate_active_work_allocation_membership_v1() is
'Company Work Responsibility invariant: an active allocation may name only an active Organization Membership in the same organization. No caller, including service-role integrations, may assign active Work to an inactive employee.';

comment on function atlas.release_work_allocations_for_inactive_membership_v1() is
'When an Organization Membership becomes inactive, release that membership''s active Work allocations. Underlying Company Work remains open unless separately resolved by its source authority.';