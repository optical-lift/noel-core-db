# V47 — Continuous Regime Grammar Transport

**Date frozen:** 2026-09-08  
**Status:** HYPOTHESIS / PREREGISTRATION — frozen before V47 continuation scoring  
**Repository:** `optical-lift/noel-core-db`  
**Parent lineage:** V41–V46 anonymous 65-state structural experiments  
**Semantic / Masoretic information:** prohibited

## 1. Motivation from V46

V46 selected a 12-regime explicit-duration hidden semi-Markov representation on development data, but its decisive hard-cell recombination test was `NOT EVALUABLE` because no motif satisfied the frozen requirement of >=50 high-confidence occurrences in at least three discrete regimes.

V47 does **not** loosen V46's `0.70` threshold or reinterpret V46. V46 remains `NOT EVALUABLE` under its own rules.

V47 tests a different hypothesis: the hard regime label itself may be the wrong object. The relevant structural condition may be represented by the full soft posterior over the 12 latent regimes.

## 2. Working hypothesis

Let

```text
q_t = P(Z_t = 1..12 | complete observed block)
```

be the aligned three-seed consensus posterior from V46's already-selected K=12 explicit-duration HSMM.

The V47 hypothesis is:

> A short ordered motif has a reusable structural effect that changes smoothly with the continuous latent structural state `q_t`; motif behavior can therefore be transported into held-out regions of posterior space even when no single discrete regime label has enough cross-regime support.

A stronger trajectory prediction is:

> Continuation behavior depends not only on structural location `q_t`, but also on the direction of motion through that latent field.

Define the one-step posterior velocity

```text
v_t = q_t - q_(t-1)
```

within block.

The conceptual architecture is:

```text
continuous latent structural field q_t
          +
trajectory v_t through that field
          ↓
modulates
          ↓
short ordered local motif M_t
          ↓
future anonymous structural state distribution
```

## 3. Structural universe and custody

V47 inherits without modification:

- the 65 anonymous structural states;
- the V46 development / internal-replication / outer-holdout block partitions;
- V46's selected K=12 explicit-duration HSMM parameters for seeds `46`, `460`, and `4600`;
- V46's seed-label alignment convention: seed46 is reference and other seeds are Hungarian-matched by Jensen–Shannon divergence of the 65-state emission profiles;
- tokenwise consensus posterior = arithmetic mean of the three aligned posterior vectors.

No state, regime, or motif may be manually renamed or regrouped after outcomes are inspected.

V47 initially uses only the 110 V46 development blocks. The 50 internal-replication blocks and the original outer holdout remain sealed until all V47 development choices and results are frozen.

## 4. Development train / validation split

V47 inherits V46's deterministic development sub-split:

```text
bucket = stable_bucket(book, block_index, 460046, 10)
```

- development-training: bucket >= 2;
- development-validation: bucket < 2.

All posterior-space geometry, motif support, holdout construction, and model fitting are determined from development-training only unless explicitly identified as development-validation scoring.

Development-validation outcomes are not used to alter the architecture after scoring begins.

## 5. Motif representation

V47 inherits V46's variable-order motif rule.

Candidate suffix lengths:

```text
{2,3,4,6}
```

For each development-training occurrence, use the longest suffix in order `6,4,3,2` whose exact development-training support is at least 100. If the length-2 suffix has support <100, that occurrence is not eligible for motif-transport analysis, though it remains eligible for regime-only and frequency baselines.

For the primary geometric-transport analysis, a motif identity must have at least **300 assigned development-training occurrences** under this longest-supported-suffix rule.

## 6. Continuous regime input

The primary models consume the raw 12-dimensional consensus posterior vector `q_t` directly.

No hard posterior threshold and no argmax regime label is supplied to the predictive model.

The vector is clipped only for numerical safety to `[1e-8, 1]` and renormalized to sum to 1.

## 7. Posterior-space geometry for holdout construction only

Discrete regions are used **only to construct geometric holes in training data**. They are not model inputs and are not interpreted as regimes.

Geometry is defined on the square-root transform

```text
u_t = sqrt(q_t)
```

so ordinary Euclidean distance corresponds monotonically to Hellinger distance on probability vectors.

Fit deterministic K-means with:

- `R = 12` geometric regions;
- input: development-training `u_t` for occurrences having an assigned motif with support >=300;
- `random_state = 47`;
- `n_init = 20`;
- standard Lloyd algorithm;
- no continuation target is used.

The resulting cluster labels are **geometric holdout regions only**.

## 8. Motif-specific geometric holdout

For each motif M with >=300 assigned development-training occurrences, identify geometric regions r satisfying all of:

- >=30 occurrences of M in r;
- >=300 occurrences of M outside r;
- outside-r occurrences of M span at least 3 other geometric regions;
- M-in-r occurs in at least 3 intact development-training blocks.

If M has at least one eligible region, choose exactly one held-out region for M using the minimum SHA-256 digest of:

```text
47:<motif_length>:<comma-separated-state-ids>:<region_id>
```

among its eligible regions.

For every selected `(M,r)` pair:

