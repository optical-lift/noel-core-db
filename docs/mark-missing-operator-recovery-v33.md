# Mark Missing Operator Recovery V33

**Date:** 2026-09-06  
**Status:** completed research experiment  
**Database:** shared `noel-core` Supabase project  
**Witness:** `mt_noel_current`  
**Write behavior:** experiment executed read-only; this document records the completed result and does not alter database authority, migrations, workflows, or deployment configuration.

## Research question

If the real center operator is removed, can the surviving anonymous structural neighborhood recover what belongs in the gap?

V33 reverses the V32 corruption idea. Instead of damaging known-correct text and asking whether the system detects the damage, V33 masks a real operator and asks whether the surrounding structure can identify the missing operator.

## Fresh whole-book holdout

The V33 holdout was frozen before scoring and excluded every V30, V31, and V32 holdout book.

V33 holdout:

- `Exo`
- `Mic`
- `Num`
- `Mal`
- `Dan`
- `2Sa`

## Masked context

The center token is hidden completely.

Visible anonymous structure:

```text
-4 -3 -2 -1   [ ? ]   +1 +2 +3 +4
```

The model sees only raw morphology at the eight visible positions. It does not receive the hidden token's surface form, lemma, morphology, semantics, translation, or inherited syntactic label.

Candidate identity is full:

`lemma_raw × morph_raw`

Primary training support threshold: at least 20 occurrences of the candidate operator in training books.

## Candidate universe and evaluation set

Primary candidate inventory:

- eligible training-supported operator identities: **1,568**
- held-out occurrences whose true operator is in that inventory: **30,116**
- supported held-out operator types: **1,390**

For exact all-candidate ranking, the evaluation set was frozen deterministically at 100 held-out occurrences per book, for **600 masked targets** total.

The primary score is the summed training-only likelihood of the eight visible neighboring morphologies under each candidate operator. Candidate frequency is excluded from the structural score and evaluated separately as a baseline.

## Exact missing-operator recovery

Across all 600 masked targets and 1,568 candidate operators:

| Metric | Structural model | Frequency-only baseline |
| --- | ---: | ---: |
| Top 1 | **9.6667%** | 4.0000% |
| Top 5 | **23.6667%** | 17.3333% |
| Top 10 | **31.1667%** | 24.6667% |
| Top 50 | **47.6667%** | — |
| Median rank | **59.5** | 86.5 |
| Mean rank | 282.755 | — |

Random top-1 chance under 1,568 candidates is approximately **0.0638%**.

Thus the true missing lexical-morphological operator is ranked first roughly 150 times more often than random chance and substantially more often than a frequency-only guess.

## Book-preserving neighborhood-shift null

A fixed subset of the evaluation set was used for paired null testing:

- 20 deterministic targets per held-out book
- 120 masked targets total

The true missing operator remained fixed, but its visible morphology neighborhood was replaced with a neighborhood from another location in the **same book** using deterministic cyclic shifts.

### Real neighborhoods on the 120 paired targets

- Top 1: **10.8333%**
- Top 5: **25.8333%**
- Top 10: **34.1667%**
- Top 50: **50.8333%**
- median rank: **50**
- mean rank: **275.592**

### Within-book cyclic shift #1

- Top 1: **0%**
- Top 5: **1.6667%**
- Top 10: **4.1667%**
- Top 50: **13.3333%**
- median rank: **819.5**
- mean rank: **765.625**

### Within-book cyclic shift #2

- Top 1: **0%**
- Top 5: **1.6667%**
- Top 10: **2.5000%**
- Top 50: **14.1667%**
- median rank: **887**
- mean rank: **797.383**

Recovery therefore depends strongly on the **specific local placement** of the anonymous morphology neighborhood and is not explained by book-wide morphology alone.

## Whole-book replication

The primary exact top-1 recovery advantage over frequency-only prediction is positive in every fresh held-out book:

