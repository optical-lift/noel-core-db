# Atlas Reality Reconciliation Protocol v1

**Status:** architecture contract + executable qualification target  
**Date:** 2026-09-22  
**Parent law:** `architecture/atlas-reality-continuation-protocol-v1.md`  
**Depends on:** production-live Reality Transition Receipt v1 + Reality Continuation v1  
**Universal mutation authority:** none

## 1. Purpose

Reality Transition Receipt answers:

> What changed?

Reality Continuation answers:

> What other governed reality should now be reconsidered?

The remaining architectural question is:

> How may Atlas lawfully account for that reconsideration without treating every Continuation Candidate as an executable command?

This matters because the three qualified Continuation domains already prove that the answer is not uniform.

### Company Work

An unresolved Work Result may require acceptance.

That is not a deterministic machine repair.

It requires authority.

### Commercial Financial Reality

An open or unknown financial position may require a new provider/payment event.

Atlas cannot reconcile missing external reality by calling itself.

It requires evidence.

### Bed readiness

A changed Maintenance Dependency may require a downstream Task readiness gate to recompute.

That resolver is deterministic, domain-owned, idempotent, and already safe to execute automatically.

Therefore:

```text
Continuation Candidate
≠ command

resolver key
≠ executable function name

reconsideration required
≠ automatic mutation allowed
```

The Reconciliation Protocol makes the lawful handling mode explicit.

## 2. Core law

> **Every Continuation Candidate must be classified by the authority/evidence required to account for it before any resolver may be invoked.**

Conceptually:

```text
Continuation Candidate
    ↓
domain reconciliation plan
    ↓
handling mode
    ├─ automatic_domain_reconcile
    ├─ authority_required
    ├─ external_evidence_required
    ├─ invariant_repair_required
    ├─ settled
    └─ not_applicable
    ↓
bounded handling membrane
    ↓
owning-domain result
    ↓
re-read / Transition Receipt / Continuation
```

The universal layer does not choose the downstream truth.

It only provides a common grammar for describing the lawful next handling boundary.

## 3. Reconciliation Plan

The universal read object is a **Reconciliation Plan**.

It answers:

> For this exact Continuation Candidate, what kind of handling is lawful now?

Minimum shape:

```json
{
  "contractVersion": "reality_reconciliation_plan_v1",
  "source": {
    "domain": "...",
    "kind": "...",
    "ref": "...",
    "state": "...",
    "changedAt": "..."
  },
  "targets": [
    {
      "target": {
        "domain": "...",
        "kind": "...",
        "ref": "...",
        "scope": {}
      },
      "resolver": {
        "key": "...",
        "version": "..."
      },
      "handlingMode": "automatic_domain_reconcile|authority_required|external_evidence_required|invariant_repair_required|settled|not_applicable",
      "reason": {
        "kind": "...",
        "basisRefs": []
      },
      "current": {},
      "blockers": [],
      "automation": {
        "eligible": false,
        "adapterKey": null
      }
    }
  ],
  "truthBoundary": {
    "readOnly": true,
    "doesNotExecute": true,
    "doesNotGrantAuthority": true,
    "doesNotCreateEvidence": true,
    "doesNotDetermineOutcome": true
  },
  "provenance": {}
}
```

The normalizer validates shape only.

It does not classify a domain.

Each domain adapter owns its own handling-mode classification.

## 4. Handling modes

### 4.1 automatic_domain_reconcile

Use only when all of the following are true:

- the dependency is already governed;
- the target resolver is deterministic from current canonical evidence;
- no new human judgment is required;
- no new external evidence is required;
- the resolver is idempotent or safely convergent;
- the resolver does not enlarge authority;
- the exact domain command is statically bound.

Example:

```text
Maintenance Dependency changed
→ recompute planting Task bed-readiness gate
```

### 4.2 authority_required

Use when the missing transition requires a human, manager, Principal, practitioner, or other governed authority to decide.

Example:

```text
Work Result reported
→ no accepted adjudication
→ authority_required
```

The orchestration layer may surface or route the decision.

It may not make the decision.

### 4.3 external_evidence_required

Use when the current state cannot lawfully resolve until new external/source-backed evidence arrives.

Example:

```text
Commercial Order open
→ payment/settlement evidence absent
→ external_evidence_required
```

The orchestration layer may request/refresh a connected source through a separately governed connector membrane.

It may not fabricate a Payment Event.

### 4.4 invariant_repair_required

Use when the domain says a consequence should already exist from admitted evidence, but a canonical projection/invariant is missing.

Example:

```text
accepted Company Work Result
+ completed Work
+ missing required Ledger consequence
→ invariant_repair_required
```

This is not ordinary automatic orchestration until a bounded repair command exists and is independently qualified.

### 4.5 settled

The continuation has been accounted for and no additional handling is currently required.

Settled does not necessarily mean the world is complete.

A Task can be correctly blocked after reconciliation.

An open business process can have one settled dependency while another remains unresolved.

### 4.6 not_applicable

The target/resolver no longer applies.

Examples:

- terminal Task;
- retired model version;
- superseded dependency;
- closed obligation;
- resolver contract no longer matches current target semantics.

