-- Atlas Company Work Position API v1
-- Authenticated, organization-scoped read membrane for the new Company Work kernel.
-- Full company work is currently restricted to active organization owners.

begin;

create or replace function atlas.company_work_position_api_v1(
  p_organization_id uuid
)
returns table (
  organization_id uuid,
  work_item_id uuid,
  title text,
  instructions text,
  work_state text,
  operation_class text,
  jurisdiction_key text,
  source_object_type text,
  source_object_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  responsible_allocation_id uuid,
  assignee_membership_id uuid,
  allocated_at timestamptz,
  time_contract_id uuid,
  earliest_lawful_at timestamptz,
  preferred_start_at timestamptz,
  preferred_end_at timestamptz,
  latest_lawful_at timestamptz,
  hard_finish_at timestamptz,
  expected_duration_minutes integer,
  movement_policy text,
  unresolved_dependency_count integer,
  open_planning_conflict_id uuid,
  open_planning_conflict_kind text,
  open_planning_conflict_reason text,
  conflict_required_by timestamptz,
  management_position text
)
language plpgsql
stable
security definer
set search_path = atlas, auth, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from atlas.organization_memberships om
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.active
      and om.role = 'owner'
  ) then
    raise exception 'Active organization-owner access is required.' using errcode = '42501';
  end if;

  return query
  select
    p.organization_id,
    p.work_item_id,
    p.title,
    p.instructions,
    p.work_state,
    p.operation_class,
    p.jurisdiction_key,
    p.source_object_type,
    p.source_object_id,
    p.created_at,
    p.updated_at,
    p.responsible_allocation_id,
    p.assignee_membership_id,
    p.allocated_at,
    p.time_contract_id,
    p.earliest_lawful_at,
    p.preferred_start_at,
    p.preferred_end_at,
    p.latest_lawful_at,
    p.hard_finish_at,
    p.expected_duration_minutes,
    p.movement_policy,
    p.unresolved_dependency_count,
    p.open_planning_conflict_id,
    p.open_planning_conflict_kind,
    p.open_planning_conflict_reason,
    p.conflict_required_by,
    p.management_position
  from atlas.company_work_position_v1 p
  where p.organization_id = p_organization_id
  order by
    case p.management_position
      when 'planning_conflict' then 1
      when 'unassigned' then 2
      when 'waiting_dependency' then 3
      when 'allocated' then 4
      else 5
    end,
    p.hard_finish_at nulls last,
    p.created_at,
    p.work_item_id;
end;
$$;

comment on function atlas.company_work_position_api_v1(uuid) is
  'Authenticated owner-only Company Work reader. Validates active organization ownership, then returns the complete canonical organization work position without legacy task fallback or presentation limits.';

revoke all on function atlas.company_work_position_api_v1(uuid) from public, anon;
grant execute on function atlas.company_work_position_api_v1(uuid) to authenticated, service_role;

commit;
