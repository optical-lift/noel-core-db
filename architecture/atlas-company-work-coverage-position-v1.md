# Atlas Company Work Coverage Position v1

**Status:** universal read-only candidate  
**Date:** 2026-09-24  
**Parent:** `architecture/atlas-commercial-commitment-to-company-work-v1.md`  
**Persistence rule:** no generic coverage-link table in v1  
**Existing live securing sources:** flower allocations, production-capacity reservations, seed allocations, work allocations  
**Future source:** external acquisition commitment

---

## 1. Purpose

Once a Commercial Order has established Company Work Requirements, Atlas needs to answer:

> **How much of this institutional requirement is actually secured by source-owned reality right now?**

Atlas already has multiple securing mechanisms:

- flower inventory allocation;
- production-capacity reservation;
- seed-lot allocation;
- work allocation;
- future supplier/external acquisition commitment;
- future equipment reservation;
- other domain-owned securing facts.

These sources do not share one table and should not be forced into one.

V1 therefore evaluates explicit coverage facts against an existing `atlas.work_requirements` row.

It persists nothing.

---

## 2. Governing law

~~~text
Company Work Requirement
!=
source allocation / reservation / purchase / assignment
~~~

The Work Requirement owns:

> what the institution must make true.

The source object owns:

> what has actually been allocated, reserved, committed, or assigned.

The coverage evaluator owns only:

> whether the currently supplied source facts cover the requirement.

---

## 3. Why no universal coverage table yet

Existing source domains already preserve their own history and state.

Examples:

### Flower demand allocation

Owns a quantity from a specific Ready lot.

### Production-capacity reservation

Owns reserved quantity, unit, window, and tentative/confirmed/released/consumed state.

### Seed allocation

Owns reserved seed quantity and allocation state.

### Work allocation

Owns responsibility/custody of a Work Item by an institutional carrier.

These meanings are not identical.

A new generic `secured_coverage` table would risk duplicating those truths before Atlas knows what must persist cross-domain.

V1 therefore uses opaque source references and explicit normalized coverage facts.

---

## 4. Coverage fact contract

Each coverage fact has:

~~~json
{
  "coverageKey":"ready-lot-123",
  "sourceRef":{
    "sourceDomain":"flower_demand_allocation",
    "sourceRef":"..."
  },
  "state":"secured",
  "quantity":40,
  "unit":"stem",
  "evidence":[
    {
      "source":"flower_demand_allocation"
    }
  ]
}
~~~

Required:

- `coverageKey`;
- `sourceRef.sourceDomain`;
- `sourceRef.sourceRef`;
- `state`.

Allowed states:

- `secured`;
- `provisional`;
- `released`;
- `failed`;
- `unresolved`.

The adapter that reads the source domain determines which normalized state is supported.

Core does not infer a source state from prose.

---

## 5. State semantics

### secured

Source-owned reality establishes current coverage.

Examples:

- confirmed inventory allocation;
- accepted supplier order;
- confirmed production reservation;
- active assigned capacity where that domain says assignment secures the requirement.

Counts toward hard coverage.

### provisional

A possible/tentative securing fact exists, but the institution is not yet entitled to treat it as hard coverage.

Examples:

- tentative production reservation;
- supplier quote not yet accepted;
- planned worker assignment not yet committed where the domain requires confirmation.

Does not count toward hard coverage.

### released

Coverage existed or was proposed but has been released.

Does not count.

### failed

The source path failed.

Does not count.

### unresolved

Atlas does not have enough evidence to classify the source as secured or failed.

Does not count, and remains visible.

---

## 6. Quantified Work Requirements

The commitment adapter stores quantity/unit in:

~~~text
work_requirements.metadata
  .commercialFulfillment.quantity
  .commercialFulfillment.unit
~~~

When both exist, V1 evaluates quantified coverage.

For `secured` and `provisional` facts:

- quantity is required;
- quantity must be > 0;
- unit must equal the Work Requirement unit.

No implicit unit conversion.

A domain adapter must normalize source quantity into the requirement unit before calling the evaluator.

---

## 7. Quantified position

For quantified requirements:

~~~text
securedQuantity
=
sum(quantity where state = secured)
~~~

~~~text
provisionalQuantity
=
sum(quantity where state = provisional)
~~~

