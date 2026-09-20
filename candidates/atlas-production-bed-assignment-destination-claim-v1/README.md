# Production Bed Assignment → Canonical Destination Claim Projection v1

Candidate source for issue #914.

## Problem

Production Bed Assignments already contain owner-established spatial decisions, but the crop requirement/warrant system reads `crop_destination_claims` as canonical destination truth.

For Rocket Mix F1, Production already says:

- BW1: 7 bed-ft / 180 planned seedlings
- BW3: 20 bed-ft / 540 planned seedlings

Yet canonical destination coverage reports missing because no claim exists.

Teaching the warrant to read both tables would preserve two competing authorities. This tranche instead projects Production Bed Assignment truth into the existing canonical claim model.

## Projection law

One Production Bed Assignment owns one deterministic projected claim:

`production-bed-assignment:<assignment_id>:destination-claim`

For an active assignment:

- exact crop-cycle authority requires exactly one **confirmed primary** Production Lot → Crop Cycle relation;
- destination object comes from the assignment;
- plant quantity comes only from explicit `metadata.planned_seedlings`;
- bed-feet remain spatial evidence and are never converted into plant count;
- owner-checkpoint / owner-instruction / owner-reconciliation sources project as `committed / principal`;
- other sources project no stronger than `planned / farm_operations`.

For source lifecycle:

- `assigned` → canonical claim `active`
- `released` → claim `released`
- `cancelled` → claim `cancelled`
- deletion terminalizes an active projected claim rather than orphaning it
- terminal claims are not silently resurrected; a new source assignment/generation is required.

A projected assignment may not move between Production Lots after the claim exists.

## Trigger ordering

The projection trigger is named `p1_sync_production_bed_assignment_destination_claim_v1`.

The existing Production work trigger is `zz_reconcile_production_work_from_bed_assignment_v1`.

For the same AFTER event, the projection therefore runs first so Production work reconciliation observes current canonical destination coverage within the same transaction.

## Current production backfill

At audit time there are six active Production Bed Assignments across four Production Lots/crop cycles.

All six have:

- exactly one confirmed primary crop-cycle lineage;
- explicit positive `planned_seedlings`;
- source `owner_checkpoint_20260829`.

The migration backfills those rows through the same projection function used by future trigger-driven changes.

## Boundary

This unifies destination authority. It does **not** infer worker responsibility, mark bed-preparation Company Work complete, or convert bed capacity into biological truth.

A later current-state observation can change the moving cohort quantity. Canonical destination coverage will then become partial if the existing plant allocation no longer covers the observed cohort, forcing a real reallocation instead of silently stretching the old bed plan.
