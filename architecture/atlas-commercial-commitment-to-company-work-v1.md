# Atlas Commercial Commitment to Company Work v1

**Status:** universal candidate contract  
**Date:** 2026-09-24  
**Parent:** `optical-lift/atlas/docs/architecture/ATLAS_UNIVERSAL_FULFILLMENT_INFRASTRUCTURE_V1.md`  
**Existing authorities reused:** Commercial Order, Commercial Order Line, Company Work Requirement  
**Persistence rule:** no new commitment/obligation table

---

## 1. Purpose

Atlas already has two separate universal truths:

### Commercial commitment

`atlas.commercial_orders`

Production Atlas documents this table as:

> Universal commercial commitment/sale record. Domain-specific fulfillment, production, booking, registration, or service-delivery facts live in typed extensions rather than on the universal order.

### Institutional requirement

`atlas.work_requirements`

Production Atlas documents this table as:

> Organization-owned requirement truth. A requirement exists independently of assignment, readiness, Day, Clock, or UI presentation.

The missing seam is therefore not a new obligation object.

It is:

~~~text
Commercial Order
→ domain interpretation of what must now be made true
→ Company Work Requirement(s)
~~~

---

## 2. Commitment boundary

Atlas core does **not** add a second "commercial commitment state" around Commercial Order.

If a domain's policy says payment must precede commitment, that domain must create the Commercial Order only once the payment condition has been satisfied.

For Feast Guild's prepay-first model, checkout should eventually persist:

~~~text
successful provider payment evidence
+ final accepted customer terms
→ one transaction establishes linked Commercial Payment + Commercial Order
~~~

The universal Commercial Order remains the commitment record.

A raw cart, quote, Offer Snapshot, pending payment, or payment attempt is not the order.

---

## 3. Why payment is not the universal trigger

Different institutions can become commercially committed at different boundaries:

- successful prepayment;
- signed contract;
- accepted purchase order;
- approved account terms;
- deposit;
- manual acceptance;
- another lawful commitment event.

Therefore Atlas core must not define:

~~~text
payment succeeded
→ always create fulfillment obligation
~~~

Instead:

~~~text
domain commitment policy
→ creates Commercial Order when commitment is real
→ Commercial Order may establish Company Work Requirements
~~~

This keeps payment and commitment distinct while allowing Feast Guild to require prepayment.

---

## 4. One order line does not equal one purchase

A Commercial Order Line describes what the customer bought.

It does not state how the institution will fulfill it.

Examples:

### Flowers

Order line:

~~~text
100 premium white roses
~~~

Possible Company Work requirement:

~~~text
secure 100 qualifying sellable roses by receiving cutoff
~~~

Coverage might later come from:

- owned inventory;
- local production;
- multiple suppliers;
- a mix.

### Construction

Order line:

~~~text
Install 2,400 sq ft white-oak flooring
~~~

Possible Work Requirements:

- secure 2,600 sq ft qualifying material;
- secure installer capacity;
- secure floor roller;
- complete site preparation;
- satisfy project deadline.

One commercial line creates multiple institutional requirements.

### Catering

Order line:

~~~text
Dinner service for 150
~~~

Possible Work Requirements:

- secure ingredient coverage;
- secure kitchen capacity;
- secure service labor;
- secure equipment;
- satisfy allergen/menu requirements;
- satisfy delivery/service timing.

Therefore the universal adapter must accept **explicit requirement specifications from the fitting domain**.

It may not infer "buy one supplier SKU per order line."

---

## 5. Domain adapter responsibility

A domain adapter supplies an array of requirement specifications.

Example:

~~~json
[
  {
    "requirementKey":"flowers",
    "sourceOrderLineId":"...",
    "requirementClass":"product_coverage",
    "summary":"Secure 100 qualifying premium white roses",
    "quantity":100,
    "unit":"stem",
    "specification":{
      "flowerFamily":"rose",
      "color":"white",
      "minimumLengthCm":50
    },
    "latestSatisfactoryAt":"2026-09-30T12:00:00Z",
    "consequenceOfDelay":{
      "customerPromiseAtRisk":true
    },
    "jurisdictionKey":"commerce.fulfillment_coverage"
  }
]
~~~

The adapter owns the meaning of:

- requirement class;
- quantity/unit;
- specification;
- timing;
- consequence;
- jurisdiction.

Atlas core validates and establishes the resulting Work Requirement.

---

## 6. Order-level requirements

Not every fulfillment requirement belongs to one line.

