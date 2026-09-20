# Atlas Personal Laundry Authority Split v1

Status: **source-complete candidate for the authority split; inert, not migration-identified, not clone-validated, not released**.

This package repairs the first blocking defect discovered while turning Laundry into the reference Personal-domain specimen.

## Defect

The live `atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)` currently combines two different authorities:

1. establish a household-specific Laundry instance; and
2. create a protected, Principal-required, capacity-blocking Household Rhythm.

Supplying `usualPattern` therefore promotes descriptive calibration directly into recurrence, responsibility, capacity, and Clock-adjacent authority.

That violates the Personal-domain chain now selected in Atlas:

`World Knowledge → Applicability → Instance → Relations → Evidence → Observed State → Consequence → Clock Arbitration → Action → Actual → Learning`

## Candidate change

`candidate.sql` replaces the existing calibration function without changing its public signature.

The candidate:

- keeps model selection and household-instance calibration intact;
- keeps `usualPattern` for backward-compatible descriptive calibration;
- removes the call to `atlas.principal_upsert_household_rhythm_api_v1`;
- creates no Rhythm;
- modifies no Rhythm;
- deletes no Rhythm;
- no longer hard-codes `principalRequired=true`;
- no longer hard-codes `blocksCapacity=true`;
- returns an explicit truth boundary describing the split;

An already-authorized Household Rhythm is deliberately left untouched. Removing it merely because calibration changed would be another unauthorized transition.

## Why this is the first change

The database already has the machinery needed for later Laundry stages:

- `atlas.world_kernel_definitions` / `atlas.household_kernel_instances` — generic world knowledge and household instance;
- `atlas.evidence_records`, `atlas.claim_records`, `atlas.claim_evidence_links` — universal evidence/claim separation;
- Personal Reality Capture membrane — raw first-party testimony before interpretation;
- `atlas.person_life_consequence_instances` — explicit separation of requirement, carrier, readiness, and placement;
- Household Rhythm and Principal Clock machinery — downstream authorities.

The problem is not absence of primitives. It is that Laundry currently jumps across them.

This tranche removes that jump before any additional Laundry writer is introduced.

## Explicit non-goals

This candidate does **not** yet:

- add a new Observation table;
- create a Laundry-specific evidence store;
- model responsibility as a new generic schema;
- create a new consequence engine;
- create a Laundry task;
- place Laundry on Today;
- infer a Rhythm from actuals;
- modify Cleaning or Groceries, even though their generic model-acceptance path has a similar calibration-to-Rhythm coupling.

Those are deliberately left for subsequent domain-binding tranches so Laundry can prove the method before it is generalized.

## Validation target

Before promotion to a migration, clone validation must prove:

1. the function definition contains no call to `principal_upsert_household_rhythm_api_v1`;
2. calibration still writes/updates the `household.laundry` kernel instance;
3. calibration returns `rhythmMutation = none`;
4. an existing Laundry Rhythm, if fixture-created before calibration, remains byte-for-byte unchanged after calibration;
5. calibration creates no new Laundry Rhythm when none exists;
6. zero candidate-introduced Atlas lint errors.

`postconditions.sql` currently provides source/schema assertions that do not require fixture identity. Behavioral fixture coverage must be added when this candidate receives a legitimate migration identity.

## Promotion rule

Do not place this file directly into `supabase/migrations/`.

A legitimate migration version must be generated with the repository-pinned Supabase CLI. The exact promoted bytes and matching validation files must then pass Production Schema Clone Validation before merge.

Production release is a later, separate authority.
