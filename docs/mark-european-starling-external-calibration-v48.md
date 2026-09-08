# V48 — European Starling External Calibration

**Date frozen:** 2026-09-08  
**Status:** EXTERNAL CALIBRATION / PREREGISTRATION — frozen before B338 sequence scoring  
**Primary external corpus:** European starling, bird `B338`  
**Source paper:** Sainburg et al. (2019), *Parallels in the sequential organization of birdsong and human speech*  
**Source data:** Arneodo et al. (2019), Zenodo 10.5281/zenodo.3237218  
**Source analysis code:** `timsainb/ParallelsBirdsongLanguagePaper` and `timsainb/AVGN` / `avgn_paper`

## 1. Purpose

V48 is not a new Hebrew hypothesis test. It is an external calibration of the Noel structural-inference machinery on a symbolic sequence system whose broad sequential organization has already been independently characterized in the published literature.

The central question is:

> If we hide the biological interpretation and give Noel only an anonymous symbolic sequence from one European starling, does the Noel structural battery recover the same broad class of short-range and long-range organization that the starling literature reports?

V48 exists to distinguish:

- statistical competence of the Noel methods;
- sequence-generic effects;
- genuinely corpus-specific structure in Hebrew.

## 2. Blind-analysis rule

The B338 analysis receives only:

- bout identity;
- ordered anonymous syllable-category IDs;
- token position within bout;
- recording/day identifiers only for splitting and replication controls.

It must not use:

- audio features;
- spectrograms;
- acoustic cluster coordinates;
- published motif/phrase labels;
- published starling sequence results;
- species interpretation during model fitting;
- any Hebrew state definitions.

Published starling findings are treated as an answer key and are consulted only after the B338 structural result is frozen.

## 3. Sequence provenance

The preferred sequence source is the exact symbolic sequence dataframe used by the 2019 paper.

The original analysis code establishes the following transformation:

1. load the already-generated UMAP/HDBSCAN clustered starling syllable dataframes from `raw/starling_umap/*/*/*.pickle`;
2. for each bird, select the most recent clustered dataframe;
3. sort syllables by `bird_name` and `syllable_time`;
4. use each row's existing categorical `labels` value as the observed syllable symbol;
5. split sequences when the interval between successive syllable onset times exceeds **10 seconds**;
6. save the resulting bout-level symbolic sequence dataframe as `song_seq_df/starling.pickle`.

This is the published `prep_STARLING` pipeline in `parallelspaper/birdsong_datasets.py` and `notebooks/birdsong/0.0-Starling-prep-dataset.ipynb`.

V48 will not invent a new clustering or bout definition if the published symbolic dataframe or its immediate clustered input can be recovered.

If the published symbolic/clustered data cannot be recovered and the raw audio must be reprocessed, V48 is marked **SOURCE RECONSTRUCTION REQUIRED** and no result is accepted until the authors' original AVGN segmentation/clustering procedure is reproduced and independently checked against published corpus-level statistics.

## 4. Primary individual

The development/calibration individual is fixed as:

```text
B338
```

No other starling may be used to tune B338-specific thresholds or rescue an unfavorable result.

The remaining 13 birds are reserved as external replication once the B338 analysis is frozen.

## 5. Anonymous alphabet

Within B338 only:

- take the authors' categorical syllable labels exactly as supplied;
- map distinct labels to integers `1..K_B338` by first occurrence in chronological bout order;
- retain a reversible mapping file for provenance;
- the structural scorer receives only the integer IDs.

No merging, splitting, relabeling, frequency filtering, or manual acoustic regrouping is allowed after sequence inspection.

Noise/unassigned categories are retained if they are present in the authors' published symbolic sequence. Any exclusion used by the source paper must be reproduced from source code rather than improvised.

## 6. Units and boundaries

The fundamental observed object is a bout:

```text
x_1, x_2, ..., x_T
```

where each `x_t` is one anonymous syllable-category ID.

No lagged statistic or predictive window may cross a published 10-second bout boundary.

Recording/day identifiers may be used for block bootstrap and holdout construction but not as predictive inputs.

## 7. Frozen B338 structural battery

V48 deliberately begins broader than V47. The first analysis is a system-identification map, not a single pass/fail neural model.

### 7.1 Corpus inventory

Report:

- number of bouts;
- total syllable tokens;
- alphabet size;
- bout-length distribution;
- state-frequency distribution;
- singleton/rare-state counts;
- repetition/run-length distribution.

### 7.2 Lag-information landscape

For lags `d = 1..64` where support is sufficient, compute:

- mutual information `I(X_t; X_{t+d})`;
- shuffled-bout-preserving null expectation;
- excess MI above null;
- conditional entropy `H(X_{t+d}|X_t)`;
- recurrence probability `P(X_t = X_{t+d})`;
- ordered-vs-reversed asymmetry where estimable.

The primary descriptive object is the complete lag curve, not a fitted decay law selected after inspection.

### 7.3 Radius / local-repertoire landscape

For radii `r = 1..16`, compute within valid bout interiors:

- distinct-state count;
- normalized entropy;
- maximum state concentration;
- left/right repertoire overlap;
- Jensen–Shannon divergence between left and right local repertoires;
- exact recurrence to center;
- order-erased versus ordered next-state predictive information.