An adapter may omit `sourceOrderLineId`.

Then the Work Requirement is sourced from the Commercial Order itself.

Examples:

- deliver entire order by Thursday;
- reserve one route slot;
- complete one venue reset;
- obtain one order-wide permit;
- perform one order-wide quality review.

This preserves the difference between:

~~~text
line-specific requirement
and
order-wide requirement
~~~

---

## 7. Work Requirement mapping

V1 maps an accepted requirement specification to:

### `organization_id`

Copied from Commercial Order.

### `organization_unit_id`

Copied from Commercial Order.

### `requirement_kind`

Fixed to:

`fulfillment_coverage`

V1 does not create arbitrary Company Work kinds.

### `summary`

Domain-supplied, nonblank.

### `source_object_type`

- `commercial_order_line` when `sourceOrderLineId` is supplied;
- `commercial_order` otherwise.

### `source_object_id`

The fitting line/order UUID.

### `state`

`active`

### `established_at`

Commercial Order `created_at`.

This matters for reconstruction. If the adapter runs later, it does not pretend the institutional responsibility began later than the commitment.

### `requirement_began_at`

Domain-supplied or defaults to order `created_at`.

### `earliest_relevant_at`

Domain-supplied or defaults to `requirement_began_at`.

### `latest_satisfactory_at`

Required in v1.

A commercial fulfillment requirement without an operational boundary is not admitted by this adapter.

### `consequence_of_delay`

Domain-supplied JSON object.

### `jurisdiction_key`

Required, domain-supplied.

### `stable_key`

Deterministic:

~~~text
commercial_order:<order UUID>:fulfillment:<requirementKey>
~~~

### `metadata`

Preserves:

- source Commercial Order;
- source line if any;
- requirement key/class;
- quantity/unit if applicable;
- specification;
- domain metadata;
- interpretation basis;
- adapter contract version.

---

## 8. Requirement key

`requirementKey` is required and unique inside the adapter call.

It identifies one durable requirement within the order commitment.

Examples:

- `flowers`
- `material`
- `installer_labor`
- `floor_roller`
- `delivery`

Do not encode customer prose into the key.

The key is stable identity.

The summary is human-readable presentation.

---

## 9. Quantity semantics

Quantity is optional because not every requirement is naturally scalar.

When quantity is supplied:

- it must be > 0;
- unit is required.

When unit is supplied:

- quantity is required.

Quantity/unit live in Work Requirement metadata in v1 because the existing Company Work root is intentionally more general than quantified inventory/resource coverage.

Do not add quantity columns to `work_requirements` merely for commerce.

If later multiple live Company Work domains prove quantity belongs on the root, promote separately.

---

## 10. Specification

`specification` is optional JSON object.

It may contain domain-owned constraints.

Examples:

### Flowers

- family;
- color;
- grade;
- minimum stem length.

### Construction

- material;
- species;
- grade;
- dimensional specification.

### Catering

- menu requirement;
- allergen restriction;
- dietary constraint.

The Work Requirement stores the domain-provided specification as evidence of what must be covered.

The universal adapter does not interpret it.

Candidate Qualification consumes fitting requirement nodes separately.

---

## 11. Cancellation boundary

If the Commercial Order already has a `cancelled` Commercial Order Event, V1 must not create new active fulfillment Work Requirements.

The adapter returns/raises a blocked state.

This does **not** define what happens when an order is cancelled **after** Work Requirements already exist.

That later reconciliation is separate because cancellation may require:

- cancelling untouched requirements;
- preserving already-incurred supplier obligations;
- creating return/refund work;
- preserving non-refundable commitments;
- transferring/releasing reserved capacity.

Do not blindly cancel downstream Work when an order cancellation appears.

---

## 12. Idempotency

The deterministic Work Requirement stable key makes establishment idempotent.

Re-running the same interpretation:

~~~text
same order
+ same requirementKey
+ same normalized requirement truth
→ same Work Requirement
~~~

No duplicate.

But:

~~~text
same stable key
+ different structural truth
→ conflict
~~~

V1 must not silently rewrite the existing Work Requirement.

Changes after commitment should use later Company Work supersession/cancellation/repair semantics, not mutate history through an "ensure" helper.

---

## 13. Preview before write

V1 provides a read-only preview function.

It validates:

- order exists;
- order not already cancelled;
- requirement array shape;
- requirement keys unique;
- source order lines belong to the order;
- times parse correctly;
- latest satisfactory time is not before earliest relevant time;
- quantity/unit shape;
- specification/metadata/consequence objects;
- jurisdiction;
- existing stable-key compatibility.

