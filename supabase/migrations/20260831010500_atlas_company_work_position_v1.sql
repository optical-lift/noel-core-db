-- Atlas Company Work Position v1
-- Complete organization-level accounting of canonical work. No portal/person filter and no presentation limit.

begin;

create or replace view atlas.company_work_position_v1
with (security_invoker = true)
as
select
  w.organization_id,
  w.id as work_item_id,
  w.title,
  w.instructions,
  w.work_state,
  w.operation_class,
  w.jurisdiction_key,
  w.source_object_type,
  w.source_object_id,
  w.created_at,
  w.updated_at,

  a.id as responsible_allocation_id,
  a.assignee_membership_id,
  a.allocated_at,

  tc.id as time_contract_id,
  tc.earliest_lawful_at,
  tc.preferred_start_at,
  tc.preferred_end_at,
  tc.latest_lawful_at,
  tc.hard_finish_at,
  tc.expected_duration_minutes,
  tc.movement_policy,

  coalesce(dep.unresolved_dependency_count, 0)::integer as unresolved_dependency_count,
  conflict.id as open_planning_conflict_id,
  conflict.conflict_kind as open_planning_conflict_kind,
  conflict.reason as open_planning_conflict_reason,
  conflict.required_by as conflict_required_by,

  case
    when conflict.id is not null then 'planning_conflict'
    when a.id is null then 'unassigned'
    when coalesce(dep.unresolved_dependency_count, 0) > 0 then 'waiting_dependency'
    else 'allocated'
  end as management_position
from atlas.work_items w
left join atlas.work_allocations a
  on a.organization_id = w.organization_id
 and a.work_item_id = w.id
 and a.state = 'active'
 and a.allocation_role = 'responsible'
left join atlas.work_time_contracts tc
  on tc.organization_id = w.organization_id
 and tc.work_item_id = w.id
 and tc.contract_state = 'active'
left join lateral (
  select count(*) as unresolved_dependency_count
  from atlas.work_item_relations r
  join atlas.work_items prerequisite
    on prerequisite.organization_id = r.organization_id
   and prerequisite.id = r.to_work_item_id
  where r.organization_id = w.organization_id
    and r.from_work_item_id = w.id
    and r.active
    and r.relation_kind = 'depends_on'
    and prerequisite.work_state <> 'completed'
) dep on true
left join lateral (
  select c.*
  from atlas.work_planning_conflicts c
  where c.organization_id = w.organization_id
    and c.work_item_id = w.id
    and c.state = 'open'
  order by c.detected_at desc, c.id desc
  limit 1
) conflict on true;

comment on view atlas.company_work_position_v1 is
  'Complete canonical company-work position. Every Work Item remains represented independent of allocation, dependency wait, time placement, or attention. management_position is an operational summary, not work identity.';

revoke all on atlas.company_work_position_v1 from public, anon, authenticated;
grant select on atlas.company_work_position_v1 to service_role;

create or replace function atlas.company_open_work_accounting_v1(
  p_organization_id uuid
)
returns table (
  total_open bigint,
  unassigned bigint,
  allocated bigint,
  waiting_dependency bigint,
  planning_conflict bigint
)
language sql
stable
security invoker
set search_path = atlas, public
as $$
  select
    count(*) filter (where work_state = 'open') as total_open,
    count(*) filter (where work_state = 'open' and management_position = 'unassigned') as unassigned,
    count(*) filter (where work_state = 'open' and management_position = 'allocated') as allocated,
    count(*) filter (where work_state = 'open' and management_position = 'waiting_dependency') as waiting_dependency,
    count(*) filter (where work_state = 'open' and management_position = 'planning_conflict') as planning_conflict
  from atlas.company_work_position_v1
  where organization_id = p_organization_id;
$$;

comment on function atlas.company_open_work_accounting_v1(uuid) is
  'Counts every open canonical Work Item into exactly one company management position. Presentation limits and person portals do not participate.';

revoke all on function atlas.company_open_work_accounting_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.company_open_work_accounting_v1(uuid) to service_role;

commit;
