# Atlas Governed Scope Living Definition v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

A Governed Scope is a living institutional construct.

Atlas does not require immutable numbered Scope-definition versions as the primary ontology. Instead, one Scope has one current definition, and changes to that definition occur through durable, append-only definition events.

The current Scope definition is therefore derived from the ordered event history that established and changed it.

This preserves an operationally simple current object while retaining complete historical reconstructability.

## 2. Definition is not factual truth

A Scope definition answers:

> What bounded institutional reality does this Scope intend to refer to?

That is a specification question, not a factual claim about the world.

For example, a Scope definition may say:

- include subjects explicitly named by the Scope;
- include child Scope A;
- include subjects matching predicate P;
- exclude subjects matching rule E.

Those are components of the institution's chosen boundary definition.

Whether a particular real subject actually satisfies those components at a particular time is a separate truth-resolution problem governed by claims, evidence, contradiction, adjudication, custody, and effective institutional treatment.

Atlas must therefore distinguish:

```text
Scope definition
  = what boundary the institution currently intends to use

Scope membership claims/evidence
  = what current reality does or does not satisfy that boundary
```

A definition change cannot make an external proposition true merely by changing the Scope.

## 3. Living definition with append-only events

The preferred conceptual model is:

```text
Governed Scope S
  current definition = fold(definition events for S)
```

Definition events are append-only institutional actions.

Conceptual event classes may eventually include:

- create Scope;
- rename/relabel Scope;
- change description/purpose;
- add explicit inclusion rule;
- remove/retire explicit inclusion rule;
- add explicit exclusion rule;
- remove/retire explicit exclusion rule;
- add/remove child Scope relationship;
- add/change/retire semantic predicate;
- change effective dates or operating bounds;
- suspend Scope;
- reactivate Scope;
- retire Scope.

This list is architectural, not an executable enum.

## 4. Current definition is derived state

Atlas may materialize a convenient current-state projection for performance or application use, but the durable historical source must remain the event trail.

The current projection must be reproducible from the event history.

A current-state row, cache, or materialized view must not become an independent truth source capable of drifting away from the underlying events.

If reconstruction and current materialization disagree, Atlas must fail closed and surface the inconsistency rather than silently preferring the mutable projection.

## 5. Historical reconstruction

Because Scope can affect visibility, responsibility, and action authority, historical aperture reconstruction requires knowing what the Scope definition meant at the historical moment being queried.

Atlas must eventually be able to answer:

- what the Scope definition was at time T;
- which definition events were effective at T;
- what membership claims/evidence were available at T;
- what adjudications were effective at T;
- what Ledger custody was effective at T;
- what aperture consequence followed from that combined state.

Historical reconstruction must not use today's current Scope definition retroactively.

## 6. Definition events are governed actions, not claims

A definition event records that the institution changed its chosen Scope specification.

It does not assert that the subjects affected by the change are objectively members or non-members in reality.

For example:

```text
Definition event:
  add predicate "all active flower-fulfillment Company Work"
```

means the Scope now intends to use that predicate.

Whether Work W is active flower-fulfillment Company Work is evaluated separately through the relevant claim/evidence/reality system.

Likewise:

```text
Definition event:
  explicitly include subject X
```

means the institution has chosen an explicit inclusion rule naming X.

If independent governed evidence creates a conflicting exclusion/membership state, the conflict law still applies. The inclusion rule does not erase contrary evidence merely because it was intentionally added.

## 7. Direct local addition law

A Person does not need pre-approval merely to contribute a Scope-definition addition concerning reality that is both:

1. independently visible to that Person; and
2. independently carried by that Person as responsibility.

When both conditions hold over the affected reality, the Person may append the local addition directly to the living definition history.

This is not a general rule that `visibility + responsibility = all action authority`.

It is a specific law for local contribution to the living Scope definition.

The contribution remains attributable to the Person and does not become factual truth merely because it entered the institutional specification.

## 8. Peer observability and broader triage

The contributor's addition becomes part of the coordination reality visible under the separately governed definition-event exposure policy.

People whose independently resolved visibility and responsibility are equivalent to or broader than the contributor's relevant aperture over the affected reality may receive that event in the appropriate coordination surface.

A Person who is provably broader in **both** visibility and responsibility over the affected reality has broader-scope triage standing over the lower-scope addition.

`same`, `broader`, and `narrower` are contextual aperture comparisons, not user ranks.

The comparison law is defined in `atlas-aperture-comparative-breadth-v1.md`.

## 9. Triage is another event, not history rewriting

