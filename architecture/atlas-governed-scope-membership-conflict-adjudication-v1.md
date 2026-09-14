# Atlas Governed Scope Membership Conflict Adjudication v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Scope membership conflict is itself governed institutional reality.

When Atlas has admissible positive and negative **claims/evidence** about whether the same subject belongs to the same Governed Scope, Atlas must not silently choose a winner by fixed precedence, source rank, claimant status, or hidden specificity rules.

Instead:

- the positive claims/evidence remain recorded;
- the negative claims/evidence remain recorded;
- effective membership becomes **unresolved**;
- any aperture behavior that depends on that membership fails closed;
- a governed adjudication may later establish the current institutional membership disposition;
- the adjudication preserves the claims/evidence that produced the conflict and may itself later be superseded.

Conflict is not data corruption. It is a first-class unresolved institutional state requiring governed resolution.

A crucial distinction applies throughout this document:

> **An adjudication establishes Atlas's current institutional treatment of the membership question. It does not make the underlying proposition objectively true by fiat.**

## 2. Why no implicit precedence

Hybrid Scope membership can be supported by:

- explicit positive membership claims;
- child Scope membership evidence;
- governed semantic predicate evaluation;
- explicit negative membership claims.

Any of those may disagree.

Atlas must not embed an invisible rule such as:

```text
explicit exclusion > explicit inclusion > child Scope > predicate
```

or:

```text
more-specific evidence always wins
```

because those rules would convert disagreement into hidden software judgment. Atlas instead preserves the disagreement until the applicable institutional resolution process establishes a current disposition.

A claim from a Person with broad action authority does not automatically outrank another claim merely because of that Person's standing.

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
The currently effective institutional disposition treats the subject as a member of the Scope for the evaluated context/time.

That disposition may arise from unconflicted admissible support or from a governing adjudication after conflict. It remains provenance-bearing and revisable if later evidence changes the institutional position.

### excluded
The currently effective institutional disposition treats the subject as excluded from the Scope for the evaluated context/time.

### unresolved
Applicable positive and negative membership claims/evidence conflict and no current governed disposition settles that conflict for institutional use.

### not_established
No admissible basis currently establishes either inclusion or exclusion.

`not_established` and `excluded` must not be conflated. Absence of membership proof is not the same as an affirmative exclusion.

## 4. Conflict detection

A conflict exists when, for one Scope and one candidate subject in the same evaluation context/time horizon:

- at least one applicable positive membership path resolves; and
- at least one applicable negative membership path resolves; and
- no current governing adjudication/disposition settles that conflict.

Positive membership paths may originate from explicit inclusion claims, child Scope resolution, or governed predicate resolution.

Negative membership paths may originate from explicit exclusion claims or future governed negative membership rules if explicitly established.

The conflict record/explanation must preserve enough evidence to reconstruct:

- which Scope was evaluated;
- which subject was evaluated;
- which Ledger custody intersection was relevant;
- which positive membership paths applied;
- which negative membership paths applied;
- which claims and evidence supported those paths;
- which predicate/rule versions were involved;
- which child Scope revisions were involved;
- when the conflict became observable;
- which prior adjudication, if any, had been superseded or ceased to apply.

## 5. Fail-closed aperture consequence

Unresolved Scope membership cannot be used as positive evidence for visibility, responsibility, or action authority.

Therefore:

```text
Scope membership = unresolved
        ↓
visibility through that Scope = no
responsibility through that Scope = no
action authority through that Scope = no
```

This does not erase independent visibility, responsibility, or action-authority facts established through another Scope or another governed path.

The failure is local to the unresolved membership dependency.

## 6. Adjudication semantics

A Scope membership adjudication answers:

> Given these competing membership claims/evidence, what effective membership disposition should Atlas rely upon for institutional use in this governed context?

Conceptually, an adjudication should preserve:

- Scope identity;
- subject identity;
- effective Ledger custody/custody evidence relevant to the decision;
- disposition such as `include` or `exclude`;
- evidence/claim snapshot;
- rationale/basis;
- actor identity and action-authority evidence for recording the institutional decision;
- effective time;
- recorded time;
- provenance;
- optional superseded adjudication identity.

The adjudication does not delete, rewrite, or deactivate the claims/evidence that produced the conflict. It governs Atlas's current effective answer while the underlying history remains auditable.

The adjudicator may be mistaken. New evidence may justify a later superseding disposition.

## 7. Existing Atlas precedent

Atlas already contains several adjudication patterns that support this architecture:

