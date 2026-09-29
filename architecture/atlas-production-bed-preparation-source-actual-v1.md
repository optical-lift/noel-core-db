# Atlas Production Bed Preparation Source Actual v1

**Status:** branch-only implementation candidate  
**Established:** September 29, 2026  
**Governing parent:** `architecture/atlas-reality-first-work-derivation-current-canon-v1.md`  
**Supersedes the source-truth inference in:** `20260905233138_atlas_company_work_production_return_completion_fix_v1.sql` and the `preparedBedFeetAuthority='company_work'` behavior of `atlas.refresh_production_transplant_gate_v1`

## Decision

Company Work completion is not Production bed-preparation truth.

For the bounded Production bed-preparation case, the lawful chain is:

```text
Production bed assignment
→ Production derives a bed-preparation requirement
→ Company Work carries the required operation
→ worker executes
→ execution result is reported
→ result contract accepts or rejects the result
→ accepted result is evidence offered back to Production
→ Production adjudicates that evidence under its own rule
→ Production writes an append-only bed-preparation Actual
→ transplant gate consumes the Production Actual
```

Forbidden collapse:

```text
work_items.work_state = 'completed'
→ therefore assigned bed is prepared
```

## Why a separate Production Actual exists

The existing `atlas.production_operation_actuals` relation is Task-shaped: it requires `task_id` and `actual_minutes`. Reusing it as the canonical state of a Production bed assignment would make an execution carrier own source-domain truth again.

The bounded `atlas.production_bed_preparation_actuals` relation instead owns only the state Production needs to establish about an exact `production_bed_assignment`:

- `prepared`
- `partially_prepared`
- `not_prepared`
- prepared bed-feet
- effective time
- recorded time
- evidence/provenance

Its history is append-only.

## Evidence versus adjudication

`atlas.work_execution_results` owns execution-result evidence.

`atlas.work_result_acceptances` owns whether that result satisfies its Company Work result contract.

Neither table owns the source bed's state.

For the current `production_bed_preparation_v1` contract, Production's bounded adjudication rule is:

> an accepted `completed` execution result for the exact bed-preparation Work is sufficient evidence for Production to establish that assignment's currently assigned bed-feet as prepared.

This rule is implemented by:

`atlas.adjudicate_production_bed_preparation_result_v1(execution_result_id)`

The rule is deliberately located in the Production domain rather than encoded as a universal meaning of Company Work completion. A later Production contract can require inspection, measurement, structured evidence, or another adjudication rule without changing Company Work semantics.

## As-of law

Source Actual resolution applies both clocks:

```text
effective_at <= as_of
AND
created_at <= as_of
```

A later-recorded backdated Actual therefore cannot rewrite what Atlas could have established at an earlier `as_of`.

## Transplant gate change

`atlas.refresh_production_transplant_gate_v1` no longer sums `production_bed_assignments.quantity_assigned` merely because a linked `atlas.work_items` row is `completed`.

It resolves the latest Production-owned Actual for each active assignment and sums only the prepared quantity established there.

Canonical authority becomes:

```text
preparedBedFeetAuthority = production_bed_preparation_actuals
```

not:

```text
preparedBedFeetAuthority = company_work
```

## Work completion change

`atlas.reconcile_production_bed_preparation_company_work_completion_v1` still closes Work-local structures:

- the operational Work requirement;
- Work time contract;
- active Work responsibility allocation;
- execution adapter;
- planned occurrence carrier.

Those terminal states mean the operation carrier has ended. They do not establish the source state.

The reconciler then looks for an exact accepted `completed` execution result under `production_bed_preparation_v1`.

If it finds one, it offers that result to the Production adjudicator.

If it does not, the source condition remains pending even though Company Work is terminal.

## Ledger law

The Production ledger now distinguishes:

### `bed_preparation_work_result`

Historical evidence that Company Work produced an accepted result.

### `bed_preparation_actual`

Production-owned state established after adjudication.

### `bed_preparation_required`

The source requirement. It may close only when the Production Actual establishes sufficient prepared capacity.

The existing `guard_completed_company_work_ledger_designation_v1` is superseded so `work_state='completed'` can no longer close `bed_preparation_required` by itself.

## Historical rows

This tranche intentionally does **not** fabricate Production Actuals for historical Work rows solely because they are already terminal.

If a historical Work item has a recoverable accepted exact execution result, it may be adjudicated through the same Production rule.

If it does not, the source state is epistemically unresolved until Production has sufficient evidence to establish it.

No backfill from `work_state='completed'` is lawful.

## Truth boundary

```text
Task done
≠ Company Work result accepted

Company Work result accepted
≠ Production state established

Company Work completed
≠ Production state established

Production bed-preparation Actual established
→ Production may count the established prepared quantity

sufficient Production-established prepared quantity
→ transplant gate may satisfy its bed-preparation condition
```

## Release boundary

This branch must not be applied directly to production while the September 25–28 source-history reconciliation remains incomplete.

Before release:

1. preserve the exact production migration ledger;
2. validate this additive migration against a production-schema clone;
3. verify all current callers of `refresh_production_transplant_gate_v1` against the new fail-closed behavior;
4. inventory already-completed bed-preparation Work and classify which rows have recoverable accepted execution results;
5. do not fabricate source Actuals for rows without sufficient evidence;
6. explicitly review operational impact before any production application.

No GitHub Actions or pull request are required for this branch-only checkpoint.