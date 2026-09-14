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

This revision makes two governing decisions explicit:

> **There is no canonical Person-to-Ledger connection object. Participation is derived from the real governed relationships that exist between a Person and Ledger reality.**

> **Visibility and responsibility are completely independent. Responsibility never creates visibility, including visibility to the responsible subject itself.**

Atlas must not persist a duplicate row whose only meaning is “this Person belongs to this Ledger.” If visibility, responsibility, authority, delivery entitlement, or another governed relationship exists, those facts are stored in their proper domains. The effective aperture is then derived from them.

## 2. Ledger aperture dimensions

A person's effective relationship to one Ledger is described by three independent semantic dimensions plus a separate delivery dimension.

### 2.1 Visibility

Visibility answers:

> What institutional reality is this person permitted to know?

Visibility is independent of responsibility and authority. A person may carry responsibility for reality they are not currently permitted to see. A person may also see reality they do not carry.

Visibility is not inferred from an account class, title, billing seat, legacy organization role, organization membership alone, responsibility, authority, or the mere fact that another person can see this person.

### 2.2 Responsibility

Responsibility answers:

> What part of this Ledger's reality currently rests with this person to carry forward?

Responsibility has at least two existing forms in Atlas:

- **standing institutional responsibility**, represented today by organization positions, reusable responsibilities, and typed responsibility scopes;
- **current work responsibility**, represented today by an active `responsible` allocation on Company Work.

A responsibility may be long-lived stewardship, temporary custody of one piece of work, or both.

Responsibility does not by itself imply **any** visibility, including visibility to the responsible subject itself, and it does not imply authority to rearrange another person's responsibility.

### 2.3 Authority

Authority answers:

> What changes to this Ledger may this person establish as institutional truth?

Authority may include, depending on explicit scope:

- changing the disposition or plan of work;
- moving responsibility from one person to another;
- accepting or adjudicating a returned result;
- establishing new institutional facts;
- changing the scope through which another person participates.

Authority is explicit. It must not be inferred from legacy labels such as `owner`, `manager`, `farm_manager`, `employee`, a display title, organization membership, responsibility, visibility, or possession of a paid seat.

### 2.4 Delivery capability is separate

Delivery answers:

> Through which Atlas surfaces or credentials may this person receive the portion of Ledger reality already admitted by their visibility and other surface-specific rules?

Delivery is not a fourth kind of institutional standing. It is product/access plumbing layered over the semantic aperture.

A paid seat, Work Pass, credential, or entitlement may permit Atlas to deliver a surface. It does not create visibility, responsibility, or authority.

## 3. Scope creates the apparent hierarchy

Atlas does not require human rank classes in order to expose organizational scaffolding.

If Person A's legitimate visibility and authority scope includes institutional reality that contains Person B's narrower responsibility scope, Atlas may show Person B and the relevant work/responsibility structure to Person A.

That is not because A belongs to a superior account class. It is because the governed scopes overlap in a way that makes B's responsibility part of the reality A is independently entitled to inspect or alter.

Likewise:

- two people with parallel scopes need not appear above or below one another;
- a person may hold broad visibility but narrow mutation authority;
- a person may hold substantial responsibility with zero visibility to that responsibility through a given context;
- a person may hold substantial responsibility without authority to redistribute another person's responsibility;
- a person's Atlas projection may change when their aperture changes without changing the kind of user they are.

The apparent organizational hierarchy is therefore a **projection of scoped relationships**, not a primitive user hierarchy.

## 4. No Person-to-Ledger membership primitive

Atlas deliberately does **not** store a generic relation such as:

```text
Person P -> member_of -> Ledger L
```

The system stores the actual facts instead.

Examples:

```text
Person P carries Company Work W
W belongs to Ledger L
```

```text
Person P occupies Position Q
Q carries Responsibility R
R is scoped to reality governed by Ledger L
```

```text
Person P holds explicit Authority A
A governs reality within Ledger L
```

```text
Person P has an explicit visibility admission for information Y
Y belongs to Ledger L
```

From those facts Atlas may truthfully conclude that P currently has one or more aperture dimensions into L.

If all such facts end, Atlas does not need to revoke a separate Ledger-membership row. The next aperture derivation simply yields nothing.

This avoids duplicated relationship truth and synchronization problems.

