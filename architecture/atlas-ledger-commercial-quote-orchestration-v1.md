# Atlas Ledger Commercial Quote Orchestration v1

**Status:** candidate-only integration contract  
**Date:** 2026-09-25  
**Base:** `architecture/atlas-ledger-commercial-market-policy-v1` @ `056af23ab73316838e7c30482248f1227479a750`  
**Sibling fulfillment source:** `architecture/feast-guild-whole-order-quote-v1` @ `b97ad69098b197582ace923a1d5599671a97d86f`  
**Production boundary:** not released; no production migration, PR, or deployment while the governed private-CI release lane is unavailable  
**First proof:** Feast Guild wholesale floral quoting under a Ledger-scoped 10% gross-margin policy and an incumbent-market ceiling

## 1. Purpose

Atlas now has two separately-correct candidate systems:

1. fulfillment economics can qualify source candidates, compose landed cost, and price from an explicit margin/markup input;
2. Ledger commercial market policy can preserve effective-dated pricing law, incumbent-market observations, and quote-evaluation receipts.

They must not remain disconnected.

The integrated commercial movement is:

```text
customer basket
→ source-backed incumbent benchmark
→ maximum lawful customer price / protected-cost ceiling
→ source candidate gathering and qualification
→ minimum feasible basket cost
→ explicit source plan
→ Ledger-native quote packet
→ policy + market evaluation
→ append-only evaluation receipt
```

The key new rule is that source preference is subordinate to commercial viability.

A locally preferred candidate is not useful if choosing it makes the whole basket commercially impossible while a cheaper qualified candidate would permit a lawful quote.

## 2. Reality / Ledger custody

All institutional policy and evaluation context is scoped by `ledger.ledgers(id)`.

This tranche introduces no `organization_id`, Principal, Organization Membership, or legacy Principal Ledger Authority dependency.

The customer demand itself remains source-owned.

The supplier catalog itself remains source-owned.

The generic orchestration layer references those source-owned objects and evaluates them; it does not replace their identity.

## 3. Why the older Feast Guild whole-order quote adapter is not the new-core quote authority

The existing candidate `atlas.feast_guild_flower_quote_prepare_v1(...)` was designed before the Reality/Ledger constitutional cutover.

Its pricing math and line-verification logic remain useful, but its `snapshotDraft` requires a legacy `organizationId` because it was shaped for `atlas.commercial_offer_snapshots`.

That legacy carrier must not become a dependency of new Reality/Ledger architecture.

This tranche therefore creates a Ledger-native quote packet that:

- does not require `organizationId`;
- does not write a legacy Commercial Offer Snapshot;
- preserves line-level candidate, qualification, fulfillment-cost, and proposed-price facts;
- can later be projected into whatever Reality/Ledger customer-offer authority replaces the legacy snapshot carrier.

## 4. Persisted policy → universal pricing input

Candidate function:

`atlas.ledger_commercial_pricing_policy_input_v1(uuid)`

It converts one exact effective-dated Ledger policy row into the existing universal:

`commercial_price_policy_input_v1`

The target rate is used for ordinary quote generation.

The minimum rate remains a separate market-policy evaluation gate and is not substituted into the pricing input.

Optional rounding and minimum-unit-price rules may be carried inside `cost_basis_policy` and passed through only when explicitly governed.

No default rounding rule is invented.

## 5. Benchmark aggregation and procurement envelope

Candidate function:

`atlas.ledger_commercial_benchmark_envelope_from_observations_v1(...)`

It receives exact market-observation references plus the benchmark contribution calculated for each requested line.

It verifies:

- every observation belongs to the same Ledger;
- each observation existed by the evaluation time;
- its effective window covers the evaluation time when an effective window is stated;
- it has not already been superseded for that evaluation time;
- currency and price basis are computationally known;
- benchmark contribution is nonnegative.

It then aggregates the basket benchmark and applies the exact effective Ledger policy.

For the current Feast Guild launch policy:

```text
pricing method = gross_margin
target = 10%
minimum = 10%
market rule = strictly below incumbent
```

a $150 incumbent basket produces:

```text
customer quote ceiling = $150 exclusive
target protected-cost ceiling = $135 exclusive
minimum protected-cost ceiling = $135 exclusive
```

This is the sourcing budget.

## 6. Commercial viability precedes source preference

The prior Feast Guild source selector can prefer Elm / regional / U.S. sources when their landed cost is within a fixed preference band.

That rule was designed before an incumbent-market ceiling existed.

A counterexample proves why the market envelope must now come first:

```text
cheapest qualified candidate = $100
preferred local candidate = $110
target protected-cost ceiling = $105
```

The old preference rule would choose $110.

The commercial system must instead preserve:

```text
$100 plan = commercially viable
$110 plan = preference-valid but commercially nonviable
```

Therefore this tranche does not automatically invoke the old line-by-line source selector as the final authority.

## 7. Feast Guild basket viability packet

Candidate function:

`atlas.feast_guild_flower_commercial_viability_from_candidates_v1(...)`

This is a domain adapter over the universal policy envelope plus the existing Feast Guild candidate evaluator.

For every basket line it:

1. evaluates all supplied source candidates through existing directional qualification and landed-cost rules;
2. identifies the cheapest selectable candidate;
3. sums the cheapest candidate for every line into the minimum feasible basket cost;
4. compares that minimum feasible basket cost with the target and minimum protected-cost ceilings;
5. calculates the maximum landed cost each individual line could consume if every other line remained at its cheapest selectable cost.

The packet returns:

- minimum feasible basket cost;
- target/minimum protected-cost ceilings;
- target headroom;
- minimum headroom;
- cheapest source per line;
- all candidate evaluations;
- per-line target/minimum candidate cost ceilings;
- overall commercial viability state.

This function does **not** select the final basket.

That is deliberate.

Multiple preference upgrades may consume the same shared headroom, so evaluating each line independently does not prove that all upgrades can be selected together.

A future portfolio planner may optimize those combinations. Until then, a human operator may choose the final explicit plan from the visible viable candidates.

## 8. Ledger-native Feast Guild quote packet

Candidate function:

`atlas.feast_guild_flower_ledger_quote_prepare_v1(...)`

Inputs:

- the florist basket;
- one explicit selected plan per line;
- the universal pricing-policy input produced from the exact Ledger policy.

For each line it reuses the existing Feast Guild candidate evaluator.

Only a candidate that is still:

- qualified;
- exactly coverable;
- economically known;
- currency-compatible;

may be priced.

The result includes:

- protected total cost;
- customer quote total;
- line-level protected cost;
- proposed unit/line prices;
- selected source references;
- selection basis;
- qualification/economic evidence.

It creates no legacy snapshot draft and no durable commercial commitment.

## 9. Policy-bound quote assessment

Candidate function:

`atlas.ledger_commercial_quote_packet_evaluate_v1(...)`

The function receives a completed Ledger-native quote packet and the exact market-observation benchmark lines.

It resolves the policy in force at the requested evaluation time, verifies the quote packet's protected-cost total against its line costs, aggregates the benchmark basket, and applies the Ledger quote evaluator.

Possible results are:

- `eligible`;
- `review_required`;
- `blocked`;
- `incomplete_evidence`.

The packet therefore cannot become a customer-facing lawful quote merely because the source math worked.

Both gates must pass:

```text
protected institutional economics
+
market rule
```

## 10. Feast Guild policy-bound orchestration

Candidate function:

`atlas.feast_guild_flower_quote_under_ledger_policy_v1(...)`

Movement:

```text
Ledger + policy key + evaluation time
→ exact policy row
→ commercial_price_policy_input_v1
→ explicit Feast Guild selected plans
→ Ledger-native quote packet
→ benchmark aggregation
→ commercial evaluation
```

The result contains both the source/quote calculation and the policy/market decision.

It still does not send the quote, take payment, or buy flowers.

## 11. Evaluation receipt

