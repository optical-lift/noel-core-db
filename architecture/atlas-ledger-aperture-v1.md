# Atlas Ledger Aperture v1

**Status:** Architecture contract only
**Date:** 2026-09-14
**Executable scope:** None

## 1. Purpose

Define the governing human-to-Ledger model for Atlas before adding any new delegation, staffing, scheduling, or employee-management surface.

The central rule is:

> **Atlas users are peers. A person is not an owner-user, manager-user, or employee-user. What differs is the aperture through which that person may participate in a Ledger.**

A Ledger aperture is the bounded intersection of what a person may see, what reality currently rests with them to carry, and what changes they may establish within that Ledger.

This architecture replaces rank-first reasoning with scope-first reasoning. Existing role labels remain compatibility evidence where current runtime contracts still depend on them, but they are not the future semantic source of human standing in Atlas.

## 2. Ledger aperture dimensions

A person's relationship to one Ledger is described by three independent dimensions.

### 2.1 Visibility

Visibility answers:

> What institutional reality is this person permitted to know?

Visibility can be narrower or broader than responsibility. A person may need to see neighboring or upstream reality in order to execute correctly without being responsible for changing it.

Visibility is not inferred from an account class, title, billing seat, or legacy organization role.

### 2.2 Responsibility

Responsibility answers:

> What part of this Ledger's reality currently rests with this person to carry forward?

Responsibility has at least two existing forms in Atlas:

- **standing institutional responsibility**, represented today by organization positions, reusable responsibilities, and typed responsibility scopes;
- **current work responsibility**, represented today by an active `responsible` allocation on Company Work.

A responsibility may be long-lived stewardship, temporary custody of one piece of work, or both.

Responsibility does not by itself imply broad visibility or the authority to rearrange another person's responsibility.

### 2.3 Authority

Authority answers:

> What changes to this Ledger may this person establish as institutional truth?

Authority may include, depending on scope:

- changing the disposition or plan of work;
- moving responsibility from one person to another;
- accepting or adjudicating a returned result;
- establishing new institutional facts;
- changing the scope through which another person participates.

Authority is explicit. It must not be inferred from legacy labels such as `owner`, `manager`, `farm_manager`, `employee`, a display title, or possession of a paid seat.

## 3. Scope creates the apparent hierarchy

Atlas does not require human rank classes in order to expose organizational scaffolding.

If Person A's legitimate visibility and authority scope includes institutional reality that contains Person B's narrower responsibility scope, Atlas may show Person B and the relevant work/responsibility structure to Person A.

That is not because A belongs to a superior account class. It is because the governed scopes overlap in a way that makes B's responsibility part of the reality A is entitled to inspect or alter.

Likewise:

- two people with parallel scopes need not appear above or below one another;
- a person may hold broad visibility but narrow mutation authority;
- a person may hold substantial responsibility without authority to redistribute another person's responsibility;
- a person's Atlas projection may change when their aperture changes without changing the kind of user they are.

The apparent organizational hierarchy is therefore a **projection of scoped relationships**, not a primitive user hierarchy.

## 4. The same Atlas at different apertures

A narrow execution-focused surface and a broad institutional surface are projections of the same Ledger.

A person carrying a narrow slice of Elm may see only:

- the work currently entrusted to them;
- the information required to execute it correctly;
- actions they are authorized to take;
- ways to return results, observations, exceptions, and completion evidence.

A person with a broader Elm aperture may see:

- the same work in institutional context;
- the people currently carrying pieces beneath that scope;
- unassigned or unresolved responsibility;
- timing and consequence relationships;
- returned results and exceptions;
- controls for changes their authority actually permits.

Neither is a separate product ontology. The UI is derived from:

```text
Person
  + Ledger
  + visibility scope
  + responsibility scope
  + authority scope
  -> Atlas projection
```

The current Anna execution surface is therefore best understood as an early narrow-aperture projection, not as evidence for a separate employee application model.

## 5. Existing substrates to preserve

No new aperture table is introduced by this document. Atlas already contains several useful canonical substrates that should be preserved and composed rather than replaced casually.

