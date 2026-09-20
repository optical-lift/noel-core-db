# Atlas Personal Laundry Instance Truth v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This candidate is stacked on **Atlas Household Claim / Evidence Membrane v1** and also assumes the separate Laundry calibration/Rhythm authority split will be promoted before the old v1 calibration route is used in product.

## Purpose

Turn Laundry from one opaque household configuration blob into the first progressively knowable Personal domain.

The governing chain is:

`World Knowledge → Applicability → Instance → Relations → Evidence → Observed State → Consequence → Clock Arbitration → Action → Actual → Learning`

This tranche owns only the early part:

`World Knowledge → Instance → source-backed household facts`

It does not create consequences, tasks, Rhythms, or Clock placement.

## Why a progressive writer

Reality Discovery already asks the correct first high-information question:

> How does laundry work where you live?

A person should not have to finish a five-question wizard before that answer becomes real domain truth.

Therefore `atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)`:

1. ensures the current Household has a `household.laundry` kernel instance shell;
2. accepts one or more **explicitly supplied** Laundry facts;
3. writes each fact through the current-Household Claim/Evidence membrane;
4. leaves every unmentioned fact unknown;
5. creates no Household Rhythm.

A later Discovery answer can call the same writer with a new `sourceActionId` and a different fact.

## First admitted fact vocabulary

### location

Accepted values:

- `home`
- `shared_machines`
- `laundromat`
- `service`
- `other`

Legacy Discovery value `building` is normalized to `shared_machines` only because those two labels already denote the same explicit answer in the current product question.

### ordinary responsibility

Accepted modes:

- `self`
- `shared`
- `other_household_member`
- `outside_household`
- `service`
- `unresolved`
- `other`

This tranche records only the mode. It does **not** accept an arbitrary Person/member id and does not select an execution carrier. Identity-bearing responsibility comes later through a relationship authority that can prove the referenced person.

### need generation

Accepted values:

- `accumulation_threshold`
- `steady_flow`
- `main_reset`
- `deadline_driven`
- `mixed`
- `other`

This is descriptive causal reality, not recurrence syntax.

### process variants

Optional explicit array. Each item requires a stable `key`. The object may describe the material path for that class, but it may not contain scheduling / Clock authority fields such as cadence, due date, floor class, Principal-required, or capacity blocking.

Example:

```json
{
  "key": "ordinary_clothing",
  "dryingMethod": "hang",
  "readyingMethod": "hang"
}
```

### turnaround relationships

Optional explicit array stored as one source-backed set claim. Absence means unknown. An explicit empty array means the person reported no currently known special turnaround relationship.

This tranche preserves the relationship description only. It does not create a deadline consequence.

## Claim subjects

All facts attach to the actual Household Laundry kernel instance:

```text
subject.domain = household.laundry
subject.kind   = kernel_instance
subject.id     = <household_kernel_instances.id>
```

Claim types:

- `location`
- `ordinary_responsibility`
- `need_generation`
- `process_variant:<variant-key>`
- `turnaround_relationships`

Each fact has its own Evidence, Claim lifecycle, provenance, validity, and correction path.

## Corrections

A new source action may add a previously unknown fact.

It may **not** create a second current accepted value for a singleton fact.

If a current accepted singleton claim already exists, the caller must supply the exact prior claim id in:

```json
{
  "supersedes": {
    "location": "<claim uuid>",
    "ordinary_responsibility": "<claim uuid>",
    "need_generation": "<claim uuid>",
    "turnaround_relationships": "<claim uuid>"
  }
}
```

A process variant may supply its own `supersedesClaimId`.

The wrapper verifies that the prior claim belongs to the same Household Laundry instance and exact claim type before sending the correction through the universal Household Claim/Evidence membrane.

This preserves:
- `just this time` as a later temporary-state concept;
- durable correction as explicit supersession;
- history rather than mutation-away.

## Model suggestions are not household truth

`modelKey` is accepted only as provenance / suggestion context.

The V2 writer does **not** copy model configuration into Household facts. A world model may help Atlas decide what to ask, but selecting or viewing a model does not silently establish location, responsibility, need-generation, or a Rhythm.

## Instance configuration

The `household_kernel_instances` row remains the durable instance root.

Its configuration is not the fact authority for V2. The candidate adds only compatibility markers:

- `factAuthority = household_claim_evidence_v1`
- `calibrationContract = household_laundry_instance_truth_v1`

Existing configuration keys are preserved rather than destructively erased.

## Read projection

`atlas.personal_laundry_kernel_self_api_v2()` wraps the existing V1 Laundry read projection and adds current Household Claim/Evidence facts for the actual Laundry instance.

It keeps any separately-authorized Household Rhythm visible as a distinct projection and explicitly states that Rhythm is not calibration truth.

## Explicit non-authority

This candidate does not:

- create or mutate Household Rhythm;
- assign the Principal merely because the Principal answered;
- select an execution carrier;
- create a Person Life Consequence;
- create a task;
- create capacity pressure;
- place anything on Today;
- turn a process variant into maintenance;
- turn a turnaround relationship into a deadline;
- infer facts from model defaults.

## Example progressive bootstrap

First Discovery answer:

```json
{
  "sourceActionId": "discovery-answer-123",
  "laundryLocation": "home"
}
```

Result: Laundry instance exists + accepted `location` claim.

Later:

```json
{
  "sourceActionId": "discovery-answer-124",
  "responsibility": {"mode": "self"}
}
```

Result: same Laundry instance + accepted `ordinary_responsibility` claim.

Later:

```json
{
  "sourceActionId": "discovery-answer-125",
  "needDriver": "accumulation_threshold",
  "processVariants": [
    {"key":"ordinary_clothing","dryingMethod":"hang","readyingMethod":"hang"},
    {"key":"towels","dryingMethod":"dryer"}
  ],
  "turnaroundRelationships": []
}
```

Still no Rhythm and nothing on Today.

## Validation target

Before promotion, clone validation must prove:

1. unauthenticated caller fails;
2. caller without current active Household fails;
3. active `household.laundry` world kernel is required;
4. at least one explicit fact is required;
5. model selection alone cannot establish a Household fact;
6. legacy `building` location normalizes only to `shared_machines`;
7. invalid responsibility / need-driver values fail;
8. process-variant keys are required and unique within a call;
9. scheduling/Clock authority fields are rejected inside process variants;
10. each accepted fact is written through the Household Claim/Evidence membrane;
11. unmentioned facts remain absent;
12. same sourceActionId + same bytes replay safely;
13. same sourceActionId + changed bytes fails through source custody;
14. a second current singleton value requires exact supersession;
15. supersession is same-instance and exact-claim-type only;
16. old Evidence and superseded Claims remain readable;
17. model configuration is not copied into accepted fact Claims;
18. no Household Rhythm row is created, changed, or deleted;
19. no task, consequence, capacity, or Clock placement is created;
20. the V2 read projection returns facts separately from any existing Rhythm;
21. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
22. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze matching fixture/postcondition bytes, and run Production Schema Clone Validation. Production release remains a later separate authority.