## 5. The same Atlas at different apertures

A narrow execution-focused surface and a broad institutional surface are projections of the same Ledger.

A person carrying a narrow slice of Elm may see only the independently admitted subset of that reality. If visibility admits none of the carried reality, the Person-facing execution surface may show none of it even though responsibility still exists canonically.

Where visibility is independently admitted, a narrow execution-focused surface may expose:

- the visible work currently entrusted to the person;
- separately admitted information required to execute it correctly;
- actions they are authorized to take;
- ways to return results, observations, exceptions, and completion evidence.

A person with a broader Elm aperture may see:

- work in institutional context;
- the people currently carrying pieces beneath that visible scope;
- unassigned or unresolved responsibility;
- timing and consequence relationships;
- returned results and exceptions;
- controls for changes their authority actually permits.

Neither is a separate product ontology. The UI is derived from:

```text
Person
  + Ledger
  + current governed relationships
  -> visibility
  -> responsibility
  -> authority
  + independent delivery capability
  -> surface-specific intersection
  -> Atlas projection
```

The current Anna execution surface is therefore best understood as an early narrow-aperture projection, not as evidence for a separate employee application model.

## 6. Existing substrates to preserve

No new aperture table is introduced by this document. Atlas already contains several useful canonical substrates that should be preserved and composed rather than replaced casually.

### 6.1 Company Work is the work identity

`atlas.work_items` remains the canonical institutional work identity.

Worker, planner, and broader Ledger views must not manufacture separate copies of the same work merely because different people see different projections.

### 6.2 `work_allocations` carries current work responsibility

An active allocation with `allocation_role = 'responsible'` already represents the current person carrying responsibility for a Company Work item.

Important existing behavior to preserve:

- responsibility is attached to the same Company Work object;
- responsibility changes release the prior allocation rather than rewriting history;
- the assigning membership and allocation timestamps are retained;
- responsibility may be unresolved/unassigned;
- responsibility changes invalidate incompatible execution plans rather than silently rewriting historical planning evidence.

This is a strong substrate for temporary custody of work.

It is **not visibility evidence**.

The existing owner-gated public responsibility RPC is compatibility authority and is **not** the governing future answer for who may move responsibility.

### 6.3 Positions, responsibilities, and responsibility scopes carry standing responsibility

The generic organization-structure substrate already separates:

- institutional positions;
- time-bounded appointments to those positions;
- reusable institutional responsibilities;
- position-to-responsibility relationships;
- typed scopes identifying the institutional/domain reality those responsibilities concern.

This substrate may describe durable stewardship without making the position title a rank or authority class.

The useful semantic rule is:

> A position says where a person is situated and what standing responsibilities are attached there. It does not automatically establish visibility or mutation authority over that scope.

### 6.4 Exposure grants are a visibility compatibility substrate

`organization_member_exposure_grants` and the semantic exposure membrane already establish an important idea: information exposure is explicit and is distinct from membership, responsibility, and authority.

However, the current v1 substrate is explicitly shaped around organization-paid employee seats, worker information classes, and worker-oriented scope kinds. It should therefore be treated as a **compatibility visibility membrane**, not as the final generic Person-to-Ledger visibility ontology.

Do not broaden or reinterpret those grants silently.

### 6.5 Operational authority allocations prove role != authority

`principal_authority_allocations` already preserves a crucial truth boundary:

- organization role does not imply authority;
- farm role does not imply authority;
- an authority grant requires an explicit source.

That rule is retained.

The current allocation carrier is Principal / portfolio-unit / operating-function shaped and therefore should not be mechanically declared the generic Person-to-Ledger authority model. It is an existing operational-authority substrate that may participate in aperture resolution only where its scope can be mapped to the queried Ledger without semantic guesswork.

### 6.6 Root Ledger authority remains distinct

`principal_ledger_authorities` establishes root governing authority over a Ledger.

Root authority is ontologically different from ordinary operational participation in a Ledger. It must not be reused as the representation for every narrower participant merely to avoid designing the correct scoped relationship.

A person with a narrow aperture does not need to become a root Principal over the Ledger.

Root authority is strong evidence for the **authority** dimension. It is not generic visibility evidence unless a separate read contract explicitly grants visibility on that basis.

