# Laundry Actual → Consequence Resolution v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche makes physical reality, not a checkbox, the authority that clears the first Laundry consequence.

## First resolution law

The first executable Laundry consequence is:

```text
consequenceKind = laundry_cycle_needed
actionKey       = household.laundry:begin_cycle
```

That requirement is satisfied when source-backed reality establishes:

```text
process_actual.transition = entered_washing
process_actual.toState    = washing
```

Therefore:

`laundry_cycle_needed → entered_washing actual → consequence resolved`

The person does not need to “complete a task” to make this true.

## Actuals

Laundry process actuals are stored through the existing current-Household Claim/Evidence membrane.

V1 admits:

- `entered_washing → washing`
- `entered_drying → drying`
- `entered_readying → readying`
- `returned_to_available → available`
- `became_blocked → blocked`

Each actual is a separate append-like source event:

```text
scope          = household
subject.domain = household.laundry
subject.kind   = kernel_instance
subject.id     = <Laundry instance>
claimType      = process_actual
lifecycle      = observed
```

The physical transition time is explicit and lives on primary Evidence.

## Why not Task completion

Task completion is a UI/execution artifact.

Laundry state is physical household reality.

Checking a box may happen before, after, or instead of the actual physical transition. It therefore cannot be the authority that says the Laundry requirement was satisfied.

## Resolution guard

The released generic Person Life consequence-resolution path accepts an arbitrary evidence object from the caller.

That remains acceptable for generic legacy use, but it is too permissive for the Laundry reference specimen.

This candidate adds a persistence guard for Laundry `consequence_resolution` events.

The guard independently verifies:

- the open consequence;
- the Laundry definition and instance;
- the Household actual Claim;
- the actual's primary Evidence;
- same-instance custody;
- the exact supported transition;
- the actual timestamp;
- that the actual occurred no earlier than the consequence opening;
- the exact resolution Evidence envelope;
- the exact generic resolution evaluation.

A caller cannot resolve Laundry by supplying `{"done":true}`.

## Resolver

`atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(consequence, actualClaim)`

accepts identities only.

It constructs the exact governed resolution packet and calls the existing `record_person_life_state_api_v1` path.

The existing Person Life machinery then:

- writes the append-oriented resolution event;
- marks the consequence instance resolved;
- preserves `resolved_by_event_id`;
- preserves `resolved_at`.

Because the V2 Clock candidate projection admits only open consequences, the resolved consequence disappears from the candidate inventory automatically. No special Clock deletion is required.

## Important non-authority

Recording an actual does not:

- create a task;
- resolve an unrelated consequence;
- establish a Rhythm;
- change responsibility;
- create Clock Characterization;
- place anything on Today.

Resolving `laundry_cycle_needed` from `entered_washing` does not claim the whole Laundry domain is finished. It proves only that the requirement to **begin the cycle** has been satisfied.

Later consequences may represent drying, readying, deadline turnaround, or return-to-use when those causal laws are explicitly admitted.

## Validation target

Before promotion, clone validation must prove:

1. actual writer requires signed-in current Household;
2. actual writer requires active same-Household Laundry instance;
3. actual writer requires explicit offset-aware `occurredAt`;
4. unsupported transitions fail;
5. each transition maps to its exact physical state;
6. retries are idempotent through sourceActionId/sourceKey custody;
7. actual produces Household Evidence + observed process_actual Claim;
8. generic arbitrary Laundry resolution is rejected by persistence guard;
9. actual from another Household is rejected;
10. actual from another Laundry instance is rejected;
11. actual before consequence opening is rejected;
12. only `entered_washing` resolves `laundry_cycle_needed`;
13. entered_drying/available/etc. do not resolve that consequence;
14. resolver cannot supply custom resolution Evidence;
15. canonical actual timestamp becomes resolved_at;
16. resolution event retains actual Claim/Evidence provenance;
17. consequence becomes resolved through existing Person Life machinery;
18. resolved consequence disappears from V2 Clock candidates by status projection, not Clock mutation;
19. no task, Rhythm, Owner Obligation, or Clock placement is created;
20. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
21. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze fixtures/postconditions, and run Production Schema Clone Validation before merge.
