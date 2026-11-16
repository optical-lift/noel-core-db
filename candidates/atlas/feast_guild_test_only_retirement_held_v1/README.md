# HELD — remove the September 2026 Feast Guild test institution

**Status:** owner-directed data-removal source candidate, **UNMERGED, UNRELEASED, never executed against production**. This directory is not under `supabase/migrations`. The independent actual-schema, synthetic-data clone completed successfully on November 16 ([run #43940318397](https://github.com/optical-lift/noel-core-db/actions/runs/43940318397)); a separately owner-authorized production release is still required.

## Outcome

The owner stated that Feast Guild was only used for testing in Atlas and does not need a real institutional implementation for at least a year. Cancel all current Feast Guild native Ledger onboarding. **Remove** the specific September 14 reconstructed *test* Organization, its legacy Atlas Ledger, the one governing participation, and the one active root authority; do not archive them in Atlas as dummy operating entities.

Source [Atlas #653](https://github.com/optical-lift/atlas/pull/653), **merged**; [Atlas #652](https://github.com/optical-lift/atlas/pull/652) earlier institutional preflight finding and held [Noel #2811](https://github.com/optical-lift/noel-core-db/pull/2811) contain superseded onboarding direction. The old mixed-container references in migration `20260914000504_atlas_institutional_custody_reconstruction_v1.sql` are **not** the deletion target: current live Organization and Ledger IDs differ from its original historical IDs. Current reconstructed named pair was created September 14 with `canonicalInstitution` / `canonicalEndeavor` metadata, active statuses and clean current direct relation. No historic ID or real principal ID appears in this candidate.

## Live read-only preflight, November 16, 2026

- One exact current test Organization `feast_guild`, `onboarding_state='new'`, and one corresponding active old-Atlas Ledger.
- Exactly one active governing participation and one active root authority. No matching native `ledger.ledgers`, native case or seat, and zero activated delegated agent carriers/Work commands.
- Dynamic catalog scan: **224 inbound foreign keys** to the three target parent tables; exactly three matching dependent rows, and they are the expected one participation-to-Organization, one participation-to-Ledger and one root-to-Ledger.
- Separate scan of **139 wider non-FK UUID-reference columns** across Atlas/Ledger/Reality/public base tables: zero matches. A separate read-only scan of **128 JSON columns in tables with reported live rows** found zero matching target IDs. Source custody, text Ledger Subject and sampled test-scope domain tables: no additional matching records. These are bounded observations, *not* permission to overlook JSON/unconstrained historical references.
- Existing real Elm, other canonical Persons, Works, operational data, Noel/Shared Intelligence/Titus and immutable migration receipts are **protected**.

## Source, test and release path

`retire_held.sql` is a single atomic PL/pgSQL DO statement. It fails closed if the identity is not exact, the graph is not exactly the expected one, a native migration/ledger exists, any new direct FK or common unconstrained UUID reference targets the test identity, or a string Ledger Subject reference survives. It then deletes in dependency order: 1 root, 1 participation, 1 Ledger, 1 Organization. It has **no CASCADE, new schema, grant, auth change, Work issue, worker/Person mutation or trigger bypass**. The primary data identity has a unique governed stable key, creation window, current owner-requested test classification and supporting reconstructed metadata; a *name match alone* cannot pass.

`pg17/fixture.sql` and `pg17/run_synthetic.sh` provide disposable **synthetic PG17** positive and eight negative cases. They have no production address or private Person IDs, and do not authorize release. Run only inside a newly isolated PostgreSQL 17 service with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` set; the runner creates independent ephemeral databases and never points at Noel or Supabase.

**Verification completed November 16:** Nine synthetic PostgreSQL 17 cases (one positive, eight negative) passed [run #43940010078](https://github.com/optical-lift/noel-core-db/actions/runs/43940010078); byte-identical source passed a **protected, read-only-production-snapshot, actual-current-schema disposable clone**, with fictional Elm/Principal/Person preserved, [run #43940318397](https://github.com/optical-lift/noel-core-db/actions/runs/43940318397). Zero new schema lint errors; fourteen inherited findings unchanged. No real source rows were copied or deleted.

**Next mandatory gates before real deletion:**

1. Exact source blob `fc894bdc3265cd49bd6e1ac26427ee7889917986` is staged byte-for-byte in **DRAFT [Noel PR #2815](https://github.com/optical-lift/noel-core-db/pull/2815)** as CLI-generated version `20261116194344_atlas_feast_guild_test_only_retirement_v1.sql`, with exact synthetic fixture and postconditions. An independent exact-version schema validation was requested via [issue #2816](https://github.com/optical-lift/noel-core-db/issues/2816); its outcome must be checked separately. Neither source nor clone authorizes production.
2. Fresh exact owner review of the protected four-record deletion source, affected audit consumers and application dependencies, and explicit check that release workers are idle for the target; do not confuse genuine schema clone proof with real signed user/browser acceptance if applicable.
3. Complete exact-version validation, owner-authorize source merge and **separately** authorize production release for Atlas version `20261116194344` to project `zirqkouammpwxlqfbsvf`, then independently verify physical absence of this exact test Organization/Ledger/root/participation and preserve Elm/Person/Work/history.
4. Update the **existing** Atlas integration completion register with actual release/receipt and post-release readback. Do not mark deleted from source-only tests.

The independent **P0 physical retirement of superseded operational tables** before outsider launch remains separate. Universal original Work issuance must be tested against a properly native governed Ledger other than Feast Guild.
