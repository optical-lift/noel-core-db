# Atlas Governed Scope v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

Atlas will treat **Scope** as a first-class governed object.

A Scope is a durable, reusable definition of a bounded set of institutional reality. Visibility, responsibility, and authority may each reference the same Scope while remaining semantically independent.

A Scope is therefore not a permission, role, responsibility, entitlement, or user class.

It answers only:

> **What reality does this boundary refer to?**

The questions:

- may this Person see that reality?
- does this Person carry responsibility for that reality?
- may this Person establish changes to that reality?

remain separate relationships layered over the Scope.

## 2. Why Scope is first-class

Atlas already contains many local scope/address conventions (`scope_kind/scope_id`, `subject_kind/subject_id`, responsibility scopes, task-subject links, claim/evidence scopes, notebook scopes, etc.). They are useful within their domains but do not form one reusable governed definition that multiple semantic systems can share.

A first-class Scope prevents Atlas from separately redefining “the same area of reality” inside visibility, responsibility, and authority.

Conceptually:

```text
Governed Scope S
  = bounded institutional reality

Visibility admission -> S
Responsibility relation -> S
Authority relation -> S
```

Those three relations may point to the same Scope without implying one another.

## 3. Scope is semantic-neutral

Creating or resolving a Scope grants nothing.

A Scope must never, by itself:

- make a Person able to see the scoped reality;
- make a Person responsible for it;
- make a Person authorized to mutate it;
- create Ledger participation;
- create delivery entitlement;
- create hierarchy or rank;
- imply that another Person is subordinate.

The same Scope may be used by different dimensions with different Persons and different time bounds.

Example:

```text
Scope: Elm perennial production

Anna
  responsibility -> Elm perennial production
  visibility -> selected semantic envelope over Elm perennial production

Another Person
  authority -> scheduling mutations over Elm perennial production

Lex
  visibility -> broader institutional context containing that Scope
```

The Scope does not encode those human relationships. It only gives them a common governed boundary.

## 4. Scope is not one universal parent/child tree

A first-class Scope does not mean Atlas will flatten all institutional reality into one hierarchy.

Underlying reality may still be structured through domain-specific relations:

- Company Work and its subject links;
- project membership;
- production-area containment;
- correspondence endpoint/conversation relations;
- organization-unit structure;
- Ledger custody;
- domain-specific object relationships;
- claim/evidence subject relationships.

A Scope may refer to or be resolved through these governed relationships, but Atlas must not invent containment where the domain does not already establish it.

## 5. Scope requires explainable membership

A Scope must be able to answer:

> Why is institutional fact/object X inside Scope S?

Scope resolution must therefore preserve provenance sufficient to identify the governed facts or rules that admitted the candidate reality.

A candidate must fail closed when Scope membership depends on ambiguous custody, stale physical ownership, unsupported containment, or an ungoverned inference.

The future resolver should conceptually support:

```text
resolve_scope_membership(scope, candidate, context)
  -> admitted | not_admitted | indeterminate
  + evidence/provenance
```

This is architectural shape only, not an established API.

## 6. Visibility interaction

The previously settled visibility law becomes:

```text
candidate fact
  + active semantic exposure policy
  + Person predicate-envelope admission
  + governed Scope match
  + purpose/context/time/evidence requirements
  -> visible
```

The Scope bounds **where** the Person admission may operate.

The semantic predicate envelope bounds **what kinds of information** may be exposed inside that Scope.

Neither layer can substitute for the other.

## 7. Responsibility interaction

Current Company Work responsibility and standing institutional responsibility remain canonical responsibility evidence.

A future responsibility relation may reference a governed Scope to express standing stewardship over a reusable boundary of reality.

However:

- responsibility does not make the Scope visible;
- responsibility does not create authority over the Scope;
- responsibility over one object does not expand automatically to every object resolved into the same Scope unless the responsibility contract explicitly says so.

Existing `organization_responsibility_scopes` remains a compatibility/domain substrate. It currently binds one organization responsibility directly to a typed target and is not itself the reusable cross-dimension Scope object established here.

## 8. Authority interaction

Authority may reference the same governed Scope while remaining action-specific.

A future authority statement should be conceptually closer to:

```text
Person P may establish Action Class A over Scope S
```

than:

```text
Person P is a manager/owner of S
```

Scope alone does not say which mutations are permitted.

## 9. Existing substrates audited

The current schema contains several scope-like carriers, but none is the generic reusable cross-dimension Scope object established by this decision.

### 9.1 `organization_responsibility_scopes`

Useful existing responsibility-to-target binding. It is organization/responsibility specific and therefore cannot be declared the generic Scope primitive.

### 9.2 `scope_kind/scope_id` on claims/evidence/care

Useful local addressing conventions. They identify scope inside those semantic systems but do not define one durable reusable Scope shared by visibility, responsibility, and authority.

### 9.3 `subject_kind/subject_id` relations

Useful domain-level subject address patterns. They identify objects/subjects but do not themselves define a reusable set/boundary of reality.

### 9.4 notebook spread scope fields

Projection/runtime addressing, not institutional authority or reusable scope canon.

### 9.5 `addressable_subjects`

The existing addressable-subject carrier is constrained to organization/institution subjects and is not a universal institutional-reality Scope object.

### 9.6 `world_kernel_definitions`

Its current `scope_kind` is constrained to person/household kernel behavior and is unrelated to the generic governed Scope needed here.

## 10. Scope lifecycle requirements

A future executable Scope object will need explicit lifecycle and provenance. At minimum, architecture must eventually answer:

- canonical identity;
- definition semantics;
- effective time/state;
- provenance/basis;
- custody relationship to Ledger reality;
- how candidate membership is resolved;
- how changes to a Scope definition preserve history;
- whether one Scope can reference/combine other Scopes;
- how fail-closed behavior works when referenced reality changes or moves custody.

This document does not settle the storage/schema shape for those fields.

## 11. Scope does not create a roster

A Scope may make a Person visible to another Person only when a separate visibility policy + Person admission permits exposure of the human/responsibility facts involved.

The existence of a common Scope reference does not itself create a roster or reveal who else has relations to that Scope.

## 12. Immediate product consequence

The future broad Ledger responsibility surface can eventually organize reality around governed Scopes rather than roles or worker classes.

For example, Atlas may expose:

```text
Scope: Elm production
  current responsibility
  unresolved Company Work
  people currently carrying visible pieces
  timing/planning state
  permitted mutations
```

But every line in that surface must still pass the current Person's effective visibility aperture, and every mutation must independently pass authority.

## 13. Explicit non-scope

This document does **not**:

- create a Scope table;
- create Scope membership rows;
- create a universal subject hierarchy;
- alter `organization_responsibility_scopes`;
- alter semantic exposure policies;
- create Person visibility admissions;
- create authority grants;
- create an aperture resolver;
- migrate Worker Day;
- change production authorization;
- change any billing/seat behavior;
- create the responsibility-management UI.

## 14. Next unresolved boundary

The first-class Scope decision is settled, but its **institutional extent** is not yet settled.

Before executable schema is created, Atlas must decide whether one canonical Scope is:

1. strictly bounded to one Ledger; or
2. allowed to span reality governed by multiple Ledgers, with each Ledger aperture resolving only the intersection relevant to that Ledger.

That decision changes custody, resolution, authority, lifecycle, and composition semantics and must be explicit before the Scope object is implemented.