| Book | Structural top 1 | Frequency top 1 | Structural top 5 | Frequency top 5 | Structural top 10 | Frequency top 10 | Structural median rank | Frequency median rank |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Exo` | **8%** | 3% | 21% | 16% | 31% | 27% | **43** | 92 |
| `Mic` | **8%** | 1% | 19% | 17% | 24% | 20% | **91** | 116 |
| `Num` | **14%** | 7% | 28% | 20% | 35% | 30% | **24.5** | 70 |
| `Mal` | **11%** | 6% | 19% | 24% | 24% | 32% | 173.5 | **42.5** |
| `Dan` | **9%** | 2% | 31% | 14% | 37% | 19% | **56.5** | 191.5 |
| `2Sa` | **8%** | 5% | 24% | 13% | 36% | 20% | **50.5** | 96.5 |

All six books improve exact top-1 recovery over frequency alone.

The deeper ranking is not uniformly superior: Malachi improves top-1 while frequency performs better at top-5, top-10, and median rank. The primary supported effect is therefore exact-choice enrichment rather than a universal improvement to the whole candidate ranking.

## Morphology-only recovery

The center morphology was then treated as the missing target independently of lexical identity.

Candidate morphologies: **714**.

| Metric | Structural model | Morphology-frequency baseline |
| --- | ---: | ---: |
| Top 1 | 7.6667% | **8.8333%** |
| Top 5 | **25.5000%** | 25.1667% |
| Top 10 | **39.6667%** | 35.0000% |
| Median rank | **19** | 27 |

Anonymous neighborhood structure improves broader morphology ranking but does **not** beat raw morphology frequency at top-1.

## Lexical recovery conditional on true morphology

The true center morphology was then supplied, restricting candidates to lexical identities that realize that same morphology.

| Metric | Structural model | Frequency within true morphology |
| --- | ---: | ---: |
| Top 1 | 48.0% | **55.8333%** |
| Top 3 | 64.5% | **73.6667%** |
| Top 5 | 72.5% | **80.0%** |
| Median rank | 2 | **1** |

Once the true morphology is given, simple lexical frequency outperforms the current neighborhood likelihood.

This means the V33 result is not well described as the neighborhood independently spelling out the missing lemma or morphology. The strongest recovery signal belongs to the **joint realized operator**.

## Harder candidate inventory

The candidate support threshold was relaxed from ≥20 to ≥10 on the fixed 120 paired targets.

Candidate inventory increased from **1,568** to **3,278** operators.

Structural recovery:

- Top 1: **6.6667%**
- Top 5: 17.5000%
- Top 10: 25.8333%
- Top 50: 38.3333%
- median rank: 199.5

Frequency-only baseline on the same target/candidate universe:

- Top 1: **2.5000%**
- Top 5: 20.0000%
- Top 10: 30.0000%
- Top 50: 45.0000%
- median rank: 69

Random top-1 chance under 3,278 candidates is approximately **0.0305%**.

Exact top-1 recovery therefore remains enriched when the candidate universe more than doubles, while deeper ranking performance becomes less robust.

## Supported interpretation

V33 supports the following claim:

> The anonymous morphological structure surrounding a missing token contains substantial information about the specific lexical-morphological operator that occupied that position. On fresh whole-book holdouts, the real operator can be recovered from among more than 1,500 candidates far above chance and above frequency-only prediction, and recovery collapses when the local neighborhood is replaced by another neighborhood from the same book.

The evidence does **not** yet support the stronger claim that the system can reconstruct a lost reading in a manuscript.

The present result is single-operator recovery under synthetic masking of otherwise intact canonical context.

## Relationship to V29-V32

- V29-V30: operator identity is associated with a sharply proximal anonymous structural footprint.
- V31: lemma and morphology both matter but contribute substantially overlapping information about that local field.
- V32: the field is directionally organized; many operators distinguish a pre-state from a post-state.
- V33: when the operator itself is removed, the surviving transition contains enough information to partially recover the missing full operator.

This progression suggests a transition from descriptive structure toward constrained reconstruction, but the reconstruction claim must remain limited to the tested masking regime.

## Epistemic ceiling

V33 is a held-out predictive reconstruction experiment on synthetic masking.

It does not establish:

- unique recovery of the lexical lemma from structure alone;
- unique recovery of morphology from structure alone;
- recovery of unattested operators;
- recovery of multi-token lacunae;
- recovery of actual damaged manuscript readings;
- textual causation.

The strongest current evidence concerns the joint full operator and exact top-rank enrichment.

## Next unresolved step

The strongest next adversarial test is to remove a **short contiguous operator path** rather than one center token:

```text
STATE A -> [ ? ? ? ] -> STATE B
```

The system should then be required to recover or rank the true multi-operator path from the surviving anonymous structure, under fresh whole-book holdout and matched path-frequency controls.
