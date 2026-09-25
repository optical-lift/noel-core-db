# Atlas Ledger Commercial Market Policy v1

**Status:** candidate-only architecture contract  
**Date:** 2026-09-25  
**Reality/Ledger prerequisite:** `architecture/reality-ledger-core-v1` @ `a30d7ceaba7901315cbdafab06635e807669e2c4`  
**Sibling fulfillment candidate:** `architecture/feast-guild-whole-order-quote-v1` @ `b97ad69098b197582ace923a1d5599671a97d86f`  
**Production boundary:** not released; no production migration or deployment before the governed validation/release lane reopens  
**First real use case:** Feast Guild wholesale quoting in Springfield, Missouri  
**Cross-domain qualification shape:** any Ledger that prices a customer commitment from a governed cost basis and may compare that price with an outside market alternative

## 1. Purpose

Atlas already has candidate machinery for:

- source-backed external supply offers;
- requirement/candidate qualification;
- neutral fulfillment composition;
- pooled break-bulk economics;
- cost-based gross-margin/markup calculations;
- Feast Guild whole-order quote preparation.

That work deliberately kept pricing policy transient. It accepted policy as a JSON input and did not establish a durable cross-company policy authority.

The Reality/Ledger cutover changes the correct custody root.

A launched Atlas needs to remember, for each Ledger:

1. what commercial pricing policy was in force at a particular time;
2. what outside market price or customer alternative was actually observed;
3. whether a proposed quote satisfied the institution's margin rule;
4. whether it satisfied the institution's market/competitive rule;
5. exactly which policy and market observations were used when the decision was evaluated.

This tranche establishes those durable facts without creating a customer Order, supplier purchase, inventory, Spend, payment, or fulfillment event.

## 2. Governing custody

The canonical institutional subject is a Reality Entity.

A Ledger is that Entity expressing one bounded action world.

Therefore new commercial policy custody is:

```text
reality.entities
  ↓ subject of
ledger.ledgers
  ↓ custody
Atlas commercial policy / market observations / evaluation receipts
```

The new relations must not depend on:

- `atlas.organizations`;
- Organization Membership;
- Principal;
- Principal Ledger Authority;
- legacy Organization-as-identity assumptions.

No `organization_id` column is permitted in this tranche.

## 3. What this tranche does not duplicate

This tranche does not create another supplier catalog.

The sibling fulfillment candidate already owns the proposed source-side distinction:

```text
External Supply Offering
!= Supply Offer Observation
!= procurement
!= inventory
!= customer price
```

Likewise, this tranche does not create a universal customer-demand store. A customer request remains source-owned and is referenced by a typed request reference. Domain adapters may use a Commercial Order line, a quote-intake record, a Ledger observation, Company Work, or another governed demand carrier.

The commercial policy layer asks:

> Given a governed cost basis and a governed customer-demand reference, what commercial envelope applies?

It does not own the demand itself.

## 4. First governing distinction: supplier offer versus market benchmark

A price observed in the market may mean two very different things.

### Acquirable supply

```text
FlowerBuyer offers Feast Guild
100 qualifying stems
at source-backed terms
```

That is an External Supply Offer candidate.

### Market benchmark

```text
Baisch & Skinner currently offers
the florist an equivalent product
at an observed market price
```

That is not automatically an acquirable Feast Guild source.

It answers:

> What can the customer already obtain elsewhere?

The same organization could be both a supplier and a benchmark in different contexts, but the observation roles must not be collapsed.

## 5. Ledger Commercial Pricing Policy

Canonical candidate relation:

`atlas.ledger_commercial_pricing_policies`

One row is one effective-dated institutional pricing policy position for one Ledger and policy key.

V1 carries typed fields for the law that is already proven by current Atlas work:

- Ledger;
- policy key;
- pricing method: `gross_margin` or `markup`;
- target rate;
- minimum acceptable rate;
- optional currency restriction;
- market benchmark constraint;
- optional required benchmark discount rate;
- cost-basis policy description;
- effective window;
- policy state;
- basis/provenance.

