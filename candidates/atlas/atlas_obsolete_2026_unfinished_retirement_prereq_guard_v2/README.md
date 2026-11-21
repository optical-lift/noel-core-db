# Held source V2 — prerequisite-preserving 2026 unfinished retirement

**NOT a migration, not a production release.** Never edit or retry the already-staged failed version `20261121184327`.

Owner requested only the retirement of obsolete 2026 Atlas unfinished queue items, not fulfillment of their physical work, not a rebuild of the legacy Task system and not changes to independent Work or the current growing season.

## Live production failure and identified missing rehearsal source

[Owner-approved production run #44937963139](https://github.com/optical-lift/noel-core-db/actions/runs/44937963139) of exact former version `20261121184327` **failed closed** at the final all-untargeted-row preservation fingerprint, after all pre-approval/source custody and target state checks passed. Full transaction rolled back. Independently verified release ledger absent and exactly 97 historical queue rows, 64 unfinished scheduled occurrences, 75 active/queued pointers, three Task statuses unchanged, canonical Work 294 and Requirements 116. No production changes.

Direct live SELECT-only inspection proves **exactly two active task_prerequisites** refer to the three retired-source Task IDs; one source is currently `blocked`, one `open`. Both active relationships require real status `done`, `hold_mode='deferred_hidden'`, `satisfied_at IS NULL`, and point to two DISTINCT independent Tasks that remain `blocked`, management-hidden, unassigned and with `prerequisite_gate_state='deferred_hidden'`. The original disposable fixture omitted these two live prerequisite links.

On archived source Task status, the existing `tasks_reconcile_prerequisite_dependents_v1` AFTER UPDATE trigger calls `atlas.reconcile_task_prerequisite_source_v1()`, which invokes `apply_task_prerequisite_gate_effect_v1` and unconditionally rewrites the two downstream Tasks' `blocker_text`, `metadata` and `updated_at` even though *archived does not satisfy done*. These two downstream Task IDs are NOT among the three target old Tasks; the original no-loss guard therefore correctly fails and rolls back. This is a source-grounded causal route to the final guard, not yet exhaustive proof that no additional live-only side effect exists.

## Exact containment design

- Reuse the existing source-and-row guard from proven former version V1 **without changing its 64/3/2/75 intended archival DML and Work/Requirements no-loss requirements**.
- Before archiving, guard exactly TWO unsatisfied original active prerequisite links and DISTINCT downstream blocked/unassigned/management-hidden Tasks, and verify the original named prerequisite reconciliation trigger is normally enabled.
- Within the ONE existing atomic transaction, isolate only the two non-security source-projection triggers (prerequisite recalculation and Goal evaluation) around the exact three archived Task updates. `ALTER TABLE atlas.tasks DISABLE TRIGGER tasks_reconcile_prerequisite_dependents_v1` takes a transactional ACCESS EXCLUSIVE table lock; concurrent Task updates cannot bypass it. Immediately `ENABLE` and verify BOTH named triggers before committing. Any failed SQL/guard rolls back both archival and trigger toggles. **All other identity, authorization, task reality, physical-completion, owner, release, capacity and signed-actor safeguards remain installed and active.**
- Preserve the original active prerequisite rows and the two independently blocked downstream Tasks byte-for-byte. The prerequisite requires actual `done` evidence; archival never satisfies it or hides a changed responsibility.
- Original V1 prevention of farm-wide task release sweep via the existing transaction-local reservoir flag remains scoped and restored; all unrelated 2027/crop/Harvest and Company Work stays untouched.
- Existing four-table-only 730 Atlas base-table original row-count and full-row fingerprint, genuine independent signed owner/worker/outsider/no-seat/revoked sessions, and schema lint remain mandatory.

## Source-positive disposable test

The attached fictional DML-only fixture extends the *already trusted* 97 original queue identities with exactly two fictional, independent, blocked downstream Tasks and two active `done`-requiring, deferred-hidden prerequisite links from the exact original source Task identities. These are ONLY synthetic Task titles, ids and state fields, not copies of live content, people or physical evidence. The new postconditions require these active prerequisites and downstream statuses unchanged, as well as the prerequisite reconciliation trigger fully re-enabled.

Use Noel's **existing** immutable protected owner-only Postgres 17 schema clone with genuinely signed C1 tests. No user credentials copied, no direct production DML, no alternative test engine.

**Next gates:** source-only controlled review; exact hash-pinned, owner protected disposable test; if it passes, one NEW canonical migration generated via existing Noel generator, protected exact-version rehearsal, and separate NEW owner approval for NEW version and bytes. Earlier owner approval was for `20261121184327` only; it cannot be reused for production release of V2.

## Additional live-only Goal history is independently protected

Follow-up read-only analysis confirmed that the affected farm also has **four active Goals and nine active Goal requirements**, none of which directly references any of the three obsolete Task IDs, task keys or Goal-to-Task links. Nevertheless, the existing `tasks_goal_recalculate_v1` AFTER UPDATE of status trigger invokes `atlas.goal_source_changed_v1()`, which always runs `atlas.evaluate_goal_unlocks_v1(...,true)` for the farm. That evaluator unconditionally inserts or refreshes historical `atlas.goal_evaluations` (and can release new Work on certain Goal transitions), even when the Task archive is only an administrative withdrawal, not new reality evidence. V1's fictional clone also omitted these active Goals. Mutating Goal history or releasing unrelated Goal tasks is outside the owner's requested queue cleanup.

The V2 held source now additionally requires **exactly four original active Goals** in the source farm, captures full-row Goal and Goal evaluation fingerprints, and verifies the original named Goal recalculation trigger is normally enabled. During only the same three-Task archive statement, the same transaction and exclusive Task lock pause **both** non-security projection triggers. Both are re-enabled immediately afterward with catalog checks; any failure rolls back all data and both trigger statuses. All other authorization, physical-reality, membership, release, preservation and source-identity triggers remain active. The source-positive fictional fixture adds four fictional active Goals with baseline evaluations. The mandatory original 730-table comparison must prove the two downstream Tasks/prerequisite links AND all four Goal histories remain completely unchanged. These are ordinary dependent states, not permission to bypass any owner, signature, physical-result or current Work rules.

**Superseded diagnostic HEAD:** the first V2 prerequisite-only source `b2f136356fd642c62d432c68591aca528cab2a97` is a historical test input, not the complete replacement release candidate. Any positive clone on that HEAD does NOT prove Goal preservation. Re-pin the exact updated source, fictional fixture and postconditions through a new test-only protected validation before source promotion, migration generation or owner approval.
