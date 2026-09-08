# V46 — Development Regime Selection and Cell Eligibility Result

**Date:** 2026-09-08  
**Parent experiment:** V46 — Regime-Conditioned Grammar Recombination Test  
**Status:** development regime selection complete; decisive recombination test **NOT EVALUABLE** under frozen eligibility rules  
**Continuation outcomes inspected:** **NO**  
**Internal replication opened:** **NO**  
**Original outer holdout opened:** **NO**

## 1. Frozen regime-count selection

The five candidate explicit-duration HSMM regime counts were scored on the frozen development-validation split using the arithmetic mean validation NLL/token across seeds `46`, `460`, and `4600`.

| K | Mean validation NLL/token |
| ---: | ---: |
| 4 | 2.823559861288007 |
| 6 | 2.8199581940187244 |
| 8 | 2.819368700052973 |
| **12** | **2.817480917327515** |
| 16 | 2.8175535831755645 |

The preregistered rule therefore selects and freezes:

> **K = 12 regimes**

K=12 beats K=16 by `0.0000726658480495` nats/token on the frozen three-seed mean. No complexity penalty, tie-breaking modification, or post-result preference was used.

The mechanical selection artifact was produced by GitHub Actions run `34230388044`, artifact `v46-development-selection`.

## 2. Consensus operationalization custody

Before regime identities or eligible-cell counts were inspected, the implementation details for seed-label alignment, consensus posterior construction, motif assignment, and cell eligibility were frozen in:

- `docs/mark-v46-consensus-cell-operationalization.md`
- commit `d04a43aca6184ff41d3444949adebaa4496ad76a`

The consensus scorer was committed before its execution in:

- `validation/v46-consensus-cells.py`
- commit `19a944fbf958242be38f2d0206b8d46c089c589c`

The dedicated workflow was committed at:

- `.github/workflows/v46-consensus-cells.yml`
- commit `3838f63059de23644a9335530eec46120302438c`

The workflow reverified the exact 110-block / 158,503-token development corpus checksum before calculation.

## 3. Seed alignment

Seed46 remained the immutable reference labeling.

Emission-profile Hungarian alignment produced:

- seed460 total Jensen-Shannon assignment cost: `0.18990792714326024`
- seed4600 total Jensen-Shannon assignment cost: `0.1786286931681878`

The aligned original columns, indexed from zero, were:

- seed460 → reference labels: `[0,3,9,10,1,2,8,6,7,11,4,5]`
- seed4600 → reference labels: `[10,7,1,8,3,5,0,4,9,6,11,2]`

No manual relabeling was performed.

## 4. High-confidence consensus regime support

Using the frozen maximum-consensus-posterior threshold `>=0.70` on the 88 development-training blocks:

| Regime | High-confidence occurrences |
| ---: | ---: |
| 1 | 576 |
| 2 | 1,141 |
| 3 | 154 |
| 4 | 297 |
| 5 | 511 |
| 6 | 1,585 |
| 7 | 1,563 |
| 8 | 4,040 |
| 9 | 1,836 |
| 10 | 2,261 |
| 11 | 911 |
| 12 | 372 |

Only regimes 2, 6, 7, 8, 9, and 10 independently clear the frozen `>=1,000` high-confidence occurrence requirement, but regime support alone is not sufficient for cell eligibility.

## 5. Frozen variable-order motif assignment

On the 88 development-training blocks (`129,434` tokens), after longest-supported-suffix assignment under the frozen `>=100` exact-support backoff rule:

| Motif length | Assigned occurrences | Distinct assigned motifs | Assigned motifs >=300 |
| ---: | ---: | ---: | ---: |
| 2 | 60,615 | 196 | 86 |
| 3 | 39,695 | 188 | 40 |
| 4 | 3,652 | 30 | 0 |
| 6 | 0 | 0 | 0 |

Thus 126 assigned motif identities clear the frozen overall `>=300` motif-support requirement before the cross-regime criterion is applied.

## 6. Decisive eligibility result

The preregistered decisive recombination design additionally requires a motif to have a cell with at least 50 high-confidence occurrences in at least **three distinct regimes**.

Result:

> **Cross-regime motifs meeting that rule: 0**

Therefore:

- qualifying regimes after motif-breadth rule: **0**
- eligible `(regime, motif)` cells before 200-cell cap: **0**
- eligible cells after cap: **0**

The V46 preregistration explicitly states that if fewer than 20 eligible cells exist, the decisive unseen-combination test is reported `NOT EVALUABLE` rather than weakening thresholds.

Accordingly:

> **V46 decisive unseen regime × motif recombination test: NOT EVALUABLE.**

This is not a pass and not a failure of the factorized grammar hypothesis. The frozen corpus / regime / confidence / support combination does not furnish the minimum counterfactual recombination cells required by V46.

## 7. What was not done

Because the prerequisite cell universe is empty, the following V46 steps were not executed:

- deliberate `(Z,M)` combination withholding;
- M0 frequency continuation scoring;
- M1 motif-only continuation scoring;
- M2 regime-only continuation scoring;
- M4 factorized grammar continuation scoring;
- primary `DeltaCE_recombine` calculation;
- 1,000 recombination nulls;
- counterfactual regime substitution on withheld cells;
- counterfactual motif substitution on withheld cells;
- internal-replication scoring;
- original outer-holdout scoring.

No continuation outcomes were opened merely to diagnose the eligibility failure.

## 8. Scientific interpretation permitted at this point

The development data support only these structural statements from V46:

1. among the frozen candidate explicit-duration models, K=12 gives the best three-seed development-validation likelihood;
2. high-confidence regime occupancy is highly uneven across the 12 consensus regimes;
3. many length-2 and length-3 motifs have ample total support;
4. under the frozen high-confidence and per-cell thresholds, none of those supported motifs is represented strongly enough in three distinct regimes to form the preregistered recombination universe.

The result does **not** establish that motifs are intrinsically regime-specific. It may reflect true regime specificity, posterior confidence structure, corpus support, or some combination of those factors. Distinguishing those possibilities requires a separately frozen experiment or explicitly labeled diagnostic; V46 may not be rescued by changing its thresholds after this result.

## 9. Formal V46 state

**Regime model:** selected and frozen (`K=12`)  
**Cell eligibility:** complete  
**Primary recombination endpoint:** **NOT EVALUABLE**  
**Internal replication:** sealed  
**Original outer holdout:** sealed  
**Semantic interpretation:** still prohibited
