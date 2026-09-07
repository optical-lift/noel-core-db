-- Atlas Company Work Ledger v1
-- Candidate executable SQL for review and migration generation.
-- This file is intentionally kept under architecture/ until promoted through
-- the noel-core-db migration custody workflow.

begin;

create or replace view atlas.company_work_ledger_v1
with (security_invoker = true)
as
select
  p.organization_id,
  o.name as organization_name,
  p.organization_unit_id,
  p.organization_unit_key,
  p.organization_unit_name,
  p.organization_unit_kind,

  p.work_item_id,
  p.title,
  p.instructions,
  p.work_state,
  p.operation_class,
  p.jurisdiction_key,
  p.source_object_type,
  p.source_object_id,

  p.responsible_allocation_id,
  p.assignee_membership_id,
  om.user_id as assignee_user_id,
  up.display_name as assignee_display_name,
  om.active as assignee_membership_active,
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
  p.management_position,

  plan.id as execution_plan_id,
  plan.plan_state as execution_plan_state,
  plan.first_planned_service_date,
  plan.planned_service_date,
  plan.exposure_service_date,
  plan.rollover_count,
  plan.plan_reason,

  (p.work_state = 'open') as is_open,
  (p.responsible_allocation_id is not null) as is_assigned,
  (p.responsible_allocation_id is null) as is_unassigned,
  (plan.id is not null) as is_planned,
  (plan.id is null and p.work_state = 'open') as is_unscheduled,
  (p.unresolved_dependency_count > 0) as is_waiting_dependency,
  (p.open_planning_conflict_id is not null) as has_planning_conflict,
  (
    p.work_state = 'open'
    and p.latest_lawful_at is not null
    and p.latest_lawful_at < now()
  ) as is_overdue,
  (
    p.work_state = 'open'
    and p.hard_finish_at is not null
    and p.hard_finish_at < now()
  ) as is_hard_finish_missed,

  p.created_at,
  p.updated_at
from atlas.company_work_position_v2 p
join atlas.organizations o
  on o.id = p.organization_id
left join atlas.organization_memberships om
  on om.id = p.assignee_membership_id
 and om.organization_id = p.organization_id
left join atlas.user_profiles up
  on up.user_id = om.user_id
left join lateral (
  select ep.*
  from atlas.work_execution_plans ep
  where ep.organization_id = p.organization_id
    and ep.work_item_id = p.work_item_id
    and ep.plan_state not in ('completed', 'cancelled', 'superseded')
  order by ep.updated_at desc, ep.id desc
  limit 1
) plan on true;

comment on view atlas.company_work_ledger_v1 is
  'Canonical organization-level Company Work Ledger read surface. One row per canonical work_item. Assignment, time, dependency, planning conflict, and active execution-plan state are overlays; Worker Day/Week delivery does not determine existence.';

-- Legacy canonicalization audit. This does not make legacy tasks authoritative;
-- it identifies which legacy carriers have or lack a canonical work adapter.
create or replace view atlas.legacy_company_work_canonicalization_audit_v1
with (security_invoker = true)
as
select
  t.id as legacy_task_id,
  t.organization_id,
  t.farm_id,
  t.title as legacy_title,
  t.status as legacy_status,
  t.task_type,
  t.action_key,
  t.work_class,
  t.operation_class,
  t.due_date as legacy_due_date,
  t.assigned_user_id as legacy_assigned_user_id,
  t.assigned_membership_id as legacy_assigned_farm_membership_id,
  t.visibility_scope,
  t.created_at as legacy_created_at,
  t.updated_at as legacy_updated_at,

  a.id as execution_adapter_id,
  a.work_item_id,
  a.state as adapter_state,
  a.adapter_kind,
  wi.work_state as canonical_work_state,

  case
    when a.id is not null and a.state <> 'retired' then 'already_mapped'
    when t.status in ('done', 'archived', 'skipped') then 'historical_terminal'
    when t.assigned_user_id is not null
      and not exists (
        select 1
        from atlas.organization_memberships om
        where om.organization_id = t.organization_id
          and om.user_id = t.assigned_user_id
          and om.active = true
      ) then 'identity_review'
    when t.due_date is not null then 'time_semantics_review'
    else 'source_review'
  end as audit_disposition
from atlas.tasks t
left join lateral (
  select wea.*
  from atlas.work_execution_adapters wea
  where wea.task_id = t.id
  order by
    case when wea.state <> 'retired' then 0 else 1 end,
    wea.updated_at desc,
    wea.id desc
  limit 1
) a on true
left join atlas.work_items wi
  on wi.organization_id = a.organization_id
 and wi.id = a.work_item_id;

comment on view atlas.legacy_company_work_canonicalization_audit_v1 is
  'Audit-only compatibility surface for classifying legacy tasks before canonical Company Work cutover. It is not a Company Work read authority and must not be consumed by the finished Employee Ledger.';

commit;
