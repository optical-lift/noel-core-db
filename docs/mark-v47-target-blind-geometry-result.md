# V47 — Target-Blind Posterior Geometry Result

**Date:** 2026-09-08  
**Parent experiment:** V47 — Continuous Regime Grammar Transport  
**Status:** target-blind geometry complete; continuation scoring not yet opened

## Frozen preregistration

V47 was frozen before any V47 continuation scoring at:

- `docs/mark-continuous-regime-grammar-transport-v47.md`
- commit `4ea41c749ff24ee6ad884146a43149dacf81d1f6`

Target-blind geometry implementation:

- `validation/v47-geometry-holdouts.py`
- exact accelerated execution wrapper `validation/v47-geometry-holdouts-fast.py`

The accelerated wrapper calls the already-validated V46 exact explicit-duration HSMM posterior kernel and passed deterministic equivalence checks before development geometry was computed.

## Custody

Only the 110 V46 development blocks were used.

The development-training subset contains **129,434 tokens** under the frozen deterministic development sub-split.

No V47 continuation target, M0–M5 predictive score, internal-replication result, or original outer-holdout result was opened in this geometry stage.

## Motif support and geometry coverage

Under V47's inherited longest-supported-suffix motif representation:

- primary supported motif identities (>=300 assigned development-training occurrences): **126**;
- occurrences of those motifs entering the posterior-space geometry: **57,228**.

The frozen 12-region Hellinger-space K-means produced region sizes:

| region | occurrences |
| ---: | ---: |
| 0 | 5,272 |
| 1 | 5,289 |
| 2 | 6,073 |
| 3 | 4,156 |
| 4 | 6,996 |
| 5 | 5,537 |
| 6 | 2,807 |
| 7 | 7,055 |
| 8 | 2,228 |
| 9 | 3,545 |
| 10 | 4,302 |
| 11 | 3,968 |

## Decisive evaluability result

Applying the frozen V47 motif-specific geometric-hole criteria produced:

- **113 eligible motif-specific geometric holdouts**.

V47 therefore passes its preregistered minimum of 20 holdouts and its primary continuous-transport test is **EVALUABLE**.

This is an eligibility result only. It is not evidence yet that continuous motif transport predicts continuation outcomes.

## Posterior geometry diagnostics

Across development-training tokens:

- mean maximum consensus posterior: **0.4889153**;
- median maximum consensus posterior: **0.4591798**;
- 90th percentile maximum consensus posterior: **0.7284478**;
- mean posterior entropy: **1.3423878 nats**;
- median posterior entropy: **1.3856050 nats**.

Thus most development-training positions do not have a single dominant posterior component above V46's former hard `0.70` threshold. This is a target-blind descriptive fact and does not itself establish the V47 predictive hypothesis.

### PCA / effective dimension

Variance fractions for the 11 nontrivial simplex dimensions:

1. 0.1837568
2. 0.1484923
3. 0.1389718
4. 0.1124877
5. 0.0841138
6. 0.0762054
7. 0.0715556
8. 0.0617666
9. 0.0517848
10. 0.0407910
11. 0.0300741

Cumulative variance:

- 3 dimensions: **0.4712210**;
- 4 dimensions: **0.5837087**;
- 6 dimensions: **0.7440279**;
- 8 dimensions: **0.8773502**;
- 9 dimensions: **0.9291349**.

Participation-ratio effective dimension: **8.70694**.

The posterior cloud therefore does not collapse to a 2–4 dimensional manifold under this simple linear diagnostic; it is lower than the full 11-dimensional simplex but remains substantially multidimensional.

## Local movement diagnostics

Hellinger step distance between adjacent consensus posterior vectors:

- mean: **0.0349154**;
- median: **0.0279400**;
- 90th percentile: **0.0651926**.

Euclidean posterior velocity norm:

- mean: **0.0248255**;
- median: **0.0175408**;
- 90th percentile: **0.0515803**.

These values describe a relatively smooth token-to-token posterior trajectory and motivate, but do not validate, V47's frozen velocity model M5.

## Seed alignment

Emission-profile Hungarian matching to seed46 reference produced total Jensen–Shannon costs:

- seed460: **0.18990793**;
- seed4600: **0.17862869**.

No manual regime interpretation or relabeling was used.

## Next frozen step

Because 113 holdouts are eligible, V47 proceeds exactly as preregistered to development continuation scoring:

- M0 global frequency;
- M1 motif-only;
- M2 continuous posterior-field only;
- M3 additive motif + posterior field;
- M4 shared motif × continuous-field interaction (primary);
- M5 M4 + posterior velocity (trajectory test).

Internal replication and the original outer holdout remain sealed until the complete development result is frozen.