- remove all development-training occurrences of motif M whose `q_t` lies in region r from the grammar learner;
- retain M in every other region;
- retain every other motif in region r;
- retain q-space geometry itself, because geometry is target-blind and fixed before grammar fitting.

This creates the intended counterfactual:

```text
seen motif M elsewhere in q-space
+
seen posterior region r through other motifs
+
unseen M × posterior-region combination for continuation learning
```

The model still receives raw continuous `q_t`, never region ID.

If fewer than 20 motif-specific geometric holdouts exist, the decisive geometric-transport test is reported `NOT EVALUABLE`; thresholds are not weakened.

If more than 200 holdouts exist, retain the first 200 in ascending SHA-256 order using the string above.

## 9. Prediction target

At each eligible position t, define

```text
R_t = x[t+1:t+4]
```

as the next-four-state soft target: each of the four future state identities contributes weight 1/4 to the 65-state target distribution.

Primary loss is cross-entropy against that 65-state soft target.

Secondary targets:

- next-state categorical CE;
- next-2 sequential CE;
- next-4 sequential CE;
- outgoing entropy error.

Secondary endpoints cannot rescue failure of the primary endpoint.

## 10. Model family

All trainable models use only anonymous structural inputs.

### M0 — Global frequency

```text
P(R)
```

Smoothed development-training frequency baseline.

### M1 — Motif only

```text
P(R | M)
```

Trainable motif embedding with output softmax.

### M2 — Continuous regime field only

```text
P(R | q)
```

Architecture:

```text
q(12) -> Linear(12,8) -> tanh -> Linear(8,65)
```

### M3 — Additive motif + continuous regime

```text
logit P(s|M,q) = b_s + u_s(M) + g_s(q)
```

with motif embedding dimension 16 and q projection dimension 8.

### M4 — Continuous motif × regime interaction — PRIMARY

```text
logit P(s|M,q)
 = b_s
 + u_s(M)
 + g_s(q)
 + <A_s e_M, B_s z_q>
```

where:

- motif embedding `e_M`: dimension 16;
- continuous regime projection `z_q`: dimension 8 from `tanh(W_q q + b_q)`;
- shared bilinear interaction rank: 8;
- no `(M, region)` or `(M, hard-regime)` lookup parameters exist.

### M5 — Continuous position + trajectory interaction

M5 extends M4 with one-step posterior velocity:

```text
v_t = q_t - q_(t-1)
```

within block.

Velocity projection dimension: 8.

M5 adds both:

- an additive shared velocity term;
- a rank-8 shared motif × velocity interaction.

No future q values are used.

## 11. Frozen optimization

For M1–M5:

- optimizer: AdamW;
- learning rate: 0.001;
- weight decay: 0.0001;
- batch size: 2048;
- maximum epochs: 200;
- early stopping patience: 10;
- early stopping metric: development-validation CE on examples **outside all selected motif-specific geometric holdouts**;
- seeds: `47`, `470`, `4700`;
- final prediction: arithmetic mean of the three seed probability vectors;
- no scheduler;
- no dropout;
- no architecture sweep.

The held-out geometric examples themselves are never used for early stopping.

## 12. Primary endpoint — continuous geometric transport

Evaluate only the deliberately withheld development-training occurrences belonging to selected `(M,r)` geometric holdouts.

For each occurrence, score M0–M4 on the next-four-state soft target.

Define the strongest noninteraction comparator:

```text
B = min(CE(M1), CE(M2), CE(M3))
```

where the minimum is computed at the aggregate level, not separately per observation.

Primary improvement:

```text
DeltaCE_transport = CE(B) - CE(M4)
```

Positive values favor motif-specific continuous regime modulation that transports into unseen posterior-space regions.

### Decisive development transport gate

V47's primary development result is positive only if all are true:

1. at least 20 motif-specific geometric holdouts are eligible;
2. aggregate `DeltaCE_transport > 0`;
3. M4 gives at least **0.5% relative CE reduction** versus B;
4. 99% intact-block bootstrap CI for `DeltaCE_transport` excludes zero;
5. at least 65% of motif-specific holdouts individually favor M4 over B;
6. real q assignments beat the 99th percentile of the frozen q-permutation null in Section 13.

The 0.5% threshold is fixed before V47 outcome scoring and reflects the stronger continuous-transport prediction without importing V46's categorical 1% gate.

## 13. Continuous-regime null

Use 1,000 deterministic nulls, seed `47004700`.

Within each development-training block, circularly shift the entire sequence of q vectors by a random nonzero offset drawn deterministically from the null seed, preserving:

- each block's q-vector distribution;
- local motif sequence;
- continuation targets;
- temporal smoothness of q within the shifted sequence;
- marginal geometry of posterior space.

The shift breaks alignment between motif/continuation position and the latent structural field while avoiding an IID shuffle of q.

For each null, evaluate the already-fit M4 functional form with shifted q inputs; do not retrain model parameters for each null.

Primary null statistic: aggregate `DeltaCE_transport` relative to the same frozen B comparator.

## 14. Trajectory gate

On the identical geometric holdout examples, compare M5 against M4.

