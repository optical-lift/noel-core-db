# Atlas Responsibility Origin Constitutional Reconciliation v1

## Status

Architecture contract only. No schema, migration, RPC, production mutation, browser permission, or application runtime change is introduced by this document.

**Date:** 2026-09-15

## Purpose

Reconcile two already-valid Atlas observations that become false if universalized in opposite directions:

1. cross-Person responsibility offers do not create receiver responsibility merely by delivery; and
2. some responsibilities already arise from a governing relationship or condition before a fresh software acceptance event occurs.

The correction is not to reject responsibility-offer / standing-intake architecture.

It is to bound that architecture to the class of responsibility it actually governs: **newly assumed responsibility**.

---

## 1. Responsibility has more than one establishment pattern

Atlas must preserve at least two different patterns.

### A. Pre-existing / relation-constituted responsibility

A responsibility may already exist because the relevant governing relationship or condition makes a response belong to a Person, institution, body, custodian, parent relation, previously accepted commitment, or other carrier.

Conceptually:

```text
condition
+
governing relationship
→ responsibility already exists
```

A present software interaction may later:

- recognize it;
- reconstruct it;
- adjudicate it;
- expose it in a current read;
- route it to an execution carrier;
- record its faithful or unfaithful carriage.

Those later operations do not necessarily create the responsibility itself.

Therefore:

```text
responsibility exists
!= Atlas has recognized it
!= Person has freshly accepted it
!= Person knows it
!= Person is culpable for failure
```

### B. Assumed responsibility

A new optional responsibility may not belong to a Person until that Person lawfully undertakes it.

Conceptually:

```text
new proposed responsibility
→ offer / undertaking opportunity
→ acceptance / prior standing assent / another valid uptake basis
→ assumed responsibility
```

This is the primary territory of:

- `atlas-cross-boundary-responsibility-offers-v1.md`;
- `atlas-responsibility-offer-and-relation-lifecycle-v1.md`;
- `atlas-standing-responsibility-intake-agreements-v1.md`.

---

## 2. Cross-boundary offer law remains intact

When one Person, institution, workflow, or external source asks another Person to take on a **new optional responsibility**, delivery is not assignment.

The governing law remains:

> A sender may propose or offer a new responsibility. The sender does not create receiver responsibility merely by delivery, title, membership, seat, sender authority, or the ability to write an assignment field.

The receiver may take up that responsibility through:

- explicit item-level acceptance;
- prior bounded standing intake;
- another truthful establishment rule that already governs the relationship/effect.

Opening, seeing, receiving, or acknowledging a request is not by itself uptake.

---

## 3. Standing intake is advance assent for assumed responsibility

A Standing Responsibility Intake Agreement is not the universal source of Responsibility.

It is a reusable receiver-assent basis for a bounded class of **future assumed responsibilities**.

Therefore the previous broad shorthand:

> Responsibility always originates in the receiver's consent.

must be read more narrowly as:

> **Assumed responsibility entering through the responsibility-offer / intake path originates in the receiver's uptake, which may be expressed item-by-item or in advance through bounded standing assent.**

This correction does not weaken the standing-intake boundary.

It prevents that boundary from erasing responsibilities that arise through a different governing relation.

---

## 4. Existing institutional responsibility may be reconstructed rather than freshly accepted

Current Atlas Organization architecture already recognizes a legitimate establishment basis of:

```text
governed reconstruction of a relationship already existing in real life
```

For example, current Person + Organization Membership + Position Appointment + Position→Responsibility + Responsibility Scope source facts may be evidence that a Person already carries a durable institutional function.

The software act that reconstructs those source facts is not necessarily the historical origin of the responsibility.

Thus:

```text
existing real institutional relationship
→ Atlas reconstructs / establishes source evidence
→ effective responsibility read may resolve current responsibility
```

is different from:

```text
institution creates a new optional responsibility for Person
→ Person must take it up under the governing uptake rule
```

---

## 5. Position appointment requires establishment basis, not one universal acceptance shape

`atlas-canonical-person-institution-responsibility-realization-v1.md` already correctly says that future generic Position-based responsibility must have a truthful establishment basis such as:

- explicit receiver acceptance;
- matching standing intake;
- governed reconstruction of an already-existing relationship;
- adjudicated institutional fact establishing that the Person already carries the relationship;
- another future recognized basis.

That remains the governing rule.

The Reality Constitution refinement is only:

> do not reduce every one of those bases to fresh receiver consent if the responsibility already exists independently of the present uptake event.

Future writes must still preserve why the relation is current.

---

## 6. Exact Company Work responsibility follows the same split

`atlas.work_allocations` may remain the current exact-work responsibility carrier.

The important question is the establishment basis for a new active allocation.

Possible bases include:

### Assumed exact-work responsibility

```text
new exact Work offered to Person
→ explicit acceptance / qualifying standing intake
→ active exact-work responsibility
```

### Already-binding exact-work responsibility

A governing relationship/domain rule may establish that a particular exact operation already belongs to a Person once the relevant real condition exists.

If Atlas supports such a rule, it must be explicit, bounded, and independently evidenced.

It must not be inferred merely from title, role, visibility, seat, or owner preference.

### Reconstructed exact-work responsibility

Atlas may reconstruct/adjudicate that the Person already carried the exact responsibility before the current database row existed.

The row then records/realizes the current responsibility; it does not fabricate its historical origin.

---

## 7. Knowledge and responsibility remain separate

This reconciliation also prevents another false collapse:

```text
Person did not know
→ Person had no responsibility
```

Some responsibilities may exist before recognition.

Whether failure to know is itself a breach is a separate question depending on whether observation/inspection/watchfulness was itself entrusted.

Therefore:

```text
responsibility
!= recognition
!= knowledge
!= culpability
```

A future effective responsibility resolver may establish current responsibility while another epistemic layer remains unknown/indeterminate.

---

## 8. Responsibility is not a transferable possession

Human-facing language such as `handoff`, `transfer`, or `reassign` may remain useful.

The underlying reality should be resolved effect-by-effect:

```text
relation A may continue, narrow, end, or be released
+
relation B may be established
```

A new receiver relation does not automatically release an earlier carrier unless the governing effect establishes that release.

This preserves the already-selected accepted-effect families:

- carrier succession;
- delegated child responsibility;
- shared participation;
- new requested responsibility.

---

## 9. Consequence for current architecture documents

The responsibility architecture should now be read with this precedence:

1. `atlas-canonical-person-institution-responsibility-realization-v1.md` — durable institutional source realization and establishment basis;
2. this reconciliation — responsibility-origin split between pre-existing/relation-constituted and assumed responsibility;
3. `atlas-responsibility-offer-and-relation-lifecycle-v1.md` — lifecycle for responsibility that enters through offer/uptake or another explicit relation basis;
4. `atlas-standing-responsibility-intake-agreements-v1.md` — advance assent for bounded future assumed responsibility;
5. `atlas-cross-boundary-responsibility-offers-v1.md` — delivery is not assignment for cross-boundary responsibility requests;
6. `atlas-event-effect-governed-uptake-v1.md` — event/effect decomposition and effect-specific uptake.

Where older prose appears to say that **all responsibility** originates in receiver consent, this document narrows that statement to **newly assumed responsibility entering through the offer/intake path**.

---

## 10. No schema is implied

This reconciliation creates no requirement for one generic Responsibility table.

Existing domain-specific source facts may remain valid carriers:

- Organization Position/Appointment/Responsibility/Scope for durable institutional responsibility;
- `work_allocations` for exact Company Work responsibility;
- Execution Lease for current execution authority;
- future Offer/Standing Intake/Responsibility Relation persistence if and when those missing realities require executable storage.

A new generic object is justified only when a real relationship cannot be faithfully represented by the existing source facts plus governed projections.

---

## Resulting law

The settled law is:

> **Responsibility is established by the governing relationship that makes a response belong to a Person or other carrier. Some responsibilities already arise from an existing relationship or condition and may later be recognized or reconstructed. Other responsibilities are optional undertakings and arise only when the Person lawfully takes them up. Cross-boundary delivery never creates a new optional receiver responsibility by itself. Standing intake is prior bounded assent for that assumed-responsibility class, not the universal origin of every responsibility. Knowledge, execution warrant, and culpability remain separate from responsibility.**
