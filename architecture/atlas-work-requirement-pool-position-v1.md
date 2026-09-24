# Atlas Pooled Fulfillment / Break-Bulk Position v1

**Status:** universal read-only candidate  
**Date:** 2026-09-24  
**Parents:**  
- `architecture/atlas-neutral-fulfillment-composition-v1.md`  
- `architecture/atlas-commercial-commitment-to-company-work-v1.md`  
- `architecture/atlas-company-work-coverage-position-v1.md`  

**Persistence rule:** no universal pool/allocation table in v1  
**First proof:** one bulk flower source apportioned across several florist commitments  
**Leak test:** one bulk construction-material source apportioned across several jobs

---

## 1. Purpose

Atlas can already answer:

~~~text
one requirement
← several possible source candidates
~~~

The missing inverse is:

~~~text
one source pool
→ several independent requirements
~~~

That is the universal structure behind wholesale break-bulk distribution, splitting one supplier pack across customers, allocating one owned lot across commitments, distributing one material pallet across jobs, and similar shared-source problems.

The v1 question is:

> **Given one proposed source pool and several quantified Company Work Requirements, how can that pool be apportioned across those requirements, what demand remains uncovered, what source output remains excess, and what economics attach to the pool?**

This is planning/evaluation. It creates no purchase and no allocation.

---

## 2. The business-model proof

Example:

~~~text
Wickman's requirement:   40 carnations
Flowerama requirement:   30 carnations
Buyer C requirement:     20 carnations

Aggregate outstanding:   90 carnations

Supplier minimum pack:  100 carnations
Supplier pool output:   100 carnations
~~~

Proposed break-bulk plan:

~~~text
40 → Wickman's
30 → Flowerama
20 → Buyer C
10 → excess
~~~

Atlas must preserve separately:

1. each customer's Work Requirement;
2. the one source pool;
3. each planned share of that pool;
4. the 10-unit excess;
5. the pool's shared economics.

It must not fake three smaller supplier purchases when the source reality is one 100-unit pack.

---

## 3. Why this is not a generic allocation table

Existing Atlas domains already own real securing/allocation truth, including flower demand allocations, seed-lot allocations, production-capacity reservations, and work allocations.

Those rows mean something has actually been allocated, reserved, or assigned according to that source domain's law.

The pooled-fulfillment evaluator is earlier:

~~~text
possible source pool
→ proposed distribution across requirements
~~~

Therefore its planned shares are not source allocations. V1 persists nothing.

---

## 4. One source pool in v1

V1 evaluates exactly one source pool.

A source pool may represent one supplier case/pack/pallet, one owned lot, one production batch, one service-capacity block, one rental block, or another source-owned candidate.

Required source identity:

~~~json
{
  "sourceRef":{
    "sourceDomain":"external_supply_offering",
    "sourceRef":"..."
  }
}
~~~

Core treats the reference as opaque.

---

## 5. Source quantity and usable output quantity

The source pool distinguishes acquisition/input quantity from usable output quantity.

Example:

~~~text
sourceQuantity = 100 stems purchased
outputQuantity = 95 qualifying sellable stems
~~~

or:

~~~text
sourceQuantity = 2,808 sq ft purchased
outputQuantity = 2,600 sq ft usable project coverage
~~~

Packet fields:

- `sourceQuantity > 0`;
- `sourceUnit`;
- `outputQuantity > 0`;
- `outputUnit`.

The transformation/yield law is supplied by the source/domain adapter. V1 never invents yield.

---

## 6. Requirements must already exist

Each proposed use references an existing Company Work Requirement.

That gives Atlas canonical demand quantity and unit from:

~~~text
work_requirements.metadata
  .commercialFulfillment.quantity
  .commercialFulfillment.unit
~~~

V1 requires quantified requirements. Nonquantified requirements belong in other planning seams.

---

## 7. Existing secured coverage

A Work Requirement may already be partly secured before the proposed pool is considered.

Example:

~~~text
required = 100 stems
already secured from owned inventory = 40
outstanding before proposed supplier pool = 60
~~~

Each planned use may therefore include:

~~~json
{
  "existingCoverageFacts":[ ... ]
}
~~~

V1 calls `atlas.work_requirement_coverage_position_v1(...)` to derive current hard secured quantity.

Then:

~~~text
outstandingBeforePool
=
max(requiredQuantity - alreadySecuredQuantity, 0)
~~~

