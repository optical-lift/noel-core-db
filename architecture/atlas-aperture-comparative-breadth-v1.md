# Atlas Comparative Aperture Breadth v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Atlas does not model `higher`, `lower`, `manager`, or `supervisor` as user classes.

For the narrow purpose of observing and triaging living Scope-definition additions, comparative standing is derived from **provable containment of independently resolved visibility and responsibility over the affected reality**.

The comparison is contextual and partial. It is not a global rank and it is not calculated from a numeric score, title, seat, organization role, or amount of data/work.

The governing rule is:

> Person B is broader than Person A for one affected Scope-definition addition only when B's independently resolved visibility contains A's relevant visibility over the affected reality **and** B's independently resolved responsibility contains A's relevant responsibility over the affected reality, with both dimensions strictly broader for triage standing.

If containment cannot be proved, Atlas does not infer hierarchy.

## 2. Comparison is over affected reality, not the whole Person

The same two people may compare differently in different contexts.

Example:

- Person A may be broader than Person B for Elm nursery reality;
- Person B may be broader than Person A for Feast Guild buyer fulfillment;
- they may be peers for one shared Scope;
- they may be incomparable for another cross-Ledger operating boundary.

Atlas must never persist a global conclusion such as:

```text
A > B
```

The only meaningful form is closer to:

```text
compare_aperture_breadth(A, B, affected_scope_or_reality, context, as_of)
```

This is architectural notation only, not an API declaration.

## 3. Compare visibility and responsibility independently

Let, for one affected reality `X` and evaluation context/time:

```text
V(P, X) = the portion of X independently visible to Person P
R(P, X) = the portion of X independently carried by Person P as responsibility
```

Visibility remains governed by semantic exposure policy + Person-specific predicate-envelope admission.

Responsibility remains governed by explicit standing/current responsibility substrates.

Neither dimension is derived from the other.

Comparative standing then evaluates containment independently:

```text
V(A, X) ⊆ V(B, X)
R(A, X) ⊆ R(B, X)
```

No amount of extra visibility can compensate for missing responsibility, and no amount of extra responsibility can compensate for missing visibility.

## 4. Containment, not cardinality

`Broader` does not mean that a Person can see or carry more rows in raw count.

A Person with visibility to 1,000 unrelated records is not broader for an Elm nursery addition than a Person with visibility to the exact nursery Scope if the former lacks the relevant containment relationship.

Likewise, responsibility for many unrelated work items does not make a Person broader over the affected reality.

Containment must be semantic and scoped:

- direct Scope containment;
- child-Scope containment;
- governed predicate coverage;
- explicit subject coverage;
- historically effective living-Scope definition;
- effective custody intersection;
- other future governed containment proofs explicitly established for that domain.

Atlas must not use record counts, job titles, organization chart position, or route names as a proxy for containment.

## 5. Comparison states

Conceptually, comparative aperture breadth may resolve to:

```text
equal
b_broader
b_narrower
overlap
crossed
incomparable
unresolved
```

These labels are architectural states, not a final enum.

### equal

Both dimensions are mutually containing over the affected reality:

```text
V(A,X) = V(B,X)
R(A,X) = R(B,X)
```

Equality is contextual. It does not make the two people globally equivalent.

### b_broader

B strictly contains A in **both** relevant dimensions:

```text
V(A,X) ⊂ V(B,X)
R(A,X) ⊂ R(B,X)
```

This is the relation that guarantees broader-scope triage standing under the living Scope-definition rule.

### b_narrower

The inverse of `b_broader`.

### overlap

The people share some relevant visibility and responsibility, but neither pair of dimension sets fully contains the other.

Overlap does not establish triage standing.

### crossed

One Person is broader in visibility while the other is broader in responsibility, or one dimension is equal while the other points the opposite way.

Examples:

```text
V(A,X) ⊂ V(B,X)
R(B,X) ⊂ R(A,X)
```

or:

```text
V(A,X) = V(B,X)
R(A,X) ⊂ R(B,X)
```

when the requested action specifically requires strict breadth in both dimensions.

`crossed` is intentionally not flattened into `broader`.

### incomparable

The scopes do not have a provable containment/overlap relation sufficient for this comparison.

### unresolved

A required Scope membership, custody, visibility admission, responsibility relation, or historical definition is itself unresolved.

Unresolved comparison fails closed for triage.

## 6. Event observability law

A local Scope-definition addition is observable to another Person through an explicit definition-event exposure rule when that Person has independently valid visibility and responsibility at least equivalent to the contributor's relevant aperture over the affected reality.

Conceptually:

```text
A adds event E concerning X

B may receive E in the relevant coordination surface when:
  V(A,X) ⊆ V(B,X)
  and
  R(A,X) ⊆ R(B,X)
```

This does **not** mean responsibility itself grants visibility to E.

The visibility of the definition event remains a separately governed exposure result whose predicate may require the responsibility-containment condition. Responsibility is a matching condition, not the visibility source.

