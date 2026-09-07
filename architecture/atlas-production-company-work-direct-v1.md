# Atlas Production → Company Work direct seam v1

## Purpose

This document records the proved Production → Company Work → Worker Day → result-return seam used by the Organization Ledger build.

The governing rule is:

> **Work can remain true after a worker changes or a planned day passes. Responsibility, schedule, exposure, authorization, report, and acceptance are separate facts.**

Production establishes work because Production reality requires it. It does not choose a person merely because one worker is familiar, currently active, or normally performs that kind of work.

## Governing lifecycle

```text
Production reality
→ Company Work
→ Responsibility
→ manager plan
→ Worker-Day exposure
→ execution authority
→ worker result
→ result acceptance
→ Company Work completion
→ Production reconciliation
→ Organization Ledger closure
```

This is a sequence of governed facts, not one task row changing labels.

### Facts that must remain separate

1. **Work truth** — the institution has work that remains true until satisfied, cancelled, or superseded under its source contract.
2. **Responsibility** — a governed institutional membership owns execution responsibility.
3. **Original manager plan** — the day management intended the work to happen.
4. **Effective exposure day** — the day Worker Day is currently allowed to expose the work; this may roll forward without rewriting the original plan.
5. **Worker-Day placement** — the work is present on the worker's current-day projection.
6. **Execution authority** — current Clock/readiness/source-reality checks and the execution lease permit the operation now.
7. **Worker report** — the worker reports Done, Partial, Blocked, or another governed result.
8. **Result acceptance** — the Work result contract determines whether that report is sufficient evidence.
9. **Company Work completion** — Work closes only after required accepted result evidence exists.
10. **Source reconciliation** — Production decides the source-domain consequence of the accepted Work result.
11. **Ledger closure** — Organization Ledger projects the meaningful institutional consequence after the source/work authorities establish it.

No later fact should be manufactured merely because an earlier fact exists.

## Production authority

Production may know:

- production lot and destination identity;
- quantity/capacity requirement;
- preparation need;
- source-owned timing/window;
- consequence of delay;
- the result contract that would satisfy the prerequisite.

Production may not infer:

- `worker_key='anna'` or any other familiar worker key;
- a private Person/Worker Day;
- current execution attention;
- Personal Atlas constraints;
- an assignee from role/title proximity;
- that a downstream biological transition is ready merely because a prerequisite operation is valid.

For the proved bed-preparation seam, an active `production_bed_assignment` can warrant the identity of the preparation operation while seed readiness or the production lot's next biological transition remains unresolved. Preparing the destination is legitimate parallel prerequisite work; it does not falsely advance Production.

## Company Work identity

The Production source path idempotently establishes source-derived Company Work independent of assignee and day:

- `work_requirements` from `production_bed_assignment`;
- `work_items` with source-derived stable identity;
- `work_requirement_links`;
- `work_time_contracts` from source-owned timing;
- `result_contract_key` describing what evidence may satisfy the Work;
- no Responsibility allocation unless a separate authority has established one.

Unassigned open Company Work is valid. The Organization Ledger / management projection should render unresolved responsibility rather than Production guessing a human.

Changing responsibility, planned date, exposure date, or legacy execution carrier must not change the Work stable key.

## Responsibility and service-date eligibility

Responsibility and scheduling are separate.

A manager may assign Responsibility without placing the Work on a day. A manager may then plan the Work for a service date only when the responsible institutional membership is eligible for that date.

For farm execution, both layers must pass:

- Organization membership eligibility on the service date; and
- farm `farm_hand` execution membership eligibility on the service date.

This is future-aware. A person who is active today but already known to become ineligible before Tuesday cannot be scheduled to execute governed Tuesday Work.

If eligibility changes after planning, the plan becomes `needs_replan`; Atlas does not silently preserve invalid execution authority.

## Manager plan versus Worker Day

Management may plan a future week. The worker-facing projection exposes the current service day rather than management's future-week plan.

`work_execution_plans` preserve at least:

- original planned service date;
- current exposure service date;
- first planned service date;
- rollover count;
- responsible allocation.

If Monday's Work remains unfinished, Atlas may expose it Tuesday while preserving Monday as the original planned date. Rollover is therefore an exposure change, not rewritten history.

Unassigned Work is invisible to the worker. Assigned-but-unscheduled Work remains invisible. Only an active eligible plan may progress toward Worker Day.

## Transitional execution carrier

Worker Day may still use a legacy Task/planned-occurrence carrier while the execution UI is being succeeded. The carrier is downstream compatibility only and is linked through `work_execution_adapters`.

The adapter is disposable:

