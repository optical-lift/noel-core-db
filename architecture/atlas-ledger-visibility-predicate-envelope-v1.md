# Atlas Ledger Visibility Predicate Envelope v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

This document settles the remaining semantic-target question in `atlas-ledger-visibility-policy-admission-v1.md`.

A generic Person-specific visibility admission does **not** name one exact semantic exposure policy and does **not** name one fixed policy family.

It is a **bounded semantic predicate envelope** evaluated against active semantic exposure policies and governed institutional facts.

Effective visibility therefore requires all of the following independently:

```text
canonical Person
+ governed subject / scope
+ active Person-specific predicate envelope
+ active semantic exposure policy
+ candidate fact satisfying both
+ effective Ledger custody
+ requested purpose/context
-> visible
```

Responsibility, authority, delivery entitlement, organization membership, position, credential, assignment, or UI route cannot substitute for any missing visibility element.

## 2. Why the admission is an envelope

Atlas visibility must be able to evolve as institutional semantics become more precise without requiring a new human grant every time a new policy row is added.

A Person admission therefore describes the **semantic boundary of what that Person has been entrusted to receive**, while `semantic_exposure_policies` continue to describe which facts are eligible for exposure at all.

The two layers intersect; neither overrides the other.

An admission may be broader than one policy row but it may never make an otherwise ineligible fact visible.

Likewise, a semantic exposure policy may permit a class of information generally while no Person-specific admission currently admits that information to a particular Person.

## 3. Predicate dimensions already present in Atlas

The existing `semantic_exposure_policies` substrate already names dimensions suitable for evaluating a semantic envelope:

- `purpose_key`;
- `information_class`;
- `semantic_kind`;
- `predicate_key`;
- `adapter_key`;
- `source_domain`;
- `source_kind`;
- allowed modality;
- allowed adjudication state;
- active state and provenance.

A future Person-specific admission may constrain some or all of those dimensions, but this document does **not** establish an executable schema, wildcard language, precedence law, or serialization format.

Those details must be chosen only when the governed subject/scope addressing model is settled.

## 4. Matching law

The future resolver must evaluate an admission as a restriction, never as a replacement policy.

Conceptually:

```text
candidate fact F
policy P
admission A

visible only if:
  P is active
  AND P semantically admits F for the requested purpose
  AND A is active for the Person and requested time/context
  AND F satisfies A's semantic predicate envelope
  AND F is inside A's governed subject/scope
  AND F resolves to the queried Ledger through canonical/effective custody
```

No one predicate dimension is sufficient by itself.

For example, admission to an `information_class` must not silently expose every fact carrying that class if the admission's source, purpose, semantic predicate, or governed scope does not also match.

## 5. Responsibility remains completely independent

An active `responsible` Company Work allocation may exist while the Person has no matching visibility admission for that work.

That state is valid institutional truth:

```text
responsibility = yes
visibility = no
```

Atlas must not auto-create or widen a predicate envelope to repair the mismatch.

The same rule applies to standing responsibility derived from positions and responsibility scopes.

A later workflow may identify such mismatches for resolution, but the aperture resolver itself remains descriptive and fail-closed.

## 6. Authority remains completely independent

A Person may hold authority over a scoped institutional change without a visibility envelope broad enough to inspect all surrounding facts.

If a mutation requires information to be read, the mutation path must require the relevant visibility admission explicitly. Authority does not manufacture read access.

## 7. Delivery remains completely independent

A paid seat, credential, Work Pass, or other delivery capability can serve only information already admitted through policy plus Person predicate envelope.

The product may therefore encounter any of these valid states:

```text
visible + deliverable
visible + not currently deliverable
responsible + not visible
responsible + visible + not deliverable
authorized + not visible
```

Those states must not be collapsed into one role or membership flag.

## 8. Existing employee-seat visibility remains compatibility-only

`organization_member_exposure_grants` and `semantic_exposure_envelope_v1` remain current compatibility machinery.

They are not the generic predicate-envelope substrate because they are coupled to organization membership, employee-seat state, worker-oriented information classes, and worker-oriented purposes.

Likewise, legacy Worker Day functions that derive visibility from assignment or placement remain compatibility behavior until equivalent policy-issued visibility exists.

No current production behavior is changed by this document.

## 9. The admission does not create a roster

A Person-specific predicate envelope is a visibility fact, not a Person-to-Ledger membership relation.

If an envelope admits some Elm reality to Anna, Atlas may derive that Anna currently has some visibility into Elm. When that envelope expires or ceases to match any Elm reality, that conclusion may disappear without revoking a separate membership row.

## 10. Provenance requirement

Future effective-visibility output must preserve enough provenance to answer:

- which Person-specific admission matched;
- which semantic exposure policy matched;
- which candidate fact was admitted;
- which governed subject/scope bounded the admission;
- which custody rule resolved that subject/fact to the Ledger;
- which purpose/context was requested;
- which temporal/adjudication/modality conditions were satisfied.

The resolver must be explainable. It must not return a bare `true` whose basis cannot be reconstructed.

## 11. Existing scope/address audit

Atlas already contains several subject and scope conventions, including:

- `scope_kind/scope_id` in claims, evidence, care state, responsibility scopes, and notebook spread instances;
- `subject_kind/subject_id` in many domain records;
- Company Work identity and subject links;
- organization Ledger subjects;
- addressable subjects and institutional bindings.

However, these are **not presently one canonical universal address system**.

In particular, `addressable_subjects` is constrained to organization/institution subject kinds and therefore cannot be reused as a universal visibility-scope carrier for Company Work, projects, conversations, production objects, and arbitrary governed subjects.

The future Person-specific admission must not invent a universal hierarchy by treating all existing `scope_kind/scope_id` pairs as interchangeable.

## 12. Explicit non-scope

This document does **not**:

- create a Person visibility-admission table;
- create a predicate-envelope serialization format;
- define wildcard or inheritance semantics;
- create a universal subject-address table;
- broaden `semantic_exposure_policies`;
- alter current employee-seat exposure grants;
- create an aperture resolver RPC;
- seed any Person visibility;
- alter Anna's current Worker Day;
- change responsibility, authority, delivery, or billing state.

## 13. Next unresolved boundary

The semantic target is now settled: **Person visibility admissions are bounded semantic predicate envelopes.**

The next unresolved question is how the envelope names the **governed reality to which it applies**.

Atlas already has multiple typed subject/scope address conventions, but no proven single generic address that spans all Ledger reality without flattening domain semantics.

Executable visibility admission must therefore stop until the subject/scope addressing law is settled.