### 6.7 Ledger graph and institutional custody establish where reality belongs

Aperture resolution requires a trustworthy answer to “which Ledger governs this reality?”

First-class Ledgers, Organization↔Ledger participation, effective institutional custody, Ledger relationships, and domain-specific custody/adjudication may provide that answer.

Aperture resolution must use canonical/effective custody where it exists. It must not infer Ledger scope solely from a stale physical `organization_id`, legacy mixed carrier, route name, or old farm-specific container when canonical custody says otherwise.

## 7. Evidence admissibility by dimension

The future resolver must treat evidence by semantic kind rather than throwing every relationship into one permission graph.

### 7.1 Admissible responsibility evidence

Current admissible sources include:

- active `work_allocations` rows with `allocation_role = 'responsible'`, after resolving the Company Work item to its effective Ledger custody;
- active position appointments joined to explicit institutional responsibilities and typed responsibility scopes, when those scopes resolve to the queried Ledger;
- future responsibility substrates only if they explicitly mean “this person carries this reality.”

Responsibility must **not** be inferred from:

- `tasks.assigned_user_id` or other legacy execution-carrier fields when canonical Company Work responsibility exists;
- plan placement alone;
- being the creator of a record;
- organization membership alone;
- an employee seat;
- a credential;
- a display title;
- visibility grants;
- root or operational authority alone.

### 7.2 Admissible visibility evidence

Current admissible sources include only explicit governed visibility contracts already intended to expose information, such as:

- semantic exposure policy plus an active compatible member exposure grant where that compatibility membrane is still authoritative;
- conversation/endpoint visibility grants for correspondence under their own contracts;
- other domain read contracts that explicitly establish visibility over a scoped subject;
- future generic visibility grants or policies only when they independently mean that the Person may know the specified reality.

Responsibility may be referenced by a visibility policy as a matching condition, but responsibility is never itself the source of visibility.

Visibility must **not** be inferred merely because:

- the person is responsible for the exact subject;
- the person is responsible for neighboring reality;
- the person holds a position;
- the person appears in the same organization;
- the person pays for or receives an Atlas seat;
- another person with broader scope can see them;
- the person holds mutation authority, unless a separate explicit read contract grants visibility;
- a legacy route historically called the person an owner or manager.

### 7.3 Admissible authority evidence

Current admissible sources include:

- active root `principal_ledger_authorities` for the queried Ledger;
- active explicit operational authority allocations only where the authority subject/scope can be mapped to the queried Ledger and requested action without guesswork;
- domain-specific mutation contracts whose existing authorization law explicitly grants the requested action over the requested subject;
- future scoped authority grants that explicitly name the action class and governed scope.

Authority must **not** be inferred from:

- responsibility alone;
- visibility alone;
- standing position title;
- organization membership role;
- employee seat class;
- being the person who originally assigned the work;
- plan ownership or placement history;
- access to a UI surface.

### 7.4 Admissible delivery evidence

Current delivery/access substrates include:

- active organization-paid seat state where the current product surface requires it;
- organization member credentials;
- Work Pass / worker-delivery capability state;
- Personal Atlas or other entitlement state for surfaces governed by those commercial contracts;
- future capability/entitlement bindings that explicitly control product delivery.

Delivery evidence must not be promoted into visibility, responsibility, or authority evidence.

## 8. Explicit negative evidence

The following facts are never sufficient, by themselves, to prove a person's effective aperture into a Ledger:

- `organization_memberships.role = 'owner'`;
- `farm_memberships.role = 'manager'` or equivalent legacy worker role;
- `seat_class = 'employee'`;
- existence of an auth credential;
- a route such as `/owner`, `/anna`, `/manage`, or `/principal`;
- a UI component name containing Owner, Manager, Employee, Worker, or Supervisor;
- payment of a $7 connection fee;
- a person's position display title;
- a legacy task assignee carrier;
- being visible in an organization roster;
- being the parent/creator/author of a record;
- simple shared Organization identity;
- simple shared Ledger participation by an Organization;
- a stale physical custody column when effective custody has been adjudicated elsewhere.

Compatibility code may still inspect some of these facts until migrated. New aperture reasoning must not.

## 9. Derived aperture resolver contract

The next executable architecture should converge on one pure semantic question:

```text
resolve_effective_ledger_aperture(Person P, Ledger L, Context C)
```

The resolver does **not** create or persist participation. It derives a current projection from canonical facts.

Conceptually:

```text
1. resolve P as the canonical Person
2. resolve L as the canonical Ledger
3. resolve effective Ledger custody for candidate institutional reality
4. gather admissible visibility evidence relevant to L and C
5. gather admissible standing-responsibility evidence relevant to L
6. gather admissible current-work responsibility relevant to L
7. gather admissible authority evidence relevant to the requested actions/scopes
8. gather delivery capability separately
9. fail closed anywhere scope/custody mapping is ambiguous
10. preserve divergence between dimensions
11. return the composed aperture projection; persist nothing
```

A future returned shape may resemble:

```text
ledger
  id
  effectiveIdentity

visibility
  scopes[]
  informationClasses[]
  evidence[]

responsibility
  standing[]
  currentWork[]
  evidence[]

authority
  grants[]
  actionClasses[]
  scopes[]
  evidence[]

delivery
  surfaces[]
  credentials/capabilities[]
```

That example is architectural shape only. It is not an API schema established by this document.

The resolver must preserve evidence provenance so a caller can distinguish:

- visibility from responsibility;
- explicit authority from visibility;
- standing responsibility from one work allocation;
- root authority from narrow operational authority;
- semantic aperture from product delivery capability.

The resolver must not discard responsibility merely because the same Person lacks visibility to it.

## 10. Necessary context is independently admitted, not derived from responsibility

A narrow responsibility may be impossible to execute without context beyond the exact subject being carried. For example, a person may need method, location, readiness, materials, neighboring state, or consequence information to execute Company Work correctly.

Atlas must **not** solve that by treating operational necessity as visibility authority.

The governing model is:

```text
responsibility for X

separately:
explicit visibility grant/policy admits Y

only then:
Y may be exposed to the Person
```

A visibility policy may use responsibility as one condition for determining whether the policy applies, but the independently governed visibility contract is the admission source.

If responsibility exists and visibility does not, Atlas preserves that state. It does not fabricate context, auto-create a grant, release the responsibility, or reinterpret delivery capability as permission to know.

The current Worker Day semantic exposure membrane is a compatibility example of explicit policy/grant admission, not evidence that responsibility itself creates visibility.

## 11. Scope containment is not one universal tree

Aperture resolution will encounter different address systems:

- Ledger;
- Organization participation in a Ledger;
- organization unit;
- portfolio/operating function compatibility scope;
- domain object;
- Company Work identity;
- conversation/endpoint;
- project;
- physical production object;
- other typed governed subjects.

These must not be flattened into a single generic parent/child hierarchy merely to make permission checks easy.

A scope contributes to a Ledger aperture only when Atlas has a governed mapping from that scope to Ledger custody and, where relevant, a governed containment/relationship rule for the requested action.

If the mapping is absent or contradictory, resolution fails closed.

## 12. “Who is in this Ledger?” is a family of derived questions

Because no Person-to-Ledger membership row exists, Atlas should not pretend there is one canonical roster question.

Different valid projections include:

- people with any currently visible Ledger reality;
- people carrying standing responsibility in the Ledger;
- people carrying current Company Work in the Ledger;
- people with authority over some Ledger reality;
- people with root Ledger authority;
- people currently receiving a paid/delivered Atlas surface concerning the Ledger;
- people visible within the current person's own aperture.

Those result sets may differ and that is correct.

A future people/responsibility spread must name the projection it is using rather than materialize a fake universal membership list.

## 13. Billing/access is not human rank

Current organization-paid employee seats were intentionally built as licensed product-access objects rather than work authority.

That distinction is retained and generalized conceptually:

> A paid connection may determine whether a person receives a particular Atlas delivery surface. It does not make that person a lesser kind of Atlas user, establish their institutional responsibility, define their visibility, or define their authority rank.

Terms such as “employee seat” may remain commercial or compatibility vocabulary while the product is migrated, but business logic must not reason from that label to conclusions such as:

- this person is subordinate;
- this person may see worker data;
- another person is automatically entitled to inspect or alter this person's work;
- this person cannot hold broader responsibility elsewhere;
- this credential is a separate class of Atlas identity.

Under the derived-aperture model, paying for delivery to a person never creates a hidden Person↔Ledger membership relation.

