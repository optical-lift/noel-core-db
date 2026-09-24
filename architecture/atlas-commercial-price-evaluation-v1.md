# Atlas Commercial Price Evaluation v1

**Status:** universal read-only candidate  
**Date:** 2026-09-23  
**Parent:** `architecture/atlas-neutral-fulfillment-composition-v1.md`  
**Persistence rule:** no generic pricing-policy table in v1  
**First proof:** Feast Guild wholesale flower line pricing  
**Promotion rule:** persisted cross-domain pricing policy requires a second materially different live domain

---

## 1. Purpose

Once Atlas has a fulfillment composition whose physical coverage is exact and whose required economic cost is known in one currency, Atlas needs a deterministic way to answer:

> **Given this known cost and an explicit institutional pricing rule, what customer-facing unit price would satisfy that rule?**

V1 evaluates one quantified fulfillment line.

It does not persist policy.

It does not create an Offer Snapshot.

---

## 2. Why policy remains an input

Production Atlas currently has no generic cross-domain margin/markup policy authority.

Atlas-service commerce has its own service-specific price-policy machinery. That authority must not be reused for flowers, construction, catering, or other organizations merely because its name contains "price policy."

The first universal step is therefore:

~~~text
known fulfillment economics
+ explicit policy input
→ deterministic proposed commercial terms
~~~

Only after another materially different live domain proves the same durable policy semantics should Atlas consider a generic persisted pricing-policy root.

---

## 3. Prerequisite

Input fulfillment composition must satisfy:

- valid neutral fulfillment packet;
- exact requirement coverage;
- economic state = known;
- exactly one currency;
- no unresolved required cost components.

Therefore:

~~~text
unknown freight
→ no protected customer price
~~~

and:

~~~text
mixed USD + EUR with no governed FX rule
→ no protected customer price
~~~

The price evaluator never converts unknown into zero and never invents exchange rates.

---

## 4. V1 pricing methods

### gross_margin

Policy:

~~~json
{
  "method":"gross_margin",
  "rate":0.30
}
~~~

Formula:

~~~text
raw unit price
=
unit cost / (1 - margin rate)
~~~

Valid rate:

~~~text
0 <= rate < 1
~~~

### markup

Policy:

~~~json
{
  "method":"markup",
  "rate":0.40
}
~~~

Formula:

~~~text
raw unit price
=
unit cost * (1 + markup rate)
~~~

Valid rate:

~~~text
rate >= 0
~~~

The two methods are not interchangeable.

---

## 5. Unit-level pricing

V1 calculates:

~~~text
known total fulfillment cost
÷ required output quantity
=
known cost per required unit
~~~

Then applies pricing policy to the unit cost.

This is important for businesses that sell:

- per stem;
- per bunch;
- per item;
- per sq ft;
- per serving;
- per labor hour;
- per equipment day.

The output unit is inherited from the fulfillment requirement.

---

## 6. Rounding

V1 supports an optional upward price increment:

~~~json
{
  "rounding":{
    "mode":"ceil",
    "increment":0.01
  }
}
~~~

The evaluator rounds the **unit price upward** to the stated increment.

Upward rounding is deliberately the only V1 rounding mode because it cannot silently reduce the requested gross-margin/markup protection.

If no rounding is supplied, the proposed unit price equals the raw unit price.

---

## 7. Minimum unit price

Policy may include:

~~~json
{
  "minimumUnitPrice":0.55
}
~~~

The proposed unit price is the greater of:

- policy-derived rounded unit price;
- minimum unit price.

The minimum must be nonnegative.

This can represent an explicit institutional floor without pretending that a competitor's price is the source of Atlas's price.

---

## 8. Result

The evaluator returns:

- currency;
- quantity;
- unit;
- total known fulfillment cost;
- cost per required unit;
- policy method/rate;
- raw unit price;
- proposed unit price;
- proposed total;
- gross profit;
- realized gross margin;
- realized markup.

These are derived commercial terms.

They are not yet an external offer.

---