### 5.1 Company Work is the work identity

`atlas.work_items` remains the canonical institutional work identity.

Worker, planner, and business views must not manufacture separate copies of the same work merely because different people see different projections.

### 5.2 `work_allocations` carries current work responsibility

An active allocation with `allocation_role = 'responsible'` already represents the current person carrying responsibility for a Company Work item.

Important existing behavior to preserve:

- responsibility is attached to the same Company Work object;
- responsibility changes release the prior allocation rather than rewriting history;
- the assigning membership and allocation timestamps are retained;
- responsibility may be unresolved/unassigned;
- responsibility changes invalidate incompatible execution plans rather than silently rewriting historical planning evidence.

This is a strong substrate for temporary custody of work.

The existing owner-gated public responsibility RPC is compatibility authority and is **not** the governing future answer for who may move responsibility.

### 5.3 Positions, responsibilities, and responsibility scopes carry standing responsibility

The generic organization-structure substrate already separates:

- institutional positions;
- time-bounded appointments to those positions;
- reusable institutional responsibilities;
- position-to-responsibility relationships;
- typed scopes identifying the institutional/domain reality those responsibilities concern.

This substrate may describe durable stewardship without making the position title a rank or authority class.

The useful semantic rule is:

> A position says where a person is situated and what standing responsibilities are attached there. It does not automatically establish all visibility or mutation authority over that scope.

### 5.4 Exposure grants are a visibility compatibility substrate

`organization_member_exposure_grants` and the semantic exposure membrane already establish an important idea: information exposure is explicit and is distinct from membership, responsibility, and authority.

However, the current v1 substrate is explicitly shaped around organization-paid employee seats, worker information classes, and worker-oriented scope kinds. It should therefore be treated as a **compatibility visibility membrane**, not as the final generic Person-to-Ledger visibility ontology.

Do not broaden or reinterpret those grants silently.

### 5.5 Operational authority allocations prove role != authority

`principal_authority_allocations` already preserves a crucial truth boundary:

- organization role does not imply authority;
- farm role does not imply authority;
- an authority grant requires an explicit source.

That rule is retained.

The current allocation carrier is Principal / portfolio-unit / operating-function shaped and therefore should not be mechanically declared the generic Person-to-Ledger authority model. It is an existing operational-authority substrate that may later participate in aperture resolution where semantically appropriate.

### 5.6 Root Ledger authority remains distinct

`principal_ledger_authorities` establishes root governing authority over a Ledger.

Root authority is ontologically different from ordinary operational participation in a Ledger. It must not be reused as the representation for every narrower participant merely to avoid designing the correct scoped relationship.

A person with a narrow aperture does not need to become a root Principal over the Ledger.

## 6. Billing/access is not human rank

Current organization-paid employee seats were intentionally built as licensed product-access objects rather than work authority.

That distinction is retained and generalized conceptually:

> A paid connection may determine whether a person receives a particular Atlas delivery surface. It does not make that person a lesser kind of Atlas user, establish their institutional responsibility, or define their authority rank.

Terms such as "employee seat" may remain commercial or compatibility vocabulary while the product is migrated, but business logic must not reason from that label to conclusions such as:

- this person is subordinate;
- this person may see only worker data;
- another person is automatically entitled to inspect or alter this person's work;
- this person cannot hold broader responsibility elsewhere;
- this credential is a separate class of Atlas identity.

## 7. Responsibility flow

The intended work flow is not:

```text
owner -> assigns -> employee
```

It is:

```text
Ledger reality
  -> responsibility is situated within a person's legitimate aperture
  -> that person carries the entrusted portion
  -> action / observation / result is returned to the Ledger
  -> the same institutional reality continues
  -> responsibility may remain, end, or move according to governed authority
```

The organization or Ledger does not cease to own its reality while a person carries responsibility for a piece of it.

"Returned" does not mean "finished." A returned result can create the next state required by another piece of Company Work, another person, another process, or another domain projection.

## 8. Work Brief as projection, not data model

