# Atlas Governed Scope — Cross-Ledger Law v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

A canonical Atlas Scope **may span more than one Ledger**.

Scope is a composition primitive for bounded institutional reality. It may describe one meaningful operating boundary whose members remain under different Ledger custody.

This does **not** make Scope a custody carrier and does not merge Ledgers.

The governing law is:

> **Scope may compose cross-Ledger reality; custody remains with each member's canonical Ledger.**

## 2. Cross-Ledger Scope does not create cross-Ledger access

A Person relation to a Scope is still evaluated separately through each queried Ledger aperture.

If Scope S contains reality under Elm Ledger custody and Feast Guild Ledger custody, then:

```text
resolve aperture(Person P, Elm Ledger, Scope S)
  -> only S members whose effective custody is Elm

resolve aperture(Person P, Feast Guild Ledger, Scope S)
  -> only S members whose effective custody is Feast Guild
```

A visibility admission over the Elm intersection does not expose Feast Guild reality merely because both are members of S.

Likewise:

- responsibility in one Ledger intersection does not create responsibility in another;
- authority over one Ledger intersection does not create authority over another;
- delivery capability for one surface does not activate another Ledger intersection;
- root authority over one Ledger does not become authority over the other Ledger through Scope composition.

## 3. Scope is above custody, not instead of custody

Scope answers:

> Which governed pieces of reality form this bounded meaningful operating set?

Effective institutional custody answers:

> Which Ledger governs each piece of that reality?

These questions must remain independent.

Scope resolution therefore requires effective custody to be resolved for every candidate member before that member contributes to a Ledger aperture.

A Scope definition may not override:

- `effective_institutional_custody_v1` or its canonical successor;
- institutional custody adjudications;
- canonical Ledger identity;
- domain custody rules;
- an explicit custody correction merely because a historic carrier differs.

If custody is ambiguous, the candidate member fails closed for aperture evaluation.

## 4. Existing Ledger graph is evidence, not Scope membership by itself

Atlas already has distinct cross-Ledger substrates:

- `ledger_relationships` — relationships between Ledgers;
- `ledger_correlations` — governed correlations between subjects in different Ledgers;
- `effective_institutional_custody_v1` and custody adjudications — canonical custody resolution.

These are useful evidence for explaining a cross-Ledger Scope, but none of them automatically places reality inside a Scope.

A Ledger relationship does not mean every subject in both Ledgers belongs to the same Scope.

A subject correlation does not mean the correlated subjects belong to every Scope involving either Ledger.

A Scope must have its own governed definition/membership basis.

## 5. Example: flower fulfillment

One meaningful Scope may eventually be:

```text
Scope: Flower fulfillment

Elm Ledger intersection
  production readiness
  harvested stems
  farm-side fulfillment work

Feast Guild Ledger intersection
  buyer demand
  order commitments
  distribution / handoff work
```

The Scope may let Atlas reason that these pieces belong to one operating boundary without asserting that Feast Guild owns Elm production reality or that Elm owns Feast Guild customer/order reality.

A Person may have visibility, responsibility, or authority over only one intersection, several intersections, or neither.

## 6. Aperture intersection law

For any Person P, Ledger L, and Scope S:

```text
scope_intersection(S, L)
  = members of S
    whose effective canonical custody resolves to L
```

Then each aperture dimension is evaluated independently over that intersection:

```text
visibility(P, L, S)
  = policy-issued visibility admitted for P
    over scope_intersection(S, L)

responsibility(P, L, S)
  = canonical responsibility evidence for P
    over scope_intersection(S, L)

authority(P, L, S)
  = explicit authority evidence for P
    over scope_intersection(S, L)
```

No dimension may use another dimension as substitute evidence.

## 7. Cross-Ledger Scope is not a hidden super-Ledger

A Scope must never become a disguised parent Ledger.

It must not:

- own institutional truth;
- receive canonical custody merely because members are grouped inside it;
- issue root Ledger authority;
- create a universal membership roster;
- collapse billing/entitlement across Ledgers;
- erase provenance showing where each member came from;
- create implied authority between the Ledgers it spans.

If Atlas eventually needs a new Ledger, that must be established explicitly as a Ledger, not approximated through Scope.

## 8. Cross-Ledger relations remain explicit

Scope composition does not manufacture a `ledger_relationships` or `ledger_correlations` row.

If the semantics of a Scope depend on a relationship or correlation between Ledger-held subjects, that relationship must already exist through its own governed contract or be established separately through proper authority.

The Scope may cite such relations in its provenance or membership explanation.

## 9. Scope relations to visibility, responsibility, and authority

One reusable Scope may be referenced independently by:

- a Person visibility admission predicate envelope;
- standing responsibility;
- current work responsibility where the work maps into the Scope;
- operational authority;
- other future scoped institutional relations.

Sharing the Scope identifier does not make those relations equivalent.

For example:

```text
Scope S = Flower fulfillment

Anna:
  visibility -> S ∩ Elm
  responsibility -> S ∩ Elm

Katie:
  visibility -> S ∩ Feast Guild
  responsibility -> S ∩ Feast Guild

Lex:
  visibility -> selected intersections of S
  authority -> selected intersections of S
```

The apparent organizational structure is a projection of these scoped relations, not a rank tree.

## 10. Explainability requirement

A cross-Ledger Scope must eventually be able to explain, for any included candidate:

1. why the candidate is a member of this Scope;
2. which canonical subject it represents;
3. which Ledger currently has effective custody;
4. which relation/correlation evidence participates in the inclusion, if any;
5. which Scope-definition rule admitted it;
6. when that inclusion became or ceased to be valid.

An answer such as “because the Ledgers are related” is not sufficient.

## 11. No universal hierarchy consequence

Because Scope may span Ledgers and heterogeneous domains, it must not assume one universal parent/child tree.

A Scope can contain reality connected by:

- exact subject inclusion;
- governed domain containment;
- explicit cross-Ledger correlation;
- project/process participation;
- other future governed membership rules.

The exact membership mechanism remains unresolved by this document.

## 12. Explicit non-scope

This document does **not**:

- create a Scope table;
- create Scope membership rows;
- define predicate serialization;
- seed a cross-Ledger Scope;
- create or alter a Ledger relationship;
- create or alter a Ledger correlation;
- change custody;
- create Person visibility admissions;
- create responsibility or authority grants;
- create an executable aperture resolver;
- change Worker Day or Company Work behavior.

## 13. Next unresolved design boundary

Cross-Ledger extent is settled.

The next question is **how a canonical Scope defines its members**.

At least three models remain possible:

1. **Extensional** — a Scope is primarily an explicit governed set of subjects/other Scopes.
2. **Intensional** — a Scope is primarily a governed rule/predicate whose matching reality is dynamically inside the Scope.
3. **Hybrid** — a Scope has a governed definition that may combine explicit includes/excludes, reusable child Scopes, and dynamic semantic predicates, with explainable membership provenance for every resolved member.

No executable Scope schema should be created until this membership law is settled.