Candidate service function:

`atlas.record_ledger_commercial_quote_packet_receipt_service_v1(...)`

A complete quote packet may be preserved through the existing append-only Ledger commercial quote-evaluation receipt authority.

The receipt preserves:

- request reference;
- exact policy version;
- protected cost;
- proposed quote total;
- benchmark observations;
- evaluation state;
- quote packet;
- provenance.

Blocked quotes may be preserved as receipts.

An incomplete quote packet with no complete cost/price evidence is not forced into a receipt schema that requires numerical totals.

## 12. Manual operator use before catalogue automation

The manual operating sequence is now explicit.

For a real florist request:

```text
1. record customer basket
2. record current incumbent benchmark observations
3. calculate benchmark basket
4. derive protected-cost ceiling
5. manually inspect supplier catalogues
6. enter source candidate facts
7. inspect minimum feasible basket cost and line headroom
8. choose explicit source plan
9. prepare Ledger-native quote
10. evaluate margin + incumbent rule
11. preserve evaluation receipt
12. only then use a separately governed customer-offer / payment / procurement action
```

The later cloud-browser/catalogue automation replaces steps 5–6.

It does not change the governing commercial law.

## 13. Feast Guild launch rule represented here

Current launch policy:

```text
target gross margin = 10%
minimum gross margin = 10%
customer quote must be strictly below the comparable incumbent basket
```

No 5% savings rule is assumed.

If Feast Guild later establishes a required customer discount, the existing market-policy kernel already supports `discount_rate`.

If Feast Guild later raises target gross margin toward 20–30%, a new effective-dated policy row is created rather than rewriting earlier quote history.

## 14. No automatic purchasing

Commercial viability is not procurement authority.

Even an `eligible` result means only:

> Under the supplied source plan, protected cost, effective policy, and benchmark evidence, these proposed customer terms satisfy the commercial rules.

It does not mean:

- buy the supplier product;
- place an auction bid;
- reserve inventory;
- create Spend;
- create customer debt;
- create an Order;
- charge payment;
- deliver product.

Those remain separate governed operations.

## 15. Cross-domain boundary

The generic functions contain no flower-specific vocabulary:

- persisted policy → pricing input;
- benchmark aggregation → commercial envelope;
- quote packet → market/policy evaluation;
- quote packet → evaluation receipt.

Only the Feast Guild adapters contain flower vocabulary.

A construction, catering, repair, rental, or other Ledger may produce the same common quote-packet fields and use the same commercial assessment layer.

## 16. Validation boundary

This branch is based on the Reality/Ledger commercial-policy candidate.

The generic orchestration functions can be validated against that branch directly.

The Feast Guild adapter functions depend on sibling fulfillment candidate functions that are not present on this branch.

Therefore the rollback validation:

- fully proves the generic Ledger policy/orchestration functions now;
- conditionally runs the Feast Guild adapter proof when the sibling fulfillment functions are installed in the same disposable validation database;
- explicitly reports when that cross-branch proof is deferred.

When private CI returns, the full combined production-schema clone must install both candidate tranches and run the complete proof before promotion.

## 17. Promotion boundary

Do not:

- create a production migration yet;
- merge the sibling fulfillment candidate implicitly;
- seed live Feast Guild policy or Baisch observations from fixtures;
- create a PR merely to trigger unavailable Actions;
- introduce a legacy `organization_id` dependency to make the old snapshot adapter convenient.

## 18. Result

Atlas now has a clean commercial decision chain:

```text
Reality Entity
  ↓
Ledger
  ↓
effective policy
+
outside-market evidence
+
source-owned demand
+
qualified supplier candidates
  ↓
commercial sourcing envelope
  ↓
explicit viable source plan
  ↓
Ledger-native quote packet
  ↓
margin + market evaluation
  ↓
append-only receipt
```

The enduring principle is:

> Atlas must know whether a source plan can produce a quote that is both economically protected for the institution and meaningfully competitive for the customer before that plan becomes customer-facing commercial action.