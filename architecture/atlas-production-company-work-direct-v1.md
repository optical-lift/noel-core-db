# Atlas Production → Company Work direct seam v1

## Purpose

Prove the first source-domain convergence required by the Organization Ledger build:

> **Production establishes the work its own reality requires without knowing the worker who will perform it.**

The existing `reconcile_production_capacity_work_v1()` correctly derives bed-preparation need from Production truth, but its current execution path still resolves `worker_key='anna'` and authors a legacy planned occurrence/task carrier before durable Company Work convergence.

This tranche removes that assumption at the work-identity boundary.

## Governing boundary

```text
Production state + destination assignment
→ Production-owned preparation requirement
→ organization-owned Company Work
→ separate Responsibility / Allocation
→ separate planning / Worker Day
```

Production may know:

- the production lot;
- intended destination;
- quantity/capacity requirement;
- preparation need;
- source-owned timing/window;
- consequence of delay;
- what result would satisfy the prerequisite.

Production may not know or infer:

- `worker_key='anna'`;
- a private Person/Worker Day;
- current execution attention;
- Personal Atlas constraints;
- an assignee merely from role/title proximity.

## Direct materialization target

A production-specific internal command/helper should idempotently establish:

- `work_requirements` with source `production_bed_assignment`;
- `work_items` with a source-derived stable key independent of assignee;
- `work_requirement_links` with `resolves` relationship;
- `work_time_contracts` from the biological/source-owned window;
- no `work_allocations` unless a separate Responsibility authority has already/independently established one;
- no legacy Task/planned occurrence as a prerequisite for Company Work identity.

The source-specific helper is preferred over inventing a universal “create work from anything” writer. Each source domain remains responsible for the semantics that justify its work.

## Responsibility

Unassigned open Company Work is valid and is the correct result when no responsibility authority is established.

The Organization Ledger should render that truth as unresolved responsibility rather than Production guessing a worker.

A later manager/delegation/standing-responsibility command may establish `work_allocations`. Changing that allocation must not change the Production Work stable key.

## Transitional execution

Existing Worker Day mechanics may continue to require a legacy Task execution carrier temporarily. If so, create that carrier **after** Company Work and link it through `work_execution_adapters`.

The adapter must remain disposable:

- retiring it does not erase Work;
- changing assignee does not change Work identity;
- Worker Day does not become the source of Production requirement truth.

## Proof target

The rollback proof uses one existing assigned Production bed assignment, temporarily moves its lot to the already-supported `transplant_ready` state inside the rollback transaction, and establishes direct Company Work.

Assertions:

1. Production source identity creates one stable Work Requirement and one Work Item.
2. Exact replay returns the same canonical Work IDs.
3. Work exists with zero responsibility allocations.
4. No execution adapter/legacy Task is required for the direct Work identity.
5. Timing is stored in `work_time_contracts`, not work lifecycle state.
6. Source object is `production_bed_assignment`.
7. Work title/instructions can remain domain-specific while Work schema remains generic.
8. Transaction rollback restores the live Production lot and leaves no direct Work rows behind.

## Next promotion after proof

Once this seam is verified, the production reconciler can be refactored in two stages:

1. **source convergence:** call direct Company Work materialization first;
2. **delivery compatibility:** create/update any legacy Task carrier strictly as `work_execution_adapters` until Worker Day consumes Company Work natively.

Only after that should Organization Ledger projection admission be attached to the meaningful Production/Work consequences.
