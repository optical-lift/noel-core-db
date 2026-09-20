# Principal Consequence Clock Characterization v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This candidate establishes the missing boundary between:

`real person-owned consequence`

and:

`admitted Principal Clock candidate`.

It does not change the Principal Clock candidate inventory yet.

## Why this is required

The live Principal Clock arbitration treats a candidate with no timing bounds as an open current window. That means an incompletely characterized source can accidentally receive `right_to_floor_now = true`.

Therefore a real consequence may exist while remaining completely outside Clock arbitration.

This candidate makes that boundary explicit.

## Storage choice

No new Clock-characterization table is introduced.

Clock characterization is stored through the existing universal person Claim/Evidence envelope as:

```text
scope.kind     = person
subject.domain = principal.clock
subject.kind   = person_life_consequence
subject.id     = <person_life_consequence_instances.id>
claimType      = clock_characterization
lifecycle      = accepted
```

This preserves:

- source Evidence;
- correction/supersession;
- provenance;
- validity/lifecycle;
- current-vs-historical truth.

The candidate adds a specialized membrane so there is only one current accepted characterization per consequence.

## Characterization fields

A characterization may be partial.

Supported V1 fields:

- `expectedMinutes`;
- `protectionLevel`;
- `floorClass`;
- `interruptibility`;
- `delegable`;
- `ownerRequired`;
- `timing`:
  - `windowStart`;
  - `windowEnd`;
  - `fixedStart`;
  - `mustBeginBy`;
  - `mustFinishBy`;
- `consequenceOfDelay`;
- `reasonForFloor`.

No unsupported field is silently retained.

## Complete characterization

A characterization is complete only when all of the following are known:

- positive `expectedMinutes`;
- valid `protectionLevel`;
- floor class 1–7;
- valid `interruptibility`;
- boolean `delegable`;
- boolean `ownerRequired`;
- non-empty `consequenceOfDelay`;
- non-empty `reasonForFloor`;
- at least one explicit timing boundary.

The timing requirement is crucial. Missing timing may never be interpreted as “open now.”

## Clock admission is stricter than characterization

Even a complete characterization does not admit the consequence.

The consequence must also have:

- `requirement_state = established`;
- `carrier_state = established`;
- `carrier_ref = principal:<current principal id>`;
- `execution_readiness = ready`.

The admission function therefore returns blockers such as:

- `requirement_not_established`;
- `principal_carrier_required`;
- `execution_readiness_required`;
- `clock_characterization_required`;
- `clock_characterization_incomplete`.

## Important separation

This candidate does not resolve carrier or execution readiness.

Those remain separate authorities.

It also does not:

- mutate `principal_clock_candidates_v1`;
- create a task;
- create a Household Rhythm;
- create an Owner Obligation;
- create a Clock placement;
- assign a floor class by default;
- invent duration;
- infer urgency from the mere existence of a requirement.

## Why Claim/Evidence instead of a settings blob

Clock characterization may come from:

- explicit human input;
- governed domain rules;
- measured historical evidence;
- later learning proposals.

Those sources need provenance and correction semantics. The universal Claim/Evidence envelope already supplies them.

## Validation target

Before promotion, clone validation must prove:

1. only the consequence owner can characterize it;
2. the caller cannot choose another Principal;
3. unsupported characterization fields fail;
4. time values require explicit offsets;
5. invalid time order fails;
6. partial characterization is preserved but reports incomplete;
7. a second current accepted characterization requires explicit supersession;
8. old characterization history remains readable after correction;
9. a complete characterization alone does not imply Clock admission;
10. unresolved carrier blocks admission;
11. non-Principal carrier blocks admission;
12. non-ready execution blocks admission;
13. missing timing blocks completeness;
14. no Clock candidate view is changed;
15. no task / Rhythm / Owner Obligation is created;
16. authenticated RPC registry drift remains clean;
17. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI and run Production Schema Clone Validation before merge.
