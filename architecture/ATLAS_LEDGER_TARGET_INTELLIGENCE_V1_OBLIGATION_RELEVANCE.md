# Atlas Ledger Target Intelligence v1 — Evidence Obligation Relevance Clarification

**Status:** candidate contract clarification  
**Date:** 2026-09-30  
**Applies to:** `ATLAS_LEDGER_TARGET_INTELLIGENCE_V1`

## Problem exposed by production-safe proof

The first production-safe temporary-object proof showed that the initial evaluator preserved Evidence Obligations from every unknown leaf even when the root Target Evaluation was already determinate.

Example:

```text
ALL
  entity_kind_is business            -> false
  relationship_exists region_a       -> unknown
  relationship_exists region_b       -> unknown

root                              -> false
```

The subject is already `not_qualified`. The two unknown relationship propositions did not prevent a deterministic answer. Treating them as active Evidence Obligations would cause Atlas to spend acquisition effort on facts that cannot change the present membership decision.

## Clarified law

An unknown leaf remains visible in the predicate trace whether or not it is decision-relevant.

An **active Evidence Obligation** is emitted upward only when resolving that unknown proposition is necessary to resolve the current root answer.

Therefore:

### `all`

```text
any false    -> false    -> no root Evidence Obligations
else unknown -> unknown  -> propagate obligations from unknown children
else          -> true     -> no root Evidence Obligations
```

### `any`

```text
any true     -> true     -> no root Evidence Obligations
else unknown -> unknown  -> propagate obligations from unknown children
else          -> false    -> no root Evidence Obligations
```

### `not`

```text
child true    -> false   -> no root Evidence Obligations
child false   -> true    -> no root Evidence Obligations
child unknown -> unknown -> propagate child Evidence Obligations
```

## Explainability is preserved

Pruning active obligations does **not** erase unknown leaves from the evaluation trace.

Atlas must still be able to explain:

```text
This subject was not qualified because predicate A was false.
Predicates B and C were unknown at evaluation time.
Those unknowns were not decision-blocking and therefore created no active research obligation.
```

This keeps historical epistemic state visible without converting every unknown fact into work.

## Acquisition consequence

A future acquisition adapter must consume only the root evaluation's active Evidence Obligations, not every unknown leaf found anywhere in the predicate trace.

This is the distinction between:

```text
unknown fact
!=
decision-blocking unknown
!=
authorized research action
```

The Target Intelligence layer still does not authorize acquisition by itself.