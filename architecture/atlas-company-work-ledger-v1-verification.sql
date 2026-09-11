-- Atlas Company Work Ledger v1 verification contract
-- Run after promoting the candidate SQL through the governed migration path.

-- 1. One ledger row per canonical work item.
select
  (select count(*) from atlas.work_items) as work_items,
  (select count(*) from atlas.company_work_ledger_v1) as ledger_rows,
  (select count(distinct work_item_id) from atlas.company_work_ledger_v1) as distinct_ledger_work_items;
-- Expected: all three counts equal.

-- 2. No duplicate work identities.
select work_item_id, count(*)
from atlas.company_work_ledger_v1
group by work_item_id
having count(*) <> 1;
-- Expected: zero rows.

-- 3. Responsibility positions partition open work exactly once.
select
  count(*) filter (where is_open) as open_total,
  count(*) filter (where is_open and responsibility_position='allocated') as open_allocated,
  count(*) filter (where is_open and responsibility_position='unresolved_named') as open_unresolved_named,
  count(*) filter (where is_open and responsibility_position='unassigned') as open_unassigned
from atlas.company_work_ledger_v1;
-- Expected: open_total = allocated + unresolved_named + unassigned.

-- 4. Unresolved named responsibility is not silently labeled Unassigned.
select work_item_id, title, responsibility_display_name,
       responsibility_position, open_planning_conflict_kind,
       open_planning_conflict_reason
from atlas.company_work_ledger_v1
where responsibility_position='unresolved_named'
order by responsibility_display_name, title;
-- Expected: each row has a responsibility_user_id and does not have is_unassigned=true.

-- 5. Person lenses work for both active allocation and unresolved named responsibility.
select responsibility_display_name, responsibility_position, count(*) as open_work
from atlas.company_work_ledger_v1
where is_open and responsibility_user_id is not null
group by responsibility_display_name, responsibility_position
order by responsibility_display_name, responsibility_position;

-- 6. Unscheduled work remains discoverable regardless of responsibility position.
select work_item_id, title, responsibility_display_name,
       responsibility_position, management_position
from atlas.company_work_ledger_v1
where is_open and is_unscheduled
order by responsibility_display_name nulls first, title;

-- 7. Dependency and planning-conflict positions remain distinct from responsibility.
select management_position, responsibility_position, count(*)
from atlas.company_work_ledger_v1
where is_open
group by management_position, responsibility_position
order by management_position, responsibility_position;

-- 8. Time semantics remain distinct.
select work_item_id, title,
       preferred_start_at, preferred_end_at,
       latest_lawful_at, hard_finish_at,
       is_overdue, is_hard_finish_missed
from atlas.company_work_ledger_v1
where is_open
  and (preferred_end_at is not null or latest_lawful_at is not null or hard_finish_at is not null)
order by coalesce(hard_finish_at, latest_lawful_at, preferred_end_at);

-- 9. Current legacy reconciliation is classified across independent dimensions.
select company_scope_position,
       work_identity_position,
       execution_structure_position,
       assignment_position,
       time_position,
       count(*) as rows
from atlas.legacy_company_work_canonicalization_audit_v1
where legacy_status in ('open','blocked')
group by 1,2,3,4,5
order by 1,2,3,4,5;

-- 10. Current Company Work identity cutover gate.
select
  count(*) filter (
    where legacy_status in ('open','blocked')
      and company_scope_position='current_company_work'
  ) as current_company_rows,
  count(*) filter (
    where legacy_status in ('open','blocked')
      and company_scope_position='current_company_work'
      and work_identity_position in ('already_mapped','map_existing_work_item')
      and resolved_work_item_id is not null
  ) as already_has_identity,
  count(*) filter (
    where legacy_status in ('open','blocked')
      and company_scope_position='current_company_work'
      and work_identity_position='execution_only'
  ) as execution_only_rows,
  count(*) filter (
    where legacy_status in ('open','blocked')
      and company_scope_position='current_company_work'
      and work_identity_position='create_work_item'
  ) as identities_to_create,
  count(*) filter (
    where legacy_status in ('open','blocked')
      and company_scope_position='scope_review'
  ) as scope_review_rows
from atlas.legacy_company_work_canonicalization_audit_v1;

-- 11. No current company-work row may remain without either canonical identity,
-- explicit execution-only classification, or an identified create-work action.
select legacy_task_id, legacy_title, work_identity_position,
       execution_structure_position, assignment_position, time_position
from atlas.legacy_company_work_canonicalization_audit_v1
where legacy_status in ('open','blocked')
  and company_scope_position='current_company_work'
  and work_identity_position not in (
    'already_mapped','map_existing_work_item','create_work_item','execution_only'
  );
-- Expected: zero rows.

-- 12. No ambiguous multiple non-retired adapters for one legacy task.
select task_id, count(*)
from atlas.work_execution_adapters
where task_id is not null
  and state <> 'retired'
group by task_id
having count(*) > 1;
-- Expected: zero rows.

-- 13. Active allocations must point at active Organization Memberships.
select wa.id as allocation_id, wa.work_item_id, wa.assignee_membership_id
from atlas.work_allocations wa
left join atlas.organization_memberships om
  on om.organization_id=wa.organization_id
 and om.id=wa.assignee_membership_id
where wa.state='active'
  and wa.allocation_role='responsible'
  and coalesce(om.active,false)=false;
-- Expected: zero rows.

-- 14. No ledger implementation dependency on legacy tasks.
select pg_get_viewdef('atlas.company_work_ledger_v1'::regclass, true) ilike '%atlas.tasks%' as reads_legacy_tasks;
-- Expected: false.
