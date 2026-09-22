# Atlas Reality Continuation Protocol v1

**Status:** production-live read-only architecture contract  
**Date:** 2026-09-22  
**Parent law:** `architecture/atlas-reality-transition-protocol-v1.md`  
**Depends on:** production-live Reality Transition Receipt v1  
**Executable authority:** none in the universal layer

## 1. Purpose

Reality Transition Receipt v1 answers:

> What consequential transition happened, what evidence resolved it, and what consequence is now effective?

That still leaves a separate architectural question:

> Because this reality changed, what other governed reality must now be reconsidered?

Atlas already performs this second operation in many domain-local ways:

- a Company Work result may need adjudication or completion/Ledger projection;
- a Commercial Financial Position may need collection, refund, or reconciliation reconsideration;
- a maintained bed may satisfy one prerequisite and cause a dependent planting-readiness resolver to recompute;
- a completed prerequisite Task may reopen a serving Task;
- task terminality may close leases, advance queues, refresh projections, or unlock downstream work;
- later Actuals may change consequence state or learning evidence.

Those mechanisms are real, but they are not yet named as one platform law.

The goal is **not** to replace those domain laws with a universal trigger engine.

The goal is to make their dependency semantics explicit enough that Atlas can explain, prove, and eventually orchestrate lawful reconsideration without becoming the authority that decides the downstream result.

## 2. Core law

> **A changed reality may create a duty to reconsider another governed reality. Reconsideration is not itself the downstream transition.**

Conceptually:

```text
effective transition / changed source reality
    ↓
continuation discovery
    ↓
one or more reconsideration targets
    ↓
owning-domain resolver
    ↓
changed / unchanged / still blocked / not applicable
```

The universal layer may identify that a resolver should reconsider.

It may not predict, manufacture, or force the resolver's outcome.

## 3. Two kinds of continuation must remain distinct

### 3.1 Local continuation

The current transition has not yet reached a resolved consequence.

Examples:

```text
Work result reported
→ acceptance missing
→ reconsider Company Work result adjudication
```

```text
Commercial order has unknown collection coverage
→ reconsider financial reconciliation
```

This is the meaning already carried by `Reality Transition Receipt.continuation`.

It answers:

> What remains unresolved inside this transition?

### 3.2 Dependent continuation

The current transition may be completely resolved, but its consequence changes the inputs of another governed resolver.

Example:

```text
Bed A becomes maintained
→ one maintenance dependency becomes satisfied
→ Planting Task readiness must be recomputed
→ Task may still remain blocked by Beds B and C
```

It answers:

> What other reality may now need reconsideration because this one changed?

These are different laws.

Do not overload the existing Receipt `continuation.reconsider` field to mean both.

## 4. Production proof for partial dependency

Production currently contains:

- 47 Maintenance Dependencies;
- 19 satisfied dependencies;
- 8 active unsatisfied dependencies;
- 6 `bed_preparation_required` Organization Ledger consequences.

A live specimen proves the critical shape:

```text
Maintenance Object A
condition = maintained
    ↓
Dependency A
satisfied_at = established
    ↓
Dependent planting Task
still blocked
    ↓
Readiness resolver
finds two other unsatisfied bed dependencies
```

Therefore:

```text
one source transition
≠ downstream target resolved

one dependency satisfied
≠ all dependencies satisfied

reconsideration requested
≠ downstream state changed
```

Continuation must support:

- one source → many targets;
- many sources → one target;
- partial satisfaction;
- repeated reconsideration;
- no-op reconsideration;
- reopened dependencies;
- target disappearance / terminality.

## 5. Universal object: Continuation Candidate

The platform-level read object is a **Continuation Candidate**.

It is not a Task, Event, command, queue item, webhook, or trigger.

A candidate states:

> This source change is sufficient reason for this exact owning-domain resolver to reconsider this exact target.

Minimum shape:

