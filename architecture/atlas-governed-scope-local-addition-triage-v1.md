# Atlas Governed Scope Local Addition and Triage v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

A Person does not need a separate approval step to add a proposed Scope-definition change when the affected reality lies within both:

- reality independently visible to that Person; and
- reality independently carried by that Person as responsibility.

For this class of local contribution, the governing condition is the overlap of visibility and responsibility, not a title, user class, organization role, paid seat, or pre-approval by a broader participant.

Conceptually:

```text
Person P
  visibility includes affected reality X
  responsibility includes affected reality X
        ↓
P may append a proposed/local Scope-definition addition concerning X
        ↓
append-only event records what P added
```

The addition enters the living Scope history directly. It is not held in a pre-approval queue merely because P occupies a narrower aperture than another Person.

This rule governs institutional specification contribution. It does not make any factual proposition inside the addition objectively true. Factual claims used by the definition remain subject to the separate claim/evidence/adjudication system.

## 2. Visibility and responsibility remain independently established

This rule does not collapse visibility and responsibility into one dimension.

Atlas must still prove each independently before permitting the local addition:

```text
visible(X, P) = true
responsible(X, P) = true
```

If either is absent or unresolved, the local-addition path fails closed.

Responsibility still does not create visibility. Visibility still does not create responsibility.

The conjunction only governs this specific contribution path after both dimensions have independently resolved.

## 3. No rank primitive

Words such as `same`, `higher`, and `lower` in this contract describe comparative breadth of resolved visibility and responsibility over the relevant reality. They do not create account ranks or user classes.

Two People may therefore be:

- peers over one Scope intersection;
- one broader than the other over another Scope intersection;
- incomparable where neither Person's visibility-and-responsibility aperture contains the other's relevant aperture.

The comparison is contextual and scoped.

## 4. Peer and broader observability

When P appends a local addition, another Person Q may see that P did so when Q has sufficient independently resolved visibility and responsibility over the affected reality.

Conceptually:

```text
P adds event E concerning X

Q may inspect E when:
  Q visibility covers X
  and
  Q responsibility covers X
```

This includes:

- another Person with materially the same visibility-and-responsibility scope over X; and
- another Person whose visibility-and-responsibility scope validly contains the narrower affected scope.

The event must preserve author/provenance information so broader or peer participants can distinguish:

- who added it;
- when it was added;
- what portion of the Scope definition it affected;
- what prior definition state it changed;
- whether a later triage event changed its effective placement or treatment.

## 5. Broader-scope triage

A Person with both broader visibility and broader responsibility over the affected reality must be able to triage additions made from a narrower aperture.

Triage may include governed actions such as:

- re-route the addition to a more appropriate child Scope or operating boundary;
- move its operational placement without erasing its source history;
- split one lower-scope addition into multiple appropriately routed additions;
- consolidate duplicate lower-scope additions;
- redirect the addition toward the Person/Scope that should carry the resulting work or definition maintenance;
- mark an addition as needing clarification or factual support;
- reverse or supersede its current Scope-definition effect through a later event when the broader responsible context requires it.

Triage is not truth adjudication.

A broader Person may change how the institution routes or uses a lower-scope contribution without thereby proving or disproving factual claims contained in that contribution.

## 6. Triage must preserve the lower contribution

Broader triage does not delete the narrower Person's event.

The history should remain reconstructable as:

```text
E1: Person P added X here
E2: Person Q later rerouted X there
```

rather than rewriting E1 to make it appear that Q authored the original addition or that the original placement never existed.

This preserves institutional provenance, learning, and accountability without requiring every local addition to wait for approval.

## 7. Comparative breadth law

For purposes of this architecture, a broader triage relationship exists only when the broader Person's relevant aperture covers the narrower addition in both dimensions:

```text
visibility_Q covers visibility required for X
responsibility_Q covers responsibility represented by X
```

A Person who merely has broader visibility but not broader responsibility does not gain triage power from visibility alone.

A Person who merely has broader responsibility but lacks the required visibility likewise does not gain triage power.

Atlas must not infer breadth from titles such as owner, manager, supervisor, steward, or employee.

## 8. Cross-Ledger consequence

Because a Governed Scope may span multiple Ledgers, a broader Person may be broader over only one Ledger intersection.

Their triage ability is therefore limited to the portion for which both their visibility and responsibility cover the affected reality.

Triage cannot silently alter another Ledger's portion of the Scope merely because the Person is broader in one neighboring Ledger.

## 9. Relationship to claims and evidence

A Scope-definition addition may contain or reference factual claims.

Examples:

```text
Definition addition:
  include all active flower orders awaiting fulfillment

Factual claim:
  Order 123 is active
```

The first is institutional specification.
The second is a claim about reality.

Appending the definition addition does not establish the second claim as true. The claim/evidence/adjudication substrate remains responsible for determining Atlas's current institutional treatment of the factual proposition.

## 10. Relationship to action authority

This contract narrows the earlier assumption that every Scope-definition change requires a separate action-authority grant.

For local proposed additions concerning reality that is both visible to and carried by the Person, the conjunction of independently established visibility and responsibility is sufficient to permit the addition itself.

This does not imply that visibility plus responsibility universally authorizes every institutional action. It establishes one specific operational law for contributing to the living Scope definition.

Broader triage is likewise grounded in broader independently resolved visibility and responsibility over the affected reality, subject to the same custody and fail-closed rules.

Any materially different action class may still require its own governing contract.

## 11. Fail-closed cases

The local-addition path must fail closed when:

- visibility to the affected reality is absent or unresolved;
- responsibility for the affected reality is absent or unresolved;
- Scope membership needed to establish the overlap is unresolved;
- effective Ledger custody is unresolved;
- cross-Ledger breadth cannot be proven;
- the proposed event would affect reality outside the Person's proven visible-and-responsible aperture.

Failure to qualify for direct addition does not turn the proposal into falsehood. It means Atlas has not established the institutional standing needed to append that definition event through this path.

## 12. No pre-approval queue by default

Atlas must not force narrow participants into a manager-approval workflow merely because another Person has a broader aperture.

The intended operating pattern is:

```text
local person sees + carries reality
        ↓
adds what needs adding
        ↓
peer/broader people can see provenance
        ↓
broader visibility + responsibility may triage/reroute afterward
```

This allows local reality to enter the system at the point where it is known and carried, while preserving broader institutional coordination.

## 13. Historical reconstruction

Historical Scope reconstruction must preserve both the local addition and any later triage events.

A historical query should be able to answer:

- what the living Scope definition looked like immediately after the lower-scope addition;
- who could see/carry that affected reality at the time;
- whether and when a broader Person triaged it;
- what the effective definition became after that triage;
- which factual claims used by the definition were established, disputed, unresolved, or later corrected.

## 14. Explicit non-scope

This document does **not**:

- create a Scope table;
- create a Scope event table;
- define the executable containment algorithm for comparing aperture breadth;
- create a generic hierarchy or supervisor relation;
- create a manager approval queue;
- create a universal action-authority implication from visibility + responsibility;
- define factual truth by responsibility;
- alter production Worker Day or employee-seat behavior.

## 15. Next unresolved boundary

The next executable design boundary is how Atlas proves **comparative breadth** between two People's independently resolved visibility and responsibility across one living Scope, especially when their apertures overlap only partially or cross multiple Ledgers.

That comparison must be based on governed Scope containment/intersection rather than titles or organization-role strings.