It returns normalized prospective Work Requirements.

It creates no rows.

This gives the Implementation Workbench and future checkout orchestration a lawful "what would this commitment create?" seam.

---

## 14. Establishment service

The service writer:

1. runs the same validation;
2. fails closed on any violation;
3. inserts only missing compatible Work Requirements;
4. returns existing compatible requirements idempotently;
5. never updates existing requirement truth;
6. creates no Work Item;
7. creates no purchase;
8. creates no reservation;
9. creates no inventory;
10. creates no Spend;
11. creates no fulfillment event.

It establishes responsibility.

Nothing more.

---

## 15. Requirement versus carrier

After requirements exist:

~~~text
Work Requirement
→ qualification/planning
→ carrier/source selection
→ source-owned securing action
~~~

Possible carriers include:

- owned inventory;
- production;
- worker capacity;
- equipment;
- supplier purchase;
- rental;
- subcontractor.

The Work Requirement does not name the carrier in advance.

---

## 16. Requirement versus Work Item

A Work Requirement is institutional responsibility.

A Work Item is concrete work.

Existing `work_requirement_links` already relates them using roles such as:

- advances;
- resolves;
- investigates;
- enables;
- protects.

V1 does not automatically create Work Items.

Example:

~~~text
Requirement:
secure 100 carnations

Possible Work Items:
- review supplier bids
- place supplier order
- harvest Elm carnations
- receive/condition product
~~~

Those are later execution/planning decisions.

---

## 17. Feast Guild adapter

Feast Guild's first adapter can translate a committed flower order into Work Requirements such as:

~~~text
line: 100 standard carnations
→ requirement:
  secure 100 qualifying sellable carnations
  before receive-by boundary
~~~

and an order-wide requirement such as:

~~~text
deliver complete order to florist by Thursday 9:00 a.m.
~~~

The flower adapter supplies the flower specification.

The universal commitment-to-work service does not know what a carnation is.

---

## 18. Construction leak test

One order line:

~~~text
Install 2,400 sq ft flooring
~~~

can legitimately produce:

~~~text
material coverage
labor coverage
equipment coverage
completion boundary
~~~

all sourced from the same Commercial Order Line but identified by distinct requirement keys.

If V1 cannot represent this without schema change, the contract has leaked flower assumptions.

---

## 19. Function contracts

### `atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)`

Read-only.

Inputs:

- Commercial Order ID;
- requirement specifications;
- interpretation basis.

Returns:

- order identity/scope;
- blocked/ready state;
- violations/warnings;
- normalized prospective Work Requirements;
- existing compatible Work Requirement IDs where applicable;
- count that would be created.

### `atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)`

Service-only writer.

Returns:

- Work Requirement IDs;
- created/existing counts;
- normalized requirement identities;
- truth boundary.

---

## 20. Security boundary

Both functions are internal service functions.

- `anon`: no execute;
- `authenticated`: no execute;
- `PUBLIC`: no execute;
- `service_role`: execute.

The implementation does not require `SECURITY DEFINER`.

The service role already has the necessary Company Work privileges.

This preserves ordinary Postgres privilege enforcement and avoids unnecessary RLS bypass.

---

## 21. Validation requirements

V1 must prove:

1. one order line can create one requirement;
2. one order line can create multiple requirements;
3. one order can create order-wide requirements;
4. another order's line cannot be used;
5. deterministic stable keys;
6. rerun is idempotent;
7. same stable key with changed truth conflicts;
8. cancelled order blocks new requirements;
9. requirement establishment time equals order commitment creation time;
10. quantity/unit remain metadata, not new Company Work columns;
11. specification remains domain-owned metadata;
12. no Work Items are created;
13. no purchase/Spend/inventory/payment/fulfillment truth is created;
14. browser roles cannot invoke writer/preview;
15. service functions are not SECURITY DEFINER;
16. flower and construction-shaped requirement arrays use the same writer.

---

## 22. Governing result

The universal commitment seam is:

~~~text
domain policy establishes real commitment
→ Commercial Order
→ explicit domain requirement interpretation
→ Company Work Requirement(s)
→ later qualification/planning/coverage/execution
~~~

Not:

~~~text
payment
→ supplier purchase
~~~

and not:

~~~text
one order line
→ one procurement obligation
~~~

Atlas preserves the institution's responsibility before choosing the carrier.
