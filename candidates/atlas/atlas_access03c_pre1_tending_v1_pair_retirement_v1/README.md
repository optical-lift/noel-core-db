# ACCESS-03C-PRE1 — paired retirement of obsolete Tending v1 functions

**Status:** HELD SOURCE CANDIDATE, **not** an authorized migration or production release. Canonical custody: `optical-lift/noel-core-db` for Atlas-owned database machinery. This unit removes exactly **two functions**, not a table, view, row, ledger, Person, Work item, or farm record.

## Reality / authority / scope

The old farm Tending task-context interface is not the universal Atlas Person/Principal/Organization/Ledger root. `atlas.tending_task_context_v1(uuid,uuid,text)` is a `SECURITY DEFINER` legacy RPC granted to `authenticated`. Its sole known runtime function caller of `atlas.tending_card_json_v1(uuid,jsonb,boolean)` is the context-v1 function itself. The helper is `SECURITY INVOKER`, with `service_role` EXECUTE but no `authenticated` or `anon` EXECUTE. This pair still reads `atlas.tending_task_track_v1`, whose eventual removal belongs to **separate** ACCESS-03C four-view retirement. Dropping the pair does not make that view or any other obsolete interface safe to drop.

The **current** `optical-lift/atlas` application has no direct literal callsite for the pair in the 432-file active source scan ([draft #569](https://github.com/optical-lift/atlas/pull/569)); the v1 name remains in the governor's intentional disclosure audit inventory and must not be scrubbed as an imitation of safety. The **unarchived** `optical-lift/farm-atlas` main branch has an actual task-context API route `app/api/atlas/tending/task-context/route.ts` that calls **`tending_task_context_v2`**, plus `tending_bed_v1` and `tending_board_v1` routes. Its `tests/atlas-narrow-tending-helpers.test.mjs` names both context v1/v2 and both card-json v1/v2, so legacy test expectations need reconciliation before release. GitHub code search returned incomplete results, so the available evidence **cannot prove** that every historic, dynamic, external, deployed or non-Atlas caller is absent. An external-consumer acceptance gate remains open.

## Exact change

- `candidate.sql` requires **separately released ACCESS-03B** two-table root-governed RLS and continued ACCESS-03A direct `zones` denial.
- It verifies exact function identity, source MD5, definer/invoker mode, `authenticated` / `anon` / `service_role` EXECUTE behavior, and the unchanged root-side governor disclosure-audit source.
- It checks catalog dependencies and runtime function-body mentions across all non-system schemas. Only the reviewed audit-list string and the retiring pair itself are permitted; unfamiliar dependencies fail closed.
- It fingerprints and preserves `tending_task_context_v2`, `tending_card_json_v2`, `tending_task_track_v1`, the zone source API and `farm_care_zone_v1`. The old v2 path is preserved for its existing clients, **not** promoted to universal Work authority.
- It issues two explicit `DROP FUNCTION ... RESTRICT` statements, context v1 first, helper v1 second. No `CASCADE`, grant, policy change, view deletion, row change or table change.
- `postconditions.sql` independently checks exact pair absence and retention of other source objects. Existence checks do **not** establish data no-loss or role-safe behavior; those require the clone probes below.

## Acceptance remains held

1. The external/historical consumer census must clear the exact v1 pair. The live `farm-atlas` route and its historical test expectations must be reconciled; a zero result from incomplete GitHub code search is **not** proof.
2. ACCESS-03B must first be independently authorized/versioned/released via the protected Noel Atlas structural lane. Unmerged source is not the prerequisite.
3. Run a protected disposable **current-production-schema** clone with the released ACCESS-03B state and exact source candidate, with **before/after** canonical Work, crop, care-history and physical-row checks. Preserve existing data.
4. Use genuinely signed synthetic owner, former manager, outsider and no-seat identities. Verify authorized native Work/Bed/zone and current v2 positives and legacy/foreign/anon negatives, plus exact old v1 REST route absence. An absent route is not the same as an authorized native positive.
5. Retain any named read-path audit/consumer contract until its owner explicitly reconciles its changed existence semantics. Review database advisors and no new RLS/ACL leakage.
6. Require separate principal approval for versioning, migration source merge and protected Production release. Never run this source candidate via direct live SQL.

**Explicit non-goals:** no farm-first Owner root, no v2 removal, no privilege restoration, no fake upgrade of inherited farm membership to native governing Ledger authority, no four-view ACCESS-03C deletion, and no invitation of real outsider testers.

## Pinned public legacy-client source evidence (not release authorization)

A separate source-only CI gate now checks the active `farm-atlas` application at exact main commit `1090d872754c170c61760a03ad232182f0538476`; it refuses to succeed when `farm-atlas/main` moves without a new audit. It scans all supported JS/TS files recursively under active application roots, **not** migrations or historical tests, for the exact two v1 function names. It also proves that the old task-context route directly calls `tending_task_context_v2`, that bed/board routes still use their v1 RPCs (which PRE1 does **not** delete), and that the original migration-custody test retains the v1 expectations. The route's `X-Atlas-Read-Path: tending-task-context-v1` header is a historical label; its actual database RPC is v2. Do not use the header alone as caller evidence.

This test addresses the current source snapshot of **one** known external repo, not all deployed client revisions, dynamic RPC construction, unknown agents, or non-Atlas clients. The PR remains held for those separate acceptance gates, signed clone, ACCESS-03B release and owner production approval.
