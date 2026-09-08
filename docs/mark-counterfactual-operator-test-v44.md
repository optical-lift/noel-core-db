# Mark Counterfactual Operator Test V44

**Date:** 2026-09-07  
**Status:** preregistered; exact frozen Gate 1 remains **unadjudicated**  
**Database:** shared `noel-core` Supabase project  
**Write behavior:** source corpus and experiment artifacts were read only; this document records V44 execution status and exploratory diagnostics and does not alter source authority, production migrations, workflows, deployment configuration, database exposure, or credentials.  
**Masoretic data:** not used.

## Research question

Does the anonymous 65-state center behave as a transferable structural operator on the incoming regime?

V44 reverses the earlier center-recovery framing. Instead of asking whether the surrounding field can identify the hidden center, it asks whether knowing the actual center improves prediction of what follows once the incoming structural regime is already known.

For each eligible nine-token window:

```text
x[-4] x[-3] x[-2] x[-1]   y   x[+1] x[+2] x[+3] x[+4]
```

define:

```text
L = x[-4:-1]
y = x[0]
R = x[+1:+4]
```

The basic comparison is:

```text
P(R | L, y)
vs.
P(R | L)
```

The stronger V44 claim requires more than conditional prediction. The actual state must also be counterfactually specific, transfer into incoming regimes where that `(regime, state)` combination was withheld, and ultimately compose correctly with another independently learned state on an unseen ordered pair.

## Frozen structural universe recovered

The preserved V41-V43 lineage was recovered directly from the existing Noel research artifacts.

The recovered universe exactly reproduces the prior evaluation scale:

- ordered structural tokens: **306,785**
- valid nine-token windows: **305,177**
- non-holdout centers: **233,929**
- held-out centers: **71,248**
- structural alphabet: **65 anonymous states**
  - 64 preserved high-frequency intrinsic structural classes
  - `OTHER` as state 65

The original outer holdout assignment was retained.

No alternative book, block, window, state definition, or favorable subset was selected after seeing V44 behavior.

## Frozen Gate 1 model

The preregistered Gate 1 operator model remains:

- incoming repertoire represented on the frozen four-left-state window;
- encoder: `65 -> 16`, tanh;
- shared operator basis: **8** residual transformation bases;
- each of the 65 states represented only through coefficients over those shared bases;
- decoder: `16 -> 65`;
- soft-target cross-entropy over the four-state outgoing repertoire;
- AdamW;
- learning rate: `0.001`;
- weight decay: `0.0001`;
- batch size: `2,048`;
- maximum epochs: `200`;
- early-stopping patience: `10`;
- seeds: `44`, `440`, `4400`;
- no scheduler, dropout, clipping, architecture sweep, or hyperparameter tuning.

The frozen Gate 1 practical-effect criterion requires at least a **1% relative cross-entropy reduction**, in addition to the preregistered statistical reliability requirement.

## Exact execution boundary

The connected Noel database exposes the preserved state sequence and holdout structure, but the local numerical runner available in the research session is isolated from that database connection.

No authorized direct file-export or general-purpose compute bridge was available.

The experiment therefore stopped at that boundary rather than:

- widening database exposure;
- exposing credentials;
- altering RLS or schema policy;
- deploying a new Edge Function;
- repurposing protected production workflows;
- or silently replacing the preregistered neural operator with an easier model.

For that reason, the exact frozen Gate 1 model has **not yet been run**, and V44 is not classified as formally passed or failed.

## Read-only pressure diagnostics

Several models that can be evaluated entirely within Noel were run against the exact preserved split.

These are **exploratory diagnostics only**. They cannot substitute for the preregistered neural Gate 1 model and cannot formally pass or fail V44.

| Diagnostic | `P(R|L)` CE | center-conditioned CE | Relative CE reduction |
| --- | ---: | ---: | ---: |
| Exact sparse `(L,y)` lookup | 3.019064 | 3.249532 | **-7.6338%** |
| Fully shared structural center-feature model | 2.837347 | 2.835280 | **+0.07283%** |
| Cross-fitted shrinkage `(L,y)` model | 3.029908 | 3.029587 | **+0.01059%** |
| Test-tuned shrinkage stress check | 3.029908 | 3.029542 | **+0.01208%** |

The final row deliberately allows the held-out set to choose its own shrinkage strength from a frozen grid. It is not a valid inferential result and is included only as an anti-conservative stress check.

## Exact sparse-table result

The direct exact `(L,y)` transition table strongly overfits.

Once the incoming four-state repertoire is known, conditioning additionally on the exact center makes held-out prediction much worse:

- M0 CE: **3.019064**
- M1 CE: **3.249532**
- relative change: **-7.6338%**

This is exactly the failure mode the preregistered shared low-dimensional operator architecture was designed to prevent, so it does not by itself reject the V44 operator hypothesis.

## Fully shared center-feature diagnostic

