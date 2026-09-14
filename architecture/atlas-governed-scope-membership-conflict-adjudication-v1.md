# Atlas Governed Scope Membership Conflict Adjudication v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Scope membership conflict is itself governed institutional reality.

When Atlas has admissible evidence that both includes and excludes the same subject from the same Governed Scope, Atlas must not silently choose a winner by fixed precedence or hidden specificity rules.

Instead:

- the positive evidence remains recorded;
- the negative evidence remains recorded;
- effective membership becomes **unresolved**;
- any aperture behavior that depends on that membership fails closed;
- an authorized adjudication may later establish the effective membership state;
- the adjudication preserves the evidence that produced the conflict and may itself later be superseded by a new adjudication.

Conflict is not data corruption. It is a first-class truth state requiring governed resolution.

## 2. Why no implicit precedence

Hybrid Scope membership can be supported by:

- explicit subject inclusion;
- child Scope membership;
- governed semantic predicate membership;
- explicit exclusion.

Any of those may disagree.

Atlas must not embed an invisible rule such as:

```text
explicit exclusion > explicit inclusion > child Scope > predicate
```

or:

```text
more-specific evidence always wins
```

because those rules would convert disagreement into hidden software judgment. Atlas instead preserves the disagreement until an authorized institutional decision resolves it.

## 3. Membership states

Conceptually, the resolver should distinguish at least:

```text
included
excluded
unresolved
not_established
```

These are architectural states, not a final enum declaration.

### included
Admissible evidence supports membership and no unresolved negative evidence remains applicable, or a governing adjudication establishes inclusion.

### excluded
Admissible evidence supports exclusion and no unresolved positive evidence remains applicable, or a governing adjudication establishes exclusion.

### unresolved
Applicable positive and negative membership evidence conflict and no governing adjudication currently settles that conflict.

### not_established
No admissible evidence currently establishes either inclusion or exclusion.

`not_established` and `excluded` must not be conflated. Absence of membership proof is not the same as an affirmative exclusion.

## 4. Conflict detection

A conflict exists when, for one Scope and one candidate subject in the same evaluation context/time horizon:

- at least one applicable positive membership path resolves; and
- at least one applicable negative membership path resolves; and
- no current adjudication governs that conflict.

Positive membership paths may originate from explicit inclusion, child Scope resolution, or governed predicate resolution.

Negative membership paths may originate from explicit exclusion or future governed negative membership rules if explicitly established.

The conflict record must preserve enough evidence to reconstruct:

- which Scope was evaluated;
- which subject was evaluated;
- which Ledger custody intersection was relevant;
- which positive membership paths applied;
- which negative membership paths applied;
- which predicate/rule versions were involved;
- which child Scope revisions were involved;
- when the conflict became observable;
- which prior adjudication, if any, had been superseded or ceased to apply.

## 5. Fail-closed aperture consequence

Unresolved Scope membership cannot be used as positive evidence for visibility, responsibility, or authority.

Therefore:

```text
Scope membership = unresolved
        ↓
visibility through that Scope = no
responsibility through that Scope = no
authority through that Scope = no
```

This does not erase independent visibility, responsibility, or authority facts established through another Scope or another governed path.

The failure is local to the unresolved membership dependency.

## 6. Adjudication semantics

A Scope membership adjudication answers:

> Given these conflicting membership facts, what is the effective membership disposition for this subject in this Scope under this governed context?

Conceptually, an adjudication should preserve:

- Scope identity;
- subject identity;
- effective Ledger custody/custody evidence relevant to the decision;
- disposition such as `include` or `exclude`;
- evidence snapshot;
- rationale/basis;
- adjudicator identity/authority evidence;
- effective time;
- recorded time;
- provenance;
- optional superseded adjudication identity.

The adjudication does not delete, rewrite, or deactivate the evidence that produced the conflict. It governs the effective answer while the underlying evidence remains auditable.

## 7. Existing Atlas precedent

Atlas already contains several adjudication patterns that support this architecture:

