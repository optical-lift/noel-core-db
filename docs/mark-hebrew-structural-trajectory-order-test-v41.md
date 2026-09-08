# Mark Hebrew Structural Trajectory / Order Test V41

**Date:** 2026-09-07  
**Status:** completed research experiment — negative  
**Database:** shared `noel-core` Supabase project  
**Witness:** `mt_noel_current`  
**Write behavior:** experimental artifacts were isolated under `instrument.v41_*`; this document records the completed result and does not alter source authority, production migrations, workflows, or deployment configuration.  
**Masoretic data:** not used in this experiment.

## Research question

Does the ordered trajectory of the eight visible Hebrew structural states surrounding a hidden center contain information about the center beyond the same surrounding information with positional order erased?

V41 was designed to distinguish a true local trajectory signal from a simpler bag-of-surrounding-structure effect.

The primary comparison is deliberately one-for-one:

- **P1:** the eight surrounding structural states with their true positions preserved;
- **P2:** the same surrounding information with positional order erased.

The center itself is hidden in both conditions.

## Frozen evaluation universe

V41 uses nine-token windows:

```text
-4 -3 -2 -1   [ ? ]   +1 +2 +3 +4
```

The fifth token is the hidden target.

Primary held-out evaluation:

- held-out centers: **71,248**
- candidate center states per target: **65**
- exact stored candidate-score rows are preserved in `instrument.v41_p1_scores` and `instrument.v41_p2_scores`.

The 65-state target alphabet is the frozen Hebrew structural-state inventory used by the subsequent V42 and V43 experiments.

## Primary result

The stored candidate scores were normalized across all 65 possible center states for each held-out center and evaluated by cross-entropy in nats.

| Model | Information retained | Held-out CE | Top-1 rate |
| --- | --- | ---: | ---: |
| P1 | true eight-position order | **2.8768119742** | **17.4082%** |
| P2 | same surrounding information, order erased | **2.8498631429** | 17.2833% |

Lower cross-entropy is better.

The order-preserving model is therefore **worse** than the order-erased model on the probabilistic endpoint:

- P1 minus P2 CE: **+0.0269488312 nats**.

P1 has a very small top-1-rate advantage of approximately **0.125 percentage points**, but that does not offset its worse full-distribution score and does not support the hypothesized ordered-trajectory advantage.

## Result classification

V41 is **negative**.

Preserving the true positions of the eight surrounding structural states does not improve prediction of the hidden 65-state center relative to erasing their order while retaining the surrounding information.

The result therefore rejects the simple hypothesis that the relevant local information is carried by a recoverable eight-position structural trajectory.

## Supported interpretation

V41 supports the following limited claim:

> Whatever Hebrew structural signal remains around the hidden center is not adequately described as an ordered eight-neighbor trajectory code. The same surrounding structural information without positional order performs at least as well, and better on the primary probabilistic score.

This does **not** mean that direction, sequence, or transition structure is absent at every scale. Earlier experiments such as V32 showed directional operator-associated transitions under a different representation and target. V41 specifically rejects the stronger claim that the eight neighboring states, in their exact local order, provide a superior code for the hidden 65-state center in this masking task.

## Relationship to the next experiments

V41 removed a tempting explanation: exact local order was not the missing source of predictive information.

That motivated V42 to ask a different question: whether an exact anonymous structural field, without depending on an ordered-center-trajectory interpretation, could predict the other states in the same local span.

V42 then showed that such exact-field prediction fails globally but behaves differently when the local state repertoire is highly contracted. V43 was designed to test that concentration phenomenon directly without using the hidden center to define concentration.

## Epistemic ceiling

V41 is a held-out predictive discrimination experiment.

It does not establish:

- that Hebrew sequence order is globally irrelevant;
- that longer-range transition order carries no information;
- that no operator-like process exists;
- that structural regimes do not exist;
- that order could not matter under a different frozen representation or target.

The supported negative claim is narrower: **the exact eight-position surrounding trajectory did not outperform the same surrounding information with order erased for recovery of the hidden 65-state center.**
