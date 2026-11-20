# SRC-RETIRE-01 A — first obsolete Atlas queue function, held deletion source

**2026-11-16. Status: REVIEW-ONLY candidate. NOT compiled or signed tested. NOT installed. NO production deletion authorized.**

Owner instruction: [Atlas P0 issue #532](https://github.com/optical-lift/atlas/issues/532). [Already merged Atlas deletion inventory](https://github.com/optical-lift/atlas/blob/main/docs/integration/ATLAS_PRELAUNCH_LEGACY_TABLE_RETIREMENT_20261116.md). The new Atlas remains the universal Principal/Person/Ledger/Subject/Need/Rulebook/Work/Actual system. Its old Task and queue operational tables are required to be physically dropped before unrestricted outsider launch, but valid actual/history must be preserved.

## This single retirement, not a new engine

Proposed source: exactly one guarded DROP FUNCTION with RESTRICT for atlas.backfill_active_task_release_gates_v1(). It is a historical release-queue **backfill administrator function**, not the central old queue table. Neither the 97 old queue rows nor any canonical Work/Result/Subject/Ledger rows are deleted. This is one source-owned clean cutover, not proof the queue table is ready to DROP.

The live read-only source/catalog evidence (as of 2026-11-16):
- Exact body MD5 623f52a2ff3ae732cdc62e459be8bfca; existence 1.
- No non-system SQL/PLpgSQL routine-body name mentions in the reviewed current catalog; no noninternal trigger reference; no tracked normal dependency on its OID.
- No executing grant for anon, authenticated or service_role; no currently visible matching pg_cron.job command.
- **Unverified:** historical/external administrative invocations, dynamic SQL without literal source reference, and future catalog drift. Negative census is not proof of never having been used.

The candidate itself rechecks identity/source hash, tracked dependencies, function-body mentions, trigger usage, role grants and scheduler jobs **inside its own transaction** before attempting the DROP; it fails closed on any drift and refuses CASCADE. The postcheck requires the legacy queue *and* canonical Work table still exist. The SQL contains no INSERT, UPDATE, DELETE, RLS/ACL or other schema changes. Application-level negative source gate [Atlas #647](https://github.com/optical-lift/atlas/pull/647) already passed 429 files and 5/5 tests and was merged. That gate did not prove this function has no external callers.

## Still required before removal

1. Exact source-owner/independent release review, including external/admin script and deprecated maintenance-call census. A formerly callable administrative routine might still have an out-of-database caller even if no API grant/cron.
2. Protected *disposable current-schema* PostgreSQL clone compile and postcondition verification, before/after every original Atlas row hash and identity count, and relevant deny/access regression. No test-purpose SQL may copy Production records.
3. A separately versioned canonical Noel atlas_ migration under the required source-generation/release lane, with explicit owner approval, protected production release, migration receipt and read-only live function-absence and original-row preservation verification.
4. Leave the 33 old queue-function-body mentions and the 97 queue row states as an independent, far larger retirement gate. Do not create Work from old queue rows, and do not autorun a successor after Result/Done (binding November 4 decision 6A). One present source-authorized Need and separately consented U1/U2 first Work may be established only by valid approved source.

**Scope:** one source-only SQL candidate, read-only postcondition, tests and CI; no production, GitHub runner/secret change, queue table DROP, personal data, farm-specific Work storage, or new status register. The Atlas completion register remains the evidence log.