## 14. Responsibility flow

The intended work flow is not:

```text
owner -> assigns -> employee
```

It is:

```text
Ledger reality
  -> responsibility is situated with a Person according to governed responsibility authority
  -> visibility is independently established or absent
  -> if visibility and delivery rules admit it, the Person may receive an execution projection
  -> action / observation / result is returned to the Ledger
  -> the same institutional reality continues
  -> responsibility may remain, end, or move according to governed authority
```

The institution or Ledger does not cease to own its reality while a person carries responsibility for a piece of it.

“Returned” does not mean “finished.” A returned result can create the next state required by another piece of Company Work, another person, another process, or another domain projection.

## 15. Work Brief as projection, not data model

A person's current Work Brief is the composed **visible and deliverable intersection** of Company Work for which that Person carries relevant responsibility and which the surface is allowed to expose.

A Work Brief does not own tasks and does not create copies of Company Work.

Responsibility that is not independently visible to the Person remains canonical responsibility but is absent from that Person's Work Brief.

Dates, order, timing, guidance, and execution affordances describe how currently entrusted and visible work is exposed. They are not the canonical work identity.

The future broader Ledger surface should therefore be able to expose responsibility scaffolding according to the current viewer's visibility without treating a calendar or employee schedule as the source of truth.

## 16. Compatibility vocabulary

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

## 17. Migration law

Existing role-gated behavior must be migrated incrementally rather than globally reinterpreted.

For each old gate such as `is_organization_owner`, `farm_manager`, or employee-seat-specific exposure:

1. identify the institutional decision it currently protects;
2. identify the Ledger reality affected;
3. identify the scope of the requested action;
4. identify which existing canonical fact, if any, explicitly establishes the person's authority for that scope;
5. identify which independent visibility contract, if any, admits the relevant reality to the Person;
6. preserve fail-closed behavior if either required semantic dimension is absent;
7. retire the legacy role gate only after equivalent governed semantics are proven.

Do not replace old role checks with broad “organization member” checks. Equality of user kind does not mean equality of aperture.

Do not create a generic Person↔Ledger row as a shortcut around an unresolved authority or visibility question.

## 18. Immediate product consequence

The next responsibility-management surface should not be modeled as an owner/manager screen for managing employees.

It should be a Ledger projection that exposes only the responsibility scaffolding independently visible to the current person.

Within that projection, a person may be able to:

- inspect people and work beneath/intersecting their visible scope;
- see where responsibility is unresolved when that fact itself is visible;
- inspect current Company Work allocations and plans when admitted;
- alter only the facts for which their effective authority admits the mutation.

A narrower person looking at the same Ledger receives a narrower projection automatically.

The surface should therefore be designed only after the effective aperture resolver has a proven read contract and after each mutation shown by the surface can name an existing authority source.

## 19. Explicit non-scope

This architecture document does **not**:

- create a Person-to-Ledger aperture or membership table;
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

## 20. Questions that remain before executable aperture work

The Person-to-Ledger relationship question is settled: **there is no first-class connection object; effective aperture is derived.**

The responsibility/visibility question is also settled: **responsibility never creates visibility.**

The next executable tranche must stop for explicit design if existing canon does not answer these remaining questions:

1. What is the canonical generic visibility truth for Person + scoped Ledger reality, given that current exposure grants are employee-seat/organization-member compatibility structures and current Worker Day visibility still derives from assignment/placement?
2. What exact governed mappings establish scope containment/custody across Ledger, organization unit, domain object, Company Work, conversation, project, and other typed subjects?
3. Which explicit authority permits one person to move current Company Work responsibility to another person after legacy role gates are removed?
4. Which authority permits one person to change another person's planned date/order without conflating planning authority with responsibility authority?
5. Which existing role-gated contracts can be translated directly to current explicit authority evidence, and which require a new scoped authority seam?
6. How should a commercial delivery entitlement identify the relevant Person and surface without becoming institutional aperture evidence?
7. Should responsibility-without-visibility produce any diagnostic or adjudication requirement for another visible/authorized Person, or remain a silent legitimate state unless another rule notices it?

Until those questions are situated, Atlas should continue using the existing canonical work/responsibility objects and fail closed rather than inventing a second delegation model.
