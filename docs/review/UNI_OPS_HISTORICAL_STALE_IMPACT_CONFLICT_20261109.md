# UNI-OPS historical retirement — stale-impact transport source-law review (HELD)

**Date:** 2026-11-09. **Owning coordinated release:** [Atlas UNI-OPS-01 #532](https://github.com/optical-lift/atlas/issues/532), [Noel full-current lifecycle history #2505](https://github.com/optical-lift/noel-core-db/issues/2505). **Source-owner approval: NOT GIVEN. Protected historical test: NOT_RUN.**

## Exact issue

The original, **unmerged and immutable** [Noel lifecycle #2368](https://github.com/optical-lift/noel-core-db/pull/2368), head `ddfb0bf5374798301fe076a61d2b944dfb52ff63`, file `candidates/atlas_universal_work_lifecycle_v1/20_native_historical_retirement_candidate.sql`, Git blob `93f7b9cf0bad5eb536ffa90d3973aabfe75542d9`, performs all of the following in this order:

1. Verifies signed native Ledger governor, exact immutable `obsolete_cancelled` review and original Work; locks the original.
2. Reuses existing retired-state action replay; otherwise compares the live `company_work_retirement_dependency_snapshot_v1` MD5 with the governor's `p_impact_token`.
3. **If the token no longer matches**, denies the cancellation with `RAISE EXCEPTION 'Retirement preflight stale; refresh impact' USING ERRCODE='40001'`.
4. Only with a still-valid token, invokes the single existing private Work lifecycle cancellation writer. No accepted physical Actual/Result or new Work is authorized by historical review.

The separately merged test bridge `tests/uniops_historical_retirement_signed_bridge_held.py` at immutable blob `f1a4eadb4d0199e8b4d9c1f17738675c281e249d` expects SQLSTATE `40001`, but accepts only HTTP 400/401/403/409 for its negative assertion. **That expectation is not compatible with the documented PostgREST transport mapping.**

## Public provider evidence, separate from Noel source

- [Supabase Knowledge Base, updated November 4, 2026](https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b): custom SQLSTATE `40001` inside an RPC is considered transient; PostgREST 14 may retry repeatedly; the vendor reports the retry bug fixed in PostgREST 16. It recommends `P0001` or explicitly mapped `PT` HTTP codes rather than using transaction-level `40001` for application rejection.
- [PostgREST 14 error reference](https://docs.postgrest.org/en/v14/references/errors.html): `40*` maps to HTTP **500**; `P0001` defaults to **400**; `PTxyz` explicitly specifies HTTP status `xyz`, e.g. `PT409` returns **409**.
- **Frozen local runtime evidence limit:** the existing trusted [U4 workflow](https://github.com/optical-lift/noel-core-db/blob/main/.github/workflows/held-uni-ops-u2-u4-signed-actual-clone.yml) uses exact Supabase CLI version **2.116.0** verified with SHA256 and builds a disposable local PostgREST/GoTrue service through `supabase start`. That CLI version is verified by the successful U4 run, but the exact **PostgREST container image digest/runtime major version** was **not reported in the retrieved U4 evidence**. Do not pretend a CLI tag independently proves the PostgREST image version. Before any *new* protected historical test, a safely redacted provider/runtime image identity should be recorded from the ephemeral local runner, without access tokens or container environment data. Even if the retry is fixed in PostgREST 16, `40001` remains a 500-class transaction error, not a source-governed 409 conflict.

**Status:** This is a confirmed *source-vs-published-transport contract mismatch* and potential retry hazard; **not** an observed failure of a new signed historical test. The original U4 positive test [#42709128622](https://github.com/optical-lift/noel-core-db/actions/runs/42709128622) is unaffected and remains verified in its earlier disposable clone.

## Source-owner decision for review

| Review option | Meaning | Assessment |
|---|---|---|
| A — preserve `40001` | Continue reporting an application stale-token rejection as serialization failure; change only test adapter to expect HTTP 500 | **Not recommended.** Potential PostgREST 14 repeated retry and misleading infrastructure error; would weaken the negative acceptance meaning |
| **B — replace exactly one `40001` with `PT409`** | Keep all signed governor/Work locking, source-dependency comparison and private cancellation logic untouched; return a **non-retryable conflict**, with the bridge requiring exact HTTP 409 and `code=PT409` | **Recommended for explicit source-owner review.** Distinguishes stale preflight from permission denial and does not silently accept a changed dependency |
| C — replace `40001` with `P0001` | Same fail-closed denial, but maps to HTTP 400 | Supported alternative; less semantically precise than conflict for stale preflight |

**Proposed exact nonproduction source-only delta B**, not a rewrite of original SQL:

```diff
 RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
-  USING ERRCODE='40001'; END IF;
+  USING ERRCODE='PT409'; END IF;
```

The separately test-only signed adapter would change its expected stale code `40001`→`PT409` and additionally require **HTTP 409** for that denial. All other source permission denials continue to require genuine `42501`.

## What this held PR does

- Stage `tests/uniops_history_stale_token_source_contract_held.py`: byte-check original frozen SQL and test-bridge Git blobs, then generate an **in-memory proposed exact one-guard SQL delta and exact test-adapter delta**. No source file modification, no SQL execution, no network, no production access, no merge or test launch.
- Stage a no-network unit-test matrix against two independent immutable source checkouts, verifying the exact one-hunk correction, unchanged native authority/lock/writer, test-adapter conflict assertion, invalid/unreviewed blob refusal, and syntactic validity of the proposed test-only Python. Does **not** establish a signed runtime POST response or backfill any historical performance.
- Stage independent ordinary **PR-only** GitHub Actions with `contents: read`; no existing owner-only issue workflow, production environment or release path touched.

## Release and validation hold

1. **Owner must explicitly approve the source-law choice** before any SQL change: Option B `PT409` (recommended), C `P0001`, or another separately reviewed contract. This review document does not count as source approval.
2. On explicit approval, create a separately versioned held Noel history source candidate (new immutable blob), re-pin its review/CI and signed test bridge, and re-evaluate full source provenance rather than silently modifying #2368 or its 18-stage pinned assembler.
3. In a **separately approved** disposable current-schema test, first prove exact historical stale denial returns the approved HTTP+SQLSTATE pair without retries and without terminal Work mutation, with the exact local PostgREST version/digest recorded safely. Then prove genuine independently signed governor/worker/outsider/no-seat, review → preflight → one `cancelled` lifecycle event and replay; check no fabricated Result/Acceptance/Done/Work/Clock. Blocked dependencies, revocation and concurrency require separate signed negatives.
4. Only **after source and workflow installation approval**, and another **separate explicit user authorization**, may the protected owner issue [#2664](https://github.com/optical-lift/noel-core-db/issues/2664) receive a run selector and execute once. The proposed carrier [draft #2665](https://github.com/optical-lift/noel-core-db/pull/2665) **must remain HELD** until it is reconciled with the newly approved source pins, including the signed bridge. It is not safe to trigger against the old `40001` cohort.
5. Atlas remains the universal main priority. Full U1A overlap, post-Result 6A eligibility, U5 household, U6 Event, P1/P3, U7 production and Titus releases remain separate. **No historical signed positive has yet run.**
