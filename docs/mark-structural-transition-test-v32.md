# Mark Structural Transition Test V32

**Date:** 2026-09-06  
**Status:** completed research experiment  
**Database:** shared `noel-core` Supabase project  
**Witness:** `mt_noel_current`  
**Write behavior:** read-only experiment; this document records the completed result and does not alter database authority, migrations, workflows, or deployment configuration.

## Research question

Do particular lexical-morphological operators occur at reproducible transitions between different anonymous structural regimes?

This is a distinct question from V29-V31. Those experiments established a local structural footprint around operator identity and then showed that lemma and morphology carry partly redundant information about that local field. V32 asks whether the two sides of the operator are themselves directionally distinguishable.

## Frozen holdout

The whole-book holdout was frozen before outcome evaluation by deterministic hash, excluding every V30 and V31 holdout book.

V32 holdout:

- `2Ki`
- `1Sa`
- `1Ch`
- `Amo`
- `Oba`
- `Hab`
- `Psa`

No V32 holdout book was used as a V30 or V31 holdout.

## Operator and anonymous state definition

Operator identity:

`lemma_raw × morph_raw`

For each operator occurrence, define two four-token anonymous morphology neighborhoods:

```text
-4 -3 -2 -1   OPERATOR   +1 +2 +3 +4
   PRE STATE                POST STATE
```

Training books only are used to estimate, for each supported operator, the morphology distribution on the pre side and the morphology distribution on the post side.

The held-out transition score asks whether the actual left-side morphology looks more probable under the learned pre-state distribution than under the learned post-state distribution, while the actual right-side morphology looks more probable under the learned post-state distribution than under the learned pre-state distribution.

Positive score means that the operator consistently separates two directionally different anonymous structural environments.

Primary support threshold: at least 20 training occurrences of the full operator.

## Primary result

On the fresh holdout:

- held-out occurrences: **32,722**
- supported operator types: **1,401**
- held-out books: **7**
- mean transition score: **+0.3466703032**
- median transition score: **+0.2258524337**
- positive occurrence rate: **68.886%**
- mean operator transition score: **+0.3466703032**

The pre- and post-operator anonymous morphology environments are therefore directionally distinguishable on untouched books.

## Morphology-only control

The same held-out occurrences were rescored using center morphology alone instead of full `lemma × morphology` identity.

Results:

- mean morphology-only transition score: **+0.1711209246**
- median morphology-only score: **+0.0962607384**
- positive occurrence rate: **66.937%**

Full operator identity scores approximately twice as strongly as center morphology alone:

- morphology only: **+0.1711**
- full operator: **+0.3467**

Thus center morphology carries genuine transition information, but lexical identity contributes substantial additional directional information.

## Matched same-morphology substitute control

For each supported operator where possible, a different lexical operator with the **same full morphology** was selected from training data, matched for approximate training frequency and corpus-position distribution.

Coverage:

- matched operator types: **1,257 / 1,401**
- held-out matched occurrences: **27,912**

Results:

- real operator score: **+0.3421797890**
- same-morphology substitute score: **+0.0724771544**
- paired real-operator advantage: **+0.2697026346**
- median paired advantage: **+0.1750714472**
- positive paired advantage at occurrence level: **59.892%**

Therefore an arbitrary operator with the same morphology does not reproduce the transition signature. The particular lexical-morphological operator carries operator-specific directional information.

## Whole-book replication

The matched real-versus-substitute advantage is positive in every fresh held-out book:

| Book | n | Real score | Substitute score | Delta |
| --- | ---: | ---: | ---: | ---: |
| `1Ch` | 4,897 | +0.367476 | +0.090644 | **+0.276832** |
| `1Sa` | 6,963 | +0.322450 | +0.068733 | **+0.253716** |
| `2Ki` | 6,902 | +0.569778 | +0.089511 | **+0.480267** |
| `Amo` | 999 | +0.323516 | +0.074897 | **+0.248619** |
| `Hab` | 258 | +0.114380 | +0.040328 | **+0.074053** |
| `Oba` | 146 | +0.299285 | +0.048369 | **+0.250915** |
| `Psa` | 7,747 | +0.151952 | +0.050396 | **+0.101556** |

No held-out book reverses the effect.

## Distance control

The same matched comparison was repeated farther from the operator:

```text
-8 -7 -6 -5   OPERATOR   +5 +6 +7 +8
```

Far-window results:

- held-out matched occurrences: **27,885**
- real-operator far score: **+0.1139791819**
- substitute far score: **+0.0004593819**
- paired far advantage: **+0.1135198000**
- median far advantage: **+0.0502243219**
- positive far advantage rate: **53.904%**

The operator-specific transition advantage therefore falls from approximately **+0.270** in the immediate `±1..4` neighborhood to approximately **+0.114** at `±5..8`.

The transition signature is strongest locally but does not vanish completely at the farther window.

## Threshold robustness

The matched primary analysis was repeated at a minimum of 10 training occurrences.

Coverage:

- held-out occurrences: **32,938**
- matched operator types: **2,403**

Results:

- real operator score: **+0.3558724748**
- substitute score: **+0.0712374889**
- paired advantage: **+0.2846349859**
- median paired advantage: **+0.1821898624**
- positive occurrence-level advantage: **60.022%**

The result is therefore not dependent on the stricter ≥20 support threshold.

## Operator-level distribution

Among operators with at least 10 occurrences in the held-out books:

- operator types: **576**
- positive mean operator advantage: **82.8125%**
- mean operator delta: **+0.3067225594**
- median operator delta: **+0.2592795323**
- 10th percentile: **-0.1291473823**
- 90th percentile: **+0.7804401574**
- minimum: **-0.5657059343**
- maximum: **+4.0840297220**

The transition effect is widespread but not universal. The minority of operators with neutral or negative transition advantage form a useful internal contrast class for subsequent experiments.

## Supported interpretation

V32 supports the following claim:

> Many lexical-morphological operators occupy reproducible directional structural transitions. Anonymous morphology immediately preceding an operator belongs to a statistically distinguishable regime from morphology immediately following it, and the specific operator identifies that transition substantially better than morphology alone or a frequency- and position-matched operator with identical morphology. The distinction is strongest locally and decays with distance.

The natural structural object suggested by V32 is therefore not merely:

`operator -> neighboring structure`

but potentially:

`state A -> operator -> state B`

## Relationship to V29-V31

V29-V30 localized an operator-associated anonymous structural footprint near the operator.

V31 showed that lemma and realized morphology both matter but carry substantially overlapping information about that local neighborhood; it rejected a simple additive or synergistic `lemma × morphology` interpretation and revealed a bidirectional local field.

V32 adds a new dimension: the field is directionally organized. The pre side and post side are not interchangeable, and the particular operator identity helps identify the transition between them.

## Epistemic ceiling

This is a controlled predictive discrimination result, not a literal intervention in the ancient text.

V32 does **not** establish that the operator causes the transition. It establishes that operator identity reliably identifies a directionally distinguishable transition between anonymous structural environments on fresh whole-book holdouts.

No semantic labels, inherited syntactic labels, or translation-derived categories are required for the primary result.

## Next unresolved questions

1. Whether operator-specific transitions compose into a finite or low-dimensional state-transition system rather than independent local signatures.
2. Whether the residual `±5..8` signal reflects longer transition zones, nested structure, or ordinary long-range autocorrelation.
3. Whether the minority of non-transitioning operators form coherent structural classes.
4. Whether transition identity generalizes across witnesses or languages under morphology-independent anonymous features.
5. Whether a learned transition system can predict held-out operator identity, detect corrupted sequences, or identify missing structural material without semantic supervision.
