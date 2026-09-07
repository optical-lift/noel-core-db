# Atlas Legacy Work Canonicalization v1

**Status:** Proposed migration/reconciliation contract  
**Scope:** Existing `atlas.tasks` and related legacy execution records

## Purpose

Atlas currently contains substantial historical and current work in legacy `atlas.tasks` alongside the canonical Company Work Kernel. This contract defines how legacy evidence crosses into canonical Company Work without allowing legacy schema semantics to become permanent architecture.

## Constitutional boundary

> Legacy work may be evidence and an ingestion source. It is not a second current-work authority.

The Company Work Kernel remains authoritative for canonical organization work:

- `atlas.work_requirements`
- `atlas.work_items`
- `atlas.work_requirement_links`
- `atlas.work_allocations`
- `atlas.work_item_relations`
- `atlas.work_time_contracts`
- `atlas.work_planning_conflicts`

`atlas.work_execution_adapters` is the compatibility seam between canonical work and execution carriers such as legacy tasks.

The Employee/Company Work Ledger must never permanently combine `work_items UNION legacy tasks`.

## Independent reconciliation dimensions

Canonicalization must not collapse work identity, assignment, time, and execution structure into one mutually-exclusive disposition. They are separate truths. A legacy row can safely establish a canonical `work_item` while its assignee remains unresolved and its old due date remains only weak timing evidence.

Every relevant legacy row therefore receives independent positions.

### 1. Company scope position

- `current_company_work` — evidence places the row inside an organization/farm/unit governed by Company Work;
- `historical_company_evidence` — terminal evidence retained for later historical migration;
- `exclude_non_company_work` — evidence establishes that this belongs outside Company Work;
- `scope_review` — custody is insufficient or contradictory.

### 2. Work identity position

- `already_mapped` — a non-retired execution adapter resolves exactly one canonical work identity;
- `map_existing_work_item` — an exact canonical work identity exists but the adapter is missing/retired;
- `create_work_item` — the row represents distinct organization work requiring canonical identity;
- `execution_only` — the row is a checklist/result/component and must remain below an existing or newly-created parent work identity;
- `historical_terminal` — not required for the first current-work cutover;
- `not_applicable` — outside Company Work.

### 3. Execution structure position

- `top_level_work`;
- `child_work` — independently actionable work whose parent relationship must become an explicit `part_of` relation between canonical work items;
- `execution_component` — result/checklist structure that must not become duplicate Company Work.

A legacy `parent_task_id` does not by itself mean `execution_only`. The content and execution role determine whether the child is real work or merely a component.

### 4. Assignment position

- `canonical_active` — current responsible allocation already exists;
- `ready_to_allocate` — legacy responsibility resolves to one active Organization Membership and can lawfully become an active responsible allocation;
- `legacy_unassigned` — no person responsibility is asserted; unassigned work is valid;
- `membership_inactive_review` — a named person exists but no active Organization Membership can lawfully receive the allocation;
- `identity_conflict_review` — legacy assignee identifiers disagree.

When a named person cannot lawfully receive an allocation, preserve the `work_item` and create/use canonical `work_planning_conflicts` with `conflict_kind='no_eligible_assignee'`. Do not guess, silently reactivate membership, or mislabel the work as ordinary unassigned work.

### 5. Time position

- `canonical_time` — canonical time contract already owns current timing;
- `preferred_target_candidate` — legacy `due_date` is available as target evidence only;
- `no_legacy_due_evidence` — no safe timing evidence exists;
- `time_review` — stronger time semantics are suggested but cannot be established automatically.

Legacy `due_date` must never automatically become `hard_finish_at` or `latest_lawful_at`. For the first adoption pass, a plain legacy due date may become an adoption-owned movable `preferred_end_at` with provenance explicitly stating `dueDateIsTargetNotHardLaw=true`.

## Current-work cutover

The first operational cutover covers non-terminal work that can still affect company responsibility: `open` and `blocked` legacy rows in current company scope.

Current-work retrieval is complete when:

1. every current company-work row has a classified work-identity position;
2. every row representing organization work resolves to exactly one canonical work identity;
3. execution-only rows resolve beneath canonical parent work rather than becoming duplicate ledger rows;
4. assignment uncertainty is preserved canonically as conflict truth;
5. timing uncertainty does not get promoted into stronger deadline law;
6. rows outside Company Work are explicitly excluded with inspectable evidence.

The cutover does **not** require every named worker to have an active allocation. It requires responsibility uncertainty to be explicit and queryable.

## Assignment translation

Legacy assignee fields are evidence, not canonical assignment authority. Where identity resolves to an active Organization Membership, responsibility is represented through `atlas.work_allocations` with `allocation_role='responsible'`.

Where membership is inactive, canonical work still exists. The responsible-person candidate may be preserved in `work_planning_conflicts.metadata` using the established `no_eligible_assignee` pattern so authorized management can find that work through the person's lens while seeing that custody is unresolved.

## Time translation

A preferred target, latest lawful time, and hard finish are different facts. Canonicalization may preserve a legacy due date as a movable preferred target, but stronger semantics require stronger source evidence.

## State translation

Completion, cancellation, supersession, and archival history must map according to explicit source evidence. `archived` is not synonymous with `completed`.

## Provenance and idempotency

Canonicalized work must retain enough provenance to answer which legacy record carried it, how identity was established, what assignment/time uncertainty remained, and which canonical work item now owns the organization obligation.

Canonicalization must be idempotent. Re-running it must not create duplicate work items, requirements, active adapters, allocations, time contracts, conflicts, or `part_of` relations.

## Verification gates

Before the Employee Ledger may claim complete current-work coverage:

1. all current company rows are classified across all independent dimensions;
2. all current organization work resolves to exactly one canonical work item;
3. no legacy task resolves to competing canonical work identities;
4. no canonical work item is duplicated merely because it had multiple carriers/components;
5. active responsible allocations satisfy membership and uniqueness constraints;
6. unresolved named responsibility remains visibly quarantined, not relabeled unassigned;
7. preferred legacy timing is not promoted to lawful/hard deadline truth;
8. Ledger reads contain no direct dependency on `atlas.tasks`.

## Historical phase

After current-work cutover is in use, terminal/historical legacy evidence may be reconciled in controlled batches so historical responsibility and planning questions become available without delaying current operational retrieval.
