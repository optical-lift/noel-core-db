# Atlas Neutral Fulfillment Composition v1

**Status:** universal read-only composition candidate  
**Date:** 2026-09-23  
**Parent:** `optical-lift/atlas/docs/architecture/ATLAS_UNIVERSAL_FULFILLMENT_INFRASTRUCTURE_V1.md`  
**Prerequisite:** `architecture/atlas-fulfillment-candidate-qualification-v1.md`  
**Persistence rule:** no new composition tables in v1  
**First proof:** mixed owned + external flower fulfillment  
**Cross-domain leak test:** construction material + labor/equipment composition

---

## 1. Purpose

Atlas needs to compose **qualified source-owned candidates** into one possible way to cover a quantified requirement.

The universal question is:

> **Given one quantified requirement and a set of already-qualified candidates, does this proposed combination cover the required output, what source quantities does it consume, what excess remains, and what known/unresolved economic cost does the plan carry?**

This is planning/evaluation.

It is not execution.

---

## 2. Why this does not write to the existing Composition runtime

Atlas already has a mature shadow Composition subsystem with useful structural concepts:

- requirements;
- candidates;
- journeys;
- steps;
- branches;
- costs;
- adjudications;
- proposal distinct from execution.

However, the current persistent write path is explicitly governed by Song/canon runtime packs.

Current functions such as:

- `create_shadow_composition_run_v2`;
- `derive_composition_packet_from_signals_v1`;
- `start_shadow_composition_derivation_v1`;

require canon-runtime-pack custody and use canon-specific packet meanings such as:

- `canon_runtime_pack`;
- `protected_claims`;
- `intended_fruit`;
- adjudication basis.

Commercial/material/resource fulfillment must not pretend to possess that authority merely to reuse table names.

Therefore v1 extracts the **neutral planning laws** without writing fulfillment records into canon-governed Composition storage.

If later work generalizes the shared Composition runtime itself, this packet should become one adapter into that neutralized runtime.

Until then:

~~~text
qualified source candidates
→ read-only neutral fulfillment composition
→ validated plan/economic position
→ later prepared commercial terms or work planning
~~~

No persistent parallel fulfillment-plan graph is created.

---

## 3. Scope

V1 composes **one quantified output requirement**.

Examples:

- 100 sellable carnations;
- 2,600 sq ft qualifying flooring;
- 16 installer labor-hours;
- 150 meal portions;
- 1 equipment-day.

Hard non-quantity conditions such as grade, color, certification, date, location, or capability should already have been evaluated through Requirement ↔ Candidate Qualification.

V1 is not a universal unit-conversion engine.

Every plan entry must state the quantity it contributes in the requirement's output unit.

---

## 4. Source quantity versus requirement output

A candidate may consume one quantity while contributing a different output quantity.

Example — flowers:

~~~text
source purchase:
75 stems

expected/allocated requirement output:
60 sellable stems

excess:
15 source stems or a smaller usable remainder depending on domain evidence
~~~

Example — catering:

~~~text
source:
20 lb raw ingredient

output:
150 cooked portions
~~~

Example — construction:

~~~text
source:
2,800 sq ft purchased flooring

output allocated to requirement:
2,600 sq ft installed-material coverage

excess/waste:
200 sq ft
~~~

The neutral plan therefore distinguishes:

- source quantity;
- source unit;
- output quantity;
- output unit;
- excess quantity/state;
- transformation/yield facts.

The transformation law remains domain/source-owned.

---

## 5. Packet contract

Candidate packet:

~~~json
{
  "contractVersion": "neutral_fulfillment_composition_v1",
  "requirementRef": {
    "sourceDomain": "commercial_order_line",
    "sourceRef": "..."
  },
  "requirement": {
    "quantity": 100,
    "unit": "stem",
    "requiredBy": "2026-09-24T12:00:00Z"
  },
  "planKey": "mixed-owned-external",
  "allocations": [
    {
      "allocationKey": "owned-ready-40",
      "candidateRef": {
        "sourceDomain": "flower_ready_inventory",
        "sourceRef": "..."
      },
      "qualificationState": "qualified",
      "sourceQuantity": 40,
      "sourceUnit": "stem",
      "outputQuantity": 40,
      "outputUnit": "stem",
      "costComponents": []
    },
    {
      "allocationKey": "supplier-a-60",
      "candidateRef": {
        "sourceDomain": "external_supply_offering",
        "sourceRef": "..."
      },
      "qualificationState": "qualified",
      "sourceQuantity": 75,
      "sourceUnit": "stem",
      "outputQuantity": 60,
      "outputUnit": "stem",
      "excess": {
        "quantity": 15,
        "unit": "stem",
        "dispositionState": "unresolved"
      },
      "costComponents": [
        {
          "componentKey": "merchandise",
          "state": "known",
          "amount": 25.50,
          "currency": "USD",
          "sourceRef": "..."
        },
        {
          "componentKey": "freight",
          "state": "unresolved",
          "sourceRef": "..."
        }
      ]
    }
  ],
  "constraints": [],
  "metadata": {}
}
~~~