A broader participant may triage a lower-scope definition addition by appending later living-Scope events that:

- reroute it to another contained Scope;
- split it;
- consolidate it with another addition;
- clarify it;
- return it for narrower local handling;
- supersede it for current institutional specification.

The original event remains preserved.

Atlas must be able to reconstruct:

```text
Person A added this here.
Person B later rerouted it there.
```

Triage does not prove that Person A was factually wrong. It changes how the institution currently specifies the operating boundary.

## 10. Cross-Ledger consequence

A living Scope may span multiple Ledgers.

Changing the Scope definition may therefore change which Ledger-held reality the Scope attempts to compose, but it does not:

- transfer custody;
- create Ledger authority;
- create visibility;
- create responsibility;
- establish factual truth;
- collapse Ledgers into a super-Ledger.

Each aperture resolver must still intersect the resolved Scope with effective custody for the Ledger being queried.

Comparative breadth is likewise evaluated per relevant Ledger-custody intersection. Breadth in one Ledger does not compensate for missing visibility or responsibility in another.

## 11. Child Scope behavior

Child Scope relationships are part of the living definition.

Adding or removing a child Scope is therefore a Scope-definition event, not a factual assertion that every current member of the child is permanently a member of the parent.

The parent's effective membership follows the child's historically effective definition and membership resolution at the relevant time.

Child-Scope resolution must remain cycle-safe and fail closed on unresolved cycles or reconstruction gaps.

## 12. Predicate behavior

Predicates in a Scope definition are durable institutional specification.

Predicate evaluation is not itself truth creation.

A predicate may depend on claims, adjudicated state, effective custody, semantic classifications, or other governed reality, but only explicitly supported inputs may satisfy it.

Predicate engines must not fill unknown values by assumption merely to make a Scope resolve.

If a predicate's required input is unresolved, the dependent membership path must preserve that unresolved state rather than coercing it to included or excluded.

## 13. Revision semantics without immutable definition versions

Atlas may expose a human-readable revision counter or event sequence number for diagnostics, concurrency control, or caching, but that counter is not a separate immutable Scope-definition object.

The canonical identity remains the Scope itself plus its event history.

Conceptually:

```text
Scope S
  event 1: created
  event 2: predicate added
  event 3: child Scope added
  event 4: exclusion rule retired

current definition = fold(events 1..4)
```

A later change appends event 5. It does not create a separate `Scope S v2` ontology.

## 14. Concurrency and conflicting definition events

Executable design must eventually define how simultaneous or contradictory definition-change attempts are serialized and accepted.

Until that law is established, Atlas must not assume `last writer wins` merely from timestamp order.

The event trail must preserve:

- action/change;
- actor/source;
- effective time;
- recorded time;
- prior current-state basis or concurrency token;
- resulting current-definition state;
- provenance;
- any conflict/triage outcome.

Local contribution is direct when visibility + responsibility qualify. That directness does not justify silent overwrite when two contemporaneous events conflict.

## 15. Retirement

Retiring a Scope is a change to the institution's use of that Scope, not a deletion of history.

A retired Scope:

- remains reconstructable historically;
- retains its event history;
- retains historical membership/evidence/adjudications;
- should not silently disappear from historical aperture resolution;
- should not accept new ordinary definition mutations unless a governed reactivation path exists.

## 16. Relationship to claims and adjudication

The full conceptual chain is:

```text
living Scope definition
        ↓
asks what reality would qualify
        ↓
claims / evidence / custody / relations
        ↓
membership resolution
        ↓
conflict? -> adjudication / unresolved state
        ↓
effective Scope membership
        ↓
visibility / responsibility / action-authority intersections
```

The Scope definition controls the question. Claims and evidence help answer it. Adjudication governs institutional treatment when required. None of those layers should be collapsed.

## 17. Explicit non-scope

This document does **not**:

- create a Scope table;
- create a Scope event table;
- define executable event types;
- create mutation RPCs;
- create a manager approval queue;
- create supervisor relationships;
- create the comparative-breadth resolver;
- define triage destination validity;
- define optimistic concurrency or event-conflict handling;
- create membership schema;
- create claim migrations;
- create visibility admissions;
- create an aperture resolver;
- change Worker Day or any production behavior.

## 18. Governing consequence

The living Scope model has three independent layers:

```text
institutional specification
  living Scope definition + append-only events

reality evaluation
  claims + evidence + custody + adjudication

coordination
  direct local contribution + peer observability + broader-aperture triage
```

Those layers must not be collapsed into one generic permission, rank, or truth system.
