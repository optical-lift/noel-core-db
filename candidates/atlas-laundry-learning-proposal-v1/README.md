# Laundry Learning Proposal v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche proves the final architectural movement in the first Personal Laundry loop:

`Actuals → cautious learning proposal`

It does **not** create a Household Rhythm.

## First learner

V1 recognizes exactly one pattern:

> The last four distinct Laundry cycle-start dates occurred on the same local weekday, and every adjacent gap was 6–8 days.

The source actual is:

`process_actual.transition = entered_washing`.

Four distinct dates are required.

This is intentionally conservative. Three weeks are not enough. Similar-looking activity that does not satisfy the exact deterministic rule produces no proposal.

## Output states

The learner returns one of:

- `insufficient_evidence`
- `pattern_not_stable`
- `already_proposed`
- `proposed`

The first two states create no records.

## Proposal representation

A detected pattern is persisted in the existing Household Claim/Evidence graph:

```text
scope          = household
subject.domain = household.laundry
subject.kind   = kernel_instance
subject.id     = <Laundry instance>

claimType      = rhythm_pattern_proposal
lifecycle      = proposed
authority      = derived_pattern_proposal
sourceKind     = household_learning_engine
```

The proposal value says only what was actually learned:

- pattern kind = weekly;
- local weekday;
- support count;
- basis transition = entered_washing;
- observed gap range.

It is not an accepted Rhythm.

## Evidence spine

The proposal's primary Evidence is a derived pattern-analysis record.

Every physical Laundry actual used by the detector is also linked to the proposal with `relation_kind = supports`.

That preserves the distinction:

```text
actual evidence
  ↓ supports
derived pattern analysis
  ↓ supports
proposed pattern Claim
```

No individual actual falsely claims that a weekly Rhythm exists.

## Same proposal, more support

If the same weekly weekday proposal is already open as `proposed`, the learner does not create another user-facing proposal.

It may append additional supporting actual Evidence links to the existing proposal and returns `already_proposed`.

## Rejected / accepted proposals

This learner does not adjudicate its own proposal.

It does not:

- accept the proposal;
- reject it;
- convert it into Household Rhythm;
- change Clock Characterization;
- alter responsibility;
- create a task.

Adjudication and any later Rhythm materialization require separate authority.

## Timezone

Weekday detection uses the active Principal's authoritative timezone.

An actual at 00:30 UTC must not accidentally become the wrong household weekday.

## Validation target

Before promotion, clone validation must prove:

1. fewer than four distinct cycle-start dates creates no proposal;
2. multiple actuals on one local date count as one date;
3. different weekdays create no proposal;
4. any adjacent gap under 6 or over 8 days creates no proposal;
5. four qualifying dates create one proposal;
6. weekday calculation uses Principal authoritative timezone;
7. proposal lifecycle is `proposed`;
8. proposal authority is `derived_pattern_proposal`, never Principal-authored authority;
9. proposal source kind is `household_learning_engine`;
10. proposal primary Evidence is derived analysis, not one physical actual;
11. all supporting actual Evidence rows are linked with `supports`;
12. supporting evidence cannot cross Household scope;
13. replay over the same basis is idempotent;
14. same already-open proposal is not duplicated;
15. additional qualifying actual evidence may strengthen the existing proposal without changing its value;
16. learner creates no Household Rhythm;
17. learner creates no task;
18. learner creates no consequence;
19. learner creates no Clock candidate or placement;
20. accepted household truth is unchanged;
21. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
22. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze fixtures/postconditions, and run Production Schema Clone Validation before merge.
