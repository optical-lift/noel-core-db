# V47 — Development Scoring Operationalization

**Date frozen:** 2026-09-08  
**Status:** implementation details frozen before V47 continuation outcomes  
**Parent:** `docs/mark-continuous-regime-grammar-transport-v47.md`

This note resolves execution details that were implicit in the V47 preregistration. It does not change the hypothesis, holdouts, architectures, thresholds, seeds, or custody rules.

## Common training set

All development models M0–M5 are trained from the same development-training positions with valid next-four-state targets, except where a model cannot consume a motif because no supported motif is assigned.

For the primary motif-transport comparison M1/M3/M4/M5, an example must have a supported motif assignment. For every one of the 113 already-frozen `(motif, geometric-region)` holdouts, all matching development-training positions are excluded from every trainable model's fitting data and from M0 frequency estimation used in the transport table.

The held-out positions are used only for final development transport scoring.

M2 may train on all non-held-out positions with a valid next-four target, including positions lacking a supported motif, because its input is q alone. Its evaluation for the transport endpoint is on the identical held-out motif-region positions as the other models.

## Development validation / early stopping

The inherited 22 development-validation blocks are never used for parameter gradients.

Each validation position is assigned to the nearest frozen Hellinger-region centroid. Any validation occurrence whose motif identity and assigned region match one of the 113 frozen motif-region holdouts is excluded from early-stopping loss. All other valid validation positions are eligible for early stopping.

The geometric holdout examples themselves therefore never influence epoch choice.

## Exact model parameterizations

All logits are 65-dimensional.

### M1

- motif embedding dimension 16;
- logits = learned global bias + linear projection of motif embedding.

### M2

- `zq = tanh(Linear(12,8)(q))`;
- logits = learned global bias + `Linear(8,65)(zq)`.

### M3

- motif embedding dimension 16;
- `zq` as M2;
- logits = learned global bias + `Linear(16,65)(eM)` + `Linear(8,65)(zq)`.

### M4

M4 contains the same M3 main effects plus a state-specific shared rank-8 bilinear interaction.

For output state `s`:

```text
interaction_s = sum_r ((A_s[r] dot eM) * (B_s[r] dot zq)), r=1..8
```

with:

- `A`: shape `(65,8,16)`;
- `B`: shape `(65,8,8)`.

No motif-region, motif-hard-regime, or exact pair lookup parameter exists.

### M5

- M4 unchanged;
- `zv = tanh(Linear(12,8)(v))`, where `v_t=q_t-q_(t-1)` and block-first velocity is zero;
- additive velocity term `Linear(8,65)(zv)`;
- separate state-specific rank-8 motif × velocity interaction using tensors `(65,8,16)` and `(65,8,8)`.

## Loss

Primary training and early-stopping loss is mean cross-entropy against the frozen next-four soft target. If future states are `r1..r4`, the target puts weight 1/4 on each occurrence, including repeated future states.

## Optimization

As preregistered:

- AdamW;
- learning rate 0.001;
- weight decay 0.0001;
- batch size 2048;
- max epochs 200;
- patience 10;
- seeds 47, 470, 4700;
- no scheduler or dropout.

Early stopping uses the lowest development-validation soft-target CE. An epoch counts as improved only when CE is strictly lower than the previous best by at least `1e-7`; otherwise patience increments. The best validation state dict is restored. Final probabilities are the arithmetic mean of the three seed probability vectors.

## M0

M0 is the 65-state frequency distribution of the four-right soft targets over the common non-held-out development-training examples, with Jeffreys smoothing `+0.5` per state before normalization.

## Aggregate comparator B

On the frozen held-out development positions, compute aggregate CE for M1, M2, and M3. `B` is the single model among M1/M2/M3 with lowest aggregate CE. The same selected comparator is then used for:

- aggregate `DeltaCE_transport`;
- relative reduction;
- block bootstrap;
- holdout-level sign comparison;
- q-shift nulls.

No observation-by-observation comparator switching is allowed.

## Block bootstrap

Use 10,000 deterministic intact-block bootstrap replicates with RNG seed `470047`. Sample evaluation blocks with replacement and include all held-out examples belonging to each sampled block. Statistic is `CE(B)-CE(M4)`. The frozen 99% interval is the percentile interval `[0.005,0.995]`.

## Holdout-level wins

For each of the 113 frozen motif-region holdouts, average soft-target CE over all of its development held-out occurrences. A holdout favors M4 exactly when its mean M4 CE is strictly below its mean B CE.

## q-shift null

Use the preregistered 1,000 within-block circular q shifts, RNG seed `47004700`.

For each null and each development-training block containing held-out evaluation positions:

- draw one integer offset uniformly from `1..T-1`;
- circularly shift the complete block sequence of q vectors by that offset;
- recompute M4 predictions at the fixed held-out evaluation positions using the shifted q but the actual motif identity;
- keep the evaluation positions and continuation targets unchanged;
- do not refit model parameters.

The null statistic is `CE(B)-CE(M4_shifted)`. The real assignment beats the 99th percentile only when real `DeltaCE_transport` is strictly greater than the empirical 0.99 quantile of the 1,000 null statistics.

## Velocity gate

M5 is evaluated on the identical held-out positions. Its block bootstrap and holdout-level comparisons use the same 10,000 replicate index sets as the primary M4-vs-B test where possible.

## Geometry integrity assertion

The scoring implementation must deterministically reconstruct the V47 geometry and assert that:

- primary supported motifs = 126;
- eligible geometric holdouts = 113;
- every selected holdout digest/identity/region equals the frozen target-blind artifact.

If the assertion fails, continuation scoring must stop.

## Custody

This development scoring stage may use only the 110 development blocks. Internal replication and the original outer holdout remain sealed.