```json
{
  "contractVersion": "reality_continuation_v1",
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
      "reason": {
        "kind": "...",
        "basisRefs": []
      },
      "disposition": "reconsider|blocked|settled|not_applicable",
      "current": {},
      "blockers": []
    }
  ],
  "truthBoundary": {
    "readOnly": true,
    "doesNotInvokeResolver": true,
    "doesNotCreateDependency": true,
    "doesNotDetermineOutcome": true,
    "doesNotGrantAuthority": true
  },
  "provenance": {}
}
```

The common grammar exists to explain dependency movement.

The domain still owns:

- dependency existence;
- target identity;
- resolver authority;
- target state;
- whether anything actually changes.

## 6. Resolver identity is descriptive, not executable authority

A Continuation Candidate names a resolver key/version.

That does **not** mean the universal layer may execute an arbitrary function by name.

Forbidden:

```text
resolver.key
→ dynamic SQL
→ call anything
```

Instead, each domain may expose a bounded adapter or governed command that knows its own resolver.

The resolver key is useful for:

- explanation;
- Runtime Proof;
- deterministic comparison;
- audit;
- future orchestration through an allowlisted domain membrane.

It is not a generic RPC registry.

## 7. Continuation disposition

Each target uses one of four dispositions.

### reconsider

The source change is relevant and the downstream resolver should be reevaluated.

This does not say the result will change.

### blocked

Reconsideration is meaningful, but known prerequisite evidence prevents a complete downstream resolution.

### settled

The dependency relationship exists, but current downstream state is already resolved for this source condition and no further reconsideration is presently necessary.

### not_applicable

The historical dependency/reference may exist, but current semantics make the resolver inapplicable.

This is important for retired Tasks, superseded models, changed operation classes, closed obligations, etc.

## 8. No universal dependency table yet

Do **not** introduce a generic table such as:

- `reality_dependencies`;
- `continuation_edges`;
- `reconsideration_queue`;
- `transition_dependencies`.

Atlas already has native dependency structures in domains that know what those dependencies mean.

Examples:

- Maintenance Dependencies;
- Task prerequisites;
- Responsibility/Authority relations;
- Commercial evidence/Financial Position;
- Implementation model references;
- source/evidence relationships.

A generic edge table would lose semantics unless it merely duplicated those authorities.

V1 therefore standardizes **read-only composition**, not dependency persistence.

## 9. Company Work qualification

Company Work proves local continuation.

```text
Execution Result
→ no acceptance
→ local continuation:
   reconsider company_work_result_adjudication
```

or:

```text
accepted Result
→ Work not yet completed / Ledger consequence absent
→ local continuation:
   reconsider company_work_completion_projection
```

Once accepted completion and Ledger consequence are established:

```text
local continuation = settled
```

Company Work does not yet justify a universal dependent continuation after completion unless a separate governed downstream dependency can be identified.

That restraint is intentional.

## 10. Commercial qualification

Commercial Financial Reality proves derived-state continuation.

```text
financial_state = open | partially_paid
→ reconsider commercial_collection_or_settlement
```

```text
financial_state = refund_due
→ reconsider commercial_refund_resolution
```

```text
financial_state = collection_unknown | invariant_gap
→ reconsider commercial_financial_reconciliation
```

A paid order with no unresolved financial condition is locally settled.

Fulfillment remains a separate axis and must not be silently promoted into financial continuation evidence.

## 11. Dependency-release qualification

Bed readiness proves dependent continuation.

Source:

```text
Maintenance Object condition changes
```

Native dependency:

```text
maintenance_dependencies
```

Downstream resolver:

```text
task_bed_weeding_readiness_v1(task_id)
```

Behavior:

- maintained source may satisfy one dependency;
- non-maintained source may reopen it;
- dependency mutation triggers the existing domain-specific readiness reconciliation;
- the dependent Task can remain blocked because other dependencies remain unsatisfied.

This is exactly the Continuation law:

> changed source reality causes a downstream resolver to reconsider; the downstream domain owns the answer.