At the opposite extreme, a fully shared model lets the four incoming states contribute independently and gives the center only one additional anonymous structural feature.

Held-out result:

- M0 CE: **2.837347**
- M1 CE: **2.835280**
- improvement: **0.002066 nats**
- relative CE reduction: **0.07283%**

The direction is favorable to the center-conditioned model, but the effect is approximately **13.7 times smaller** than V44's frozen 1% practical-effect gate.

## Cross-fitted shrinkage diagnostic

A stronger read-only diagnostic retained the exact incoming repertoire and exact center but shrank sparse `(L,y)` behavior back toward `P(R|L)`.

The secondary split contained:

- training centers: **197,128**
- validation centers: **36,801**
- untouched outer-test centers: **71,248**

Validation selected the strongest available shrinkage value:

- `tau = 1024`

Validation itself preferred the no-center baseline:

- M0 CE: **3.049423**
- M1 CE: **3.051197**

On the untouched 71,248-center outer holdout:

- M0 CE: **3.029908**
- M1 CE: **3.029587**
- improvement: **0.000321 nats**
- relative CE reduction: **0.01059%**

The validation choice is itself informative: the model wanted to suppress almost all `(L,y)`-specific behavior and fall back toward what the incoming repertoire already predicted.

The held-out gain is approximately **94 times smaller** than the frozen 1% V44 effect threshold.

## Anti-conservative stress check

As a deliberately invalid upper-pressure check, the held-out set itself was allowed to select the best shrinkage strength from the frozen grid.

Best held-out result:

- selected `tau = 2048`
- M0 CE: **3.029908**
- M1 CE: **3.029542**
- relative CE reduction: **0.01208%**

Even after allowing the test set to tune the shrinkage in its own favor, the center-conditioned gain remains far below 1%.

This check cannot count as evidence for V44. Its only purpose is to ask whether an optimistically tuned lookup-style center effect comes anywhere near the preregistered practical threshold. It does not.

## Current result classification

V44 remains formally **open / unadjudicated** because the exact preregistered 16-dimensional, 8-basis operator model has not been executed.

However, the available diagnostics put the operator hypothesis under severe negative pressure.

The consistent pattern is:

> Once the incoming structural repertoire is known, the actual center contributes at most a microscopic amount of additional held-out information about the outgoing four-state repertoire in the models currently executable inside Noel.

The strongest legitimate directional diagnostic is **0.07283%**, well below the frozen **1%** Gate 1 threshold.

The more conservative cross-fitted estimate is **0.01059%**.

Therefore the current evidence does not support treating the center as a large local transformation operator of the simple form:

```text
L -> y -> R
```

No V44 threshold, representation, holdout, dimensionality, support rule, or pass/fail criterion is changed in response to these diagnostics.

## Hypothesis reversal prompted by the diagnostics

The negative pressure suggests a different structural model deserves explicit testing.

Instead of:

```text
L -> y -> R
```

consider:

```text
          Z
       /  |  \
      L   y   R
```

where `Z` is a latent structural regime extending across the local window.

Under this hypothesis:

- the center and its neighbors are jointly generated by a larger latent state;
- `y` is an observation of that regime rather than necessarily an operator acting on it;
- much of the apparent center-surrounding relationship should disappear once the local regime is already known;
- structural concentration and recurrence can still be real without requiring a large causal-style center transformation;
- regime transitions, rather than individual center identities, become the principal object of study.

This formulation naturally fits the present diagnostic pattern better than a strong local operator interpretation.

It is still only a hypothesis. V44 itself has not established it.

## Consequence for the research sequence

The frozen V44 neural Gate 1 should still be run when an authorized compute path exists. The exploratory diagnostics do not license replacing or canceling that test after the fact.

But the next separately preregistered experiment should no longer privilege the center.

The proposed next question is:

> Does the anonymous structural sequence behave as emissions from a recoverable latent regime whose boundaries and transitions explain local concentration, recurrence, and trajectory better than center-operator models do?

A proper follow-up should therefore infer latent regimes from sequence structure without using semantic labels and then test, on held-out material:

1. whether stable latent regimes are recoverable;
2. whether regime identity predicts multiple neighboring states jointly;
3. whether inferred regime boundaries predict changes in structural repertoire and trajectory;
4. whether the center adds meaningful information after conditioning on the inferred regime;
5. whether regime transitions generalize across held-out books/blocks rather than merely reconstructing local frequency.

If that model succeeds while the center adds little conditional information, the active interpretation should move from **state-as-operator** toward **state-as-emission of a larger latent structural regime**.

## Research custody note

The exploratory diagnostics recorded here cannot rescue or retrospectively modify V44. They are preserved because they materially change the next hypothesis worth testing.

V44's formal claim remains governed by its frozen model and frozen gates. The latent-regime proposal is a new experiment and must receive its own preregistration before results are inspected.
