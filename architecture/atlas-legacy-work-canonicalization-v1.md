# Atlas Legacy Work Canonicalization v1

**Status:** Proposed migration/reconciliation contract  
**Scope:** Existing `atlas.tasks` and related legacy execution records

## Purpose

Atlas currently contains substantial historical and current work in legacy `atlas.tasks` alongside the canonical Company Work Kernel. This contract defines how legacy work crosses into canonical Company Work without allowing legacy schema semantics to become permanent architecture.

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

## Prohibited shortcut

The Employee/Company Work Ledger must not permanently combine:

```text
work_items
UNION
legacy tasks
```

Doing so would force every downstream filter to reconcile two different ontologies and would violate the canonical effective-position rule.

## Canonicalization disposition

Every legacy task considered for organization-work preservation must receive exactly one audit disposition:

- `already_mapped` — an active/non-retired execution adapter already connects it to canonical work;
- `map_existing_work_item` — evidence identifies an existing canonical work identity but the adapter is missing/retired;
- `create_work_item` — the legacy record represents distinct organization work requiring canonical materialization;
- `execution_only` — the legacy row is only an execution carrier/result/history for an existing work identity;
- `historical_terminal` — terminal historical work retained for provenance but not required in the initial current-work cutover;
- `identity_review` — assignee/person identity cannot be reconciled lawfully;
- `time_semantics_review` — legacy due-date evidence cannot safely be mapped to a canonical time-contract meaning;
- `source_review` — source/domain identity is insufficient to materialize canonical work without interpretation;
- `exclude_non_company_work` — evidence establishes that the row is not company work governed by this kernel.

No row may disappear merely because classification is difficult.

## Current-work cutover

The first operational cutover should prioritize non-terminal work:

- open;
- blocked;
- other active states that can still affect company responsibility.

Current-work retrieval must not be declared complete until every relevant non-terminal legacy task is classified and every row that represents current company work has a canonical work identity.

## Assignment translation

Legacy assignee fields are evidence, not the canonical assignment authority.

Where identity is lawfully resolved, current responsibility is represented through `atlas.work_allocations` with `allocation_role = 'responsible'`.

If identity is ambiguous or the relevant organization membership is inactive/inconsistent, the canonicalization process must preserve the discrepancy for review rather than inventing a valid current allocation.

## Time translation

Legacy `due_date` must not automatically become `hard_finish_at` or `latest_lawful_at`.

Canonicalization must determine the supported temporal meaning from source evidence. Possible outcomes include preferred window, latest satisfactory time, hard finish, or no lawful canonical time contract until review.

Unknown time semantics remain unknown.

## State translation

Completion, cancellation, supersession, and archival history must map according to explicit source evidence. `archived` must not be assumed synonymous with `completed`.

## Provenance

Canonicalized work must retain enough provenance to answer:

- which legacy record carried it;
- when it was mapped/materialized;
- whether identity or time semantics required adjudication;
- which canonical work item now owns the organization-level work identity.

Provenance may live in execution adapters, source-object references, metadata, or a dedicated reconciliation audit surface, but must remain inspectable.

## Idempotency

Canonicalization must be idempotent. Re-running the process must not create duplicate work items or duplicate active responsible allocations.

## Verification gates

Before the Employee Ledger is allowed to claim current-work completeness:

1. all relevant non-terminal legacy tasks are classified;
2. all rows classified as current company work resolve to exactly one canonical work item;
3. no legacy task resolves to multiple competing canonical work identities;
4. no canonical work item is duplicated merely because it had multiple legacy carriers;
5. active responsible allocations satisfy kernel uniqueness constraints;
6. unresolved identity/time/source cases remain visibly quarantined;
7. Ledger reads contain no direct dependency on `atlas.tasks`.

## Historical phase

After current-work cutover is complete and in use, terminal/historical legacy work may be canonicalized in controlled batches so historical responsibility and planning questions become available without delaying current operational use.
