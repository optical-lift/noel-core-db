# Mark State Recovery Calibration v1

## Purpose

This layer connects Noel's physical `mark` custody to the existing `instrument` experiment system without allowing analytical predictions to overwrite physical observations.

The core question is:

> When one physical distinction is hidden, does non-target structure recover it above baseline under leakage-safe holdouts?

The State Recovery contract is not a claim that an ancient writing system contains modern error-correcting code. It is an instrument for measuring whether physical state is redundantly constrained by surrounding structure.

## Authority boundary

```text
mark.*
  owns observed physical source truth
       ↓
instrument.state_recovery_*
  owns masks, predictions, exclusions, reveals, metrics
       ↓
draft/research layers
  may later own functional or historical interpretation
```

A predicted component does not become observed source evidence.

A damaged source remains damaged after a successful prediction.

## Trial lifecycle

```text
planned
  ↓
masked
  ↓
predicted_frozen
  ↓
revealed
  ↓
scored
```

A trial may instead become `invalidated` with a required reason.

At `prediction_frozen_at`, all information that could affect the prediction is fixed:

- target component/instance/zone,
- corpus snapshot,
- masked feature family and mask specification,
- benchmark tier,
- exclusion policy,
- explicit exclusion rows,
- training query digest and evidence set,
- predicted state and confidence,
- prediction support,
- leakage audit.

After reveal, observed state and correctness are immutable.

## Leakage exclusions

Every excluded evidence source is represented explicitly in `instrument.state_recovery_trial_exclusions`.

Supported reasons include:

- same physical occurrence,
- same row,
- overlapping routine,
- exact duplicate capture,
- viewer duplicate capture,
- derivative capture,
- same physical capture,
- manually declared leakage control.

Exclusions cannot be changed after prediction freeze.

## Benchmark tiers

```text
0  carrier-only baseline
1  immediate local context
2  wider local context
3  cross-row repeated routine
4  cross-surface repeated routine
5  future cross-witness/cross-corpus routine
```

The tier number is not a semantic confidence score. It is a holdout/context contract.

## Metrics

Runs may record:

- accuracy,
- balanced accuracy,
- log loss,
- entropy before context,
- entropy after context,
- information gain in bits,
- state distribution,
- leakage summary.

A frozen metric row is immutable.

## Strict-blind features

The next registration migration permits only physical/mechanical mark features at prior-load levels 0-1:

- capture byte/pixel identity,
- source coordinates,
- physical channel,
- component geometry,
- damage state,
- junction topology,
- anonymous sequence position,
- capture duplicate/derivative identity.

Explicitly prohibited from strict-blind discovery:

- Unicode/conventional sign identity,
- lexical or phonetic reading,
- translation,
- cultural/script identity as discovery evidence,
- scholarly interpretation.

## Engines

`mark_sequence_miner_v0`

Discovers recurrence and repeated anonymous procedures from permitted physical topology and sequence features.

`mark_state_recovery_v0`

Runs held-out prediction of masked physical states under explicit exclusion rules.

Both are experimental and capped at maximum prior-load level 1.

## Calibration before archaeology

No ancient corpus should be the first place these engines are tested.

The calibration tranche defines five synthetic controls:

1. **Redundant positive control** — context deliberately determines the target state. The engine should recover it above carrier/global baselines.
2. **Random negative control** — target state is independent of context. The engine must not manufacture recoverability.
3. **Row-confounded control** — row identity predicts state, but cross-row routine context does not. Same-row leakage must be detectable.
4. **Duplicate-leakage control** — copied observations can make prediction look perfect until duplicate evidence is excluded.
5. **Damage/uncertainty control** — source state includes known damage/uncertainty while contextual recovery remains partly possible. Predictions must not alter source truth.

The engine is not ready for ancient marks until it both finds the intended positive signal and correctly fails or abstains on the controls.

## Release order

The database release lane validates one candidate migration before it exists on canonical `main`.

Therefore these contracts are released sequentially:

1. physical `mark` kernel,
2. State Recovery trial contract,
3. strict-blind feature + engine registrations,
4. synthetic calibration corpus definitions/fixtures,
5. engine implementation and frozen calibration run,
6. governed private image byte storage,
7. first ancient mark corpus.

This sequencing is intentional: every later migration depends only on already released production authority.
