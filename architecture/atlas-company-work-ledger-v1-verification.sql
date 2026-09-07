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

-- 3. Assignment lenses partition current work without changing population.
select
  count(*) filter (where is_open) as open_total,
  count(*) filter (where is_open and is_assigned) as open_assigned,
  count(*) filter (where is_open and is_unassigned) as open_unassigned
from atlas.company_work_ledger_v1;

-- Expected: open_total = open_assigned + open_unassigned.

-- 4. Person lens is resolvable from canonical allocation identity.
select
  assignee_display_name,
  count(*) filter (where is_open) as open_work
from atlas.company_work_ledger_v1
where is_assigned
group by assignee_display_name
order by assignee_display_name;

-- 5. Unscheduled work remains discoverable.
select work_item_id, title, assignee_display_name, management_position
from atlas.company_work_ledger_v1
where is_open and is_unscheduled
order by assignee_display_name nulls first, title;

-- 6. Dependency and planning-conflict positions remain distinct from assignment.
select management_position, is_assigned, count(*)
from atlas.company_work_ledger_v1
where is_open
group by management_position, is_assigned
order by management_position, is_assigned;

-- 7. Time semantics remain distinct.
select work_item_id, title,
       preferred_start_at, preferred_end_at,
       latest_lawful_at, hard_finish_at,
       is_overdue, is_hard_finish_missed
from atlas.company_work_ledger_v1
where is_open
  and (latest_lawful_at is not null or hard_finish_at is not null)
order by coalesce(hard_finish_at, latest_lawful_at);

-- 8. Legacy-current canonicalization coverage.
select
  count(*) filter (where legacy_status not in ('done','archived','skipped')) as relevant_nonterminal,
  count(*) filter (
    where legacy_status not in ('done','archived','skipped')
      and audit_disposition = 'already_mapped'
  ) as already_mapped,
  count(*) filter (
    where legacy_status not in ('done','archived','skipped')
      and audit_disposition <> 'already_mapped'
  ) as unresolved_nonterminal
from atlas.legacy_company_work_canonicalization_audit_v1;

-- Current-work cutover gate: unresolved_nonterminal must reach zero before
-- the Employee Ledger is allowed to claim complete current-work coverage.

-- 9. No ambiguous multiple active adapters for one legacy task.
select task_id, count(*)
from atlas.work_execution_adapters
where task_id is not null
  and state <> 'retired'
group by task_id
having count(*) > 1;

-- Expected: zero rows.