The proposed pool may only plan against the outstanding requirement. This prevents double-coverage from being hidden.

---

## 8. Planned-use contract

Example:

~~~json
{
  "useKey":"wickmans",
  "workRequirementId":"...",
  "qualificationState":"qualified",
  "plannedQuantity":40,
  "unit":"stem",
  "existingCoverageFacts":[]
}
~~~

Required:

- unique `useKey`;
- `workRequirementId`;
- `qualificationState = qualified`;
- `plannedQuantity > 0`;
- unit equal to both the Work Requirement unit and source pool output unit.

A source candidate that is unresolved or incompatible with that specific requirement cannot be planned into the pool.

Qualification remains directional:

~~~text
this source
→ this requirement
~~~

---

## 9. Per-requirement position

For each Work Requirement:

~~~text
requiredQuantity
alreadySecuredQuantity
outstandingBeforePool
plannedFromPool
outstandingAfterPool
~~~

Derived planned coverage state after this pool:

- `already_secured`;
- `uncovered`;
- `partial`;
- `exact`;
- `overplanned`.

`overplanned` is invalid in v1. The proposed pool may not assign more to a requirement than its outstanding quantity.

---

## 10. Pool quantity position

~~~text
plannedOutputQuantity
=
sum(plannedQuantity)
~~~

~~~text
excessOutputQuantity
=
max(outputQuantity - plannedOutputQuantity, 0)
~~~

~~~text
unallocatedDemandQuantity
=
sum(outstandingAfterPool)
~~~

Pool utilization state:

- `unused` — no output planned;
- `partial_use` — planned < output;
- `fully_used` — planned = output.

If planned > output, packet is invalid.

Demand position:

- `none_covered`;
- `partially_covered`;
- `all_covered`.

These dimensions are deliberately separate.

Example:

~~~text
supplier pack output = 100
aggregate demand = 90
planned = 90

pool utilization = partial_use
demand position = all_covered
excess = 10
~~~

That is the normal break-bulk case.

---

## 11. Pool cost components

The source pool may carry the same cost-component shape used by neutral fulfillment composition:

~~~json
[
  {
    "componentKey":"merchandise",
    "state":"known",
    "amount":31.00,
    "currency":"USD"
  },
  {
    "componentKey":"freight",
    "state":"known",
    "amount":7.00,
    "currency":"USD"
  }
]
~~~

Allowed states:

- `known`;
- `unresolved`;
- `not_applicable`.

Unknown never becomes zero. No implicit FX conversion.

---

## 12. Economic position

When all required cost components are known in one currency:

~~~text
sourceBasisUnitCost
=
knownPoolCost / outputQuantity
~~~

The evaluator may derive:

~~~text
allocatedOutputCostBasis
=
sourceBasisUnitCost * plannedOutputQuantity
~~~

~~~text
excessOutputCostBasis
=
sourceBasisUnitCost * excessOutputQuantity
~~~

These are proportional cost-basis facts. They do not decide whether excess will be sold later, become inventory, be lost, donated, transferred, or discarded.

---

## 13. Worst-case committed-demand burden

For business-model testing, Atlas also needs the conservative scenario:

> **What if the entire pool cost has to be recovered from the units currently committed to customers?**

When economics are known in one currency and `plannedOutputQuantity > 0`:

~~~text
fullCostBurdenPerPlannedUnit
=
knownPoolCost / plannedOutputQuantity
~~~

This is a scenario metric. It is not asserted as historical cost accounting.

For the flower example:

~~~text
100-stem pool costs $38
90 stems are currently committed
10 remain excess

sourceBasisUnitCost = $0.38
fullCostBurdenPerPlannedUnit = $38 / 90 = $0.422222...
~~~

This lets Atlas test whether the business still works even if the 10 excess stems recover no value.

---

## 14. Excess economics remain unresolved unless separately governed

V1 always preserves:

- excess output quantity;
- proportional excess cost basis;
- worst-case full-cost burden on currently planned units.

It does not choose between them.

A later inventory/disposition source may establish what actually happened to excess.

This keeps possible future resale value from silently subsidizing today's customer quote.

---

## 15. Requirement-level proportional cost basis

When economics are known in one currency, each planned use may derive:

~~~text
proportionalCostBasis
=
plannedQuantity * sourceBasisUnitCost
~~~

This is useful for customer/job profitability analysis, later actual-cost reconciliation, quote comparison, and contribution-margin analysis.