### Target versus minimum

These are separate.

`target_rate` answers:

> What rate should an ordinary quote protect?

`minimum_rate` answers:

> Below what rate is the quote not commercially admissible without a different governed decision?

A quote that satisfies minimum but not target may be returned as `review_required`.

A quote below minimum is blocked.

## 6. Benchmark constraints

V1 admits four market rules.

### `none`

No outside-market price gate applies.

### `at_or_below`

The proposed customer quote must be less than or equal to the benchmark total.

### `strictly_below`

The proposed customer quote must be strictly less than the benchmark total.

This is the correct current shape for Feast Guild's stated launch requirement:

> Feast Guild must actually be cheaper than the Springfield incumbent price.

It does not invent a 5% savings target that has not been established as policy.

### `discount_rate`

The quote must satisfy:

```text
proposed quote
<=
benchmark total * (1 - benchmark_discount_rate)
```

This supports a future policy such as "quote at least 5% below the customer's incumbent alternative" if and when that policy is actually established.

## 7. Feast Guild pilot position represented by the contract

The user-established launch economics can be represented as:

```text
pricing method = gross_margin
target rate = 10%
minimum rate = 10%
benchmark constraint = strictly_below
benchmark discount rate = null
```

The cost basis may require, as applicable:

- flowers/merchandise;
- inbound freight;
- package/box/depot fees;
- unavoidable overbuy required to fulfill current committed demand;
- expected shrink only when governed by policy/evidence;
- delivery or handling cost when Feast Guild absorbs it.

The table stores the policy. It does not decide which domain-specific cost components exist. The fulfillment/cost layer must establish the protected cost basis upstream.

## 8. Effective dating

Policy history must never be rewritten into the present.

A policy row has:

- `effective_from`;
- optional `effective_until`;
- `policy_state = established | superseded | withdrawn`.

An established policy may be superseded prospectively.

The prior row remains historically resolvable for its original effective interval.

Overlapping non-withdrawn positions for the same Ledger + policy key are rejected.

Therefore:

```text
September quote
→ September policy

later margin change
→ new policy row
```

not:

```text
later margin change
→ rewrite September history
```

## 9. Ledger Commercial Market Observation

Canonical candidate relation:

`atlas.ledger_commercial_market_observations`

One row records one source-backed outside-market price observation available to the Ledger's decision process.

This is append-only evidence.

Minimum semantics:

- Ledger;
- optional canonical Reality Entity for the observed market actor;
- source label;
- observation role;
- market context;
- item/specification context;
- observation/effective timestamps;
- price amount;
- currency if source-backed;
- price denominator if source-explicit or confirmed;
- pack/increment when known;
- terms;
- source kind/reference;
- evidence/provenance;
- optional superseded-observation reference.

### Observation roles

V1 includes:

- `incumbent_benchmark`;
- `market_reference`;
- `customer_alternative`;
- `competitor_quote`;
- `public_price`.

The role describes why the observation is relevant. It does not transform the observed actor into a supplier.

## 10. Source-faithfulness

Market observation must preserve what the source actually establishes.

A source that shows:

```text
Carnations 0.65
```

but does not explicitly establish currency or denominator must not be silently stored as:

```text
$0.65/stem
```

V1 therefore carries:

`price_basis_state = source_explicit | confirmed | unknown`

and allows currency / quantity / unit to remain unknown.

A computational benchmark is usable only when the required currency and price basis are known through source evidence or explicit confirmation.

## 11. Quote envelope

The read-only function:

`atlas.ledger_commercial_quote_envelope_v1(policy_id, benchmark_total, currency)`

answers:

> Given this exact policy version and this benchmark total, what is the maximum customer quote permitted by the market rule, and what is the corresponding maximum protected cost that still meets target/minimum economics?

Example under a 10% gross-margin policy and a $150 strict benchmark:

```text
market quote ceiling = $150 exclusive
target protected-cost ceiling = $135 exclusive
minimum protected-cost ceiling = $135 exclusive
```

If a later policy requires 5% savings:

```text
market quote ceiling = $142.50 inclusive
target protected-cost ceiling at 10% margin = $128.25
```

This is the bid-sheet number needed by a human operator before automated supplier browsing exists.

## 12. Quote evaluation

The read-only function:

`atlas.ledger_commercial_quote_evaluate_v1(...)`

takes:

- exact policy version;
- governed protected cost total;
- proposed customer quote total;
- optional governed benchmark total;
- currency.

It derives:

- realized margin/markup;
- target/minimum state;
- market state;
- customer savings amount/rate where applicable;
- overall decision state.

Decision states:

- `eligible`;
- `review_required`;
- `blocked`;
- `incomplete_evidence`.

### Eligibility law

A quote is ordinarily `eligible` only when:

1. target pricing economics are met;
2. the benchmark rule is satisfied or no benchmark is required.

A quote becomes `review_required` when:

1. minimum economics are met;
2. target economics are not met;
3. the market gate is otherwise satisfied.

A quote is `blocked` when:

- minimum economics fail; or
- a known benchmark rule fails.

A quote is `incomplete_evidence` when a required benchmark is absent.

## 13. Quote Evaluation Receipt

Canonical candidate relation:

`atlas.ledger_commercial_quote_evaluation_receipts`

This is append-only decision provenance.

It does not itself constitute a customer-facing offer.

Each receipt preserves:

- Ledger;
- evaluation key;
- request reference;
- exact pricing-policy row;
- protected cost total;
- proposed quote total;
- benchmark total;
- derived pricing state;
- derived market state;
- decision state;
- realized economics;
- customer savings;
- evaluation packet;
- provenance;
- optional result reference to a later offer carrier.

Child relation:

`atlas.ledger_commercial_quote_evaluation_benchmarks`

links the receipt to every market observation used to calculate the benchmark basket.

That allows a future question:

> Why did Atlas say this quote was lawful?

to be answered from preserved evidence rather than reconstructed from current prices.

## 14. Basket-level benchmark

The benchmark gate is primarily evaluated against the comparable whole customer basket.

Individual benchmark lines remain visible and linked.

This permits a source mix where one line is slightly less favorable while the whole order still satisfies the institutional market rule.

A later policy may impose line-level ceilings as an additional rule. V1 does not assume that rule.

## 15. Request identity remains source-owned

The receipt stores a typed `request_ref` object rather than inventing a universal Demand table.

Example:

```json
{
  "sourceDomain": "florist_quote_intake",
  "sourceRef": "request-123"
}
```

or:

```json
{
  "sourceDomain": "commercial_order_line",
  "sourceRef": "..."
}
```

This preserves the current universal-infrastructure rule:

```text
source-owned demand
→ generic evaluation
→ receiving commercial authority
```

A future universal demand relation may only be introduced if multiple live domains prove that source-owned demand cannot carry the required identity/history.

## 16. Supplier-source integration

The candidate sibling fulfillment stack remains responsible for:

```text
source observation
→ qualification
→ fulfillment composition
→ protected cost basis
```

This tranche begins only after the cost basis is governed.

It does not decide that a FlowerBuyer listing is compatible with a florist request.

It does not choose a supplier.

It does not convert a market benchmark into an acquirable source.

## 17. Reality identity boundary

An observed market actor may already exist as a canonical `reality.entities` row.

If so, the observation may reference that Entity.

If not, the observation may preserve a source label without minting a convenience Entity.

Source ingestion must not create duplicate real-world identities merely to satisfy pricing storage.

Identity admission remains governed by Reality.

## 18. Ledger isolation

Every canonical row in this tranche is directly scoped to `ledger.ledgers(id)`.

A policy from one Ledger cannot be resolved for another.

A market observation from one Ledger cannot be linked into another Ledger's quote receipt.