### 7.4 Markov-order decomposition

Evaluate held-out next-symbol and next-four-soft-target prediction for:

- M0 global frequency;
- M1 first-order Markov;
- M2 second-order Markov;
- variable-order backoff models with maximum history lengths `3,4,6,8`;
- order-erased local-history baseline using the same visible history multiset.

Smoothing and support thresholds must be fixed from development blocks before held-out scoring.

### 7.5 Block entropy / predictive information

Estimate where support permits:

- block entropy `H(n)` for `n=1..8`;
- conditional entropy increments `H(n)-H(n-1)`;
- finite-n predictive information / excess-entropy diagnostics;
- surrogate comparison against global shuffle and first-order Markov surrogate sequences.

### 7.6 Transition geometry

Construct the observed one-step transition matrix and report:

- raw and smoothed transition probabilities;
- frequency-residual transition matrix;
- singular-value spectrum;
- effective rank / participation ratio;
- leading left/right singular vectors only as anonymous numeric structures;
- directional versus symmetrized transition components.

No post-hoc state naming is allowed before the blind result is frozen.

### 7.7 Latent-state comparison

Fit, with development-only selection:

- first-order Markov baseline;
- HMM candidate K in `{2,4,6,8,12,16}`;
- explicit-duration HSMM candidate K in `{2,4,6,8,12,16}` with maximum duration 64;
- a variable-order Markov model;
- a switching first-order Markov model if exact implementation is available before outcomes are opened.

Selection uses held-out development likelihood / CE only.

Required outputs:

- selected K;
- held-out CE / NLL improvement over first-order Markov;
- posterior-confidence distribution;
- state-duration distributions;
- whether soft posterior conditioning predicts continuation better than hard argmax state;
- whether current visible syllable adds information after latent posterior plus short motif context.

### 7.8 Boundary landscape

Using the selected duration-aware latent model, compute target-blind boundary score from posterior change / local repertoire divergence and test whether continuation uncertainty, motif changes, and transition residual magnitude are enriched near high-boundary locations.

This is descriptive in V48 and cannot rescue failures elsewhere.

## 8. Data split

B338 bouts are assigned deterministically by SHA-256 hash of the source bout identifier with seed `48`:

- 70% development;
- 30% blind B338 holdout.

Within development, an additional deterministic 80/20 split with seed `480048` is used for model/hyperparameter selection.

No statistic from the B338 blind holdout may choose alphabet treatment, support thresholds, model K, architecture, or lag/radius range.

If B338 has too few bouts for an intact-bout split to support the frozen analyses, V48 reports the affected endpoint `NOT EVALUABLE`; bouts are not fragmented merely to increase sample size.

## 9. Surrogate worlds

At minimum construct:

1. global symbol permutation within B338 preserving marginal frequencies;
2. within-bout positional shuffle preserving each bout's length and symbol multiset;
3. first-order Markov surrogate preserving the fitted one-step transition matrix and empirical bout lengths;
4. reversible-chain surrogate matched as closely as possible to the symmetrized one-step transitions.

The real sequence is compared to these worlds across lag information, block entropy, motif/order gain, and boundary diagnostics.

## 10. Blind output to freeze before literature comparison

The B338 result must be written to GitHub before the published answer key is used for interpretation. It must include:

- complete corpus inventory;
- lag curves and characteristic scales found without literature fitting targets;
- Markov/variable-order/latent model held-out comparisons;
- transition spectral structure;
- latent-state K and posterior geometry;
- boundary structure;
- which Noel observations replicate familiar V41–V47 phenomena and which do not;
- explicit failed/null diagnostics.

## 11. External answer-key comparison

Only after Section 10 is frozen may V48 compare the blind reconstruction with published findings from the 2019 starling work.

The comparison must distinguish:

- **recovered independently** — Noel found the same qualitative/quantitative phenomenon without being given it;
- **compatible but not independently diagnostic** — Noel result is consistent but too broad;
- **missed** — the published phenomenon was measurable but Noel failed to detect it;
- **additional** — Noel finds structure not tested in the source paper, which requires replication across the other 13 birds before being treated as a starling result.

## 12. Replication

After B338 and its answer-key comparison are frozen, repeat the unchanged structural battery on the remaining 13 starling individuals.

No B338-derived state IDs transfer across birds. Only analysis definitions transfer.

The replication question is whether the *shape/class of organization* reproduces across individuals.

## 13. Interpretation

A successful V48 calibration does not validate a theological or Hebrew interpretation. It validates that specific Noel structural procedures can recover independently known organization from an unrelated symbolic sequence.

A failure is equally informative: any Noel diagnostic that fails on B338 where the published starling literature provides an appropriate target must be downgraded before it is used as evidence about Hebrew.

## 14. Immediate execution gate

Before any B338 scoring:

1. recover the authors' exact B338 symbolic sequence dataframe or immediate clustered syllable dataframe;
2. verify provenance against the published `prep_STARLING` implementation;
3. freeze token/bout/alphabet counts and a cryptographic checksum of the anonymous sequence export;
4. only then run the structural battery.
