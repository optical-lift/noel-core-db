-- Atlas Company Work Ledger read authority v1
-- Canonical organization-level read surface for discoverable Company Work.
-- One row per atlas.work_items.id. No Worker Day/Week or legacy task feed
-- determines whether Company Work exists.

begin;

create or replace view atlas.company_work_ledger_v1
with (security_invoker = true)
as
with positioned as (
  select
    p.*,
    wi.work_definition_id,
    wi.stable_key as work_stable_key,
    wi.completed_at,
    wi.cancelled_at,
    wi.superseded_by_work_item_id,
    o.name as organization_name,
    om.user_id as allocated_user_id,
    om.active as assignee_membership_active,
    case
      when p.open_planning_conflict_kind = 'no_eligible_assignee'
       and pc.metadata->>'assignedUserId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then (pc.metadata->>'assignedUserId')::uuid
      else null::uuid
    end as unresolved_candidate_user_id,
    plan.id as execution_plan_id,
    plan.plan_state as execution_plan_state,
    plan.first_planned_service_date,
    plan.planned_service_date,
    plan.exposure_service_date,
    plan.rollover_count,
    plan.plan_reason
  from atlas.company_work_position_v2 p
  join atlas.work_items wi
    on wi.organization_id = p.organization_id
   and wi.id = p.work_item_id
  join atlas.organizations o
    on o.id = p.organization_id
  left join atlas.organization_memberships om
    on om.id = p.assignee_membership_id
   and om.organization_id = p.organization_id
  left join atlas.work_planning_conflicts pc
    on pc.organization_id = p.organization_id
   and pc.id = p.open_planning_conflict_id
  left join lateral (
    select ep.*
    from atlas.work_execution_plans ep
    where ep.organization_id = p.organization_id
      and ep.work_item_id = p.work_item_id
      and ep.plan_state not in ('completed', 'cancelled', 'superseded')
    order by ep.updated_at desc, ep.id desc
    limit 1
  ) plan on true
), resolved as (
  select
    positioned.*,
    coalesce(allocated_user_id, unresolved_candidate_user_id) as responsibility_user_id,
    case
      when responsible_allocation_id is not null then 'allocated'
      when unresolved_candidate_user_id is not null then 'unresolved_named'
      else 'unassigned'
    end as responsibility_position
  from positioned
)
select
  r.organization_id,
  r.organization_name,
  r.organization_unit_id,
  r.organization_unit_key,
  r.organization_unit_name,
  r.organization_unit_kind,
  r.work_item_id,
  r.work_stable_key,
  r.work_definition_id,
  r.title,
  r.instructions,
  r.work_state,
  r.operation_class,
  r.jurisdiction_key,
  r.source_object_type,
  r.source_object_id,
  r.responsible_allocation_id,
  r.assignee_membership_id,
  r.allocated_user_id as assignee_user_id,
  allocated_profile.display_name as assignee_display_name,
  r.assignee_membership_active,
  r.allocated_at,
  r.responsibility_position,
  r.responsibility_user_id,
  responsibility_profile.display_name as responsibility_display_name,
  (r.responsibility_position = 'unresolved_named') as has_unresolved_responsibility,
  r.time_contract_id,
  r.earliest_lawful_at,
  r.preferred_start_at,
  r.preferred_end_at,
  r.latest_lawful_at,
  r.hard_finish_at,
  r.expected_duration_minutes,
  r.movement_policy,
  r.unresolved_dependency_count,
  r.open_planning_conflict_id,
  r.open_planning_conflict_kind,
  r.open_planning_conflict_reason,
  r.conflict_required_by,
  r.management_position,
  r.execution_plan_id,
  r.execution_plan_state,
  r.first_planned_service_date,
  r.planned_service_date,
  r.exposure_service_date,
  r.rollover_count,
  r.plan_reason,
  (r.work_state = 'open') as is_open,
  (r.responsibility_position = 'allocated') as is_assigned,
  (r.responsibility_position = 'unassigned') as is_unassigned,
  (r.execution_plan_id is not null) as is_planned,
  (r.execution_plan_id is null and r.work_state = 'open') as is_unscheduled,
  (r.unresolved_dependency_count > 0) as is_waiting_dependency,
  (r.open_planning_conflict_id is not null) as has_planning_conflict,
  (
    r.work_state = 'open'
    and r.latest_lawful_at is not null
    and r.latest_lawful_at < now()
  ) as is_overdue,
  (
    r.work_state = 'open'
    and r.hard_finish_at is not null
    and r.hard_finish_at < now()
  ) as is_hard_finish_missed,
  r.completed_at,
  r.cancelled_at,
  r.superseded_by_work_item_id,
  r.created_at,
  r.updated_at
