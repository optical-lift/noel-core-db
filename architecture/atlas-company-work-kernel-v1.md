# Atlas Company Work Kernel v1

This repository owns the canonical shared database migration for the new Atlas company-work architecture.

## Governing law

Work exists at the organization level before assignment. Assignment is custody layered onto work. Readiness, planning, Day admission, Clock placement, and attention may change presentation but must not erase the underlying work identity.

## Canonical primitives

- `atlas.work_requirements`
- `atlas.work_items`
- `atlas.work_requirement_links`
- `atlas.work_allocations`
- `atlas.work_item_relations`
- `atlas.work_time_contracts`
- `atlas.work_planning_conflicts`

## Hard invariants

1. `work_items` is organization-owned and contains no assignee or presentation state.
2. Unassigned open work is valid.
3. One active `responsible` allocation is permitted per work item; allocation history is retained.
4. Causal relations are explicit and do not imply visibility inheritance.
5. Time truth lives outside work lifecycle state.
6. Planning failure is explicit conflict truth, not disappearance.
7. The migration does not backfill or reference legacy `atlas.tasks`.
8. Direct client access remains revoked until canonical authorization APIs are added.

## First product proof

The first clean fixture should prove requirement → work → allocation → dependency → time contract → planning conflict without any dependency on legacy Worker Day or task-feed semantics.