- `identity_reconciliation_adjudications` preserves evidence snapshots and supports superseding prior adjudications;
- `institutional_custody_adjudications` records evidence-backed canonical custody decisions;
- `source_custody_adjudications` records disposition, evidence, rationale, adjudicator, and supersession;
- `company_operating_knowledge_adjudications` preserves evidence snapshots and explicit decision basis;
- `crop_relation_evidence_adjudications` records adjudication state, rationale, and resulting mutation separately from source evidence;
- `claim_records` and `claim_adjudication_relations` already distinguish claims from adjudication relationships.

These are precedents, not the Scope schema. No existing domain-specific adjudication table is silently repurposed as the cross-domain Scope adjudication primitive.

## 8. Immutability and supersession

The preferred semantic pattern is append-only decision history.

A later decision that changes the effective answer should supersede the earlier adjudication rather than mutate its historical decision in place.

This preserves the ability to answer:

- what evidence existed at the time;
- what decision was made;
- who was authorized to make it;
- what later changed;
- which decision is currently effective.

Historical aperture reconstruction must be able to evaluate the adjudication that was effective at the historical time being queried.

## 9. Authority remains independent

Conflict adjudication requires authority, but authority to adjudicate is not inferred from visibility or responsibility.

The future action contract must independently prove that the Person establishing the adjudication has authority over:

- the relevant Scope or institutional reality;
- the type of membership decision being established;
- and, for cross-Ledger Scopes, the Ledger intersections affected by that adjudication.

No legacy `owner`, `manager`, `employee`, route, seat, or organization membership label may substitute for that proof.

## 10. Cross-Ledger Scope consequence

A single Scope may contain reality from multiple Ledgers, but one membership adjudication cannot silently transfer custody or authority across Ledgers.

The effective subject membership may be composed at the Scope level, while each aperture resolver still intersects that result with canonical Ledger custody.

If the conflict itself concerns whether a subject belongs to one cross-Ledger Scope, the adjudication may settle Scope membership. It cannot settle or overwrite the subject's canonical Ledger custody unless a separate custody adjudication does so through the custody system.

## 11. No hidden conflict healing

Atlas must not automatically resolve a Scope membership conflict merely because:

- one evidence source is newer;
- one source came from an explicit inclusion;
- one source is more specific;
- one source is attached to a paid seat or active worker route;
- one source belongs to a Person with broader visibility;
- one source appears in a higher-level Scope;
- one predicate is evaluated later in time.

Any such tie-breaker would need to be an explicit governed rule or adjudication policy established separately.

## 12. Explainability requirement

For any candidate subject, Scope resolution should eventually be able to return an explanation shaped conceptually like:

```text
subject
scope
membership_state
positive_evidence[]
negative_evidence[]
current_adjudication?
effective_ledger_custody
resolved_at
```

This is an architectural shape only.

If membership is `unresolved`, the explanation must expose the disagreement rather than reducing it to a generic permission failure.

## 13. Migration law

Existing domain-local scope carriers may continue operating under their current semantics until a governed migration exists.

When migrating a legacy scope path:

1. identify its actual positive/negative membership semantics;
2. identify whether the legacy path contains hidden precedence;
3. preserve conflicting evidence rather than flattening it;
4. establish equivalent Scope membership/adjudication semantics;
5. prove the new resolver is no broader than the old exposure/authority boundary;
6. only then retire the compatibility path.

## 14. Explicit non-scope

This document does **not**:

- create a Scope table;
- create membership evidence tables;
- create a conflict table;
- create an adjudication table;
- define an executable disposition enum;
- define who may adjudicate Scope conflicts;
- create Person visibility admissions;
- create an aperture resolver;
- change any production permission or Worker Day behavior.

## 15. Next unresolved boundary

The conflict law is now settled.

The next architectural boundary is **Scope authorship and stewardship**:

> Who or what is permitted to establish, revise, retire, or adjudicate a Governed Scope definition itself?

Because Scope can affect visibility, responsibility, and authority across multiple Ledgers, its lifecycle authority cannot be inferred from ownership labels, responsibility, visibility, or simple participation. That authority law must be settled before executable Scope schema is created.
