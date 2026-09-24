# Atlas Pooled Commercial Price Protection v1

**Status:** universal read-only candidate  
**Date:** 2026-09-24  
**Parents:**  
- `architecture/atlas-commercial-price-evaluation-v1.md`  
- `architecture/atlas-work-requirement-pool-position-v1.md`  

**Persistence rule:** no generic pooled-pricing policy table in v1  
**First proof:** wholesale break-bulk flowers  
**Leak test:** pooled construction-material purchasing

---

## 1. Purpose

A pooled source creates two different economic unit-cost views when some source output remains excess:

~~~text
source-output basis
=
whole pool cost / whole usable source output
~~~

and:

~~~text
full-pool burden on current planned demand
=
whole pool cost / currently planned output
~~~

Those are not interchangeable.

Atlas needs to answer:

> **Which cost-recovery basis is the institution explicitly willing to use for customer pricing, and what unit price protects the requested margin/markup under that basis?**

V1 keeps the choice explicit.

---

## 2. Why this layer exists

Example:

~~~text
source pool = 100 stems
known pool cost = $38
current committed/planned demand = 90 stems
excess = 10 stems
~~~

Source-output basis:

~~~text
$38 / 100 = $0.38/stem
~~~

Full-pool burden on current demand:

~~~text
$38 / 90 = $0.422222.../stem
~~~

At a 30% gross-margin target with upward cent rounding:

~~~text
source-output pricing
→ $0.55/stem
~~~

but:

~~~text
full-pool/current-demand pricing
→ $0.61/stem
~~~

If only 90 stems sell and the 10 excess stems recover nothing, $0.55 does not protect 30% gross margin.

Therefore the pooled-price layer must not silently choose the cheaper basis.

---

## 3. Shared pricing law

The margin/markup math itself should exist once.

V1 extracts:

`atlas.commercial_price_from_cost_basis_v1(...)`

That helper receives:

- quantity;
- unit;
- total governed cost basis;
- currency;
- explicit pricing policy;
- explanatory context.

It owns:

- gross-margin formula;
- markup formula;
- minimum unit-price floor;
- upward rounding;
- realized margin/markup calculation.

Ordinary fulfillment pricing and pooled fulfillment pricing both use this helper.

This prevents the two paths from drifting into different pricing math.

---

## 4. Pooled recovery bases

V1 admits two explicit bases.

### `full_pool_on_planned_output`

Cost basis:

~~~text
knownPoolCost
~~~

Quantity basis:

~~~text
plannedOutputQuantity
~~~

Meaning:

> Current planned/committed output must be able to recover the entire pool cost.

This is the conservative basis.

It does not assume the excess has future economic value.

### `source_output`

Cost basis:

~~~text
knownPoolCost
~~~

Quantity basis:

~~~text
outputQuantity
~~~

Meaning:

> Pricing uses the cost per unit across the entire usable source output.

V1 allows this basis only when:

~~~text
excessOutputQuantity = 0
~~~

If excess remains, V1 blocks this as a protected pricing basis because recovery of the excess has not been established.

A future version may admit a source-backed recoverable-excess credit once Atlas has a governed inventory/disposition authority that proves the economic treatment.

---

## 5. Why V1 does not accept "we'll probably sell the excess"

Possible future sale is not current recovery evidence.

V1 does not accept:

- hoped-for resale;
- assumed future inventory value;
- historical average sell-through;
- competitor demand;
- AI expectation;

as a reason to reduce the protected cost burden.

Those may later become planning evidence.

They are not a current secured recovery fact.

---

## 6. Pricing policy shape

Pooled policy:

~~~json
{
  "contractVersion":"work_requirement_pool_price_policy_v1",
  "costRecoveryBasis":"full_pool_on_planned_output",
  "pricingPolicy":{
    "contractVersion":"commercial_price_policy_input_v1",
    "method":"gross_margin",
    "rate":0.30,
    "currency":"USD",
    "rounding":{
      "mode":"ceil",
      "increment":0.01
    }
  }
}
~~~

The inner pricing policy is the same contract used for ordinary fulfillment pricing.

---

## 7. Prerequisites

The pooled position must be:

- valid;
- economically `known`;
- one currency;
- positive planned output;
- `demandPosition = all_covered`.

Why require all demand covered?

Because a customer-facing protected price should not be derived from an incomplete fulfillment plan that still omits known required quantity.

A later multi-pool portfolio planner can combine several source pools before invoking final price protection.

---

## 8. Selected protected basis

The selected basis produces:

- protected cost basis;
- protected quantity basis;
- protected cost per planned unit;
- protected proposed unit price;
- protected proposed revenue on current planned output;
- protected gross profit against whole selected basis;
- protected realized gross margin/markup.

For `full_pool_on_planned_output`, the proposed unit price is applied to current planned demand.

---

## 9. Scenario comparison

