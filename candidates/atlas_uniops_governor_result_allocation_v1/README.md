# HELD UNI-OPS governor Result-linked responsibility projection

**Status: source-only candidate, not a generated migration, signed schema test, runtime installation, or release.** Owner [Atlas #532](https://github.com/optical-lift/atlas/issues/532) / existing [completion register](https://github.com/optical-lift/atlas/blob/main/docs/integration/ATLAS_INTEGRATION_COMPLETION_REGISTER.md). Supports [Noel #2822](https://github.com/optical-lift/noel-core-db/issues/2822) diagnosis without reusing the consumed protected test authorization.

## One bounded outcome

Make the existing owner-authorized `company_work_accountability_native_ledger_self_api_v1` reveal **only source-linked Result responsibility** when a completed original's prior allocation is no longer active. The ordinary `responsibility` object still means CURRENT active allocation. `lastResponsibleAllocation` remains historical chronology and cannot be accepted as the reporting worker simply because it is the most recent old allocation.

Current live read-only `pg_get_functiondef` function fingerprint `md5=302be9714957f5bf76d665092c9609b1` (2026-11-17) is the exact guarded base. This candidate is intentionally an additive `CREATE OR REPLACE FUNCTION` on that function identity only; no new authorizer, task engine, direct table writer, RLS/grant policy, title search, UI inference, broad data disclosure, or permissions. If the existing source changed, the candidate guard fails. Regenerate only through Noel's normal independently reviewed source/migration/release lane when authorized.

### Result custody and why the link is real

The `atlas.work_execution_results.responsible_allocation_id` FK references `atlas.work_allocations.id` (nullable, `ON DELETE SET NULL`). In the separate **HELD** source [Noel #2487](https://github.com/optical-lift/noel-core-db/pull/2487), `candidates/atlas/20261028235811_atlas_care_single_done_signed_proof_v1.sql` defines `atlas.record_continuing_care_actual_self_api_v1`: it selects the currently signed canonical Person's exact responsible allocation under the original Work, then inserts the accepted physical Result with `responsible_allocation_id=v_allocation.id`. That source law was separately exercised in the signed U2/U4/P3 disposable proof. It is **not** proof that the same writer is installed in production.

In this candidate the latest-worker-report's new `reportAllocation` is populated only by the Result's actual FK, joined on the exact same Organization, original Work, responsible allocation role and admitted current or completed/released states. Require a recorded canonical assignee, and an allocation time not later than the report's recorded time. Emit the exact source Result ID and allocation ID, canonical assignee, state, historical flag and bounded same-original relation. **Absence/NULL/dangling/cross-Work/cross-Organization/participant allocation or missing canonical assignee yields NULL.** An unrelated newer historical allocation, even on the same Work, is never substituted.

**Additional reporter-provenance boundary (November 17):** The new `reportAllocation.recordedReporterMatchesAllocation` is a source-recorded consistency flag, **not** independent signed-actor proof. It is true only when the physical Result has a non-null `reported_by_user_id`, its governed `result_contract_key` is `continuing_care_actual_v1`, and its recorded `metadata.authenticatedReporterPersonId` equals the exact source-linked responsible allocation's canonical Person. The held physical Actual writer stores these claims from its independently checked GoTrue/`current_person_id_v1` context. The owner projection checks the recorded fields but cannot itself recreate or independently prove the historic GoTrue authentication event. A fresh disposable signed actor-run must still prove the reporter's actual session, the Work authorization, accepted Result, and outsider denial. Both the native Today governor entrance and the native Work Focus Done predicate fail closed if this flag is not `true`.

The caller's owner authorization, exact native-Ledger scope, report/acceptance separation, latest-report timestamp-tie ambiguity, page cursor and original source state remain unchanged. `reportAllocation` does **not** prove which on-screen actor signed in or that a source report is accepted: Atlas separately requires the correct Result, decision, order and scope.

## Negative acceptance obligations

- Same original, canonical responsible Result FK: active/completed/released historical states each preserve their distinct status.
- Wrong original, Organization, allocation ID, role, premature allocation, missing direct canonical assignee or NULL report FK: no evidence, no Done.
- Multiple reported Results at the same latest timestamp: keep `exactOrderWithinTimestampProven=false`; a UUID sort is not chronology.
- Accepted Result ID different from latest worker report: no Done.
- Reassigned Work: a later/current unrelated assignee must never displace the Result-linked historical performer.
- Independently signed owner/worker/outsider, changed/disclosed Ledger, replay, and no-successor checks are **NOT** established by source-only tests.

## Checked versus held

- `tests/atlas_uniops_governor_result_allocation_source.test.mjs`: authored source/synthetic positive and negative checks; a future exact-head Node execution and PostgreSQL parser/current-schema compile are required before source acceptance.
- Noel Database Custody CI is source custody only, **not** an installed-function execution.
- Existing held [Atlas #535](https://github.com/optical-lift/atlas/pull/535) maps the new source field into the already-strict signed governor Done verifier. Without this separately released Noel projection it must remain unverified.
- **Next independently authorized protected gate:** exact-source, disposable current-schema PG17 + signed GoTrue/PostgREST test, including completed allocation, accepted Result/ID/order, rejected outsider and wrong-Result/allocation, and unmodified Work/Need/Clock successor count. A new Noel bridge/immutable Atlas source pin and one-time owner authorization are required. No automatic replay of Noel issue #2822.

**Whole Atlas finish line remains open:** ordinary Foundry→Rulebook→Need→one authorized original→signed Actual/Result→governor readback→Index/Today/Work Focus, second nonfarm domain, and physical deletion of adjudicated legacy operational tables before unrestricted outsider launch.
