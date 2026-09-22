# Atlas Canonical Person↔Institution Responsibility Realization v1

## Status

Architecture contract only. This tranche creates no schema, migration, RPC, production mutation, browser permission, or `/anna` application change.

This contract is based on an audit of the existing production `noel-core` organization structure and operates under:

- `atlas-canonical-person-v1.md`;
- `atlas-person-institution-effect-uptake-relationship-evidence-v1.md`;
- `atlas-responsibility-offer-and-relation-lifecycle-v1.md`;
- `atlas-standing-responsibility-intake-agreements-v1.md`;
- `atlas-event-effect-governed-uptake-v1.md`;
- `atlas-effective-position-authority-v1.md`.

## September 21, 2026 implementation correction

The earlier production audit in this document treated `Organization Membership` as the practical Person↔Organization affiliation carrier. That remains useful compatibility evidence for authenticated participants, but it is **not** sufficient as the universal institutional-human root because the live Membership schema requires `auth.users`.

Source migration `20260921150000_atlas_institutional_person_record_v1.sql` therefore introduces `atlas.institutional_person_records` as the Organization-scoped fact that a canonical Person is known to the institution without requiring a login.

This does **not** reverse the decision against a generic Person↔institution permission/responsibility table. Institutional Person Record creates no Position, employee status, seat, Responsibility, visibility, decision authority, action permission, or Company Work. Those remain separate governed relations.

Accordingly, references below that use Organization Membership as the necessary Person↔Organization identity carrier should now be read as authenticated compatibility paths. Future accountless institutional projections resolve through Canonical Person + Institutional Person Record, then compose Position/Responsibility/Work/access evidence independently.

## Purpose

Settle whether Atlas needs a new generic Person↔institution relationship object before a worker projection such as `/anna` can be grounded correctly.

The production audit establishes that Atlas already has the necessary institutional primitives:

```text
Canonical Person
  ↓
Organization Membership
  ↓
Organization Position Appointment
  ↓
Organization Position
  ↓
Position ↔ Responsibility
  ↓
Responsibility ↔ bounded institutional Scope/domain reality
```

The governing decision is:

> **Do not add a new generic Person↔institution responsibility table merely to restate reality already expressed by canonical Person, institution membership, position appointment, institutional responsibility, and responsibility Scope. Instead establish one canonical effective responsibility projection over those source facts.**

The existing primitives are the source evidence. The derived effective relation is the current-state read authority.

## 1. Existing source objects have distinct jobs

The current production design is already intentionally separated.

### Canonical Person

`atlas.people` is the durable human identity.

Authentication, employee access, organization-local identity, and payment do not create the Person.

A future Person-specific Ledger projection must ultimately resolve to Person rather than stop at `auth.users`, a seat, or an Organization Membership.

### Organization Membership

`atlas.organization_memberships` is the Person↔Organization affiliation/relationship compatibility substrate.

It can establish that a Person belongs to or participates in an Organization under a current institutional relationship.

It does not, by itself, identify what institutional reality the Person carries.

Therefore:

```text
membership != responsibility
membership != visibility
membership != institutional source for every effect
membership != Ledger membership
```

### Organization employee seat

`atlas.organization_employee_seats` is an organization-wide access/commercial delivery object.

The migration that introduced universal organization structure explicitly preserves this distinction:

```text
employee seats = billing/access
positions + appointments = institutional placement
```

Therefore an active employee seat may be required for an employee to enter the product, while remaining irrelevant to the ontology of what responsibility that employee carries once inside.

### Organization-local identity subject

`atlas.identity_subjects` remains an institution-local identity carrier.

It is useful for preserving the institutional identity through which appointments, employee credentials, and domain adapters resolve.

It is not a substitute for canonical Person.

For a cross-Ledger Person projection, Atlas must be able to resolve the institutional subject/membership to the canonical Person or fail closed where Person identity is materially required.

### Position

`atlas.organization_positions` defines a persistent institutional place inside an Organization Unit.

A position title is organization language, not authority.

The position provides a durable structural carrier to which institutional responsibilities may be attached.

### Position Appointment

`atlas.organization_position_appointments` records time-bounded occupancy of a position by an institutional identity/membership.

Appointment is therefore the existing durable source fact for:

```text
this institutional subject currently occupies this institutional position
```

It does not itself imply all possible responsibility, visibility, resource custody, or action authority.

### Organization Responsibility

`atlas.organization_responsibilities` names reusable institutional responsibilities such as stewardship or execution functions.

This is the correct existing vocabulary for durable institutional responsibility concepts.

### Position ↔ Responsibility relation

`atlas.organization_position_responsibilities` states which institutional responsibilities belong to a position and in what relationship, currently using values such as `accountable`.

This is position-definition evidence, not a work-item assignment.