Even when only one basis is permitted as the protected basis, V1 returns both scenarios for analysis.

### Source-output scenario

Uses:

~~~text
knownPoolCost / outputQuantity
~~~

Then shows:

- source-output unit cost;
- price generated under the same margin/markup policy;
- revenue if that unit price is charged only on current planned output;
- resulting gross margin against the **whole pool cost** if excess recovers zero.

When excess exists, this scenario is explicitly marked:

`unprotected_without_excess_recovery`

### Full-pool/current-demand scenario

Uses:

~~~text
knownPoolCost / plannedOutputQuantity
~~~

Then shows:

- conservative unit burden;
- protected price;
- revenue on current planned output;
- gross margin against whole pool cost.

This makes the risk visible rather than hiding it inside one number.

---

## 10. Flower proof

Pool:

~~~text
100 stems
$38 known total pool cost
90 planned/customer stems
10 excess stems
~~~

Policy:

~~~text
30% gross margin
ceil to $0.01
~~~

Source-output scenario:

~~~text
cost basis per source-output unit = $0.38
price = $0.55

current 90-stem revenue = $49.50
whole-pool gross profit = $11.50
whole-pool gross margin ≈ 23.23%
~~~

Full-pool/current-demand scenario:

~~~text
cost burden per planned stem = $38 / 90
≈ $0.422222...

price = $0.61

current 90-stem revenue = $54.90
whole-pool gross profit = $16.90
whole-pool gross margin ≈ 30.78%
~~~

Therefore:

~~~text
source-output basis
!=
protected current-demand basis
when excess is unresolved
~~~

---

## 11. Construction leak test

One 100-box pallet costs $900.

Current jobs require 90 boxes.

10 boxes remain excess.

At a 25% markup:

~~~text
source-output unit cost = $9.00
source-output price = $11.25
~~~

Conservative current-demand burden:

~~~text
$900 / 90 = $10.00
protected 25% markup price = $12.50
~~~

Same contract.

No flower vocabulary.

---

## 12. Per-requirement proposed totals

The pooled evaluator returns each planned use with:

- use key;
- Work Requirement;
- planned quantity;
- proposed protected unit price;
- proposed protected total.

V1 uses one pool-wide unit price because one policy is being evaluated.

Account/customer-specific price adjustments remain a later commercial-policy layer.

They may raise or otherwise modify customer terms only through a separately governed rule.

---

## 13. Relationship to Commercial Offer Snapshot

A pooled protected-price result remains derived planning truth.

It does not itself create an offer.

After review, customer-facing terms may be frozen in the existing Commercial Offer Snapshot.

The snapshot should preserve:

- pool key;
- selected cost-recovery basis;
- selected cost basis;
- pricing policy;
- protected price;
- scenario comparison;
- source references.

That preserves why the price was lawful at the moment it was offered.

---

## 14. No persistence or authority expansion

The pooled-price evaluator creates no:

- pricing-policy row;
- standing price;
- Commercial Offer Snapshot;
- Commercial Order;
- supplier purchase;
- source allocation;
- inventory;
- Spend;
- payment;
- Work Requirement;
- fulfillment.

It is deterministic evaluation only.

---

## 15. Candidate functions

### `atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)`

Shared pure pricing math.

### `atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)`

1. calls `atlas.work_requirement_pool_position_v1`;
2. requires complete known pooled economics;
3. validates explicit cost-recovery basis;
4. blocks `source_output` when excess remains;
5. calculates protected pooled price through the shared helper;
6. returns source-output and full-pool scenario comparison;
7. maps the protected unit price back onto each planned use.

---

## 16. Validation requirements

V1 must prove:

1. shared helper preserves existing gross-margin calculation;
2. shared helper preserves markup calculation;
3. full-pool basis prices $38/90 at 30% margin to $0.61 with cent-ceiling;
4. source-output scenario still reports $0.55;
5. source-output basis is blocked while 10 excess units remain;
6. source-output basis is allowed when the pool is fully used;
7. source-output $0.55 scenario shows only about 23.23% whole-pool margin on 90 current units;
8. full-pool $0.61 scenario protects at least 30% whole-pool margin;
9. unresolved pool cost blocks pricing;
10. multi-currency blocks pricing;
11. incomplete aggregate demand blocks customer-price protection;
12. each Work Requirement receives a derived proposed total without creating an offer;
13. construction-shaped pooled economics use the same evaluator;
14. no durable truth is written;
15. browser roles cannot invoke either internal evaluator.

---

## 17. Governing result

The pricing movement is now:

~~~text
source-backed pooled economics
→ explicit cost-recovery basis
→ shared institutional pricing law
→ protected proposed price
→ optional Commercial Offer Snapshot
~~~

Atlas does not decide that excess will sell.

The institution must either:

- price current demand to carry the whole pool cost; or
- establish a governed economic basis that makes another treatment lawful.
