# Planned Work Occurrence Execution-Carrier Terminality Reconciliation v1

Candidate source for issue #898.

## What the Rocket specimen proved

Rocket's hardening occurrence remained `released` while its exact released task was already `done`.

A live census found 13 such exact pairs. Every one completed on September 1 or September 5, before migration `20260906004231_atlas_company_work_terminal_release_isolation_v1` installed the current occurrence-terminalization behavior.

Post-fix evidence shows the runtime law is healthy: 23 newer done task / occurrence pairs are correctly `completed`, with zero newer released+done pairs.

## Scope

This tranche therefore does not replace runtime terminality.

It:

- adds an internal audit for released occurrence / terminal task contradictions;
- deterministically reconciles only exact `released ↔ done` custody pairs to `completed`;
- records task identity, historical completion time, reconciliation provenance, and the explicit fact that domain result acceptance was **not** inferred;
- leaves historical archived/skipped carriers untouched for separate classification.

The current census includes 130 `released ↔ archived` cases. Archive semantics are not assumed here.

## Boundary

Execution-carrier terminality is not domain-result acceptance.

For Production structured-result work, issue #892 separately governs whether the biological result exists. Completing an occurrence from exact historical task custody must never manufacture Production events, crop state, Harvest results, or any other domain result.
