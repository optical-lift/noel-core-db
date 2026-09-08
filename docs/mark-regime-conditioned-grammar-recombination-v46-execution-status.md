# V46 — Execution Status Before Regime Scoring

**Date:** 2026-09-07  
**Experiment:** V46 — Regime-Conditioned Grammar Recombination Test  
**Status:** execution started; frozen regime model not yet scored  
**Formal result:** **UNADJUDICATED**

## Frozen hypothesis

The V46 hypothesis/preregistration was committed before V46 scoring at:

- `docs/mark-regime-conditioned-grammar-recombination-v46.md`
- commit `76fca133dc7a2fb748a9324608da47e6b9a2fb41`

The exact read-only preflight and numerical regime fitter were subsequently committed before regime scoring.

## Preflight correction made before model fitting

The first preflight accounting treated `block_index` as if it were globally unique. Inspection showed that `block_index` repeats across books; the preserved block identity is therefore `(book, block_index)`.

The preregistered split rule already hashes the complete block identifier (`book:block_index`), so the experiment definition did not change. Only the implementation/accounting check was corrected before any V46 model fit or outcome scoring.

Corrected preflight file:

- `validation/v46-preflight.sql`
- corrected commit `d2b7ceacd425e3c98773eb719f0cd48a597446f3`

Corrected non-outer-holdout partition:

- nonholdout blocks: **160**
- development blocks: **110**
- internal replication blocks: **50**
- nonholdout tokens: **235,209**
- development tokens: **158,503**
- internal replication tokens: **76,706**
- outer-holdout blocks: **41**
- outer-holdout token rows: **71,576**

The previously preserved valid-center outer holdout remains 71,248 centers; the 71,576 figure above is token-row count including block-edge tokens that cannot serve as nine-token centers.

## Corrected motif support on development

Under the frozen motif-length and support rules:

| Motif length | Distinct | support >=100 | support >=300 | max support |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 2,645 | 216 | **100** | 5,071 |
| 3 | 21,543 | 236 | **54** | 958 |
| 4 | 66,681 | 53 | 0 | 211 |
| 6 | 145,550 | 0 | 0 | 30 |

Consequences already implied by the frozen rules:

- decisive recombination cells can originate only from exact length-2 or length-3 motifs, because cell eligibility requires motif support >=300;
- length-4 contexts can still be used by variable-order prediction when support reaches 100;
- length-6 contexts necessarily back off under the frozen support rule.

This is a support fact, not an experiment outcome.

## Frozen development export

Read-only export query committed at:

- `validation/v46-export-development.sql`
- commit `eda117237ee95b8d2e9a9180bf1bf4599ef89b4c`

It emits only anonymous integer state sequences (V41 ranks 1–64 plus OTHER=65) for development blocks.

## Frozen explicit-duration regime fitter

The numerical implementation is committed at:

- `validation/v46-fit-regimes.py`
- commit `9b0c35eb6c0cb898100e6b3b51c1443f24f2c86e`

It implements the preregistered categorical explicit-duration hidden semi-Markov model with:

- K in `{4,6,8,12,16}`;
- explicit duration support 1–64;
- 65-state categorical emissions;
- frozen seeds `46, 460, 4600`;
- maximum 200 EM iterations;
- patience 10;
- development-only deterministic train/validation selection before K is frozen.

No internal-replication or original outer-holdout observations have been used for V46 regime selection or V46 scoring.

## Compute / custody boundary encountered

The connected Supabase database can execute SQL but has no installed Python/ML runtime suitable for the frozen duration-aware numerical model.

The local numerical runner can execute the frozen fitter but is network/DNS isolated from Supabase.

A Supabase publishable key exists, but local DNS isolation still prevents the numerical runner from reaching the project.

The GitHub repository currently has no dedicated non-production research data-access variable or workflow. Existing database workflows are production/custody workflows and were not repurposed.

A proposed one-shot GitHub export workflow that embedded the Supabase publishable key was rejected by platform credential-safety controls. That safeguard was not bypassed.

The repository is **public**, so the 158,503-token anonymous development sequence was deliberately **not committed as a data-staging artifact** merely to bridge the two runtimes.

No database exposure, RLS policy, production credential, Edge Function, public data surface, or protected workflow was changed to obtain compute.

## Current scientific status

**V46 has not failed. V46 has not passed. The frozen regime model has not yet been scored.**

The experiment is stopped immediately before its first model-dependent step:

1. fit the frozen duration-aware model on development;
2. choose K using development validation only;
3. freeze regime assignments/posteriors;
4. compute eligible regime × motif cells;
5. withhold exact combinations;
6. train and score the factorized grammar;
7. open internal replication only after development choices are frozen;
8. open the original outer holdout only after internal replication is written.

The corrected split counts and motif-support counts above are preflight eligibility facts only and must not be represented as evidence for or against the V46 recombination hypothesis.
