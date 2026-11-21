# HELD Atlas Package B — remove obsolete 2026 items from unfinished

**Owner instruction:** The old 2026 queue tasks are no longer important or required to complete. Withdraw obsolete obligations; do not conduct another individual interview or invent execution evidence. This is a narrowly scoped **data-disposition candidate, not a release**.

## Exactly what changes

- Cancel the **64** currently `planned` / `eligible` occurrences linked to the 97-row 2026 task-release queue (62 planned + 2 eligible). This withdraws the obsolete schedule, not a claim that physical weeding, crop clearance or another job happened.
- Archive the **three exact historical Tasks** previously adjudicated by the owner but still `open` / `blocked`: Field Note — Morning Rounds; Thursdays at Elm poster/payment sign; Quick Print order. They remain `completed_at IS NULL`; no `done` transition or Result is generated.
- Set the remaining **75** `active` / `queued` old queue pointers to `skipped`; 22 previously `completed` / `skipped` rows remain unchanged. The queue table is not deleted in this step.
- Preserve the original **21 completed** and **8 cancelled** linked occurrences; all existing canonical Work/Requirements, original source Subjects and crops, valid shared release policies, live harvest-preparation trigger, and spring 2027 work governance remain untouched.

The 64 source identities, 75 queue identities and three Task identities are fenced by exact before-state MD5 and record counts from **read-only** production inspection on 2026-11-21. The candidate transaction aborts on any drift, existing canonical Work/adapters/active child obligations, wrong update counts, or mutation of ANY unaffected Task, occurrence, queue row or canonical Work/Requirement row. The package has no direct production execution path.

**Specific physical exception:** Field Row 9 Navy beans remain a real physical crop source with no proven clearance; cancellation of that old queue entry does not clear the crop or mark the Bed ready.

## Required proof before release

1. Review exact source and transaction guards, dependency and trigger effects, including the three Task `status` update triggers and 64 occurrence state-change effects; verify SQL syntax and the correct identities against the live source **read-only**.
2. Reuse Noel's **existing** protected current-schema disposable PostgreSQL + signed actor mechanism. This is a **data-dependent** 97-row migration; the schema-only clone cannot prove the 64/75/3 effects without controlled fixture rows representing the original pre-state. Construct the smallest trusted fixture in the existing harness; no copied private crop/personal records. Test successful disposition plus stale census, changed ID/digest, active adapter, real Work, child Task, and signed-denial rollback.
3. Verify no unrelated data or canonical Work/Requirements/Results changed, and no old queue item reappears on the next existing Work/worker/day evaluation. Reuse 730-table row conservation, custody/lint and canonical migration rehearsal gates. Avoid dropping/altering the 11 shared policies.
4. Generate canonical versioned migration **only on proof PASS**, rehearse exact source, request separately named owner production-release approval, and verify the exact *live* 67 unfinished statuses and 75 queue pointers are gone from unfinished views. If any guard fails, stop; don't broaden mutation automatically.

The held five-function consumer decoupling [Noel #3133](https://github.com/optical-lift/noel-core-db/pull/3133) and protected [#3135](https://github.com/optical-lift/noel-core-db/issues/3135) are a **separate future table-drop dependency**. They do **not** block proposing this minimal unfinished-list withdrawal. Physical table deletion before outsider launch remains governed by [Atlas #532](https://github.com/optical-lift/atlas/issues/532).

No source/CI merge, production status change, Task completion, Result, shared-policy deactivation, new feature or infrastructure is authorized by the existence of this draft.
