# Mark Exact Anonymous Structural Field Test V42

**Date:** 2026-09-07  
**Status:** completed research experiment — negative as preregistered  
**Database:** shared `noel-core` Supabase project  
**Witness:** `mt_noel_current`  
**Write behavior:** experiment executed against isolated `instrument.v42_*` artifacts; this document records the completed result and does not alter source authority, production migrations, workflows, or deployment configuration.  
**Masoretic data:** not used.  
**Witness-opening SHA prefix:** `76f7eedb`

## Research question

Can an exact anonymous four-token structural field predict the other five structural states within a nine-token Hebrew span better than simple center-state frequency?

V42 was designed after V41 rejected exact local positional order as the missing signal. Instead of asking whether order itself encodes the center, V42 asks whether the local anonymous field carries predictive information in its exact state combination.

## Evaluation universe

V42 uses the same rolling nine-token universe later reused by V43:

- total spans: **305,177**
- held-out spans: **71,248**
- total span members: **2,746,593**
- held-out span members: **641,232**
- frozen target alphabet: **65 structural states**

Each span is divided into:

- **A:** four revealed tokens
- **B:** five scored tokens

The A/B assignment is frozen independently of textual order.

Primary models:

- **F0:** global training-state frequency
- **F1:** exact anonymous A-field conditional model

F1 uses Jeffreys/add-1/2 smoothing across the 65-state target inventory and falls back to F0 when the A signature was unseen in training.

## Primary result

On the full held-out set:

| Model | Cross-entropy |
| --- | ---: |
| F0 — global frequency | **2.84331288974468** |
| F1 — exact anonymous field | 3.01461889130882 |

Lower cross-entropy is better.

The exact anonymous field is therefore substantially worse than simple state frequency on the primary endpoint.

## Unseen-B result

Among the **30,654** scored B tokens in the frozen unseen-B subset:

| Model | Cross-entropy |
| --- | ---: |
| F0 | **3.64448640289361** |
| F1 | 3.74344662659323 |

The exact-field model again loses.

## Same-window pairing control

The real A/B pairing was compared with a pairing in which the B side came from a different window.

- real same-window F1 CE: **3.01462**
- different-window F1 CE: **3.03869**

Thus nearby Hebrew structural states are not simply independent: the real same-window association is better than a different-window pairing.

That local association is nevertheless too weak, under the exact-field model, to beat the global frequency baseline.

## Arbitrary membership-partition control

The real A/B partition was compared against 20 arbitrary membership partitions.

- real partition beat: **12 / 20**
- frozen success threshold: **19 / 20**

V42 therefore fails the preregistered partition-control criterion.

## Post-hoc concentration diagnostic

After the primary failure, held-out spans were stratified by the number of distinct structural states among all nine tokens.

| Distinct states in span | F0 CE | F1 CE |
| ---: | ---: | ---: |
| 2 | 2.01160 | **1.94825** |
| 3 | 2.06498 | **2.02633** |
| 4 | **2.27427** | 2.30706 |
| 5 | **2.51315** | 2.62100 |
| 6 | **2.75932** | 2.94178 |
| 7 | **3.01670** | 3.23663 |
| 8 | **3.29124** | 3.50127 |
| 9 | **3.57325** | 3.73384 |

The exact field helps only in highly contracted local repertoires, particularly at two and three distinct states.

This diagnostic was **post-hoc** and initially counted the hidden/scored token among the nine states. It therefore could not be treated as confirming evidence and was not allowed to rescue the failed V42 result.

V43 was preregistered specifically to test whether the concentration phenomenon survives when concentration is defined using only the eight visible non-center neighbors.

## Result classification

V42 is **negative as preregistered**.

The following frozen criteria fail:

- F1 does not beat F0 on full holdout;
- F1 does not beat F0 on unseen-B tokens;
- the real A/B partition beats only 12/20 arbitrary partitions rather than the required 19/20.

The same-window pairing control does show genuine local dependence, but not a successful exact-field predictor.

## Supported interpretation

V42 supports the following limited claim:

> Exact anonymous local structural identity is not a general predictive code for the other states in the span. However, the failure is strongly heterogeneous: when the local state repertoire is highly contracted, exact-field prediction becomes competitive and can outperform frequency.

The concentration pattern is hypothesis-generating only within V42 because it was discovered post-hoc.

## Epistemic ceiling

V42 does not establish:

- a general local structural code;
- a named-state transmission rule;
- a causal operator process;
- structural regimes;
- concentration-dependent constraint as a confirmed effect.

It establishes a negative primary result plus a sharply structured failure pattern that justifies a new frozen experiment.
