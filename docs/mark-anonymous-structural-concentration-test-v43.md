# Mark Anonymous Structural Concentration Test V43

**Date:** 2026-09-07  
**Status:** completed research experiment — negative as preregistered  
**Database:** shared `noel-core` Supabase project  
**Witness:** `mt_noel_current`  
**Write behavior:** experiment executed against isolated research artifacts; this document records the completed result and does not alter source authority, production migrations, workflows, or deployment configuration.  
**Masoretic data:** not used.  
**Frozen preregistration SHA-256:** `af5d8c1a7394ebe6945c4a804e46c11f9a85d89073de4fe13869e835764a1eeb`

## Research question

Does the anonymous concentration of the eight visible surrounding Hebrew structural states contain information about the hidden center, especially whether that center remains inside the locally active repertoire?

V43 was designed to test the concentration pattern discovered post-hoc in V42 while removing the main leakage concern: concentration is defined using only the eight non-center neighbors.

## Frozen design

Each held-out example is a nine-token window:

```text
-4 -3 -2 -1   [ ? ]   +1 +2 +3 +4
```

The fifth token is hidden.

Visible predictor:

- only the other eight structural states;
- positions and state identities removed for the primary concentration representation;
- represented by the occupancy partition of the eight neighbors, for example `5-2-1`.

Frozen target alphabet:

- **65 structural states**.

Primary P1 task:

- predict the named 65-state center from anonymous occupancy.

Primary P2 task:

classify the center's relationship to the visible repertoire as one of:

- `dominant`
- `other_recurring`
- `singleton`
- `new`

Conditional models use Jeffreys/add-1/2 smoothing.

The frozen unseen-center subset is defined by center skeleton absent from all training centers.

## Anti-leak replication of the V42 concentration pattern

The V42 F0/F1 diagnostic was recomputed using the number of distinct states among the eight non-center neighbors only.

| Distinct visible neighbor states `k8` | Scored B tokens | F0 CE | F1 CE |
| ---: | ---: | ---: | ---: |
| 2 | 485 | 2.0236507155 | **1.9849937025** |
| 3 | 6,755 | 2.1648976425 | **2.1628319713** |
| 4 | 35,345 | **2.3988537226** | 2.4725110354 |
| 5 | 93,945 | **2.6327198747** | 2.7747819921 |
| 6 | 121,685 | **2.8833944933** | 3.0849484775 |
| 7 | 77,835 | **3.1480505952** | 3.3658705150 |
| 8 | 20,190 | **3.4315849047** | 3.6113372021 |

The V42 crossover survives leakage correction:

- F1 wins at `k8 = 2`;
- F1 is essentially neutral at `k8 = 3`;
- F1 loses increasingly at `k8 >= 4`.

Thus the concentration-dependent failure pattern is not an artifact of counting the hidden center when measuring local diversity.

## P1 — named center-state prediction

Full holdout:

- held-out centers: **71,248**
- F0 CE: **2.84160783484553**
- concentration F1 CE: **2.84206239967230**

The concentration model is slightly worse than global state frequency.

Unseen-center subset:

- N: **6,252**
- F0 CE: **3.67059851716142**
- F1 CE: **3.66821280903401**

There is a very small unseen-only improvement, but it does not rescue the failed full-holdout endpoint.

**P1 conclusion:** anonymous concentration does not encode the named center identity.

## P2 — center role relative to the visible repertoire

Full holdout:

- F0 CE: **1.15304617761312**
- concentration F1 CE: **1.04028103209088**

Unseen-center subset:

- F0 CE: **1.01933222809878**
- F1 CE: **0.943048512890067**

The concentration model therefore strongly improves prediction of the center's relationship to the visible repertoire relative to its own marginal baseline.

## Frozen 20-null test

The preregistration required the real P2 absolute F1 cross-entropy to beat at least 19 of 20 deterministic shuffled-center null worlds.

The nulls preserve center-state distribution within train and holdout while reassigning centers to visible neighborhoods and recomputing the P2 role.

Real P2 F1 CE:

- **1.04028103209088**

Null P2 F1 CE distribution:

- mean: **1.01131044560603**
- minimum: **1.00862367684124**
- maximum: **1.01401948027124**
- real world beats: **0 / 20**

V43 therefore **fails its frozen primary null criterion**.

## Why the absolute-CE null is confounded

The shuffled worlds change the marginal distribution of the constructed P2 role variable.

That means the role-prediction problem itself becomes easier or harder under permutation. Comparing raw F1 cross-entropy across worlds is therefore not invariant to the null transformation.

This does not permit a retrospective endpoint change. The frozen endpoint remains failed.

The confound is nevertheless important for designing the next experiment.

## Frozen directional expectation

The preregistration also expected raw probability of center continuation inside the visible repertoire to increase with greater concentration.

Observed held-out continuation probability:

| `k8` | N | P(center state appears among visible neighbors) |
| ---: | ---: | ---: |
| 2 | 97 | 0.4742268041 |
| 3 | 1,351 | 0.4663212435 |
| 4 | 7,069 | 0.4894610270 |
| 5 | 18,789 | 0.5017297355 |
| 6 | 24,337 | 0.5174425771 |
| 7 | 15,567 | 0.5324725381 |
| 8 | 4,038 | 0.5141158990 |

The frozen directional prediction is wrong.

Raw continuation does not rise with concentration because larger visible repertoires mechanically cover more of the center-state probability mass.

## Post-hoc chance-adjusted continuation diagnostic

After the frozen directional failure, the observed continuation rate was compared with the exact random-pairing expectation implied by held-out center-state marginals and each visible repertoire.

| `k8` | Observed | Random expectation | Excess recurrence |
| ---: | ---: | ---: | ---: |
| 2 | 0.474227 | 0.283712 | **+0.190515** |
| 3 | 0.466321 | 0.370123 | **+0.096198** |
| 4 | 0.489461 | 0.421239 | **+0.068222** |
| 5 | 0.501730 | 0.459538 | **+0.042192** |
| 6 | 0.517443 | 0.485998 | **+0.031445** |
| 7 | 0.532473 | 0.506259 | **+0.026213** |
| 8 | 0.514116 | 0.521843 | **-0.007727** |

This is the clearest pattern produced by V43:

> The excess tendency of the center to remain inside the visible structural repertoire is strongest when that repertoire is highly contracted and approaches zero as the repertoire opens.

This analysis is **post-hoc** and cannot rescue V43.

## Post-hoc information-gain diagnostic

Real P2 improvement relative to its own marginal baseline:

- `1.15304617761312 - 1.04028103209088`
- **0.11276514552224 nats**

Across the 20 shuffled worlds, each world's own F0-to-F1 gain has:

- mean: approximately **0.10548812938513 nats**
- range: **0.102733257280677 to 0.108403942872790**

The real pairing beats **20 / 20** null worlds on information gain.

This demonstrates why absolute F1 CE was a poor permutation metric: the real pairing carries more conditional information relative to its own marginal entropy, even though the shuffled worlds have lower raw F1 CE because their role marginals are easier.

Again, this was not the preregistered endpoint and therefore does not convert V43 into a success.

## Identity-added diagnostic

A diagnostic retained actual unordered neighbor-state identities using an exact `state=count` signature while still erasing position.

Only **31,759 / 71,248** held-out identity signatures were seen in training.

Using V42-style fallback to F0 for unseen signatures:

- P1 identity-added CE: **3.26407965858704**
- P1 F0 CE: **2.84160783484535**

- P2 identity-added CE: **1.16548603462533**
- P2 F0 CE: **1.1530461776128**

Exact unordered state identity makes both tasks worse.

The concentration phenomenon therefore is not rescued by sparse exact neighbor identities.

## Result classification

V43 is **negative as preregistered**.

Reasons:

1. P1 fails on full holdout.
2. The real P2 absolute F1 CE beats **0/20** frozen nulls instead of the required 19/20.
3. The frozen raw continuation direction is wrong.

The experiment is not retrospectively reclassified despite two strong post-hoc diagnostics.

## Supported interpretation

V43 supports the following limited conclusions:

> Anonymous local concentration does not identify the named center state. The V42 concentration crossover is real and survives removal of center leakage. The center's relationship to the visible repertoire is predictable from concentration relative to its own marginal baseline, but V43's frozen absolute-CE null is invalid as a difficulty-invariant comparison because permutation changes the marginal entropy of the constructed role variable.

The strongest hypothesis generated by V43 is narrower and more structural:

> When the local visible repertoire is highly contracted, the actual center remains inside that repertoire substantially more often than ordinary state-frequency coverage would predict. That excess coupling decays toward zero as the repertoire opens.

This chance-adjusted formulation was discovered after outcome inspection and remains unconfirmed until tested prospectively.

## Relationship to V41-V42

- **V41:** exact eight-position local order does not outperform the same surrounding information with order erased.
- **V42:** exact anonymous local-field prediction fails globally, but succeeds only in strongly contracted local repertoires.
- **V43:** the concentration crossover survives anti-leak testing, named-state prediction still fails, and the relevant quantity appears to be excess repertoire membership relative to combinatorial chance rather than raw recurrence.

Together these results shift the working hypothesis away from an exact local code and toward a concentration-dependent constraint on local structural repertoire membership.

## Epistemic ceiling

V43 does not establish:

- a causal operator process;
- a finite-state grammar;
- structural regime boundaries;
- compositional state transformations;
- a confirmed chance-adjusted repertoire-closure law.

Those stronger claims require new preregistered experiments whose endpoints are defined before outcome inspection.
