# Laundry Household Evidence → Person Consequence v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche proves the first downstream causal transition in the Personal Laundry specimen:

`accepted household causal fact + current household observation → person-owned consequence requirement`

It does **not** create a task, select a carrier, evaluate execution readiness, or place anything on the Clock.

## First supported causal rule

This candidate intentionally supports exactly one Laundry rule:

```text
accepted Household fact:
  need_generation.kind = accumulation_threshold

AND current Household observation:
  claimType = present_state
  lifecycleState = observed
  value.state = ready_for_cycle

THEN:
  establish operation_requirement:
    consequenceKind = laundry_cycle_needed
    actionKey = household.laundry:begin_cycle
    carrierState = unresolved
    executionReadiness = not_evaluated
    placementState = unresolved
```

Other known need-generation modes remain valid household truth but are **not executable in this tranche**. Atlas must not guess the causal policy for `steady_flow`, `main_reset`, `deadline_driven`, `mixed`, or `other`.

## Why no second policy acceptance

The existing Person Life Consequence engine was designed around an accepted `consequence_policy` Claim.

Personal Laundry already has a stronger domain-specific source of causal authority: the person explicitly accepted how Laundry need is generated in this household.

For `accumulation_threshold`, the executable policy is a deterministic adapter from that accepted Household fact. Asking the person to separately accept a hidden generic consequence-policy object would duplicate the same decision.

This candidate therefore treats:

`accepted Household need_generation Claim`

as the source authority and derives the exact shared-engine policy from it.

The derivation is code-governed and narrow. Callers cannot supply policy JSON.

## Reusing the existing consequence engine

This candidate does **not** create a Laundry consequence table.

It reuses:

- `atlas.person_life_definitions`
- `atlas.person_life_state_events`
- `atlas.person_life_consequence_instances`
- `atlas.evaluate_life_state_consequence_policies_v1`

The consequence remains person-owned because the Principal is the person whose Clock may eventually need to arbitrate it. The *observation and causal fact* remain Household-scoped.

That gives the intended separation:

```text
Household truth
  ↓
person-owned requirement consequence
  carrier unresolved
  readiness not evaluated
  placement unresolved
```

## New pieces

### 1. Deterministic Laundry policy adapter

`atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(owner, claim)`

It accepts only the current active Principal Household's accepted Laundry `need_generation` Claim.

For `accumulation_threshold` it emits the single explicit shared-engine policy above.

For every other need-generation kind it returns `supported=false` and no policies.

### 2. Laundry consequence definition guard

Any person-life consequence definition whose subject domain is `household.laundry` must:

- source from Claim/Evidence;
- source from the accepted current-Household Laundry `need_generation` Claim;
- carry the exact deterministic policy emitted by the adapter;
- target the same Laundry kernel instance.

This prevents a caller from using the generic person-life definition API to smuggle arbitrary Laundry policy JSON into the engine.

### 3. Definition ensure endpoint

`atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid)`

The caller supplies the accepted `need_generation` Claim id, not a policy.

The endpoint builds the canonical `atlas_life_signal_v1` consequence signal and persists it through the existing person-life definition API.

### 4. Household consequence Evidence snapshot

`atlas.household_consequence_evidence_snapshot_v1(owner, evidence)`

It reconstructs current Household Evidence + Claim under the Principal's active Household custody.

Callers cannot submit snapshot JSON.

### 5. Split consequence-event guards

The existing person-scope consequence event guard is preserved for legacy/person Evidence.

Its trigger is narrowed so it does not run when:

`input_payload.evidenceScopeKind = household`.

A second guard handles Household consequence evaluations and currently permits them only for the governed Laundry definition above.

### 6. Household Laundry evaluator

`atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(definition, payload)`

The caller supplies only:

- `sourceKey`;
- `evidenceId`.

Atlas reconstructs:

- Household snapshot;
- accepted need-generation source Claim;
- deterministic policy set;
- evaluation;
- exact evidence envelope.

Matching consequences are projected into the existing `person_life_consequence_instances` table.

## Why the result is not a task

The shared evaluator already returns:

- `requirementState = established`;
- `carrierState = unresolved` unless policy explicitly provides one;
- `executionReadiness = not_evaluated`;
- `placementState = unresolved`.

This candidate deliberately supplies **no carrierRef** and performs no downstream placement.

Therefore a matching Laundry observation proves only:

> There is now a Laundry-cycle requirement.

It does not prove:

> You must do Laundry now.

## Observation shape

The first executable state is intentionally explicit:

```json
{
  "claimType": "present_state",
  "lifecycleState": "observed",
  "value": {
    "state": "ready_for_cycle"
  }
}
```

Extra source-backed detail is allowed, for example:

```json
{
  "state": "ready_for_cycle",
  "pressure": "backlog"
}
```

The shared evaluator uses JSON containment, so the explicit rule can match the required state without discarding richer observation detail.

A weaker observation such as:

```json
{"state":"accumulating"}
```

does not open the consequence in V1.

## Correction behavior

If the accepted `need_generation` Claim is later superseded, any old definition sourced from it becomes non-executable because the definition/evaluation guards require the source Claim to remain current accepted authority.

This tranche does not silently rewrite the old definition. A later cleanup tranche may retire obsolete definitions explicitly.

## Production state

At the time this candidate was written, production contained:

- 0 `consequence_policy` Claims;
- 0 person-life consequence definitions;
- 0 consequence evaluation events;
- 0 person-life consequence instances.

So this can be validated as the first real Personal consequence specimen without legacy-row migration.

## Validation target

Before promotion, clone validation must prove:

1. only an accepted current-Household Laundry `need_generation` Claim can authorize the definition;
2. unsupported need-generation kinds produce no executable policy;
3. caller cannot supply Laundry policy JSON;
4. the Laundry definition packet policy exactly equals the deterministic adapter output;
5. a Household Evidence snapshot cannot read another Household;
6. the snapshot requires current same-scope Claim authority;
7. the original person-scope consequence guard still governs ordinary/person evaluations;
8. Household evidence evaluations route only through the new Household guard;
9. Household evaluation is rejected for non-Laundry consequence definitions;
10. the observation Claim must match `present_state / observed / ready_for_cycle`;
11. `accumulating` alone opens zero consequences;
12. a matching observation opens exactly one `laundry_cycle_needed` requirement;
13. the resulting consequence has carrier unresolved;
14. execution readiness remains `not_evaluated`;
15. placement remains `unresolved`;
16. no task row is created;
17. no Household Rhythm is created or changed;
18. no Clock placement is created;
19. caller cannot supply snapshot or policies;
20. event persistence guard recomputes snapshot, policy, and evaluation independently;
21. same sourceKey replay is idempotent;
22. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
23. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze fixture/postcondition bytes, and run Production Schema Clone Validation before merge. Production release remains a separate authority.