A Person with visibility to X but no corresponding responsibility does not gain this coordination feed merely by being able to inspect X.

A Person with responsibility for X but insufficient visibility does not receive the event either.

## 7. Triage law

A Person has guaranteed broader-scope triage standing over another Person's local Scope-definition addition only when the triager is strictly broader in **both** relevant dimensions over the affected reality:

```text
V(actor,X) ⊂ V(triager,X)
R(actor,X) ⊂ R(triager,X)
```

The broader Person may then, subject to the living-Scope event protocol:

- reroute the addition to another contained Scope;
- split one addition across contained Scopes;
- consolidate duplicate lower-scope additions;
- clarify the institutional specification;
- supersede a lower-scope definition event;
- return an addition to a narrower Scope for further local handling.

Every triage event preserves the original contributor, original event, and later triage provenance.

Triage is not deletion and is not a declaration that the original contributor was factually wrong.

## 8. Equality does not create supervisory standing

A Person with exactly equivalent relevant visibility and responsibility is a peer for this comparison.

That peer can see the addition under the event-observability rule and, where they independently satisfy the direct-addition law, can contribute additional living-Scope events concerning the same reality.

Equality alone does not establish the guaranteed broader-scope triage relation described above.

If peer contributions conflict, the normal living-Scope event and claim/evidence conflict laws apply. Atlas must not silently invent a supervisor between peers.

## 9. Cross-Ledger comparison

For a Scope spanning multiple Ledgers, containment must be proved per effective Ledger-custody intersection.

Example:

```text
Scope X
  Elm intersection
  Feast Guild intersection
```

If A's relevant addition concerns both intersections, B is broader only if the required visibility/responsibility containment is proved for both.

A broad Elm aperture cannot compensate for missing Feast Guild visibility or responsibility.

Likewise, root authority in one Ledger is not a substitute for the missing visibility/responsibility dimensions in another Ledger.

## 10. Historical comparison

Comparative breadth is time-sensitive.

Historical reconstruction must use:

- the living Scope definition effective at the historical time;
- visibility admissions/policies effective then;
- responsibility relationships effective then;
- effective Ledger custody then;
- adjudications effective then.

Atlas must not use today's aperture to justify a historical triage event retroactively.

## 11. No inferred chain of command

Comparative breadth may produce local coordination structure, but Atlas must not materialize that as a universal chain of command.

For example:

```text
A < B for Elm nursery
B < C for Elm production
```

does not automatically prove:

```text
A < C for every Elm or Feast Guild context
```

Transitivity may be used only where the same affected reality, same semantic dimensions, same custody intersections, and valid containment proofs make it true.

No generic `reports_to`, `manager_id`, `supervisor_id`, or global seniority primitive is established by this architecture.

## 12. Fail-closed conditions

Atlas must not claim broader triage standing if any required proof depends on:

- unresolved Scope membership;
- unresolved custody;
- stale compatibility role labels;
- organization membership alone;
- position title alone;
- employee seat class;
- route name;
- record count;
- responsibility inferred from plan placement;
- visibility inferred from responsibility;
- responsibility inferred from visibility;
- an unproven semantic information-class hierarchy;
- an unproven cross-Ledger equivalence.

## 13. Existing-schema audit

The current database contains no reliable global seniority/level primitive and none should be invented from compatibility fields.

Relevant existing facts reinforce a containment model:

- `semantic_exposure_policies` is multi-dimensional across purpose, information class, semantic kind, predicate, source domain/kind, modality, and adjudication state;
- current member exposure grants are compatibility-scoped and do not define an Atlas-wide visibility ladder;
- `organization_responsibility_scopes` carries typed domain scopes but no universal numeric breadth;
- `work_allocations` carries current work responsibility for exact Company Work objects;
- `principal_authority_allocations` is separate action-authority machinery and is not a breadth measure;
- Ledger relationships and effective custody establish institutional topology/custody, not human rank.

Therefore the generic future comparison must operate on resolved semantic sets/Scopes, not existing titles or numeric levels.

## 14. Explicit non-scope

This document does **not**:

- create a comparative-breadth table;
- create a hierarchy table;
- create supervisor/manager relationships;
- create a numeric aperture score;
- create a Scope table or Scope event table;
- create the visibility-admission substrate;
- create a generic responsibility substrate;
- create a triage RPC;
- change Worker Day behavior;
- change production permissions.

## 15. Next unresolved boundary

The comparison law now establishes who is a contextual peer and who is provably broader for a specific living-Scope addition.

The next architectural boundary is **triage destination validity**:

> When a broader Person reroutes a lower-scope addition, what must be true of the destination Scope/reality so the reroute is legitimate rather than merely moving the item somewhere the triager can see?

At minimum, the destination cannot exceed the triager's own independently resolved visibility/responsibility aperture, but the exact destination law remains deliberately unsettled here.