It is not a purchase allocation record.

---

## 16. Temporal boundary

A proposed source pool may include available-from, available-through, receive-by, or other source/domain facts.

V1 does not infer timing compatibility from those timestamps.

Timing compatibility belongs in Requirement ↔ Candidate Qualification.

Every planned use still requires `qualificationState = qualified`.

---

## 17. No automatic optimization in v1

V1 evaluates one proposed break-bulk packet.

It does not search all combinations of customers, supplier packs, pack sizes, vendors, or freight tiers.

That comes later.

The deterministic evaluator is valuable first because humans, algorithms, or AI can propose a pool and all proposals pass through the same law.

---

## 18. Flower proof

Three active Work Requirements:

~~~text
R1 = 40 standard carnations
R2 = 30 standard carnations
R3 = 20 standard carnations
~~~

One source pool:

~~~text
100 qualifying carnations
known pool cost = $38
~~~

Planned uses:

~~~text
R1 ← 40
R2 ← 30
R3 ← 20
~~~

Result:

~~~text
aggregate outstanding before pool = 90
planned output = 90
all requirements covered = yes
source output excess = 10

source basis unit cost = $0.38
proportional committed cost basis = $34.20
proportional excess cost basis = $3.80
full-cost burden per committed stem = $0.422222...
~~~

This is the minimum mathematical machinery required for wholesale break-bulk economics.

---

## 19. Construction leak test

Three job requirements:

~~~text
Job A = 40 boxes tile
Job B = 30 boxes tile
Job C = 20 boxes tile
~~~

One pallet:

~~~text
100 boxes
~~~

Same evaluator:

~~~text
40 + 30 + 20 planned
10 excess
~~~

No florist vocabulary. No schema change.

---

## 20. Relationship to secured coverage

A pooled plan does **not** create secured coverage.

Before supplier acceptance:

~~~text
planned share from supplier pack
!=
secured source coverage
~~~

After a future external-acquisition commitment exists, a source adapter may emit normalized secured coverage facts for each Work Requirement.

Likewise, a real owned-inventory allocation may emit secured coverage.

The pool packet remains planning evidence.

---

## 21. Relationship to procurement

The evaluator can show:

~~~text
one 100-unit source pool
would economically cover
three customer requirements
~~~

It cannot place the order.

Future buy-side authority must separately establish supplier, accepted terms, ordered quantity, expected receipt, supplier commitment state, financial obligation, and source evidence.

That source-owned transaction may later satisfy the same planned pool.

---

## 22. Candidate function

`atlas.work_requirement_pool_position_v1(jsonb)`

Input:

- one source pool;
- planned-use array.

Output:

- pool quantity position;
- per-requirement position;
- aggregate demand position;
- excess;
- known/unresolved economic state;
- source-basis unit cost;
- proportional allocated/excess cost basis;
- conservative full-cost burden per planned unit;
- requirement-level proportional cost basis;
- truth boundaries.

No writes.

---

## 23. Validation requirements

V1 must prove:

1. 40 + 30 + 20 requirements against a 100-unit pool leaves 10 excess;
2. all demand can be covered while source pool remains partially unused;
3. pool smaller than demand leaves uncovered demand;
4. planned use cannot exceed source output;
5. planned use cannot exceed a requirement's outstanding quantity;
6. already-secured quantity reduces pool demand;
7. unresolved candidate qualification cannot enter pool;
8. incompatible candidate qualification cannot enter pool;
9. Work Requirement unit must match pool output unit;
10. source quantity and output quantity may differ;
11. known single-currency economics derive both proportional and conservative burden scenarios;
12. unresolved pool cost blocks complete economics but not quantity math;
13. multi-currency remains multi-currency;
14. excess never silently disappears;
15. evaluator creates no Work Requirement, allocation, reservation, purchase, Spend, inventory, payment, or fulfillment truth;
16. flower and construction-shaped requirements use the same evaluator;
17. browser roles cannot invoke it.

---

## 24. Governing result

The universal break-bulk seam is:

~~~text
one qualified source pool
+ several quantified outstanding Company Work Requirements
→ proposed pooled distribution
→ requirement coverage plan
→ excess position
→ shared economics
~~~

Not:

~~~text
one source pack
→ one customer
~~~

and not:

~~~text
planned distribution
→ real allocation
~~~

This is the first Atlas primitive that directly models the economic advantage of buying in bulk and distributing smaller quantities across several customer commitments.
