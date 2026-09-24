# Feast Guild Whole-Order Quote v1 — Candidate Manifest

**Status:** candidate-only, not released  
**Date:** 2026-09-24  
**Branch:** `architecture/feast-guild-whole-order-quote-v1`  
**Parent checkpoint:** `optical-lift/noel-core-db@78f705484ba0302395eae784ee5861e0da80d597`

## Purpose

This candidate is the first flower-specific whole-order adapter above the frozen Fulfillment Economics candidate tranche.

It does not add new buy-side authority.

It composes the already-defined candidate contracts into one florist-facing preparation movement:

~~~text
florist basket
→ candidate source plans
→ Candidate -> Requirement Qualification
→ exact known landed economics
→ Feast Guild source preference policy
→ selected line plans
→ Commercial Price Evaluation
→ whole-order aggregation
→ Commercial Offer Snapshot-ready packet
~~~

## Files

1. `architecture/feast-guild-whole-order-quote-v1.md`
   - governing flower-adapter contract and production boundary.

2. `candidates/atlas_feast_guild_whole_order_quote_v1.sql`
   - read-only `atlas.feast_guild_flower_quote_prepare_v1(jsonb,jsonb,jsonb,jsonb)`.

3. `candidates/atlas_feast_guild_whole_order_quote_v1_validation.sql`
   - rollback proof for complete and incomplete multi-line florist baskets.

4. `candidates/fixtures/feast_guild_whole_order_quote_fixture_v1.json`
   - human-readable fixture, arithmetic, source-fact presentation, and expected states.

5. `architecture/feast-guild-flower-source-selection-policy-v1.md`
   - Feast Guild-specific source tiers and fixed +10% landed-cost preference band.

6. `candidates/atlas_feast_guild_flower_source_selection_policy_v1.sql`
   - immutable V1 policy, candidate evaluation, deterministic source selection, and whole-basket candidate-to-quote orchestration.

7. `candidates/atlas_feast_guild_flower_source_selection_policy_v1_validation.sql`
   - rollback proof for source preference boundaries, fail-closed economics, and mixed-source whole-order quoting.

8. `architecture/feast-guild-flower-candidate-gathering-v1.md`
   - source-discovery contract for actual Elm Ready inventory and admitted External Supply Offers.

9. `candidates/atlas_feast_guild_flower_candidate_gathering_helpers_v1.sql`
   - normalized flower requirement matching and Elm Ready candidate projection.

10. `candidates/atlas_feast_guild_flower_candidate_gathering_external_v1.sql`
   - external pack/minimum arithmetic, availability/date qualification, source-tier preservation, and explicit landed-cost completeness.

11. `candidates/atlas_feast_guild_flower_candidate_gathering_service_v1.sql`
   - service-only current-source reader that assembles per-line candidate sets from Elm Ready inventory and admitted External Supply Offers.

12. `candidates/atlas_feast_guild_flower_candidate_gathering_v1_validation.sql`
   - rollback proof from source-owned supplier observation -> candidate gathering -> Feast Guild source selection -> protected quote, plus pure Ready-inventory boundary proofs.

## Dependency

Do not install this candidate by itself against current production.

It depends on the parent Fulfillment Economics candidate contracts, including:

- `atlas.requirement_set_evaluate_v2`;
- `atlas.fulfillment_candidate_qualification_v1`;
- `atlas.fulfillment_composition_position_v1`;
- `atlas.commercial_price_from_cost_basis_v1`;
- `atlas.commercial_price_evaluate_v1`.

The production Commercial Offer Snapshot authority already exists, but this adapter only returns a snapshot-ready draft and does not invoke its writer.

## Disposable validation order

When private GitHub Actions are available again:

1. install the frozen parent candidate bundle:
   `candidates/atlas_fulfillment_economics_tranche_v1.sql`

2. run its three parent rollback bundles:
   - `atlas_fulfillment_economics_tranche_v1_validation.sql`
   - `atlas_fulfillment_economics_tranche_v1_acquisition_validation.sql`
   - `atlas_fulfillment_economics_tranche_v1_fulfillment_validation.sql`

3. install:
   `candidates/atlas_feast_guild_whole_order_quote_v1.sql`

4. run:
   `candidates/atlas_feast_guild_whole_order_quote_v1_validation.sql`

5. install:
   `candidates/atlas_feast_guild_flower_source_selection_policy_v1.sql`

6. run:
   `candidates/atlas_feast_guild_flower_source_selection_policy_v1_validation.sql`

7. install, in order:
   - `candidates/atlas_feast_guild_flower_candidate_gathering_helpers_v1.sql`
   - `candidates/atlas_feast_guild_flower_candidate_gathering_external_v1.sql`
   - `candidates/atlas_feast_guild_flower_candidate_gathering_service_v1.sql`

8. run:
   `candidates/atlas_feast_guild_flower_candidate_gathering_v1_validation.sql`

9. only after all parent + quote-adapter + source-policy + candidate-gathering proofs pass, decide whether the layers should become one ordered release set or separate governed migrations.

Do not create migration history from either candidate bundle directly.

## Expected complete proof

Fixture basket:

- 90 Standard Carnations;
- 50 White Roses 60 cm;
- 5 bunches Eucalyptus.

