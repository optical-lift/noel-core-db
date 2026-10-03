# Atlas Reality / Ledger Booking Offering, Requirements & Routing v1

**Status:** live kernel under canonical source custody  
**Established:** September 26, 2026  
**Parent scheduling constitution:** `architecture/ATLAS_REALITY_LEDGER_SCHEDULING_CONSTITUTION_V1.md`

## 1. Purpose

Scheduling becomes genuinely reusable only when Atlas can distinguish:

1. **what may be requested**;
2. **what must be true or available to fulfill it**; and
3. **how eligible fulfillment candidates may be selected**.

Those are separate from the eventual Booking, Occurrence, Resource Claim, Commercial transaction, or human assignment.

This kernel therefore establishes three universal scheduling primitives:

```text
Booking Offering
  → composite fulfillment requirements
  → routing policy / eligible candidates
```

They sit upstream of the existing request / hold / approval / booking path:

```text
Offering
→ requested interval / intent
→ requirement evaluation
→ Request
→ provisional Hold where appropriate
→ Approval where required
→ Booking
→ Resource Claims
→ canonical Occurrence / actualization
```

## 2. Root law

> **An Offering defines repeatable scheduling intent. Requirements describe what fulfillment needs. Routing chooses among already-eligible candidates. None of those acts is itself a Booking, assignment, authority grant, payment, or realized Occurrence.**

## 3. Booking Offering

`ledger.booking_offerings` is a Ledger-owned reusable scheduling definition.

It may describe something as different as:

- a consultation;
- an inspection;
- a delivery window;
- a laboratory session;
- use of equipment;
- a repair appointment;
- a lesson;
- a room reservation;
- a vehicle reservation;
- a recurring institutional service;
- or any other repeatable time-bound commitment.

The table intentionally uses no industry-specific noun such as appointment type, venue package, medical service, salon service, class type, or desk reservation.

An Offering carries only the scheduling definition Atlas needs now:

- Ledger custody;
- stable identity within that Ledger;
- ordinary name / description;
- booking kind produced downstream;
- occurrence type produced downstream;
- default duration;
- lifecycle state;
- metadata / provenance.

### 3.1 Offering != Commercial Offering

Existing `atlas.commercial_offerings` belong to commercial/product semantics.

A thing can be commercially sold without being schedulable.

A schedulable Offering can exist without a price or Sale.

A future typed reference may relate the two, but neither owns the other.

### 3.2 Offering != Teaching Offering

Existing teaching/course offerings express education-specific semantics.

A scheduling Offering may later reference a teaching offering when a course/session is schedulable, but the scheduling kernel does not inherit education vocabulary.

### 3.3 Offering != Booking

The Offering is repeatable definition.

A Booking is one Ledger commitment involving one concrete occurrence/time context.

### 3.4 Offering != Occurrence

An Offering may describe the kind of occurrence that will eventually be established or associated.

It is not itself a real-world occurrence.

### 3.5 Offering lifecycle

Current states:

- `draft`;
- `active`;
- `inactive`;
- `retired`.

A new Offering must begin non-active, receive a valid requirement graph, and only then be activated.

An active Offering's structural scheduling definition is frozen. Change requires explicit deactivation first.

A retired Offering is historical and immutable.

This prevents a reusable definition from changing underneath outstanding requests or human expectations without an explicit lifecycle transition.

## 4. Composite fulfillment requirements

The requirement system answers:

> **What must be satisfiable for this Offering to be fulfillable?**

It does not answer:

> Who has already been assigned?

or:

> What has already been reserved?

### 4.1 Requirement groups

`ledger.booking_offering_requirement_groups` forms a nested tree.

Each group uses one of three operators:

- `all` — every active child must be satisfiable;
- `any` — at least one active child must be satisfiable;
- `minimum` — at least N active children must be satisfiable.

Exactly one root group exists per Offering.

This supports structures such as:

```text
ALL
├── one qualified host
├── ANY
│   ├── Room A
│   ├── Room B
│   └── Room C
└── one vehicle
```

or:

```text
ALL
├── one machine of kind X
└── MINIMUM 2
    ├── technician A
    ├── technician B
    └── technician C
```

An empty group is never considered satisfied.

### 4.2 V1 requirement atoms

V1 admits only two requirement kinds whose truth Atlas already understands:

1. `resource`
2. `seat_responsibility`