- retiring it does not erase Work;
- changing assignee does not change Work identity;
- changing day does not change Work identity;
- Worker Day does not become the source of Production requirement truth;
- release provenance must exist before the manager-plan carrier is synchronized.

A Worker-Day placement is not execution authority. Current execution readiness, canonical source-operation warrant, responsibility, manager plan, service-date placement, and final execution lease must still agree.

## Worker result and acceptance

Worker input is a report, not automatically source truth.

The result path uses:

- `work_result_contract_policies`;
- append-only `work_execution_results`;
- append-only `work_result_acceptances`.

For `production_bed_preparation_v1`, the contract permits worker attestation. The familiar one-tap **Done** remains sufficient and does not require a second popup, but under the hood it creates a worker result and an accepted result before governed Company Work may complete.

Work whose contract requires structured evidence cannot bypass that requirement through ordinary Done. Quantities, tallies, custody, or other genuinely required result data must be captured by the appropriate structured/domain result path.

A direct attempt to set governed Company Work to `completed` without accepted result evidence is rejected.

### Blocked

`Blocked` is an execution result, not completion.

A blocked report:

- remains attached to the Work history;
- leaves Company Work open;
- does not manufacture Production completion;
- surfaces a management exception through the planning queue.

## Legacy release isolation

Completing manager-scheduled Company Work must not invoke the unrelated legacy farm-wide release sweep. That legacy release engine may continue to serve legacy farm work, but governed Company Work owns its planning/release path and must not be able to collide with it merely because a compatibility Task reaches a terminal state.

## Rollback-only human-path proof

The live-schema proof walked the human experience rather than only testing object creation.

Proved sequence:

```text
unassigned → invisible to worker
assigned but unscheduled → still invisible
assigned + manager scheduled → Worker Day
Worker Day → actual execution lease
Blocked → remains open + manager exception
unfinished → rolls forward while preserving original planned date
Done → accepted worker result
     → Company Work completed
     → Production reconciled
     → Ledger closed
```

Additional proof assertions:

- future Organization/farm execution ineligibility prevents scheduling;
- placement alone cannot grant execution permission;
- Production prerequisite work may proceed without falsely asserting the next biological transition is ready;
- structured-result contracts cannot cheat through Done;
- governed completion without accepted result evidence is rejected;
- the old terminal-task release sweep is isolated from manager-scheduled Company Work.

The proof caught and required separate fixes for:

- UUID aggregation in execution-membership resolution;
- Clock provenance sequencing;
- missing Production prerequisite-operation warrant;
- legacy terminal-task release collision;
- ambiguous manager-planning-queue SQL.

## Persisted production boundary after proof

The human proof used rollback transactions for temporary worker activation, Responsibility, planning, Worker-Day placement, result return, completion, Production reconciliation, and Ledger closure.

The real Elm bed-preparation obligations remain persisted as open Company Work but are not assigned or scheduled by the proof.

As audited after the proof:

- six real `production_bed_preparation_v1` Work items are open;
- all six have zero active Responsibility allocations;
- all six have zero active/current manager plans;
- no released compatibility Task carriers exist for them;
- no Worker-Day placements exist for them;
- no execution-result or accepted-result rows exist for them.

This is intentional. Proof machinery did not silently create live work commitments for Anna.

## Live migration slice for the manager/worker UX proof

The following migrations are live and mirrored in repository history in their actual application order:

1. `20260906002837_atlas_company_work_planning_v1.sql`
2. `20260906003115_atlas_company_work_worker_day_bridge_v1.sql`
3. `20260906003432_atlas_company_work_execution_eligibility_fix_v1.sql`
4. `20260906003549_atlas_company_work_result_acceptance_v1.sql`
5. `20260906003713_atlas_company_work_execution_membership_uuid_fix_v1.sql`
6. `20260906003814_atlas_company_work_clock_provenance_bridge_v1.sql`
7. `20260906004144_atlas_company_work_operation_warrant_bridge_v1.sql`
8. `20260906004231_atlas_company_work_terminal_release_isolation_v1.sql`
9. `20260906004430_atlas_company_work_planning_queue_ambiguity_fix_v1.sql`

Do not squash these into a fictional clean migration history. The fixes are part of the authoritative live sequence and document what the proof actually discovered.

## Promotion boundary

This seam is no longer waiting for the Worker-Day/result-return proof. That proof is complete.

The next promotion work is release hardening and product wiring:

1. keep the PR draft until repository/live migration parity and review are complete;
2. run the final Supabase security/performance advisor and live-state audit;
3. wire management planning and worker-day UI only to the proved contracts;
4. preserve the management exception path for Blocked / `needs_replan`;
5. do not collapse Responsibility, schedule, exposure, authorization, report, or acceptance back into a single task state;
6. do not merge until the release review is explicitly complete.