### Responsibility Scope

`atlas.organization_responsibility_scopes` bounds an institutional responsibility to the Organization Unit or domain reality it stewards.

This is the existing local realization of the rule that responsibility must identify the governed reality being carried rather than remain a free-floating title.

### Work Allocation

`atlas.work_allocations` assigns a specific Company Work object to an Organization Membership.

That is a separate, item-specific responsibility relation.

It answers:

```text
Who currently carries this exact work item?
```

It does not answer:

```text
What durable institutional function does this Person carry?
```

Nor does a durable position automatically answer which specific work items are currently allocated to the Person.

### Farm Membership

`atlas.farm_memberships` remains a domain/execution adapter used by existing Worker Day machinery.

It can carry the execution identity needed by farm-specific runtimes.

It must not become the source of the Person's institutional responsibility when the Organization-level responsibility is already canonical.

Current production already records this distinction in Company Work carrier synchronization by marking legacy task/farm assignment as not itself responsibility evidence.

## 2. Canonical durable responsibility realization

For institutional position-based responsibility, Atlas should derive one effective relation conceptually shaped as:

```text
Person P
  carries
Organization Responsibility R
  within
Governed Scope S
  for
Institution / Organization Unit I
  because
P currently occupies Position Q
and Q currently carries R over S
with sufficient establishment/assent provenance
```

The source chain is:

```text
people
  ↓
organization_memberships.person_id
  ↓
organization_position_appointments
  ↓
organization_positions
  ↓
organization_position_responsibilities
  ↓
organization_responsibilities
  ↓
organization_responsibility_scopes
```

The derived relation is not a new source-of-truth object merely because consumers need a convenient row shape.

## 3. Proposed canonical read authority

A future executable implementation should create one side-effect-free canonical effective-position/responsibility projection, provisionally described here as:

```text
effective_person_institution_responsibility_v1
```

The exact executable name remains implementation-owned.

It should be able to expose at least:

- canonical `person_id`;
- organization/institution identity;
- Organization Membership identity used as current affiliation evidence;
- institution-local identity subject where applicable;
- appointment identity and appointment effective window;
- position identity, key, title, and Organization Unit;
- responsibility identity, key, name, and responsibility kind;
- position/responsibility relationship kind;
- bounded responsibility Scope/domain relation;
- establishment/assent basis where known;
- historical/effective time semantics;
- conflict or indeterminate state where the relation cannot be established safely;
- source provenance sufficient to explain why Atlas says the Person carries this responsibility.

Downstream consumers should not independently reconstruct this chain with slightly different filters.

This follows the already-established effective-position-authority law:

```text
source facts + lawful transition/history
        ↓
one canonical effective position
        ↓
all current-state consumers
```

## 4. Anna is already the production proof

Production currently contains the following coherent institutional chain:

```text
Person: Anna
  ↓
active Feast Guild Organization Membership
  ↓
active employee seat / credential for product access
  ↓
active primary appointment
  ↓
Position: Farm Steward
  ↓
Organization Unit: Elm
  ↓
Responsibilities:
  - Production stewardship
  - Harvest execution
  - Nursery care
  - Grounds readiness
  - Venue preparation
  ↓
each bounded to the Elm Organization Unit
```

Anna also has a separate active Elm Farm `farm_hand` membership used by farm execution compatibility machinery.

This means Atlas does **not** need to invent a new row saying merely:

```text
Anna has a relationship with Elm.
```

The relationship is already richly expressed.

The missing read seam is the ability to ask canonically:

```text
What Elm institutional responsibilities does Person Anna effectively carry now, and why?
```

## 5. Durable responsibility and item allocation must remain separate

A future `/anna` projection needs both layers.

### Durable layer

Examples:

```text
Production stewardship
Harvest execution
Nursery care
Grounds readiness
Venue preparation
```

These explain the institutional field Anna carries over time.

### Specific work layer

Examples are individual `work_allocations` over exact Company Work objects.

These explain which concrete work is currently Anna's responsibility.

The following inferences are prohibited:

```text
Anna is Farm Steward
-> every Elm work item belongs to Anna
```

and:

```text
this task is allocated to Anna
-> Anna is therefore Elm's Farm Steward
```

A task allocation may be consistent with a durable responsibility, may be a bounded delegated child responsibility, may be accepted through standing intake, or may be exceptional. The exact relationship must remain explainable rather than inferred solely from membership or title.

## 6. Current Company Work compatibility meaning

Production currently treats an active `work_allocations` row with `allocation_role='responsible'` as canonical responsibility for that exact Company Work item.

Current synchronization correctly treats legacy farm/task carrier delivery as downstream execution compatibility and explicitly preserves that carrier assignment is not responsibility evidence.

That distinction should remain.