---

## 6. Required packet fields

Top level:

- `contractVersion = neutral_fulfillment_composition_v1`
- `requirementRef` object;
- `requirement` object;
- `planKey`;
- `allocations` array.

Requirement:

- `quantity > 0`;
- nonblank `unit`;
- optional `requiredBy`;
- optional domain facts.

Each allocation:

- unique `allocationKey`;
- `candidateRef` object;
- `qualificationState = qualified`;
- `outputQuantity > 0`;
- nonblank `outputUnit`;
- optional `sourceQuantity > 0`;
- optional `sourceUnit`;
- optional `excess` object;
- optional `costComponents` array;
- optional `facts` object.

The allocation output unit must equal the requirement unit in v1.

Unit conversion must occur upstream in a domain-owned transformation adapter and be presented here as an explicit output quantity.

---

## 7. Coverage position

The plan's output contribution is:

~~~text
sum(allocation.outputQuantity)
~~~

Compared with:

~~~text
requirement.quantity
~~~

Result:

- `exact` — equal;
- `undercovered` — below requirement;
- `overcovered` — above requirement.

A normal candidate plan may be undercovered during exploration.

Only exact coverage may be treated as a complete fulfillment plan in v1.

Overcoverage should normally be expressed as source/excess quantity rather than allocated requirement output.

This keeps the customer/work requirement quantity distinct from purchase pack size.

---

## 8. Qualification boundary

Every allocation must refer to a candidate already evaluated as:

~~~text
qualified
~~~

V1 rejects:

- `unresolved`;
- `incompatible`;
- missing qualification.

That does not mean the source is secured.

It means the candidate is lawfully inside the planning field.

---

## 9. Cost components

Cost remains source-backed.

Each component has:

- `componentKey`;
- `state = known | unresolved | not_applicable`;
- `amount` when known;
- `currency` when known;
- optional `sourceRef`;
- optional details.

Rules:

### known

- amount is required;
- amount must be >= 0;
- currency is required;
- currency must be a three-letter uppercase code.

### unresolved

- amount must be absent/null;
- currency may be present only if source-backed;
- unresolved remains unresolved.

### not_applicable

- amount must be absent/null.

No unknown component becomes zero.

---

## 10. Economic position

The read-only position function returns:

- known cost totals by currency;
- unresolved required cost-component count;
- known component count;
- economic state.

Candidate states:

### known

All supplied required cost components are known and there is exactly one currency.

### known_multi_currency

All supplied required components are known, but more than one currency is present.

Atlas does not invent FX conversion.

### unresolved

At least one required cost component is unresolved.

### no_cost_evidence

No cost components were supplied.

The function should not claim "free" when cost evidence is absent.

---

## 11. Excess

Pack size, yield, and conversion may create source excess.

An allocation may preserve:

~~~json
{
  "excess": {
    "quantity": 15,
    "unit": "stem",
    "dispositionState": "unresolved"
  }
}
~~~

Possible adapter-owned states may include:

- `unresolved`;
- `retained_inventory`;
- `expected_loss`;
- `allocated_elsewhere`;
- `included_in_requirement_cost`;
- another domain-owned state.

Core v1 does not impose one universal economic treatment for excess.

It merely preserves the fact.

---

## 12. Plan completeness

A plan is `completeForPlanning` only when:

- packet validation passes;
- coverage is exact;
- all allocations are qualified;
- no blocking plan-level unresolved item is declared.

Economic state may still be unresolved.

That distinction matters.

Example:

~~~text
100 stems exactly covered
but freight unknown
~~~