## 12. Reopening is first-class

Continuation is not monotonic.

A dependency may move:

```text
unsatisfied
→ satisfied
→ unsatisfied again
```

if the source reality changes lawfully.

Therefore Continuation cannot mean “unlock once.”

It means:

> recompute the downstream reality from current governed evidence.

This matters for:

- physical readiness;
- resource availability;
- financial settlement after refund/reversal;
- Responsibility/Authority changes;
- Personal/Household rhythms;
- model/proof staleness.

## 13. No-op reconsideration is legitimate

A resolver may run and conclude:

> nothing changes.

Example:

One bed becomes maintained, but two other beds still block planting.

That is still a successful reconsideration.

The platform must not create fake state movement merely to prove Continuation occurred.

## 14. Staleness

A source transition can make a prior projection stale without directly invalidating its underlying truth.

Examples:

- a new payment event makes the previous Financial Position projection stale;
- a reopened dependency makes prior execution-readiness projection stale;
- a new accepted Work result may make manager/accountability projections stale;
- a new model version may stale Runtime Proof.

Staleness means:

> recompute before relying on this projection again.

It does not mean:

> delete or rewrite historical evidence.

## 15. Continuation versus side effects

The platform must distinguish:

### Domain-owned immediate consequence

A transactionally necessary consequence belonging to the same governing law.

Example:

accepted Company Work completion → canonical Organization Ledger completion consequence.

### Dependent continuation

A different resolver now has reason to reconsider.

Example:

maintenance condition → dependency state → planting readiness.

### Projection refresh

A read model may need to recompute because source state changed.

### Learning opportunity

New Actual evidence may support a learning proposal.

These must not be bundled into one generic “side effects” list.

## 16. Relationship to database triggers

Existing triggers remain valid where they enforce local transactional invariants.

The Continuation Protocol does not require replacing them.

Instead it gives Atlas a way to describe what they mean.

A trigger is acceptable when:

- source and target are within a bounded governed law;
- the target mutation is transactionally required;
- the trigger cannot invent unrelated authority;
- the behavior is idempotent or safely repeatable;
- provenance remains reconstructible.

A trigger is suspect when it acts as an invisible cross-domain orchestration bus.

## 17. Relationship to Reality Transition Receipt

Reality Transition Receipt remains:

> What changed?

Continuation becomes:

> What should now be reconsidered because of that change?

Preferred composition:

```text
Reality Transition Receipt
    ↓
domain continuation adapter
    ↓
Reality Continuation Candidate(s)
    ↓
owning-domain resolver
```

The receipt alone does not discover every dependency.

The domain adapter knows where lawful dependency semantics live.

## 18. Relationship to Semantic Interaction

Semantic Interaction remains above mutation:

```text
visible governed reality
→ SemanticTarget
→ ActionResolver
→ owning-domain command
```

After the command:

```text
canonical consequence
→ Transition Receipt
→ Continuation Candidate(s)
```

Continuation does not enlarge the user's action universe.

## 19. Relationship to Runtime Proof

Runtime Proof can now distinguish two questions:

1. Did the source transition resolve correctly?
2. Were all required downstream reconsiderations accounted for?

A Runtime Proof checkpoint may inspect Continuation Candidates and classify:

- accounted for;
- blocked with explicit evidence;
- settled;
- missing resolver;
- stale projection;
- uncontained unresolved continuation.

It must not execute arbitrary resolver keys.

## 20. Relationship to Intelligence

Intelligence may:

- suggest possible continuation relationships;
- explain why a known candidate matters;
- detect likely missing dependency coverage;
- compare continuation patterns across domains.

Intelligence may not:

- create a canonical dependency merely because two things correlate;
- execute a resolver;
- declare a target changed;
- suppress an unresolved candidate;
- convert a learned pattern into accepted dependency law.

## 21. First executable contract

The first executable tranche should remain read-only.

Introduce:

- `atlas.reality_continuation_normalize_v1(jsonb)`;
- `atlas.company_work_result_continuation_v1(uuid)`;
- `atlas.commercial_financial_continuation_v1(uuid)`;
- `atlas.bed_readiness_continuation_v1(uuid)`.

The first two adapt the already-live Transition Receipt/local continuation semantics.

The third reads the native Maintenance Dependency graph and the existing readiness resolver.

No function invokes a downstream resolver to mutate state.

The bed-readiness adapter may read `task_bed_weeding_readiness_v1` because that function is itself a read-only readiness projection.

## 22. Qualification criteria

The tranche is qualified only if clone proof establishes:

1. no generic continuation/dependency storage exists;
2. all universal functions are read-only;
3. browser roles receive no cross-domain continuation authority;
4. Company Work unresolved Result maps to an adjudication continuation without accepting it;
5. settled Company Work produces no fake downstream change;
6. Commercial open/refund/unknown states preserve their distinct resolver needs;
7. fulfillment does not become financial continuation evidence;
8. one maintained bed can be settled while its dependent Task remains blocked by other bed dependencies;
9. reopened bed conditions can surface reconsideration again;
10. domain resolver outcomes are never inferred by the universal normalizer.

## 23. Promotion boundary

Even after qualification, V1 is an explanation/proof membrane.

It does not create:

- a scheduler;
- an event bus;
- a background job queue;
- a universal dependency graph;
- generic resolver execution;
- automatic AI orchestration.

Those may only be considered later if repeated domain evidence proves a further abstraction is necessary.

## 24. Resulting architecture

```text
Reality
→ lawful domain transition
→ canonical consequence
→ Reality Transition Receipt
→ Continuation discovery
→ Continuation Candidate(s)
→ owning-domain reconsideration
→ changed / unchanged / blocked / inapplicable
→ new Transition Receipt when reality actually changes
```

This gives Atlas recursive coherence without creating a universal mutation engine.
## 25. Production receipt — 2026-09-22

Reality Continuation v1 crossed its first production boundary on September 22, 2026.

Canonical source lineage:

- architecture/candidate PR #1135 → merge `5d277068f0dd6b79a012c1ca96da0a1c9879131d`;
- generated package `20260922143035` was retired after clone-only fixture failure; never released;
- fixture repair PR #1139 → merge `94ea797ec2b672511747b6ac21b9adc83f6c69c0`;
- generated package `20260922144256` was retired before release after source review found caller truth-boundary values could override universal flags;
- fail-closed hardening PR #1143 → merge `270f01d341c3b58ca656823dcd5ef4d1b7ec83f5`;
- final generated migration `20260922145102_atlas_reality_continuation_protocol_v1.sql`;
- final generated package PR #1145 → merge `6c94364eda0ed3be5435d4e21fb7305fa32bf408`;
- Production Schema Clone Validation run `35743240860` → PASS;
- governed production release request #1147;
- Production Database Release run `35747655264` → PASS.

Production now exposes internal-only:

- `atlas.reality_continuation_normalize_v1(jsonb)`;
- `atlas.company_work_result_continuation_v1(uuid)`;
- `atlas.commercial_financial_continuation_v1(uuid)`;
- `atlas.bed_readiness_continuation_v1(uuid)`.

Direct production verification confirms:

- no `anon` or `authenticated` execute grant exists on any of the four functions;
- caller attempts to weaken universal truth-boundary flags are normalized back to the enforced read-only/no-authority values;
- settled Company Work produces zero fabricated continuation targets;
- unresolved Commercial Financial Reality produces exact blocked reconsideration targets;
- one satisfied bed-readiness dependency may coexist with a still-blocked downstream Task because other dependencies remain unresolved.

This is sufficient to promote the Continuation grammar as production-live **read-only cross-domain infrastructure**.

It still does not justify a generic dependency store, workflow engine, event bus, resolver registry, scheduler, or universal mutation layer.

