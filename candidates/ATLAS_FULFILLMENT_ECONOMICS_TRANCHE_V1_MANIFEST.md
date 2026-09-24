# Atlas Fulfillment Economics Tranche v1 — Candidate Manifest

**Status:** candidate-only, not released  
**Date:** 2026-09-24  
**Branch:** `architecture/atlas-external-supply-offer-v1`

## Governing rule

Nothing in this tranche is a canonical Supabase migration yet.

The production Supabase migration ledger contains no migration matching:

- fulfillment economics;
- external supply offer;
- external acquisition;
- work requirement pool;
- pooled commercial price protection;
- fulfillment candidate qualification;
- neutral fulfillment composition.

No Supabase development branch exists for this work.

Do not create a paid Supabase development branch merely to continue building.

## Canonical source files

The source candidate SQL files are:

1. `atlas_external_supply_offer_v1.sql`
2. `atlas_fulfillment_candidate_qualification_v1.sql`
3. `atlas_neutral_fulfillment_composition_v1.sql`
4. `atlas_commercial_price_from_cost_basis_v1.sql`
5. `atlas_commercial_price_evaluation_v1.sql`
6. `atlas_commercial_commitment_to_company_work_v1.sql`
7. `atlas_company_work_coverage_position_v1.sql`
8. `atlas_work_requirement_pool_position_v1.sql`
9. `atlas_pooled_commercial_price_protection_v1.sql`
10. `atlas_external_acquisition_commitment_v1.sql`
11. `atlas_external_acquisition_fulfillment_intake_v1.sql`

These files own the candidate definitions.

The large tranche install file is generated from these sources and is not an additional authority.

## Disposable install bundle

Run:

`candidates/atlas_fulfillment_economics_tranche_v1.sql`

only against a disposable production-schema clone / local validation database.

It is intentionally wrapped as one candidate install transaction.

It must not be copied into the production migration ledger under its current filename.

## Validation order

After the install bundle, run these rollback validation bundles in order:

1. `candidates/atlas_fulfillment_economics_tranche_v1_validation.sql`
   - pre-acquisition fulfillment-economics proofs;
   - supplier observations;
   - qualification;
   - neutral composition;
   - pricing;
   - Commercial Order -> Company Work;
   - coverage;
   - pooled/break-bulk planning;
   - pooled price protection.

2. `candidates/atlas_fulfillment_economics_tranche_v1_acquisition_validation.sql`
   - External Acquisition Commitment;
   - pooled plan -> protected price -> authorized supplier commitment;
   - commitment-only coverage and cancellation boundaries.

3. `candidates/atlas_fulfillment_economics_tranche_v1_fulfillment_validation.sql`
   - actual external delivery/performance;
   - partial quantitative handoff;
   - accepted/rejected/unresolved output;
   - cancellation after partial fulfillment;
   - external-service cross-domain proof.

Each embedded proof rolls itself back.

The split exists because a single monolithic validation bundle became unnecessarily large for repository transport. It is not an architectural split.

## Individual validation files

Individual `*_validation.sql` files remain source proofs.

The three tranche validation files above are generated convenience bundles.

When a source proof changes, refresh the fitting bundle before treating the candidate tranche as checkpoint-clean.

## Fixtures

Files under `candidates/fixtures/` are evidence / ingestion fixtures, not migrations and not production seed data.

They must not silently become canonical supplier truth merely because they exist in Git.

## Production boundary

This tranche must not be promoted piecemeal.

When release time arrives:

1. validate the complete current source set against a disposable production-schema clone;
2. run the fitting Supabase security/performance advisors;
3. produce one clean canonical migration or an intentionally ordered minimal migration set;
4. verify the generated migration against the current production ledger;
5. only then apply/release through the normal governed path.

Do not convert exploratory commit timestamps into migration versions.

Do not promote generated validation bundles as migrations.

Do not create migration-history entries while still iterating on candidate SQL.

## Current handoff boundary

The candidate chain currently ends at:

`External Acquisition Fulfillment Intake`

It intentionally does not yet establish:

- generic inventory;
- Organization Spend;
- payment;
- customer delivery completion;
- Company Work completion.

The next likely tranche is actual-cost reconciliation, but it should build from this clean candidate checkpoint rather than mutate prior migration history.
