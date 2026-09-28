# Atlas Governed Subject Zero-Cost Behavioral Validation — 2026-09-28

Status: **behavioral contract passed; PostgreSQL-engine execution still pending**

Date: 2026-09-28

Validation branch:

`validation/governed-subject-observation-applicability-v1`

Executable harness:

`validation/atlas_governed_subject_behavioral_harness.py`

## Purpose

The isolated Supabase development-branch route was rejected because it would cost money. This validation therefore uses a zero-cost deterministic harness to execute the source-domain laws and the first Elm end-to-end consequence loop without touching production.

This receipt must not be read as proof that PostgreSQL compiled the migration or enforced RLS/GRANT semantics. It records the behavioral layer only.

## Result

The harness executed successfully in the local session:

```text
PASS — 14 / 14 behavioral proofs
```

Passed assertions:

1. missing observation remains `indeterminate / no_admitted_observation`;
2. same-key/same-content observation admission replays the canonical receipt;
3. same-key/different-content observation reuse fails closed;
4. observation evidence does not leak across resource identities;
5. a later observation becomes current without erasing historical as-of recovery;
6. same-key/same-content applicability admission replays the canonical receipt;
7. overlapping applicability intervals for the same scope/resource/operation fail closed;
8. exact Responsibility-scope → resource → operation applicability resolves current;
9. absence of applicability remains unknown/indeterminate rather than false;
10. adjacent replacement applicability intervals preserve historical resolution;
11. missing canonical Grounds observation + current carrier + exact applicability derives one acquisition encounter;
12. applicability cannot be borrowed across resource subjects;
13. absence of a current Responsibility carrier produces silence under the proving policy;
14. admitting the canonical Grounds observation causes natural operational silence on re-derivation.

## First Elm loop proven behaviorally

The executable proof now validates the narrower source-backed loop established by the corrected architecture:

```text
no admitted observation for canonical Grounds
→ observation availability unresolved

+

current Person-carried grounds_readiness Responsibility
+
exact Responsibility-scope → Grounds applicability
for acquire_current_grounds_observation

→ supported observation-acquisition encounter

canonical Grounds observation admitted
→ current source read established
→ same operational policy re-evaluated
→ silence
```

No Task completion, encounter completion, queue dismissal, synthetic mowing threshold, or synthetic freshness rule participates in closure.

## Historical behavior

The harness separately verifies that source correction is additive rather than destructive:

```text
observation A
→ observation B later admitted
→ current read selects B
→ historical observed-as-of still selects A
```

and:

```text
applicability interval A [t0,t1)
→ applicability interval B [t1,∞)
→ historical read during A returns A
→ later read returns B
```

This matches the intended source-law distinction between present resolution and durable history.

## What this materially increases confidence in

The passing harness exercises the core semantics embodied by the proposed SQL:

- append-only source evidence;
- exact canonical subject identity;
- idempotent admission;
- conflict-on-reused-key-with-different-content;
- current-versus-historical observation selection;
- half-open applicability intervals;
- overlap rejection;
- exact scope/resource/operation matching;
- epistemic absence distinct from established falsehood;
- independent current Responsibility carriage;
- encounter support as relational fan-in;
- writeback through source truth followed by re-resolution;
- natural disappearance of an unsupported operational projection.

## What remains unproven without a real PostgreSQL engine

Four engine-specific concerns are deliberately still open:

1. PostgreSQL parser / PL/pgSQL compilation of the exact migration text;
2. RLS enforcement on the new canonical tables;
3. exact `GRANT` / `REVOKE` privilege behavior, especially service-role direct INSERT removal;
4. advisory-lock concurrency behavior under real concurrent PostgreSQL transactions.

Those are not behavioral-design uncertainties. They are engine/security validation items.

## Why SQLite was not used

SQLite would not materially increase confidence in the four remaining items because it does not implement PostgreSQL PL/pgSQL, RLS, PostgreSQL role grants, or advisory locks. A behavioral model is therefore more honest than labeling a SQLite execution as database validation.

## PGlite attempt

A real PostgreSQL-in-WASM engine (PGlite) was investigated as a free isolated route. The environment can access the project documentation/repository through controlled connectors, but outbound package/binary download is blocked and the official source repository does not commit the generated WASM/data artifacts required to instantiate the engine here.

No paid resource was created and production was not used as a substitute.

## Current gate

The source architecture no longer needs redesign before implementation.

Current evidence is:

```text
production dependency/schema preflight: PASS
behavioral source-law harness: PASS (14/14)
live Elm identity/Responsibility compatibility preflight: PASS
synthetic Grounds maintenance assumption: REMOVED
real PostgreSQL compilation/security/concurrency validation: PENDING
```

Because the outstanding items are engine-specific rather than semantic, application work may proceed only as isolated typed adapters/pure tests against the already-defined resolver envelopes. Do not wire production calls or declare the source tranche released until a real PostgreSQL execution path becomes available at zero cost (for example, a local PostgreSQL installation, free ephemeral Postgres/PGlite runtime, or restored free CI capacity).

## Reopen boundary

When a zero-cost PostgreSQL engine becomes available, do not repeat architecture discovery or the behavioral proof. Execute only the remaining engine-specific validation:

1. apply both source migrations in order;
2. execute all three rollback SQL proofs;
3. assert RLS and direct-table privilege behavior;
4. exercise overlapping applicability admissions concurrently to confirm serialization/overlap rejection;
5. record the resulting engine-validation receipt.

Until then, this branch is the durable zero-cost validation checkpoint.