A person's current Work Brief is the composed projection of Company Work that intersects their present responsibility and delivery context.

A Work Brief does not own tasks and does not create copies of Company Work.

Dates, order, timing, guidance, and execution affordances describe how currently entrusted work is exposed. They are not the canonical work identity.

The future broader Ledger surface should therefore be able to expose the scaffolding of current responsibility without treating a calendar or employee schedule as the source of truth.

## 9. Required future aperture resolver

Atlas does **not yet** have one proven canonical relation or resolver that answers, generically:

> For Person P and Ledger L, what is P's effective visibility, standing responsibility, current work responsibility, and mutation authority at this moment?

That absence is explicit. This document does not invent the answer.

A future tranche must decide whether effective aperture is:

- derived from existing relations only;
- represented by a new canonical Person-to-Ledger relation plus derived overlays;
- or composed through another already-governed identity/authority seam.

That decision must be made before adding generic delegation mutations or a broad responsibility-management spread.

## 10. Compatibility vocabulary

The following current terms may still appear in schemas, RPC names, routes, or migrations:

- owner
- manager
- farm manager
- employee
- employee seat
- worker
- supervisor

They may describe current compatibility behavior, commercial packaging, historical roles, or a particular UI projection.

They must not be treated as evidence that Atlas has different classes of human user.

New architecture should prefer explicit questions:

- Which Ledger?
- Which person?
- What may they see?
- What are they carrying?
- What may they establish or change?
- Over what scoped reality?
- For what period?
- On what explicit basis?

## 11. Migration law

Existing role-gated behavior must be migrated incrementally rather than globally reinterpreted.

For each old gate such as `is_organization_owner`, `farm_manager`, or employee-seat-specific exposure:

1. identify the institutional decision it currently protects;
2. identify the Ledger reality affected;
3. identify the scope of the requested action;
4. resolve the person's explicit authority for that scope;
5. preserve fail-closed behavior until that resolution exists;
6. retire the legacy role gate only after equivalent governed authority is proven.

Do not replace old role checks with broad "organization member" checks. Equality of user kind does not mean equality of aperture.

## 12. Immediate product consequence

The next responsibility-management surface should not be modeled as an owner/manager screen for managing employees.

It should be a Ledger projection that exposes the responsibility scaffolding visible to the current person.

Within that projection, a person may be able to:

- inspect people and work beneath/intersecting their visible scope;
- see where responsibility is unresolved;
- inspect current Company Work allocations and plans;
- alter only the facts for which their effective authority admits the mutation.

A narrower person looking at the same Ledger receives a narrower projection automatically.

The surface should therefore be designed only after the effective aperture resolver is situated.

## 13. Explicit non-scope

This architecture document does **not**:

- create a Person-to-Ledger aperture table;
- create a new visibility grant;
- broaden any existing exposure grant;
- change any billing seat;
- remove or rename legacy role columns;
- change responsibility allocation authority;
- change scheduling authority;
- change result-acceptance authority;
- create a roster API;
- create a delegation UI;
- create a Work Brief data model;
- migrate Anna's current institutional records;
- change effective institutional custody;
- deploy any application behavior.

## 14. Questions that must be answered before executable aperture work

The next executable tranche must stop for explicit design if existing canon does not already answer these questions:

1. What canonical relation makes a non-root Person a participant in a specific Ledger, independent of old Organization role and commercial seat language?
2. Is visibility represented as a direct scoped relation, fully derived from responsibility/authority, or a composition of both?
3. How is scope containment evaluated across Ledger, organization unit, domain object, work identity, and other typed reality without flattening them into one hierarchy?
4. Which authority permits one person to change another person's current work responsibility, and how is that authority scoped?
5. How does standing responsibility contribute to default visibility without silently granting mutation authority?
6. How does a paid connection attach delivery capability to a Person/Ledger relationship without becoming the semantic relationship itself?
7. Which existing role-gated contracts can be translated directly to scoped authority, and which require new governed seams?

Until those questions are situated, Atlas should continue using the existing canonical work/responsibility objects and fail closed rather than inventing a second delegation model.
