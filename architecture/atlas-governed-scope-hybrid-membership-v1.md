# Atlas Governed Scope Hybrid Membership v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

A canonical Atlas Scope is a first-class governed object whose current membership may be resolved from a **hybrid composition** of:

- explicit subject inclusions;
- reusable child Scopes;
- governed semantic predicates;
- explicit subject exclusions.

A Scope answers only:

> Which bounded institutional reality is this Scope referring to right now, and why?

A Scope does **not** itself grant visibility, responsibility, authority, billing entitlement, delivery capability, rank, or Person↔Ledger membership.

Visibility, responsibility, and authority may each reference the same Scope while remaining semantically independent.

## 2. Hybrid membership law

Conceptually, a Scope definition may contribute candidate reality through multiple governed sources:

```text
Scope
  explicit inclusions
  + child Scope resolutions
  + predicate matches
  - explicit exclusions
  -> candidate Scope membership
```

The final resolved membership must preserve the evidence chain for every included and excluded subject.

The expression above is conceptual only. It does **not** yet establish executable precedence when sources conflict; conflict law remains explicitly deferred.

## 3. Explicit inclusion

An explicit inclusion says that a specifically identified governed subject is intended to belong to the Scope.

An inclusion must preserve enough identity and provenance to answer:

- what subject was included;
- what canonical/effective Ledger custody governs that subject;
- who or what established the inclusion;
- on what basis;
- when it became effective;
- when or whether it ceased to apply.

Explicit inclusion does not alter the subject's canonical custody or domain identity.

It is membership evidence only.

## 4. Child Scope composition

A Scope may include another governed Scope as a child.

This permits reusable operating boundaries without flattening every subject directly into every parent Scope.

For example:

```text
Scope: Flower fulfillment
  child Scope: Harvest-ready production
  child Scope: Buyer order fulfillment
  child Scope: Delivery coordination
```

Each child Scope remains independently governed and may itself span multiple Ledgers.

Parent-child composition must not create institutional custody, Ledger relationships, or Person access.

A resolver must detect cyclic Scope composition and fail closed rather than recurse indefinitely or silently truncate the graph.

This document does not yet choose whether cycles are prevented at write time, rejected at resolution time, or both.

## 5. Governed predicate membership

A Scope may contain one or more governed predicates that dynamically admit institutional reality matching semantic conditions.

Predicate membership is intended for operating boundaries whose real contents change as institutional reality changes.

A predicate must be:

- explicit rather than inferred from UI labels;
- versioned or otherwise provenance-preserving;
- evaluable against canonical governed facts;
- explainable for each matched subject;
- bounded so that failure or ambiguity fails closed;
- custody-aware when the Scope spans multiple Ledgers.

A predicate is not arbitrary application code and is not a hidden query string. Its eventual executable grammar must be governed and inspectable.

## 6. Explicit exclusion

A Scope may explicitly exclude governed reality that would otherwise enter through an inclusion, child Scope, or predicate.

Exclusion exists so a broad dynamic Scope can remain operationally useful without forcing its predicate definition to encode every exceptional case.

An exclusion must preserve provenance and subject identity just as an inclusion does.

This document does not yet establish whether exclusion always dominates every positive membership source, whether explicit inclusion may override an exclusion, or whether conflicts require adjudication. That is the next unresolved semantic boundary.

## 7. Explainability requirement

For any subject `X` and Scope `S`, Atlas must eventually be able to answer at least:

```text
Is X in S right now?
Why?
Which inclusion / child Scope / predicate / exclusion contributed?
Which Ledger currently has custody of X?
Which definition versions were evaluated?
At what effective time?
```

A bare boolean is insufficient as the canonical Scope resolver result.

The resolver must preserve positive and negative evidence sufficient for later audit, responsibility reasoning, authority checks, visibility evaluation, and historical reconstruction.

## 8. Cross-Ledger behavior

A Scope may span multiple Ledgers.

Hybrid membership does not weaken the custody law established by the cross-Ledger Scope architecture.

For each resolved member:

1. effective institutional custody is resolved independently;
2. the subject remains governed by its canonical Ledger;
3. the Scope records/composes membership without moving custody;
4. a Ledger aperture sees only the Scope intersection whose effective custody belongs to that queried Ledger;
5. policy-issued visibility is then evaluated independently for the Person and purpose.

A Scope therefore cannot be used to smuggle reality from one Ledger into another person's aperture.

## 9. No universal hierarchy

