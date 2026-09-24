# Atlas Fulfillment Candidate Qualification v1

**Status:** universal candidate contract / read-only infrastructure  
**Date:** 2026-09-23  
**Parent:** `optical-lift/atlas/docs/architecture/ATLAS_UNIVERSAL_FULFILLMENT_INFRASTRUCTURE_V1.md`  
**First new adapter:** Feast Guild flower fulfillment  
**Existing live structural precedent:** Atlas task/resource requirements  
**Persistence rule:** no durable qualification table in v1

---

## 1. Purpose

Atlas needs one universal seam that can answer:

> **Given one source-owned requirement and one source-owned candidate, is there enough explicit evidence to allow that candidate into a fulfillment-planning field?**

The seam must work whether the candidate is:

- owned inventory;
- a supplier item;
- employee capacity;
- equipment;
- expected production;
- a rental;
- a subcontractor;
- another governed resource/capability.

The seam does not decide what the source objects are.

The seam evaluates explicit requirement nodes supplied by the fitting domain adapter.

---

## 2. Why v1 is a function contract, not a table

Atlas already owns:

- source-domain requirements;
- Organization Work Requirements for durable institutional responsibility;
- resource readiness helpers;
- a generic requirement-set evaluator;
- shadow Composition requirements/candidates/journeys.

A new universal qualification table would prematurely create another truth store.

V1 therefore persists nothing.

The movement is:

~~~text
source-owned requirement
+ source-owned candidate
+ domain adapter
        ↓
explicit requirement-node evaluations
        ↓
generic qualification evaluator
        ↓
qualified | incompatible | unresolved
        ↓
shadow Composition planning when qualified
~~~

If repeated live use later proves that an accepted qualification must persist independently of its source evidence, that durability must be earned separately.

---

## 3. Requirement node contract

Each node must identify one explicit condition.

V1 shape:

~~~json
{
  "requirementKey": "length_minimum",
  "required": true,
  "state": "satisfied",
  "evidence": [
    {
      "source": "supplier_specification",
      "ref": "..."
    }
  ],
  "details": {
    "minimumCm": 50,
    "observedCm": 60
  }
}
~~~

Required fields:

- `requirementKey`
- `state`

Optional fields:

- `required` — defaults to `true`;
- `evidence` — array;
- `details` — object;
- adapter-owned explanatory fields.

Allowed states:

- `satisfied`
- `unsatisfied`
- `unresolved`

The universal evaluator does not infer those states from prose.

The domain adapter must establish them from governed evidence.

---

## 4. Three-state requirement semantics

### satisfied

The available source/domain evidence establishes that the candidate satisfies this condition.

### unsatisfied

The evidence establishes that the candidate fails this condition.

### unresolved

Atlas does not have enough lawful evidence to say satisfied or unsatisfied.

Examples:

- supplier price sheet gives price but no availability;
- cultivar identity is unclear;
- freight is not yet known where delivered-cost eligibility requires it;
- equipment condition has not been observed;
- worker certification is unknown.

Unresolved is not false.

But unresolved required conditions fail closed for planning admission.

---

## 5. Aggregation law

For **required** nodes:

~~~text
any unsatisfied
→ requirement set = unsatisfied

else any unresolved
→ requirement set = unresolved

else
→ requirement set = satisfied
~~~

Optional/soft nodes are preserved and counted but do not block the required-set result.

This permits a domain adapter to preserve ranking preferences separately from hard qualification.

Example:

~~~text
hard:
- rose
- white
- >=50 cm

soft:
- Missouri-grown preferred
~~~

A non-Missouri rose may still qualify while ranking below a qualifying Missouri rose.

---

## 6. Qualification verdict

The fulfillment wrapper maps the generic requirement-set state to:

~~~text
satisfied   → qualified
unsatisfied → incompatible
unresolved  → unresolved
~~~

Only `qualified` may enter the ordinary fulfillment-planning candidate field.

`unresolved` may remain visible for investigation or price-confirmation workflows.

`incompatible` remains explicit evidence that this candidate cannot satisfy this requirement under the evaluated contract.

---

## 7. Source references

The evaluator receives opaque source references:

### Requirement reference

Example:

~~~json
{
  "sourceDomain": "commercial_order_line",
  "sourceRef": "<uuid>",
  "kind": "customer_product_requirement"
}
~~~

### Candidate reference

Example:

~~~json
{
  "sourceDomain": "external_supply_offering",
  "sourceRef": "<uuid>",
  "kind": "external_acquisition"
}
~~~

The evaluator preserves these refs.

It does not dereference or mutate the source objects.

This lets the same function work with future domains without a universal polymorphic foreign-key table.

---

## 8. Existing live Resource Requirement adapter

Atlas already has:

- `task_resource_requirements`;
- `resources`;
- `resource_operational_state`;
- `resource_requirement_ready_v1()`.

A compatibility adapter can express current resource readiness as one qualification node:

~~~json
{
  "requirementKey": "resource_ready",
  "required": true,
  "state": "satisfied | unsatisfied",
  "evidence": [
    {
      "source": "atlas.resource_requirement_ready_v1",
      "requirementId": "..."
    }
  ]
}
~~~

This does not replace Resource Requirement authority.

It proves the universal qualification evaluator can consume an existing live Atlas domain without schema conversion.