from resolved r
left join atlas.user_profiles allocated_profile
  on allocated_profile.user_id = r.allocated_user_id
left join atlas.user_profiles responsibility_profile
  on responsibility_profile.user_id = r.responsibility_user_id;

comment on view atlas.company_work_ledger_v1 is
  'Canonical organization-level Company Work Ledger read surface. One row per canonical work_item. Responsibility distinguishes allocated, unresolved_named, and unassigned. Assignment, time, dependency, planning conflict, and execution-plan state are overlays; Worker Day/Week delivery does not determine existence.';

create or replace view atlas.legacy_company_work_canonicalization_audit_v1
with (security_invoker = true)
as
with base as (
  select
    t.id as legacy_task_id,
    t.organization_id,
    t.farm_id,
    f.organization_id as farm_organization_id,
    f.organization_unit_id as farm_organization_unit_id,
    t.title as legacy_title,
    t.status as legacy_status,
    t.task_type,
    t.action_key,
    t.work_class,
    t.operation_class,
    t.task_scope,
    t.origin_kind,
    t.visibility_scope,
    t.due_date as legacy_due_date,
    t.assigned_user_id,
    t.assigned_membership_id as assigned_farm_membership_id,
    fm.user_id as farm_membership_user_id,
    coalesce(t.assigned_user_id, fm.user_id) as legacy_responsibility_user_id,
    coalesce(
      t.parent_task_id,
      case
        when t.metadata->>'parent_task_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (t.metadata->>'parent_task_id')::uuid
        else null::uuid
      end
    ) as effective_parent_task_id,
    t.created_at as legacy_created_at,
    t.updated_at as legacy_updated_at,
    a.id as execution_adapter_id,
    a.work_item_id as adapter_work_item_id,
    a.state as adapter_state,
    a.adapter_kind,
    direct_wi.id as direct_work_item_id,
    coalesce(a.work_item_id, direct_wi.id) as resolved_work_item_id
  from atlas.tasks t
  left join atlas.farms f
    on f.id = t.farm_id
  left join atlas.farm_memberships fm
    on fm.id = t.assigned_membership_id
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
  left join atlas.work_items direct_wi
    on direct_wi.organization_id = t.organization_id
   and direct_wi.source_object_type = 'legacy_task'
   and direct_wi.source_object_id = t.id
), enriched as (
  select
    b.*,
    wi.work_state as canonical_work_state,
    wa.id as active_responsible_allocation_id,
    wa.assignee_membership_id as canonical_assignee_membership_id,
    om.user_id as canonical_assignee_user_id,
    wt.id as active_time_contract_id,
    case
      when b.legacy_status in ('done', 'archived', 'skipped')
        then 'historical_company_evidence'
      when b.organization_id is not null
       and b.farm_id is not null
       and b.farm_organization_id = b.organization_id
       and b.farm_organization_unit_id is not null
        then 'current_company_work'
      else 'scope_review'
    end as company_scope_position,
    case
      when b.task_type = 'checklist_step' then 'execution_component'
      when b.effective_parent_task_id is not null then 'child_work'
      else 'top_level_work'
    end as execution_structure_position
  from base b
  left join atlas.work_items wi
    on wi.organization_id = b.organization_id
   and wi.id = b.resolved_work_item_id
  left join atlas.work_allocations wa
    on wa.organization_id = b.organization_id
   and wa.work_item_id = b.resolved_work_item_id
   and wa.state = 'active'
   and wa.allocation_role = 'responsible'
  left join atlas.organization_memberships om
    on om.organization_id = wa.organization_id
   and om.id = wa.assignee_membership_id
  left join lateral (
    select tc.id
    from atlas.work_time_contracts tc
    where tc.organization_id = b.organization_id
      and tc.work_item_id = b.resolved_work_item_id
      and tc.contract_state = 'active'
    order by tc.updated_at desc, tc.id desc
    limit 1
  ) wt on true
)
select
  e.*,
  case
    when e.adapter_work_item_id is not null and e.adapter_state <> 'retired'
      then 'already_mapped'
    when e.legacy_status in ('done', 'archived', 'skipped')
      then 'historical_terminal'
    when e.company_scope_position <> 'current_company_work'
      then 'not_applicable'
    when e.execution_structure_position = 'execution_component'
      then 'execution_only'
    when e.direct_work_item_id is not null
      then 'map_existing_work_item'
    else 'create_work_item'
  end as work_identity_position,
  case
    when e.active_responsible_allocation_id is not null
      then 'canonical_active'
    when e.assigned_user_id is not null
     and e.farm_membership_user_id is not null
     and e.assigned_user_id <> e.farm_membership_user_id
      then 'identity_conflict_review'
    when e.legacy_responsibility_user_id is null
      then 'legacy_unassigned'
    when exists (
      select 1
      from atlas.organization_memberships candidate_om
      where candidate_om.organization_id = e.organization_id
        and candidate_om.user_id = e.legacy_responsibility_user_id
        and candidate_om.active
    ) then 'ready_to_allocate'
    else 'membership_inactive_review'
  end as assignment_position,
  case
    when e.active_time_contract_id is not null then 'canonical_time'
    when e.legacy_due_date is not null then 'preferred_target_candidate'
    else 'no_legacy_due_evidence'
  end as time_position