A quote receipt cannot reference a policy from another Ledger.

This makes the model usable for unrelated Atlas customers without a shared Organization authority layer.

Browser roles receive no direct table access in v1. Service/internal commands remain the only writers/readers until an explicit user-facing membrane is built.

PostgreSQL row-level security remains enabled as an additional database boundary, but direct authenticated access is not granted by this tranche.

## 19. Cross-domain qualification

The schema contains no:

- flower;
- stem;
- florist;
- farm;
- Baisch;
- Springfield;
- wholesale-floral-specific column.

A construction-material Ledger can use the same policy:

```text
target gross margin = 25%
minimum gross margin = 20%
benchmark constraint = none
```

and evaluate a material quote from a governed cost basis.

That proves schema neutrality.

It does not claim that flower source qualification and construction source qualification are the same domain logic.

## 20. Authority boundaries

This tranche establishes no authority to:

- contact a supplier;
- place a bid;
- buy product;
- create Spend;
- create inventory;
- issue a customer offer;
- create an Order;
- collect payment;
- fulfill an Order.

It stores policy, market evidence, and deterministic evaluation provenance.

An operation that crosses from evaluation into external action still requires its own governed authority.

## 21. Candidate service membrane

Candidate service/internal functions:

- `atlas.record_ledger_commercial_pricing_policy_service_v1(...)`
- `atlas.ledger_commercial_pricing_policy_at_v1(...)`
- `atlas.record_ledger_commercial_market_observation_service_v1(...)`
- `atlas.ledger_commercial_quote_envelope_v1(...)`
- `atlas.ledger_commercial_quote_evaluate_v1(...)`
- `atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(...)`

None are browser-executable in v1.

## 22. Validation requirements

Candidate validation must prove at least:

1. all rows are Ledger-scoped;
2. there is no `organization_id` dependency;
3. active/effective policy windows cannot overlap;
4. superseded policy history remains resolvable for its historical time;
5. target and minimum rates are distinct;
6. benchmark discount is required only for `discount_rate`;
7. source-faithful market observations may preserve unknown currency/denominator;
8. unknown-basis observations cannot be used computationally as quote benchmarks;
9. a 10% gross-margin + strict-below policy against a $150 benchmark yields a target cost ceiling of $135 exclusive;
10. a $120 protected cost and $142.50 quote against $150 is eligible and preserves $7.50 / 5% customer savings;
11. a quote above the benchmark is blocked even when its margin is strong;
12. a required benchmark that is missing produces incomplete evidence;
13. a non-flower Ledger with no market gate uses the same policy/evaluation machinery;
14. quote receipts are append-only and preserve exact policy + benchmark references;
15. direct browser table access remains absent;
16. no Order, Spend, payment, inventory, procurement commitment, or customer offer is created.

## 23. Release boundary

This is candidate source only.

Do not:

- create a production migration from this candidate yet;
- apply these objects directly to production;
- use the live Feast Guild policy as seed data merely because the fixture represents it;
- connect live wholesaler credentials through this tranche;
- merge the sibling fulfillment candidate implicitly.

When the governed validation/release lane reopens, the integration sequence should be:

```text
Reality/Ledger core
→ supplier/fulfillment economics candidate
→ Ledger commercial market policy
→ Feast Guild quote adapter
→ authenticated Workbench / operator surface
```

The final promotion must reconcile branch histories rather than treating either candidate branch as if the other does not exist.

## 24. Resulting architecture

```text
Reality Entity
  ↓ subject of
Ledger
  ↓
effective commercial pricing policy
+
source-backed market benchmark observations
+
source-owned customer demand reference
+
governed fulfillment cost basis
  ↓
deterministic quote envelope/evaluation
  ↓
append-only evaluation receipt
  ↓
later governed customer-offer carrier
```

The enduring rule is:

> Atlas must remember not only the number it quoted, but the institutional rule, outside alternative, protected cost basis, and evidence that made that number lawful at that time.