---

## 9. Feast Guild flower adapter

A flower adapter may eventually produce nodes such as:

~~~text
flower_family
flower_form
color
stem_length
quality_grade
delivery_date
availability
quantity
origin_requirement
exact_cultivar_requirement
~~~

Example:

~~~json
[
  {
    "requirementKey": "flower_family",
    "required": true,
    "state": "satisfied",
    "evidence": [{"source":"supplier_source_item"}]
  },
  {
    "requirementKey": "stem_length_minimum",
    "required": true,
    "state": "satisfied",
    "details": {"minimumCm":50,"sourceCm":60}
  },
  {
    "requirementKey": "availability_for_delivery_window",
    "required": true,
    "state": "unresolved",
    "evidence": [{"source":"price_list_without_availability"}]
  },
  {
    "requirementKey": "american_grown_preference",
    "required": false,
    "state": "satisfied",
    "evidence": [{"source":"provider_origin_label"}]
  }
]
~~~

Verdict:

~~~text
unresolved
~~~

The price may still inform market intelligence.

The candidate may not enter a guaranteed fulfillment plan until required availability evidence is resolved.

---

## 10. Exact versus alternative semantics remain domain-owned

The universal result `qualified` does not mean:

- identical;
- same cultivar;
- silent substitution permitted;
- cheapest;
- preferred;
- admitted for customer presentation.

A domain may additionally classify a qualified candidate as:

- exact;
- same specification;
- approved alternative;
- another domain-specific class.

Those meanings remain domain-owned.

This prevents flower vocabulary from leaking into core.

---

## 11. Qualification is not ranking

Two candidates may both qualify.

Ranking may later consider:

- economic cost;
- origin/local preference;
- reliability;
- freshness;
- lead time;
- capacity preservation;
- supplier relationship strategy;
- customer preference.

The qualification evaluator answers only whether a candidate is lawfully in the candidate field.

It does not pick the winner.

---

## 12. Qualification is not availability reservation

A supplier candidate may qualify by specification and still not be secured.

~~~text
qualified candidate
!= available quantity
!= reservation
!= purchase
!= coverage
~~~

Availability may itself be one required node when the planning context requires current availability.

A live quote may qualify for a quote-planning field but not for hard order coverage.

The domain adapter determines which requirement set applies to which planning stage.

---

## 13. Qualification and shadow Composition

Qualified candidates may be projected into the existing shadow Composition runtime as carrier facts.

Conceptually:

~~~text
Qualification result
        ↓
qualified candidate facts
        ↓
composition_candidates
        ↓
composition journey / candidate plan
        ↓
costs / constraints / branches
~~~

The Composition runtime remains proposal/planning infrastructure.

It does not gain purchase or execution authority from qualification.

---

## 14. Qualification and Work Requirements

A qualification calculation occurs before and after commitment.

After commitment, an unmet institutional coverage responsibility may be represented through existing `work_requirements`.

The qualification seam does not create that requirement.

It may later help work/planning logic answer:

> Which candidate sources or resources could cover this active institutional requirement?

The work requirement remains the responsibility truth.

The qualification result remains evaluation.

---

## 15. Functions

V1 candidate functions:

### `atlas.requirement_set_evaluate_v2(jsonb)`

Generic three-state requirement aggregation.

It extends the existing v1 law without changing v1 behavior.

### `atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)`

Read-only wrapper that preserves:

- requirement ref;
- candidate ref;
- requirement nodes;
- generic evaluation;
- context;
- qualification verdict;
- planning-admission flag;
- truth-boundary declaration.

No table writes.

---

## 16. Authority boundary

These functions may:

- evaluate supplied explicit requirement nodes;
- preserve source refs;
- count satisfied/unsatisfied/unresolved nodes;
- say whether a candidate may enter planning.

They may not:

- infer requirement facts from prose;
- establish supplier identity;
- establish product equivalence;
- create availability;
- create inventory;
- create procurement;
- create Spend;
- create Work;
- create an Order;
- create a Commercial Offer;
- reserve capacity;
- authorize execution.

---

## 17. Validation requirements

Candidate validation must prove:

1. all required satisfied → `qualified`;
2. one required unsatisfied → `incompatible`;
3. no unsatisfied but one required unresolved → `unresolved`;
4. optional unsatisfied node does not block qualification;
5. optional unresolved node does not block qualification;
6. malformed node fails closed;
7. empty requirement set fails closed;
8. duplicate requirement keys fail closed;
9. evidence must be an array when present;
10. details must be an object when present;
11. requirement/candidate refs must be JSON objects;
12. evaluator creates no work/order/payment/Spend/inventory truth;
13. one live Atlas Resource Requirement can be adapted without rewriting its source truth;
14. one flower-shaped unresolved fixture preserves unknown availability rather than guessing it;
15. browser roles do not gain a new write surface.

---

## 18. Promotion rule

This function contract may be shared because it is read-only evaluation infrastructure and directly extends an already-live generic requirement evaluation law.

Do **not** promote a durable universal candidate↔requirement qualification relation yet.

Durable qualification persistence requires evidence that at least two materially different live domains need the same institutional relation independently of their source objects.

Until then:

~~~text
source evidence
→ adapter evaluation
→ read-only qualification result
→ shadow planning
~~~

is sufficient.