Define:

```text
DeltaCE_velocity = CE(M4) - CE(M5)
```

Evidence that direction through latent space matters requires all of:

1. `DeltaCE_velocity > 0`;
2. relative CE reduction >=0.25%;
3. 99% intact-block bootstrap CI excludes zero;
4. at least 60% of motif-specific holdouts favor M5 over M4.

Failure of the trajectory gate does not negate a positive M4 transport result.

## 15. Posterior geometry diagnostics — frozen, non-rescuing

Before opening replication, report target-blind geometry of development-training q:

- distribution of maximum posterior probability;
- posterior entropy distribution;
- PCA eigenvalue spectrum of q;
- cumulative variance for dimensions 1..11;
- participation-ratio effective dimension;
- mean and quantiles of Hellinger step distance `||sqrt(q_t)-sqrt(q_(t-1))||`;
- mean and quantiles of Euclidean velocity `||v_t||`;
- 12 geometric region sizes;
- motif region occupancy counts.

These diagnostics describe the latent field but cannot alter the frozen predictive architecture or rescue a failed primary gate.

## 16. Counterfactual surface diagnostics

For each selected motif, evaluate M4 over the 12 target-blind region centroids in raw q space while holding M fixed.

Report:

- variation in predicted continuation entropy across q-space;
- Jensen–Shannon divergence between centroid-conditioned continuation distributions;
- whether the observed held-out centroid ranks unusually well for the actual held-out continuations.

These are supporting diagnostics only.

## 17. Center-redundancy audit

After M4 is fit, add a shared regularized current-center-state feature y without any `(M,q,y)` lookup table.

Compare:

```text
P(R | M,q)
```

against

```text
P(R | M,q,y)
```

on the same geometric holdouts.

This tests whether V44's center redundancy persists once the hard regime representation is replaced by the continuous field.

It cannot rescue the primary transport gate.

## 18. Internal replication

Only after the complete V47 development result and all development choices are frozen in GitHub may the 50-block internal-replication set be opened.

For replication:

- the K=12 HSMM and seed alignment remain frozen;
- q-space K-means centroids remain frozen from development-training and replication q vectors are assigned to the nearest frozen centroid in Hellinger geometry;
- selected motif identities and their designated held-out regions remain frozen;
- model architecture and optimization remain frozen;
- predictive models are trained only on development-training and scored directly on replication examples matching the selected motif-region holdouts;
- no replication retraining or threshold change is allowed.

The same primary and trajectory criteria are applied, except that the evaluability requirement is >=20 selected motif holdouts represented by at least one replication example and >=500 total replication evaluation occurrences.

## 19. Original outer holdout

The original outer holdout remains sealed until the internal-replication result is frozen in GitHub.

Only if internal replication is evaluable is the same frozen pipeline applied to the original outer holdout. The primary claim requires the direction of `DeltaCE_transport` to reproduce and its 99% block-bootstrap CI to exclude zero. The original development 0.5% magnitude threshold is also retained.

## 20. Interpretation ladder

### A. Fewer than 20 geometric motif holdouts

Conclusion: V47 primary transport test is `NOT EVALUABLE`; do not loosen region/support thresholds.

### B. M4 does not beat M1/M2/M3 on geometric holdouts

Conclusion: soft latent location does not provide evidence for motif-specific transport beyond additive local and regime information.

### C. M4 wins development but not the q-shift null

Conclusion: flexible continuous conditioning helps, but the actual temporal alignment of q is not specifically supported.

### D. M4 passes development but not internal replication

Conclusion: continuous transport does not generalize beyond development lineage.

### E. M4 confirms in internal replication and outer holdout

Permitted claim:

> Short anonymous structural motifs exhibit reusable continuation behavior that varies systematically with a continuous latent structural field. The same motif can be transported into posterior-space regions withheld from its training occurrences by learning how the latent field modulates other motifs.

### F. M5 additionally confirms

Additional permitted claim:

> Continuation behavior depends on direction of motion through the latent structural field in addition to position within it.

Not permitted from V47 alone:

- semantic meaning of latent coordinates;
- claim that K=12 is the unique latent representation;
- intentional authorship;
- theological interpretation;
- causal mechanism outside the measured anonymous sequence.

## 21. Forward trigger

Only if continuous transport confirms on the original outer holdout should the next experiment replace the 12-dimensional posterior coordinates with an explicitly learned lower-dimensional manifold and test whether motif transformations obey a reusable differential / algebraic structure along that manifold.

## 22. Frozen expectation

Before continuation scoring, the active expectation is:

1. hard K=12 regime labels are a coarse discretization of a softer structural field;
2. sufficiently supported motifs will occupy multiple posterior-space regions even though they did not occupy three high-confidence hard regimes in V46;
3. M4 will outperform motif-only, q-only, and additive motif+q models on deliberately withheld motif-region combinations;
4. the actual q alignment will beat blockwise circular-shift nulls;
5. M5 will provide additional predictive information for at least part of the corpus, indicating that direction through latent state-space matters;
6. the q posterior cloud will have effective dimension materially below the full 11-dimensional simplex.