Explicit fixture economics:

- carnations: 100-stem source pack, $38 landed, 10 stems excess;
- roses: $55 landed for 50;
- eucalyptus: $25 landed for 5 bunches;
- explicit 30% gross-margin input;
- upward cent rounding.

Expected prepared customer terms:

~~~text
Carnations       90 × $0.61 = $54.90
White roses      50 × $1.58 = $79.00
Eucalyptus        5 × $7.15 = $35.75
-------------------------------------
Whole order                    $169.65
~~~

Expected state:

- `complete`;
- three priced lines;
- zero blocked lines;
- USD;
- Commercial Offer Snapshot draft `offerState = complete`.

These are validation numbers only, not live Feast Guild prices.


## Feast Guild source-selection law

The previously unresolved source-selection boundary is now decided for V1.

Automatic line selection uses:

~~~text
1. elm_owned_or_grown
2. regional_us
3. us_grown
4. imported
~~~

Rules:

- qualification precedes preference;
- comparison basis = complete known landed economic cost;
- policy currency = USD;
- maximum automatic preference premium = 10% above the cheapest qualified known-cost candidate;
- exactly +10% is allowed;
- anything above +10% is not automatically selected;
- within the best in-band tier, lower landed cost wins;
- unknown freight, unresolved qualification, or unsupported source tier cannot enter automatic selection;
- an out-of-band more-preferred candidate remains visible and requires separate operator approval authority.

The automatic +10% band cannot be widened by a caller parameter.

### Automatic whole-order fixture

The source-policy validation also proves a three-line mixed-source basket:

~~~text
Carnations:
  imported lawful cost = $38
  Elm lawful cost      = $41
  selected             = Elm
  customer line        = 90 × $0.66 = $59.40

White roses:
  imported             = $55
  U.S.-grown           = $58
  regional U.S.        = $62 (outside 10% band)
  selected             = U.S.-grown
  customer line        = 50 × $1.66 = $83.00

Eucalyptus:
  imported             = $25
  regional U.S.        = $27.50 (exactly +10%)
  selected             = regional U.S.
  customer line        = 5 × $7.86 = $39.30

Whole prepared quote   = $181.70
~~~

Those values are validation fixtures only, not live supplier or Feast Guild prices.

## Expected incomplete proof

Replace the eucalyptus landed-cost component with:

~~~text
known merchandise = $25
required freight = unresolved
~~~

Expected state:

- two priced lines;
- eucalyptus blocked;
- priced subtotal = $133.90;
- whole-order total = null;
- snapshot draft `offerState = incomplete_evidence`;
- explicit `required_cost_unresolved` pricing reason.

Unknown freight may not become zero.

## Additional fail-closed proofs

Validation also requires:

- missing selected line plan -> incomplete;
- satisfied required qualification without evidence -> incomplete;
- fulfillment quantity mismatch -> incomplete;
- quote preparation creates no:
  - Commercial Order;
  - Commercial Payment;
  - Organization Spend;
  - Work Requirement;
  - flower inventory;
  - Commercial Offer Snapshot;
  - External Acquisition Commitment.

## Real-source note

The existing Baisch & Skinner fixture remains useful source evidence but is intentionally not promoted into a complete quote merely from its displayed price list.

Where that source does not explicitly establish currency, price denominator, availability, freight, or other required terms, the quote path must preserve those facts as unresolved.

This candidate must not “clean up” source ambiguity for convenience.


## Candidate gathering checkpoint

The quote path no longer requires an operator to hand-build candidate plans.

The candidate gathering layer reads:

~~~text
Elm Ready inventory position
+
current admitted external supply observations
→ per-line candidate sets
→ Feast Guild source policy
→ selected plans
→ protected quote
~~~

Elm Ready inventory uses `available_quantity`, not the original prepared/birth quantity.

Because flower inventory is perishable, remaining quantity alone is insufficient. Automatic Elm qualification also requires explicit usable-through/freshness evidence covering the florist requested date. Existing Ready lots without that evidence remain visible source truth but are not automatically offerable.

External candidates preserve:

- current price basis and currency;
- pack and minimum-order math;
- explicit quantity capacity;
- requested-date evidence;
- freight;
- handling/provider fees;
- source-preference evidence.

Unknown fields remain unresolved.

### Remaining Elm economic boundary

Current Elm Ready inventory has retail valuation but no governed owned-inventory economic cost basis.

Therefore the candidate gatherer deliberately emits:

~~~text
Elm Ready candidate:
  physical availability = source-backed
  source tier = elm_owned_or_grown
  economic cost = unresolved
~~~

It does **not** use retail price, Retail Flower Product Price Book value, or historical sale price as cost.

Until an owned-inventory cost basis is established, Elm inventory can be discovered and shown as the most-preferred physical source but cannot automatically defeat or beat an external supplier in the +10% landed-cost comparison.

That is now the next explicit business/economic decision boundary.

## GitHub Actions lock boundary

Until private Actions reset on **2026-10-01**:

- keep this branch candidate-only;
- do not open a validation/release issue;
- do not create a PR merely to obtain checks that cannot run;
- do not merge into `main`;
- do not create production migration history.

Useful work may continue above this checkpoint, but this branch should remain a recoverable quote-adapter proof.