## 5. Static binding is mandatory

A Reconciliation Plan may contain:

```text
resolver.key = task_bed_weeding_readiness
automation.adapterKey = bed_readiness_reconcile_v1
```

This is descriptive.

A universal function must never do:

```text
execute resolver.key(...)
```

or:

```text
lookup function name from registry
→ dynamic SQL
```

Automatic execution must occur through a statically authored domain wrapper.

Example:

```text
atlas.reconcile_bed_readiness_continuation_service_v1(...)
    ↓
atlas.reconcile_bed_weeding_gate_v1(...)
```

The wrapper may call only the resolver it was written to call.

## 6. No generic queue yet

Do not introduce:

- `reconciliation_queue`;
- `reconciliation_jobs`;
- `resolver_registry`;
- `reality_orchestration_tasks`;
- generic event-bus dispatch.

The current evidence proves handling modes and bounded execution.

It does not yet prove that Atlas needs a generic persisted orchestration queue.

Existing native mechanisms remain valid:

- database triggers for transactional invariants;
- source connector ingestion for external evidence;
- explicit human decision surfaces;
- domain-specific reconciler entrypoints;
- scheduled/domain runners where already governed.

## 7. No generic reconciliation history yet

A durable cross-domain Reconciliation Receipt ledger may eventually be useful.

Do not create it in v1.

First prove that current domain truth can answer:

- what continuation existed;
- which handling mode applied;
- whether automatic reconciliation is currently converged;
- whether authority/evidence is still outstanding.

If later Runtime Proof needs historical proof that an orchestration attempt occurred even when domain state later changed, that will justify a separate append-only receipt layer.

Do not preemptively create it.

## 8. Company Work classification

Input:

`atlas.company_work_result_continuation_v1(execution_result_id)`

Rules:

### Missing result acceptance

```text
resolver = company_work_result_adjudication
handlingMode = authority_required
automation.eligible = false
```

Reason:

Result acceptance changes institutional truth and requires the authority encoded by Company Work.

### Accepted result but missing completion/Ledger consequence

```text
resolver = company_work_completion_projection
handlingMode = invariant_repair_required
automation.eligible = false
```

V1 does not create a generic completion repair command.

### Settled result

When no continuation target remains:

```text
handlingMode = settled
```

No fake target is created merely so the plan has work to do.

## 9. Commercial classification

Input:

`atlas.commercial_financial_continuation_v1(commercial_order_id)`

Rules:

### Open / partially paid

```text
resolver = commercial_collection_or_settlement
handlingMode = external_evidence_required
```

A new Payment Event or other admitted evidence must arrive.

### Refund due

```text
resolver = commercial_refund_resolution
handlingMode = external_evidence_required
```

### Collection unknown

```text
resolver = commercial_financial_reconciliation
handlingMode = external_evidence_required
```

because the problem is missing/insufficient collection evidence.

### Invariant gap

```text
resolver = commercial_financial_reconciliation
handlingMode = invariant_repair_required
```

because admitted evidence exists but internal invariants do not reconcile.

### Paid / cancelled / not required

```text
handlingMode = settled
```

No automatic collection action is invented.

## 10. Bed-readiness classification

Input:

`atlas.bed_readiness_continuation_v1(maintenance_object_id)`

The plan must compare:

- Continuation Candidate;
- native Maintenance Dependency state;
- current Task readiness;
- current Task bed-readiness gate metadata.

A target is **settled** when the Task already reflects the correct current readiness result.

Examples:

```text
dependency satisfied
+ two other blockers remain
+ Task is blocked by bed_weeding gate
→ settled
```

```text
all bed dependencies satisfied
+ Task gate already ready
→ settled
```

A target is **automatic_domain_reconcile** only when current domain projection is stale or inconsistent with current governed dependency/readiness truth.

Examples:

```text
readiness says blocked
+ Task currently open without bed gate
→ automatic_domain_reconcile
```

```text
readiness says ready
+ old bed gate still locks Task
→ automatic_domain_reconcile
```

The domain wrapper may then call only:

`atlas.reconcile_bed_weeding_gate_v1(task_id, as_of)`

Afterward it re-reads the plan.

Success means convergence, not necessarily `Task.status = open`.

A correctly blocked Task is a successful reconciliation outcome.

## 11. Reconciliation execution result

A bounded automatic wrapper returns a **Reconciliation Execution Result**.

V1 return shape:

```json
{
  "contractVersion": "reality_reconciliation_execution_v1",
  "source": {},
  "before": {},
  "attempts": [
    {
      "target": {},
      "adapterKey": "bed_readiness_reconcile_v1",
      "domainResult": {},
      "afterHandlingMode": "settled|automatic_domain_reconcile|not_applicable"
    }
  ],
  "after": {},
  "converged": true,
  "truthBoundary": {
    "boundedDomainAdapter": true,
    "noDynamicDispatch": true,
    "doesNotCreateAuthority": true,
    "doesNotCreateEvidence": true
  }
}
```

This is a synchronous return value, not persisted universal truth.

## 12. Idempotency and convergence

Reconciliation must prefer **convergence semantics** over “run once” semantics.