Hard coverage states:

- `none` — secured quantity = 0;
- `partial` — 0 < secured < required;
- `exact` — secured = required;
- `overcovered` — secured > required.

`fullySecured` is true for exact or overcovered.

Overcoverage remains explicit.

It is not silently discarded.

---

## 8. Non-quantified Work Requirements

Some Work Requirements are not naturally scalar.

Examples:

- obtain a permit;
- complete final quality review;
- secure one approval state whose meaning is not a count.

For these, a secured/provisional fact uses:

~~~json
{
  "extent":"full"
}
~~~

or:

~~~json
{
  "extent":"partial"
}
~~~

Hard coverage states:

- `none`;
- `partial`;
- `full`.

One `secured/full` source fact is enough for full hard coverage.

The evaluator does not decide whether a domain should have represented the requirement quantitatively instead.

---

## 9. Source adapters remain authoritative

Examples of future adapters:

~~~text
flower_demand_allocations
→ secured flower coverage facts
~~~

~~~text
production_capacity_reservations
confirmed
→ secured production-capacity coverage fact

tentative
→ provisional coverage fact

released
→ released coverage fact
~~~

~~~text
work_allocations
→ fitting labor/custody coverage fact
~~~

~~~text
external acquisition commitment
accepted
→ secured external coverage fact
~~~

Each adapter owns the translation from source state into the normalized coverage state.

The universal evaluator does not query or mutate those domains.

---

## 10. Coverage is not fulfillment

Even full secured coverage does not mean the customer outcome has been fulfilled.

~~~text
100 stems secured
!=
100 stems received
!=
100 stems conditioned
!=
100 stems delivered
~~~

Likewise:

~~~text
16 labor-hours secured
!=
16 labor-hours worked
~~~

Coverage is upstream of execution/fruit.

---

## 11. Coverage is not Work Requirement satisfaction

V1 does not mutate:

~~~text
work_requirements.state
~~~

A Work Requirement may need to remain active after resources are secured because execution has not occurred.

Example:

~~~text
Requirement:
secure and deliver 100 flowers
~~~

If the adapter modeled that as one requirement, merely securing inventory may not satisfy the whole requirement.

More commonly the domain should create separate requirements:

~~~text
secure 100 qualifying flowers
deliver complete order
~~~

Then securing the flowers may support satisfying the first requirement but not the second.

Requirement closure remains a governed later seam.

---

## 12. Coverage facts are explicit inputs

V1 does not search all Atlas domains by itself.

Why:

- each domain has different state semantics;
- implicit joins would hard-code current domains into the universal evaluator;
- source adapters need to preserve their own evidence and authority.

The movement is:

~~~text
source-owned fact
→ domain coverage adapter
→ normalized coverage fact
→ universal coverage evaluator
~~~

---

## 13. Candidate function

`atlas.work_requirement_coverage_position_v1(uuid,jsonb)`

Inputs:

- Work Requirement ID;
- coverage-fact array.

Returns:

- requirement identity/state;
- quantified/nonquantified mode;
- required quantity/unit where applicable;
- secured quantity;
- provisional quantity;
- hard coverage state;
- fully secured flag;
- unresolved/provisional/released/failed counts;
- normalized coverage facts;
- truth boundary.

No writes.

---

## 14. Validation requirements

V1 must prove:

1. zero facts → no coverage;
2. partial secured quantity;
3. exact secured quantity;
4. overcoverage;
5. provisional quantity does not count as hard coverage;
6. unresolved remains unresolved;
7. released/failed facts do not count;
8. unit mismatch fails closed;
9. duplicate coverage keys fail closed;
10. nonquantified partial/full semantics;
11. coverage creates no Work Requirement state transition;
12. coverage creates no source allocation/reservation/purchase truth;
13. source references remain opaque;
14. flower-inventory and labor-capacity shaped facts use the same evaluator;
15. browser roles cannot invoke the evaluator.

---

## 15. Governing result

The universal coverage seam is:

~~~text
Company Work Requirement
+ explicit normalized facts from source-owned securing domains
→ current coverage position
~~~

not:

~~~text
Company Work Requirement
→ universal allocation row
~~~

and not:

~~~text
supplier quote
→ secured coverage
~~~

Atlas can see what is covered without stealing truth from the domains that actually secured it.
