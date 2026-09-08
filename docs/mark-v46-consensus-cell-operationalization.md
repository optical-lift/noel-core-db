# V46 — Consensus Regime and Cell Operationalization

**Date frozen:** 2026-09-08  
**Status:** implementation clarification frozen before inspection of regime identities or eligible-cell counts  
**Parent experiment:** V46 — Regime-Conditioned Grammar Recombination Test

This note makes the already-preregistered terms “emission-profile matching,” “mean / consensus across seeds,” and “development-training support” executable without altering the V46 hypothesis, thresholds, model family, candidate K set, or holdout discipline.

## 1. Regime-count selection

The selected regime count remains the candidate `K ∈ {4,6,8,12,16}` with the lowest arithmetic mean validation NLL/token across seeds `46,460,4600` on the frozen development train/validation split. No complexity penalty, tie rescue, or post-hoc preference is introduced.

## 2. Seed-label alignment

For the selected K only:

- seed `46` is the immutable reference labeling;
- seeds `460` and `4600` are matched to seed46 by Hungarian assignment;
- assignment cost is Jensen–Shannon divergence between the corresponding 65-state categorical emission distributions;
- the deterministic minimum-cost assignment is used as returned by `scipy.optimize.linear_sum_assignment`;
- transition matrices, duration distributions, and posterior columns are permuted by the resulting emission-based label mapping; they do not participate in choosing the mapping.

No regime may be manually relabeled according to apparent behavior.

## 3. Consensus posterior

For every token occurrence in the 110 development blocks:

1. compute the exact explicit-duration HSMM tokenwise posterior occupancy under each selected-K seed fit;
2. align seed460 and seed4600 posterior columns to seed46 using Section 2;
3. take the arithmetic mean of the three aligned posterior vectors;
4. renormalize only for floating-point roundoff;
5. assign a discrete regime only when the maximum consensus posterior is at least the frozen `0.70` threshold.

The discrete label is the argmax of the consensus posterior. Ties, if any, resolve to the lowest seed46 reference label by ordinary `argmax` behavior.

## 4. Development-training subset used for grammar support

The same deterministic development sub-split already used by the frozen HSMM fitter is retained:

- development-training block: `stable_bucket(book, block_index, 460046, 10) >= 2`;
- development-validation block: bucket `< 2`.

All motif-support and decisive `(regime,motif)` eligibility thresholds are computed from the 88 development-training blocks only. The 22 development-validation blocks are not used to make a motif or cell eligible.

This is the conservative interpretation of the preregistered phrase “support is measured on development training data only.”

## 5. Variable-order motif assignment

For each token in development-training, compute exact suffix supports for lengths `{2,3,4,6}` using development-training only.

The occurrence’s motif is the longest suffix in order `6,4,3,2` whose exact support is at least the frozen minimum of `100`. If no length-2 suffix reaches 100, the occurrence has no eligible exact motif representation for recombination analysis.

After that longest-supported-suffix assignment, motif frequency for the decisive cell rules means the number of occurrences actually assigned to that motif representation. Thus a shorter motif does not receive occurrences that are represented by a supported longer suffix.

The frozen decisive motif threshold remains `>=300` assigned development-training occurrences.

## 6. Cell eligibility

On high-confidence development-training occurrences only, form counts by `(regime Z, assigned motif M)`.

A motif first qualifies for cross-regime use if:

- assigned motif support >=300 development-training occurrences; and
- it has cells with >=50 high-confidence occurrences in at least 3 distinct regimes.

A regime qualifies if:

- it has >=1,000 high-confidence development-training occurrences; and
- it contains at least 20 distinct motifs meeting the cross-regime motif condition above with a >=50-occurrence cell in that regime.

A decisive cell `(Z,M)` is eligible when:

- Z qualifies;
- M qualifies;
- the cell contains >=50 high-confidence development-training occurrences;
- the cell occurs in at least 3 intact development-training blocks.

This resolves the apparent circularity in “regime Z contains at least 20 distinct eligible motifs” by first establishing motif cross-regime eligibility, then regime breadth, then final cell eligibility. No outcome variable is used.

If fewer than 20 final cells exist, V46’s decisive unseen-combination test is reported `NOT EVALUABLE` as preregistered.

## 7. Deterministic cell ordering and cap

If more than 200 final eligible cells exist, order them by SHA-256 of the UTF-8 string:

```text
460046:<seed46_regime_label>:<motif_length>:<comma-separated-state-ids>
```

and take the first 200 in ascending hexadecimal digest order.

If 200 or fewer exist, all are retained.

This implements the preregistered deterministic seed `460046` cap without inspecting continuation outcomes.

## 8. Outputs before grammar scoring

The consensus/cell step may report only pre-outcome structural facts:

- selected K and five candidate validation means;
- seed-alignment permutations and their total JS costs;
- high-confidence occurrence counts by regime;
- assigned motif counts by length/support;
- number of cross-regime motifs;
- number of qualifying regimes;
- number of eligible cells before/after the 200-cell cap;
- cell identities and support/block counts.

It must not inspect or report four-right continuation performance, M0–M5 CE, recombination gains, null performance, internal replication, or outer-holdout outcomes.

## 9. Holdout custody

This step uses only the 110 development blocks. The 50 internal-replication blocks and original outer holdout remain unopened for V46 grammar scoring.