The physical plan may be complete enough to investigate pricing, while customer price remains unresolved.

---

## 13. Plan-level unresolved facts

Packet may include:

~~~json
{
  "unresolved": [
    {
      "key": "freight",
      "blockingFor": ["customer_price"],
      "sourceRef": "..."
    }
  ]
}
~~~

This keeps planning uncertainty explicit without forcing every unresolved fact into candidate qualification.

Examples:

- freight unknown;
- tax treatment unknown;
- exact receiving window unknown;
- excess disposition unresolved.

V1 preserves these facts.

It does not automatically infer which downstream action is lawful.

---

## 14. No automatic candidate selection

V1 validates/evaluates a proposed combination.

It does not search every mathematical combination or choose the cheapest one.

A later planner may generate candidate packets.

The validator remains deterministic.

This separation allows:

- human-proposed plans;
- algorithmically generated plans;
- AI-proposed plans;

to pass through the same deterministic contract.

---

## 15. No persistence in v1

Functions are pure/read-only.

They create no:

- Composition Run;
- Commercial Offer;
- Order;
- Work Requirement;
- allocation;
- purchase;
- reservation;
- Spend;
- inventory;
- payment;
- fulfillment event.

The packet may later become evidence inside:

- a Commercial Offer Snapshot;
- a Work planning result;
- an approved procurement proposal;
- another source-owned decision record.

That later persistence remains governed by the receiving authority.

---

## 16. Candidate functions

### `atlas.fulfillment_composition_validate_v1(jsonb)`

Validates packet shape and returns:

- validation state;
- violations;
- warnings;
- normalized counts.

### `atlas.fulfillment_composition_position_v1(jsonb)`

Calls validation and returns:

- coverage state;
- required/output quantity;
- source allocation count;
- cost totals by currency;
- economic state;
- unresolved counts;
- complete-for-planning state;
- truth boundary.

No writes.

---

## 17. Flower proof

Requirement:

~~~text
100 carnations
~~~

Plan:

~~~text
40 owned Ready stems
+
75 purchased stems
→ 60 allocated output stems
→ 15 source excess
~~~

Requirement output:

~~~text
40 + 60 = 100
~~~

Coverage:

~~~text
exact
~~~

If supplier merchandise cost is known but freight is unresolved:

~~~text
economic state = unresolved
physical coverage = exact
completeForPlanning = true
customer-price readiness = not established
~~~

This is precisely the distinction Feast Guild needs.

---

## 18. Construction leak test

Requirement:

~~~text
2,600 sq ft qualifying flooring material
~~~

Plan:

~~~text
sourceQuantity = 2,808 sq ft from Supplier B
outputQuantity = 2,600 sq ft
excessQuantity = 208 sq ft
~~~

Cost:

~~~text
material known
freight known
handling known
~~~

Same packet contract.

No flower vocabulary required.

Labor can be another quantified requirement:

~~~text
16 labor-hours
~~~

with employee-capacity candidates contributing output hours.

---

## 19. Relationship to Company Work

After commitment, source-domain adapters may establish Company Work Requirements for fulfillment coverage.

This packet can then help answer:

> Which qualified source candidates, in what quantities, could cover this active requirement?

The packet does not satisfy the Work Requirement itself.

Only source-owned securing/execution truth can do that.

---

## 20. Relationship to Commercial Offer Snapshot

Once:

- physical coverage is adequate;
- economic composition is sufficiently known;
- pricing policy has been applied;

the exact customer-facing terms may be frozen through the existing Commercial Offer Snapshot.

Do not persist this neutral plan as a quote merely because it contains costs.

---

## 21. Promotion boundary

This read-only packet is universal evaluation infrastructure because it introduces no competing truth store.

Do not yet create:

- universal Fulfillment Plan tables;
- universal allocation tables;
- universal cost ledgers;
- universal source reservation tables.

If two materially different live domains later require durable plan history independent of existing source/offer/work evidence, then promote that persistence deliberately.

---

## 22. Governing result

The correct reuse boundary is:

~~~text
source-owned requirement
→ candidate qualification
→ neutral read-only fulfillment composition
→ economic position
→ receiving authority
~~~

while the existing canon-governed Composition runtime remains untouched until Atlas deliberately separates its neutral composition kernel from its Song/canon governance adapter.