Child Scopes provide composition, not a claim that all institutional reality fits one parent-child tree.

Domain-local hierarchies remain domain-local, including examples already present in Atlas such as:

- project parent/child relationships;
- organization-unit parentage;
- household-space parentage;
- place parentage;
- growing-object relationships;
- task and work relations.

Those structures may provide evidence to a Scope predicate or explicit composition rule where governed, but none is automatically promoted into the canonical Scope hierarchy.

## 10. Existing substrate audit

Atlas already contains useful patterns but no existing object that satisfies the full hybrid Scope contract.

Current examples include:

- `organization_responsibility_scopes` — responsibility-specific typed scope carrier;
- `principal_authority_allocations.scope` — authority-specific JSON scope payload;
- `claim_records` / `evidence_records` — domain scope + subject addressing;
- `task_subject_links`, `organization_ledger_subjects`, and other relation tables — typed subject linkage;
- project, organization-unit, place, household-space, and growing-object parent/child relationships — domain-local hierarchy;
- `goal_requirements.predicate`, operation rules, semantic exposure policies, and other JSON/text predicate mechanisms — domain-local predicate patterns;
- `ledger_correlations` — cross-Ledger subject relationships;
- `effective_institutional_custody_v1` — effective Ledger custody resolution.

None of these should be silently renamed or promoted to the generic Scope primitive.

The future Scope implementation may reuse proven conventions from them, but must preserve semantic separation.

## 11. Scope references from aperture dimensions

The intended architecture remains:

```text
                    Scope
                     |
       +-------------+-------------+
       |             |             |
   visibility   responsibility   authority
   relation        relation        relation
```

Each relation must establish its own Person, purpose, authority/basis, temporal state, and semantic rules.

A Person having responsibility over Scope S does not make Scope S visible.
A Person having visibility over Scope S does not create responsibility.
A Person having authority over Scope S does not create visibility or responsibility.

Scope identity is reusable; aperture dimensions are not collapsed.

## 12. Dynamic membership and Work Brief consequence

Because predicate membership can change as institutional reality changes, the work exposed through a narrow Person aperture may also change without editing a Person↔Ledger membership object.

For example, a Scope used by a responsibility or visibility relation may admit new Company Work because that work now satisfies a governed predicate.

That does not by itself mean the Person is responsible for or may see the new work. The separate responsibility and visibility relations still have to admit it under their own laws.

This preserves the distinction:

```text
Scope membership
  != visibility
  != responsibility
  != authority
```

## 13. Historical reconstruction requirement

A hybrid Scope cannot be treated as a timeless query whose past result is unknowable.

Eventually Atlas must be able to reconstruct, for a relevant effective time, which definition/version and governed facts produced Scope membership.

This architecture therefore requires provenance/version awareness for:

- explicit inclusions/exclusions;
- child-Scope relations;
- predicate definitions;
- effective custody;
- the underlying institutional facts evaluated by predicates.

This document does not yet prescribe the storage mechanism for that history.

## 14. Failure law

Scope resolution fails closed when:

- a subject cannot be canonically identified;
- effective custody is ambiguous where custody is required;
- a predicate cannot be evaluated under its governed version;
- a child-Scope cycle prevents deterministic resolution;
- the resolver cannot explain the membership basis;
- conflict between membership sources cannot be resolved under an established conflict law.

Fail-closed Scope resolution must not silently widen visibility, responsibility, or authority.

## 15. Explicit non-scope

This architecture document does **not**:

- create a Scope table;
- create Scope membership rows;
- create child-Scope relation rows;
- create predicate serialization or execution schema;
- create inclusion/exclusion tables;
- create a Person visibility-admission table;
- create a generic aperture resolver;
- migrate any existing Worker Day behavior;
- migrate any responsibility or authority contract;
- seed an Elm, Feast Guild, or other production Scope;
- create a delegation UI.

## 16. Next unresolved boundary: membership conflict law

Hybrid Scope composition is now settled.

The next executable design must decide what happens when positive and negative membership evidence disagree.

Examples:

- a predicate includes Subject X, but X is explicitly excluded;
- Child Scope A includes X while Child Scope B contributes an exclusion affecting X;
- X is explicitly included after an earlier exclusion;
- one predicate admits X while another governed predicate marks X outside the boundary;
- a child Scope changes over time and creates a conflict with a parent-level inclusion/exclusion.

Before executable Scope schema is created, Atlas must establish a deterministic, explainable conflict/precedence law rather than relying on insertion order, UI order, or application-specific behavior.