Running the same bounded reconciler repeatedly against unchanged canonical truth must produce no new domain truth after convergence.

For automatic bed readiness:

```text
first call
→ stale Task gate corrected

second call, unchanged evidence
→ zero required reconciliation / same settled plan
```

This is stronger than a request-id dedupe alone.

The owning domain may still use idempotency keys where it creates durable events.

## 13. Concurrency

Bounded automatic reconciliation must lock the smallest canonical identity needed to prevent conflicting convergence.

Preferred:

```text
advisory transaction lock:
domain + source/target identity
```

or existing row locks inside the domain resolver.

The universal layer must not take broad cross-domain locks.

## 14. Failure semantics

A failed automatic resolver call is not equivalent to an unresolved business fact.

Return/raise the exact domain error.

Do not silently downgrade:

```text
automatic failure
→ authority_required
```

or:

```text
automatic failure
→ settled
```

A failure means the bounded reconciliation attempt itself failed.

The underlying Continuation Candidate remains governed by its domain.

## 15. Relationship to triggers

Transactional domain triggers may already reconcile before a higher orchestration surface sees the candidate.

That is valid.

In that case the Reconciliation Plan should return `settled`.

The orchestration layer does not need to execute something merely because a Continuation Candidate historically existed.

This is important for Bed Readiness, where:

```text
Maintenance condition change
→ dependency sync trigger
→ dependency gate trigger
→ Task gate reconciliation
```

may converge transactionally.

The Plan is therefore also an **audit of current convergence**.

## 16. Relationship to Runtime Proof

Runtime Proof may inspect:

```text
Transition Receipt
→ Continuation Candidate
→ Reconciliation Plan
```

and classify:

- settled;
- authority required and explicitly contained;
- external evidence required and explicitly contained;
- invariant repair required;
- automatic reconciliation still outstanding;
- not applicable.

For qualified automatic adapters, Runtime Proof may optionally invoke the exact bounded reconciliation wrapper in a disposable/reference environment.

Production Runtime Proof should not automatically mutate merely because a plan says `automatic_domain_reconcile` unless the proof context separately authorizes execution.

## 17. Relationship to Principal

An `authority_required` plan may later feed Principal/manager/practitioner decision surfaces.

The Reconciliation Protocol does not choose which human surface receives it.

That belongs to existing Responsibility/Authority/Principal routing.

## 18. Relationship to connected sources

An `external_evidence_required` plan may later inform source refresh/connector orchestration.

It does not itself authorize polling, webhook creation, source access, or provider calls.

Connected Source custody remains independently governed.

## 19. First executable tranche

Introduce read-only:

- `atlas.reality_reconciliation_plan_normalize_v1(jsonb)`;
- `atlas.company_work_result_reconciliation_plan_v1(uuid)`;
- `atlas.commercial_financial_reconciliation_plan_v1(uuid)`;
- `atlas.bed_readiness_reconciliation_plan_v1(uuid)`.

Introduce one bounded automatic adapter:

- `atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamptz)`.

The automatic adapter:

1. reads the Bed Readiness Plan;
2. acquires a bounded advisory lock;
3. invokes `reconcile_bed_weeding_gate_v1` only for targets classified `automatic_domain_reconcile`;
4. re-reads the Plan;
5. returns before/attempts/after/converged;
6. creates no generic queue/history/dependency rows.

It is internal-only.

## 20. Qualification criteria

Clone proof must establish:

1. the universal normalizer cannot query or mutate domain truth;
2. caller metadata cannot weaken universal truth-boundary flags;
3. no generic resolver execution or dynamic SQL exists;
4. no generic reconciliation storage exists;
5. browser roles receive no execute grant;
6. unresolved Company Work acceptance is `authority_required`;
7. settled Company Work produces a settled plan and no automation;
8. open Commercial Financial Reality is `external_evidence_required`;
9. collection-unknown Commercial Reality remains evidence-required rather than fabricated;
10. paid Commercial Reality is settled;
11. a correctly blocked Bed Readiness target is settled even when the Task is still blocked;
12. a stale bed gate is classified automatic;
13. the bounded bed adapter converges it through the exact domain resolver;
14. repeated execution against unchanged truth is a no-op/converged;
15. the automatic adapter never calls Company Work or Commercial mutation functions.

## 21. Promotion boundary

Even after production qualification, v1 does **not** justify:

- a central scheduler;
- a generic work queue;
- a universal resolver registry;
- dynamic dispatch;
- automatic authority decisions;
- automatic connected-source writes;
- a cross-domain mutation transaction.

Only after multiple independent automatic-domain adapters prove the same orchestration contract should Atlas consider a higher-level runner.

## 22. Resulting architecture

```text
Reality
→ Transition
→ Transition Receipt
→ Continuation Candidate
→ Reconciliation Plan
    ├─ settled
    ├─ authority_required
    ├─ external_evidence_required
    ├─ invariant_repair_required
    └─ automatic_domain_reconcile
           ↓
      bounded domain adapter
           ↓
      owning-domain resolver
           ↓
      re-read Plan
           ↓
      converged / still outstanding
```

This is orchestration without a generic trigger engine.