## 9. Example — carnation line

Known fulfillment position:

~~~text
100 stems
total true cost = $38.00
unit cost = $0.38
~~~

Policy:

~~~text
gross margin = 30%
round upward to $0.01
~~~

Calculation:

~~~text
raw unit price
= 0.38 / 0.70
= 0.542857...

proposed unit price
= 0.55

proposed total
= $55.00
~~~

Realized margin after rounding is above 30%.

The evaluator does not know or care that the unit is a flower stem.

---

## 10. Example — construction material

Known fulfillment position:

~~~text
2,600 sq ft
true material fulfillment cost = $7,340
unit cost = $2.8230769...
~~~

Policy:

~~~text
markup = 25%
round upward to $0.01
~~~

Same evaluator.

No flower-specific logic.

---

## 11. Reference/competitor pricing remains separate

A buyer's current price may later be compared against Atlas's derived proposed price.

It must not be passed in as the pricing basis unless an explicit institutional policy actually uses an external index/reference.

V1 does not support competitor-anchored pricing.

The sequence remains:

~~~text
true cost
→ institutional pricing rule
→ proposed price
→ optional market/current-price comparison
~~~

---

## 12. No persistence or authority expansion

The evaluator creates no:

- generic Pricing Policy;
- Commercial Offering Price;
- Commercial Offer Snapshot;
- Order;
- payment;
- Work Requirement;
- purchase;
- Spend;
- inventory;
- fulfillment.

A reviewed result may later be frozen in the existing Commercial Offer Snapshot.

A genuinely standing sell-side price may later be written through the owning Commercial Offering Price authority.

---

## 13. Candidate function

`atlas.commercial_price_evaluate_v1(p_fulfillment_packet jsonb, p_policy jsonb)`

The function:

1. calls `atlas.fulfillment_composition_position_v1`;
2. fails closed unless exact/known/single-currency economics exist;
3. validates the explicit policy object;
4. calculates deterministic unit/total price;
5. returns derived terms and truth boundaries.

---

## 14. Validation requirements

V1 must prove:

1. gross-margin formula;
2. markup formula;
3. gross margin and markup produce different results;
4. upward cent rounding;
5. minimum unit price;
6. unknown cost blocks price;
7. no cost evidence blocks price;
8. multi-currency blocks price;
9. undercoverage blocks price;
10. zero known cost remains explicit zero rather than unknown;
11. invalid margin >= 1 fails;
12. negative markup fails;
13. price evaluation creates no durable commercial/financial truth;
14. flower and construction fixtures use the same evaluator;
15. browser roles gain no write/read-through authority merely because evaluator exists.

---

## 15. Promotion boundary

V1 proves a universal **calculation contract**, not a universal persistent pricing-policy ontology.

Do not create a generic pricing-policy table until another live domain proves:

- shared policy scoping;
- shared effective dating;
- shared override authority;
- shared precedence;
- shared customer/account/category application rules.

Until then, policy enters explicitly from the fitting domain/institution adapter.


---

## 16. Shared pricing-law extraction — 2026-09-24

The pooled/break-bulk work proved that Atlas should not maintain separate gross-margin/markup formulas for ordinary fulfillment and pooled fulfillment.

The canonical calculation seam is now:

`atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)`

It receives an already-governed cost basis and owns only:

- gross-margin calculation;
- markup calculation;
- minimum unit-price floor;
- upward rounding;
- realized margin/markup calculation.

`atlas.commercial_price_evaluate_v1(jsonb,jsonb)` now remains the ordinary-fulfillment adapter:

~~~text
Fulfillment Composition Position
→ known exact cost basis
→ shared pricing law
→ ordinary proposed terms
~~~

The pooled path uses the same shared pricing law after a separate cost-recovery-basis decision.

This separation matters:

~~~text
pricing law
!=
cost-recovery-basis law
~~~

A pricing formula cannot decide whether excess inventory is economically recovered.

That judgment belongs upstream in the fitting fulfillment/pooling adapter.
