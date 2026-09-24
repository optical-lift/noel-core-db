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
→ explicit selected line plans
→ Candidate -> Requirement Qualification
→ Neutral Fulfillment Composition
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

5. only after all parent + adapter proofs pass, decide whether the parent and adapter should become one ordered release set or separate governed migrations.

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

## GitHub Actions lock boundary

Until private Actions reset on **2026-10-01**:

- keep this branch candidate-only;
- do not open a validation/release issue;
- do not create a PR merely to obtain checks that cannot run;
- do not merge into `main`;
- do not create production migration history.

Useful work may continue above this checkpoint, but this branch should remain a recoverable quote-adapter proof.