from enriched e;

comment on view atlas.legacy_company_work_canonicalization_audit_v1 is
  'Audit-only compatibility surface for current/historical legacy task reconciliation. Company scope, work identity, execution structure, assignment, and time are independent positions. It is not Company Work read authority and must not be consumed by the finished Employee Ledger.';

insert into atlas.architecture_truth_authorities (
  authority_key,
  domain_key,
  truth_question,
  authority_owner,
  authority_status,
  canonical_relations,
  canonical_functions,
  supporting_relations,
  consumer_surfaces,
  known_competitors,
  source_custody,
  rationale,
  updated_at
) values (
  'company_work_ledger_position',
  'company_work',
  'What Company Work exists now, who lawfully owns or is canonically named for it, what time truth applies, and what is its current management/planning position?',
  'atlas.company_work_ledger_v1',
  'canonical',
  array['atlas.work_items','atlas.work_allocations','atlas.work_time_contracts','atlas.work_item_relations','atlas.work_planning_conflicts','atlas.work_execution_plans','atlas.company_work_position_v2'],
  array[]::text[],
  array['atlas.work_execution_adapters'],
  array['Employee Ledger','Atlas Work retrieval','management work search','person responsibility queries','unassigned work queries','planning and capacity inspection'],
  array['atlas.tasks as current Company Work authority','atlas.worker_week_projection as Company Work existence authority','Worker Day delivery as Company Work existence authority','consumer-specific reconstruction of responsibility or planning state'],
  'optical-lift/noel-core-db:supabase/migrations',
  'Company Work identity exists independently of assignment, planning, Day admission, Clock placement, or worker exposure. The Ledger delegates current management position to company_work_position_v2 and adds only side-effect-free responsibility, execution-plan, and filter lenses. Legacy tasks remain reconciliation evidence only.',
  now()
)
on conflict (authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

commit;