However, the current owner mutation path can directly create or replace a `work_allocations` row for another Organization Membership.

Under the new generic responsibility law, that behavior must be treated as compatibility behavior rather than promoted into the universal rule:

```text
organization owner selected Person
-> receiver responsibility exists
```

Future cross-Person responsibility creation must resolve through the responsibility-offer / acceptance / standing-intake architecture, or through a truthful reconstruction/adjudication basis for responsibility that already exists.

The existing work-allocation table may remain the canonical exact-work carrier after lawful uptake. The point is that the **basis for creating the active allocation** must become governed.

## 7. Appointment does not eliminate receiver assent

A position is institutional structure.

An institution may define:

```text
Position Q
carries responsibilities R1..Rn
within Scopes S1..Sn
```

That does not mean the institution can silently make any Person the current carrier merely by writing an active appointment row.

For future generic creation, an active appointment that establishes Person responsibility must have a truthful establishment basis such as:

- explicit receiver acceptance of the position/responsibility bundle;
- a matching receiver-assented standing intake agreement;
- governed reconstruction of a relationship already existing in real life;
- an adjudicated institutional fact whose provenance establishes that the Person already carries the relationship;
- another future basis explicitly recognized by the responsibility lifecycle architecture.

Current migrated Anna rows are reconstruction evidence of an already-existing operational relationship. They must not be reinterpreted as proof that unilateral appointment is the generic creation rule.

## 8. Position definition changes cross the Person boundary too

This is the most important missing seam in the current static structure.

Suppose Anna accepted or is reconstructed as carrying:

```text
Farm Steward
  - Production stewardship
  - Harvest execution
```

If Elm later edits the position definition to add:

```text
- Treasury stewardship
```

Atlas must not conclude:

```text
Anna now carries Treasury stewardship
```

merely because the current join table now contains another row.

A position-definition change and a Person's uptake of that changed responsibility are distinct consequences.

A new responsibility added to a position may become current for an existing appointee only where Atlas has sufficient uptake basis, such as:

- the Person explicitly accepts the added responsibility;
- an active standing intake agreement already admits that bounded class of position-definition changes/responsibility offers;
- the new row is a governed reconstruction of responsibility already established in real life;
- another effect-specific rule truthfully establishes uptake.

The same law applies when a responsibility Scope is materially widened.

## 9. Historical definition must not be rewritten

The current production schema is adequate as a static institutional-structure seed, but two relationships are historically thin:

```text
organization_position_responsibilities
organization_responsibility_scopes
```

They currently identify present links but do not themselves preserve an append-only lifecycle for:

- addition;
- removal;
- supersession;
- narrowing;
- widening;
- relationship-kind change;
- Scope-definition change.

No active production mutation surface currently compensates for this with a canonical definition-event history.

Therefore the architecture rule is:

> **Do not make broad live editing of position responsibilities or responsibility Scopes authoritative until their changing definition can be reconstructed historically and one canonical effective definition projection exists.**

The existing seeded rows remain valid source evidence for the current static definition.

A future executable tranche may introduce append-only definition events or another equally auditable temporal source model, but this architecture does not prescribe final table names.

## 10. Effective responsibility must be historical

Atlas must be able to answer not only:

```text
What does Anna carry now?
```

but also:

```text
What did Anna carry at time T?
Why was that relation current then?
Which position definition was effective then?
Had Anna taken up that version of the responsibility then?
When was she released/completed/replaced?
```

Today's position definition cannot be projected backward onto an older appointment.

Likewise, today's narrower definition cannot erase historical responsibility that really existed.

This follows the same no-rewrite law already governing living Scope and event/effect history.

## 11. Membership, seat, appointment, and responsibility lifecycles do not collapse

These facts can change independently:

```text
Person exists
Organization Membership exists / ends
employee seat active / suspended / ended
credential active / retired
position appointment begins / ends
standing intake begins / ends
responsibility relation current / completed / released
specific work allocation active / released / completed
visibility admission active / withdrawn
```

Atlas must not use one lifecycle as a shortcut for another.

Examples:

- suspending a paid seat may remove application access without proving Anna ceased to carry an unresolved real-world responsibility;
- ending a standing intake agreement stops future automatic uptake but does not erase already-current responsibilities;
- ending an appointment may be strong evidence for releasing its durable position responsibilities but the resulting responsibility lifecycle must preserve the true effective event/basis;
- completing one work item does not complete the broader position responsibility;
- releasing one work allocation does not end the Farm Steward appointment;
- visibility can be narrower or broader than responsibility.

## 12. `/anna` source composition

A future `/anna` page should compose several independent projections.

Conceptually:

```text
CURRENT PERSON
  canonical Person = Anna

CONNECTION / DELIVERY
  active credential
  active commercial employee connection/seat where required

INSTITUTIONAL PLACEMENT
  active Organization Membership
  active effective position appointment(s)
  Organization Unit = Elm

DURABLE RESPONSIBILITY
  canonical effective Person↔institution responsibility projection

SPECIFIC CURRENT RESPONSIBILITY
  active exact-work Responsibility Relations / Company Work allocations

PENDING INTAKE
  responsibility offers awaiting Anna

STANDING INTAKE
  active receiver-assented agreements admitting bounded future offers

VISIBILITY
  independent governed exposure projection

EXECUTION ADAPTERS
  farm membership / Worker Day carriers only where domain execution needs them

ACTIVITY / RESULT HISTORY
  Anna's reports, observations, transitions, completion evidence
```

The page is then a projection of institutional reality relevant to Anna rather than a hard-coded employee dashboard.

## 13. Future Ledger connection consequence

A Ledger connection for Anna should not create another membership ontology.

The connection can answer:

```text
May this Person enter this product/institutional surface now?
```

The responsibility projection answers:

```text
What governed institutional reality does this Person carry?
```

Visibility answers:

```text
What governed institutional reality may this Person see in this context?
```

Work allocation answers:

```text
Which exact work items does this Person carry now?
```

These can then be intersected by the Ledger aperture without being collapsed.

## 14. No new generic relationship table

The audit does not justify introducing a table such as:

```text
person_institution_relationships
```

with generic fields such as:

```text
relationship_type
allowed_actions
scope
rank
permissions
```

Such a table would duplicate richer existing source objects and invite the permission-first architecture back into the system.

A new source object is justified only when Atlas discovers a real relationship that cannot truthfully be represented by the existing Person, Membership, Position, Appointment, Responsibility, Scope, Offer/Acceptance, custody, or specific-work primitives.

No such missing generic relationship has been established by the current audit.

## 15. Existing objects that are compatibility evidence, not the new ontology

The following may remain useful without becoming the generic model:

- `organization_memberships.role`;
- `organization_memberships.permissions`;
- `farm_memberships.role`;
- `principal_authority_allocations`;
- owner-specific work-allocation RPCs;
- seat class;
- endpoint send grants;
- legacy task assignment columns.

Where these provide real historical evidence, Atlas preserves them.

They must not outrank the canonical responsibility realization merely because older runtime paths already depend on them.

## 16. Minimal executable seam implied by this contract

When implementation begins, the smallest truthful seam is not a new ontology.

It is:

1. establish historical/effective definition semantics for mutable position responsibility/Scope definitions before exposing broad mutation;
2. establish one canonical effective Person↔institution responsibility read projection;
3. bind that projection to canonical Person rather than only auth user/seat;
4. keep employee seat/credential checks as access/delivery gates where commercially required;
5. keep exact Company Work allocation separate;
6. introduce governed offer/acceptance/standing-intake basis before generic future writes create cross-Person current responsibility;
7. migrate `/anna` reads to compose these authorities rather than infer from seat, farm role, or task placement.

No production migration is authorized by this architecture document itself.

## 17. Verification contract for a future executable tranche

A future implementation is incomplete unless it can prove at least:

1. Anna resolves from auth credential to one canonical Person;
2. Anna's current Feast Guild affiliation resolves without treating role text as responsibility;
3. Anna's current Farm Steward appointment resolves to Elm;
4. the five current Elm responsibilities resolve independently from the employee seat;
5. suspending/removing a seat does not rewrite historical responsibility evidence;
6. a responsibility outside the effective position definition does not appear merely because Anna is an employee;
7. a newly added position responsibility does not silently become Anna's current responsibility without lawful uptake basis;
8. a Scope widening does not silently widen Anna's responsibility without lawful uptake basis;
9. historical reads use the definition and uptake effective at the requested time;
10. Company Work allocation remains exact-work responsibility and does not manufacture durable position responsibility;
11. durable position responsibility does not auto-allocate all matching Company Work;
12. farm membership remains an execution/domain carrier and does not outrank Organization-level responsibility;
13. current Person responsibility can be explained with source provenance;
14. unresolved identity/definition/uptake evidence fails closed locally;
15. `/anna` can consume the canonical projection without acquiring direct table authority.

## Resulting law

> Atlas already has the source objects needed to represent durable Person↔institution responsibility. Canonical Person identifies the human; Organization Membership expresses affiliation; Position Appointment places the institutional subject; Position Responsibility and Responsibility Scope describe the durable institutional reality carried; Work Allocation describes exact work; seat/credential provides access; farm membership provides domain execution compatibility. Atlas should derive one canonical effective Person responsibility projection from those sources rather than add a generic relationship table. Before position definitions become broadly mutable, responsibility-definition changes and Person uptake must become historically reconstructable so a later edit cannot rewrite what the Person carried or silently impose new responsibility.