- `identity_reconciliation_adjudications` preserves evidence snapshots and supports superseding prior adjudications;
- `institutional_custody_adjudications` records evidence-backed canonical custody decisions;
- `source_custody_adjudications` records disposition, evidence, rationale, adjudicator, and supersession;
- `company_operating_knowledge_adjudications` preserves evidence snapshots and explicit decision basis;
- `crop_relation_evidence_adjudications` records adjudication state, rationale, and resulting mutation separately from source evidence;
- `claim_records`, `claim_evidence_links`, and `claim_adjudication_relations` already distinguish propositions, evidence, contradiction/correction, and adjudication state.

These are precedents, not the Scope schema. No existing domain-specific adjudication table is silently repurposed as the cross-domain Scope adjudication primitive.

## 8. Immutability and supersession

The preferred semantic pattern is append-only decision history.

A later decision that changes the effective institutional answer should supersede the earlier adjudication rather than mutate its historical decision in place.

This preserves the ability to answer:

- what was claimed;
- what evidence existed at the time;
- what conflict existed;
- what institutional disposition was adopted;
- who recorded that decision and under what action authority;
- what later changed;
- which disposition is currently effective.

Historical aperture reconstruction must be able to evaluate the disposition that was effective at the historical time being queried.

## 9. Action authority remains independent and downstream

Authority in this architecture is **action authority**, not truth authority.

The action contract for recording/adopting an adjudication must independently prove that the Person may take that institutional action over the relevant governed extent.

That proves only that the Person may establish the institution's current operational disposition. It does **not** prove that the proposition they chose is objectively true.

No legacy `owner`, `manager`, `employee`, route, seat, organization membership label, visibility grant, responsibility allocation, or claim-source label may substitute for the required action-authority proof.

Likewise, lack of action authority to adjudicate does not make a Person's factual claim inadmissible as a claim or evidence. Claim provenance and action authority answer different questions.

## 10. Cross-Ledger Scope consequence

A single Scope may contain reality from multiple Ledgers, but one membership adjudication cannot silently transfer custody or action authority across Ledgers.

The effective subject membership may be composed at the Scope level, while each aperture resolver still intersects that result with canonical Ledger custody.

If the conflict concerns whether a subject belongs to one cross-Ledger Scope, the adjudication may establish Atlas's current Scope-membership disposition. It cannot settle or overwrite the subject's canonical Ledger custody unless a separate custody adjudication does so through the custody system.

## 11. No hidden conflict healing

Atlas must not automatically resolve a Scope membership conflict merely because:

- one claim/evidence source is newer;
- one source came from an explicit inclusion;
- one source is more specific;
- one source is attached to a paid seat or active worker route;
- one claimant has broader visibility;
- one claimant has broader action authority;
- one source appears in a higher-level Scope;
- one predicate is evaluated later in time.

Any such tie-breaker would need to be an explicit governed resolution rule established separately and would itself need provenance.

## 12. Explainability requirement

For any candidate subject, Scope resolution should eventually be able to return an explanation shaped conceptually like:

```text
subject
scope
membership_state
positive_claims_evidence[]
negative_claims_evidence[]
current_adjudication?
effective_ledger_custody
resolved_at
```

This is an architectural shape only.

If membership is `unresolved`, the explanation must expose the disagreement rather than reducing it to a generic permission failure.

## 13. Migration law

Existing domain-local scope carriers may continue operating under their current semantics until a governed migration exists.

When migrating a legacy scope path:

1. identify its actual membership assertions/rules;
2. identify its evidence and provenance;
3. identify whether the legacy path contains hidden precedence or truth-by-role behavior;
4. preserve conflicting claims/evidence rather than flattening them;
5. establish equivalent effective Scope membership/adjudication semantics;
6. prove the new resolver is no broader than the old exposure/action boundary;
7. only then retire the compatibility path.

## 14. Explicit non-scope

This document does **not**:

- create a Scope table;
- create membership claim/evidence tables;
- create a conflict table;
- create an adjudication table;
- define an executable disposition enum;
- define the action-authority contract for adopting an adjudication;
- create Person visibility admissions;
- create an aperture resolver;
- change any production permission or Worker Day behavior.

## 15. Governing companion contract

The claims/evidence/truth distinction in `atlas-claims-evidence-effective-reality-v1.md` governs this document.

Where any earlier architecture wording suggests that an authorized Person can make a factual proposition true merely by establishing or adjudicating it, that wording is superseded.

## 16. Next unresolved boundary

The membership-conflict law is now settled under the corrected claims model.

The next architectural boundary is **Scope definition and revision adoption**:

> Which parts of a Governed Scope are institutional specification rather than factual claims, how are proposed revisions represented, and what governed action turns one proposed definition into the currently adopted Scope definition?

That question is about institutional action over a construct, not about granting a Person the power to manufacture factual truth. It must be settled before executable Scope schema is created.
