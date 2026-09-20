# Person Life Consequence → Principal Clock Candidate v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche creates the first lawful Clock projection for Person Life consequences without altering the live V1 Clock path.

## Boundary

The movement is:

`Person Life Consequence → Principal carrier → execution ready → complete accepted Clock Characterization → Clock Candidate → Principal Clock arbitration`

The candidate projection is read-only. It does not mutate the consequence, create a task, or create a placement.

## Why V2

The live contracts remain untouched:

- `atlas.principal_clock_candidates_v1`
- `atlas.principal_clock_arbitration_v1`
- `atlas.principal_clock_api_v1`

The candidate adds side-by-side contracts:

- `atlas.principal_person_life_consequence_clock_candidates_v1`
- `atlas.principal_clock_candidates_v2`
- `atlas.principal_clock_arbitration_v2`
- `atlas.principal_clock_api_v2`

`principal_clock_candidates_v2` is exactly:

`all V1 candidates + admitted Person Life consequences`.

No existing source class is rewritten.

## Admission

The new source view independently requires:

- open Person Life consequence;
- established requirement;
- established carrier;
- carrier exactly `principal:<active principal id>`;
- execution readiness = `ready`;
- one current accepted `clock_characterization` Claim;
- complete characterization according to the governing completeness function.

Incomplete consequences do not appear in the Clock inventory.

## Relevance-start safety

Characterization completeness requires an explicit `timing.windowStart` or `timing.fixedStart`.

A future deadline alone does not establish current relevance. This closes the live arbitration behavior in which a null relevance start would otherwise be interpreted as an already-open window.

## Candidate mapping

The candidate receives timing, duration, floor, protection, interruptibility, delegability, owner-required semantics, consequence-of-delay, and reason-for-floor from the accepted Clock Characterization Claim.

Requirement/carrier/readiness/source evidence remain separately traceable in candidate metadata.

The title is presentation-only and deterministic. `laundry_cycle_needed` displays as `Laundry`.

## Arbitration

V2 arbitration is generated from the exact live V1 arbitration definition with only the candidate source changed from `principal_clock_candidates_v1` to `principal_clock_candidates_v2`.

No ranking rule changes.

## API

`atlas.principal_clock_api_v2(day, as_of)` is generated from the live V1 API with V2 arbitration substituted.

The returned contract version is `principal_clock_api_v3` so consumers can distinguish the expanded inventory.

## Non-authority

This candidate does not:

- replace the live Clock;
- modify V1 Clock views/functions;
- create Clock Characterization;
- resolve carrier;
- establish readiness;
- create tasks;
- create Household Rhythms;
- create Owner Obligations;
- persist Today placement;
- change ranking law.

## Validation target

Before promotion, clone validation must prove:

1. V2 contains every V1 candidate unchanged;
2. unresolved consequence is absent;
3. non-Principal carrier is absent;
4. non-ready consequence is absent;
5. missing/partial characterization is absent;
6. deadline-only characterization without relevance start is absent;
7. admitted characterization maps exact candidate fields;
8. source id is consequence instance id;
9. candidate metadata preserves consequence/characterization provenance;
10. V2 arbitration over a V1-only fixture is identical to V1;
11. adding one admitted consequence changes only the candidate field and resulting ranking;
12. V1 definitions remain unchanged;
13. V2 API creates no state;
14. authenticated V2 API is registered and anonymous denied;
15. internal V2 arbitration is not authenticated-executable;
16. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze V1/V2 comparison fixtures, and run Production Schema Clone Validation. Cutover from V1 to V2 is a separate later authority.