This is deliberate restraint.

Atlas does not invent a generic employee-skill ontology merely because commercial booking systems call things staff, providers, technicians, doctors, instructors, or hosts.

### 4.3 Resource requirement

A Resource requirement may select:

- one specific canonical `reality.resources` Resource; **or**
- any Resource of a canonical Resource kind owned by the Offering Ledger's subject Entity.

It also declares the Resource Claim semantics it would require:

- exclusive;
- shared;
- capacity + quantity.

A Resource requirement is not a Resource Claim.

It says what would need to be claimed if the request later becomes an actual Booking.

### 4.4 Seat-responsibility requirement

A Seat-responsibility requirement says fulfillment needs one or more active Ledger Seats that already carry a named active `ledger.seat_responsibilities` responsibility.

This reuses Atlas authority/responsibility vocabulary instead of creating booking-specific staff types.

A requirement for a responsibility does **not** grant that responsibility.

A routed candidate must already possess it.

## 5. Requirement != assignment

This distinction is constitutional:

```text
requirement
!= candidate
!= selection
!= assignment
!= Resource Claim
!= authority
```

Examples:

- “needs one room” is a requirement;
- “Conference Room is currently available” is candidate evidence;
- “choose Conference Room” is a routing/selection result;
- “Conference Room is claimed 2–3 PM” is occupancy truth.

Likewise:

- “needs a Seat responsible for X” is a requirement;
- “Seat 123 currently carries X” is eligibility evidence;
- selecting Seat 123 does not change that Seat's authority or responsibility.

## 6. Fulfillment routing

Routing answers:

> **Among candidates that already satisfy the requirement, how may Atlas select or recommend one?**

Current modes are:

- `manual`;
- `requester_choice`;
- `first_eligible`;
- `ordered_priority`.

### 6.1 Manual

Atlas exposes eligible candidates but makes no recommendation.

### 6.2 Requester choice

The requesting actor may choose among eligible candidates, subject to later governed validation.

This does not mean every candidate becomes publicly visible; knowledge jurisdiction still governs presentation.

### 6.3 First eligible

Atlas may deterministically recommend the first eligible candidate without interpreting configured business priority.

This is useful when identity does not matter and the institution merely needs one valid fulfiller.

### 6.4 Ordered priority

Atlas may recommend the highest-priority eligible candidate according to explicit configured priority.

Priority is institutional routing preference, not authority.

### 6.5 Why V1 has no balanced routing

Systems such as appointment schedulers often expose round-robin or workload balancing.

Atlas does not yet have one canonical cross-domain workload metric.

Therefore V1 intentionally does **not** claim to support `balanced`, `least_loaded`, or similar routing modes.

Those may be added only after Atlas can state exactly which governed operational quantity is being balanced.

## 7. Explicit routing candidates

`ledger.booking_offering_routing_candidates` can constrain a routing policy to a curated candidate set.

A Resource candidate must:

- belong to the Offering Ledger subject Entity;
- match the requirement's specific Resource or Resource kind.

A Seat candidate must:

- belong to the same Ledger;
- already possess the required active responsibility while the candidate is active.

Historical inactive routing rows may remain even if the Seat later loses that responsibility.

This preserves historical truth without allowing stale candidates to remain active.

## 8. Time-availability truth boundary

Resource time availability is already governed in Atlas.

For Resource requirements, Offering evaluation can call the existing Resource availability/conflict service for the requested interval and therefore say whether enough candidate Resources are actually available.

Person free/busy is **not yet** a first-class canonical kernel.

Therefore a Seat-responsibility requirement can currently establish:

- Seat exists;
- Seat is active;
- Seat belongs to the Ledger;
- Seat currently possesses the required responsibility;
- Seat is therefore an eligible fulfillment candidate.

It cannot yet truthfully establish:

- that Person is free during the requested interval.

The evaluator must preserve this boundary explicitly:

```text
seat eligibility known
!=
Person free/busy known
```

Consequently:

- Seat requirements may be `potentiallySatisfiable=true`;
- they remain `fullyTimeVerified=false` until canonical Person free/busy exists.

A composite Offering containing both Resources and Seats may therefore be potentially satisfiable while still not fully time verified.

That is not an error. It is accurate incomplete truth.

## 9. Active-definition integrity

Once an Offering is active:

- its booking kind cannot change;
- its occurrence type cannot change;
- its default duration cannot change;
- its requirement graph cannot be replaced.

The human must deliberately deactivate it before structural editing.

Name, description, presentation metadata and lifecycle state may still change through the governed service where allowed.

This prevents existing scheduling intent from silently changing shape.

## 10. Authority membrane

Offering reads/writes remain subordinate to Ledger Seat responsibility.

The active institutional scheduling responsibility now includes:

- `offering.read`;
- `offering.manage`.

Authenticated application access is exposed only through Atlas self APIs.

Internal `ledger.*` services remain non-executable to API roles.

Current self APIs:

- `atlas.ledger_booking_offerings_self_api_v1`;
- `atlas.ledger_booking_offering_self_api_v1`;
- `atlas.evaluate_ledger_booking_offering_self_api_v1`;
- `atlas.upsert_ledger_booking_offering_self_api_v1`;
- `atlas.replace_ledger_booking_offering_requirement_graph_self_api_v1`.

Possessing a bearer token does not establish Offering authority.

Routing a Seat does not establish Offering-management authority.

## 11. Evaluation contract

`ledger.evaluate_booking_offering_v1` / the authenticated wrapper evaluate one Offering against one requested interval.

The result separates:

- definition completeness;
- potential satisfiability;
- full time verification;
- nested group evaluation;
- eligible candidates;
- Resource availability evidence;
- routing mode;
- optional recommendation;
- explicit truth boundaries.

The evaluator does not create:

- Request;
- Hold;
- Booking;
- Resource Claim;
- Occurrence;
- Seat responsibility;
- assignment.

It is a governed read/evaluation membrane.

## 12. Proof

A rollback-only live proof established a generic Offering containing:

```text
ALL
├── ANY
│   ├── any reservable room
│   └── one specific shared Resource
└── one Seat carrying a temporary generic fulfillment responsibility
```

The proof established that:

- the nested `ALL` + `ANY` graph was potentially satisfiable;
- the room requirement was fully time verified through real Resource availability;
- `first_eligible` returned a Resource recommendation;
- the Seat requirement found an eligible explicitly prioritized candidate;
- `ordered_priority` returned that candidate;
- the Seat requirement remained not fully time verified because Person free/busy is not canonical;
- structural mutation of an active Offering was rejected;
- requirement-graph replacement on an active Offering was rejected.

The proof transaction rolled back. No proof Offering or temporary Seat responsibility remains in production.

## 13. First-adopter restraint

Existing Elm Resources were used only as real production fixtures for Resource availability.

No Elm noun, venue type, event-center concept, floral concept, or booking package has been added to the universal schema.

The same primitives can describe scheduling needs for professional services, education, medicine, repair, transportation, manufacturing, laboratories, equipment fleets, coworking, interviews, inspections, deliveries, or other institutions.

## 14. Next governed seam

The next database integration should connect Booking Request to Offering without collapsing their identities.

A future request should be able to say, in substance:

```text
I want Offering X
for interval Y
with these requester choices / contextual facts
```

Atlas can then:

1. evaluate the Offering requirements;
2. preserve requester-selected candidates where policy permits;
3. create provisional Resource holds where warranted;
4. route unresolved fulfillment decisions;
5. require approval where policy requires it;
6. materialize the existing Booking + Resource Claim path exactly once.

The Request must reference the Offering definition/version or an immutable snapshot sufficient to explain what was requested even if the Offering later changes.

That is the next seam. It is not implemented implicitly by this V1 kernel.

## 15. Governing tests

Before extending this kernel, ask:

1. Is this describing reusable scheduling intent or one actual commitment?
2. Is the concept really scheduling-specific, or already owned by Commercial, Teaching, Work, Responsibility, Reality, or another kernel?
3. Is a requirement being confused with an assignment or claim?
4. Does a routed candidate already possess the required eligibility/authority?
5. Is routing being mistaken for authority?
6. Is Resource availability being evaluated from canonical claims/availability rather than UI inference?
7. Are we claiming Person availability where Atlas only knows Seat eligibility?
8. Does the model require an industry-specific noun that can be replaced by a functional primitive?
9. Can an active reusable definition change underneath existing requests without an explicit lifecycle transition?
10. Does the result remain truthful if every presentation layer and external booking provider disappears?

If those answers are not clear, the extension is not yet governed.
