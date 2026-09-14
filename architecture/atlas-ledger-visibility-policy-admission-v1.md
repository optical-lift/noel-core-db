# Atlas Ledger Visibility Policy + Admission v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Atlas visibility is **policy-issued**.

For a Person to see a piece or class of Ledger reality, Atlas must have both:

1. an explicit semantic exposure policy saying that this kind of information may be exposed for the stated purpose under the stated evidence conditions; and
2. an explicit Person-specific admission saying that this Person is entrusted to receive that policy within the stated governed scope.

Responsibility, authority, billing, credentials, position, organization membership, and UI route do not substitute for either layer.

In particular:

> **Responsibility creates zero visibility by itself, including visibility to the subject being carried.**

A state in which a Person carries responsibility for reality they are not currently admitted to see is semantically valid. Atlas must surface or resolve that mismatch through governed policy/admission work; it must not silently grant visibility to repair it.

## 2. Two independent layers

### 2.1 Semantic exposure policy

A semantic exposure policy answers:

> Under what semantic conditions may information of this kind be exposed at all?

The existing `atlas.semantic_exposure_policies` table is the current substrate for this layer. Its existing shape already expresses useful dimensions such as:

- audience kind;
- purpose;
- information class;
- semantic kind;
- predicate;
- adapter/source domain/source kind;
- allowed modality;
- allowed adjudication state;
- provenance and active state.

Those are semantic admissibility rules. They are not Person-specific visibility grants.

### 2.2 Person-specific admission

A Person-specific admission answers:

> Which Person has actually been entrusted to receive which policy-governed information, over what governed scope, for what period and purpose?

This admission is the human-specific side of visibility. It must identify the canonical Person, the governed scope, the admitted semantic envelope/policy family, temporal state, and provenance sufficient to explain why visibility exists.

The admission does **not** create Ledger membership, responsibility, authority, rank, or delivery entitlement.

## 3. Effective visibility law

Conceptually:

```text
candidate institutional fact
  + effective Ledger custody
  + active semantic exposure policy
  + active Person-specific admission
  + purpose/context match
  + evidence/modality/adjudication requirements
  -> visible
```

If any required element is absent or ambiguous, visibility fails closed.

The aperture resolver therefore does not ask whether a Person is an employee, manager, owner, organization member, or paid seat holder. It asks whether the candidate reality is admitted by policy and whether this Person has an applicable admission over that scope.

## 4. Scope of admission

An admission must be able to be narrower than a whole Ledger.

Examples of admissible scope families may include, where already governed:

- one Company Work identity;
- a typed work family or responsibility scope;
- an organization unit or operating scope whose Ledger custody is proven;
- a project;
- a conversation or communication endpoint;
- a physical production object;
- another typed governed subject.

The admission must not flatten these into one universal hierarchy. Scope applies only where Atlas has a governed custody/containment mapping from the admitted subject to the queried Ledger reality.

## 5. Responsibility remains independent

An active Company Work `responsible` allocation proves responsibility only.

It does not prove:

- the Person may see the work title;
- the Person may see method/guidance;
- the Person may see neighboring state;
- the Person may see consequences or related work;
- the Person may see the identity of other people involved.

Any of those exposures require applicable policy + Person admission.

The same law applies to standing responsibility through positions/responsibility scopes.

## 6. Authority remains independent

Root or operational authority does not automatically create visibility.

A Person may be authorized to establish or alter a class of institutional truth without being admitted to every piece of information around that truth. Where an authority action requires read access, the action contract must name or require the corresponding visibility admission rather than assuming it from authority.

## 7. Delivery remains independent

A paid seat, credential, Work Pass, Personal Atlas entitlement, or other product capability may determine whether Atlas can deliver an admitted surface to a Person.

Delivery capability does not create the policy or the Person admission.

Conceptually:

```text
semantic policy + Person admission
  -> may know

delivery capability
  -> may receive through this Atlas surface
```

Both may be required for a particular product surface, but they answer different questions.

## 8. Existing compatibility substrate

`atlas.organization_member_exposure_grants` is not the generic admission model.

It is currently tied to:

- `organization_id`;
- `organization_membership_id`;
- optional `employee_seat_id`;
- worker-specific information classes;
- worker-oriented scope kinds.

The existing semantic exposure envelope also currently requires an active organization employee seat and supports worker-oriented purposes.

That machinery remains a compatibility membrane for current Worker/Employee surfaces. It must not be silently reinterpreted as the generic Person-specific Ledger visibility ontology.

At the time of this architecture audit, the production table contains no active `organization_member_exposure_grants`, reinforcing that current title/work delivery behavior should not be mistaken for a completed generic visibility system.

## 9. Legacy Worker Day visibility is compatibility behavior

Existing functions such as `worker_day_visibility_floor_v1` and other Worker Day projections still derive visibility from legacy assignment/placement/task-carrier logic.

Under this architecture those functions are compatibility behavior only.

They are **not admissible evidence** for a future generic Ledger aperture resolver because assignment/responsibility must not imply visibility.

Migration must preserve current product behavior until equivalent policy-issued visibility exists; it must not globally disable those paths merely because the future semantic law is stricter.

## 10. Generic aperture resolver consequence

The future visibility portion of:

```text
resolve_effective_ledger_aperture(Person, Ledger, Context)
```

should conceptually gather:

```text
visibility
  admissions[]
    person
    admitted policy/policy family
    governed scope
    purpose/context
    begins/ends
    provenance
  effective exposures[]
    semantic identity
    information class
    source/custody
    policy evidence
    admission evidence
```

This is an architectural shape, not an established API schema.

## 11. No universal roster consequence

A Person-specific visibility admission still does not create `Person -> member_of -> Ledger`.

It is one real scoped fact from which Atlas may derive that the Person currently has some visibility into that Ledger. If all applicable admissions end, that visibility disappears without revoking a separate membership row.

## 12. Migration law

When migrating an old visibility path:

1. identify exactly what information the old surface exposes;
2. resolve its effective Ledger custody;
3. identify or create the semantic exposure policy for that information class/purpose;
4. establish the Person-specific admission through a governed authority path;
5. prove the new policy + admission yields no broader exposure than the old path;
6. only then retire the compatibility visibility rule.

Do not translate legacy `owner`, `manager`, `employee`, membership, assignment, or seat status directly into a Person admission.

## 13. Explicit non-scope

This document does **not**:

- create a generic Person visibility-admission table;
- alter `semantic_exposure_policies`;
- alter `organization_member_exposure_grants`;
- seed any visibility admission;
- change Anna's current Worker Day visibility;
- change any employee seat or credential;
- create an aperture RPC;
- change any production authorization or read path.

## 14. Next unresolved design boundary

The policy-issued model is settled. The missing generic Person-specific admission substrate is real and must not be invented implicitly.

Before creating it, Atlas must decide what an admission names as its primary semantic target:

- a **specific policy key**;
- an **information class / policy family** that may match multiple policies;
- or a more general **semantic predicate set** evaluated against active policies.

That choice determines whether admissions are brittle and highly explicit, broad but governable, or dynamically policy-composed. It must be settled before executable schema is added.
