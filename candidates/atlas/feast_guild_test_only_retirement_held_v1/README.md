# HELD — remove the September 2026 Feast Guild test institution

**Status:** owner-directed data-removal source candidate, **UNMERGED, UNRELEASED, NOT RUN**. This directory is not under `supabase/migrations`. It cannot be deployed as a release without an independent current-schema clone review and exact owner-authorized Noel `atlas_` migration.

## Outcome

The owner stated that Feast Guild was only used for testing in Atlas and does not need a real institutional implementation for at least a year. Cancel all current Feast Guild native Ledger onboarding. **Remove** the specific September 14 reconstructed *test* Organization, its legacy Atlas Ledger, the one governing participation, and the one active root authority; do not archive them in Atlas as dummy operating entities.

Source [Atlas #653](https://github.com/optical-lift/atlas/pull/653), **merged**; [Atlas #652](https://github.com/optical-lift/atlas/pull/652) earlier institutional preflight finding and held [Noel #2811](https://github.com/optical-lift/noel-core-db/pull/2811) contain superseded onboarding direction. The old mixed-container references in migration `20260914000504_atlas_institutional_custody_reconstruction_v1.sql` are **not** the deletion target: current live Organization and Ledger IDs differ from its original historical IDs. Current reconstructed named pair was created September 14 with `canonicalInstitution` / `canonicalEndeavor` metadata, active statuses and clean current direct relation. No historic ID or real principal ID appears in this candidate.

## Live read-only preflight, November 16, 2026

- One exact current test Organization `feast_guild`, `onboarding_state='new'`, and one corresponding active old-Atlas Ledger.
- Exactly one active governing participation and one active root authority. No matching native `ledger.ledgers`, native case or seat, and zero activated delegated agent carriers/Work commands.
- Dynamic catalog scan: **224 inbound foreign keys** to the three target parent tables; exactly three matching dependent rows, and they are the expected one participation-to-Organization, one participation-to-Ledger and one root-to-Ledger.
- Separate scan of **44 unfenced UUID-reference columns** across Atlas/Ledger/Reality/public base tables: zero matches. Source custody, text Ledger Subject and sampled test-scope domain tables: no additional matching records. These are bounded observations, *not* permission to overlook JSON/unconstrained historical references.
- Existing real Elm, other canonical Persons, Works, operational data, Noel/Shared Intelligence/Titus and immutable migration receipts are **protected**.

## Source, test and release path

`retire_held.sql` is a single atomic PL/pgSQL DO statement. It fails closed if the identity is not exact, the graph is not exactly the expected one, a native migration/ledger exists, any new direct FK or common unconstrained UUID reference targets the test identity, or a string Ledger Subject reference survives. It then deletes in dependency order: 1 root, 1 participation, 1 Ledger, 1 Organization. It has **no CASCADE, new schema, grant, auth change, Work issue, worker/Person mutation or trigger bypass**. The primary data identity has a unique governed stable key, creation window, current owner-requested test classification and supporting reconstructed metadata; a *name match alone* cannot pass.

`pg17/fixture.sql` and `pg17/run_synthetic.sh` provide disposable **synthetic PG17** positive and seven negative cases. They have no production address or private Person IDs, and do not authorize release. Run only inside a newly isolated PostgreSQL 17 service with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` set; the runner creates independent ephemeral databases and never points at Noel or Supabase.

**Next mandatory gates before real deletion:**

1. Independent actual-current-schema protected clone and genuine signed actor/permission/row no-loss checks (synthetic fixture alone is insufficient).
2. Fresh exact owner review of the protected four-record deletion source and affected audit consumers, no unexamined JSON/history reliance, and explicit check that release workers are idle for the target.
3. Generate an `atlas_` migration using the governed Noel release tooling; obtain separately approved production release, and independently verify physical absence of this exact test Organization/Ledger/root/participation, no missing Elm/Person/Work and no native ghost identity.
4. Update the **existing** Atlas integration completion register with actual migration version, run proof, post-release readback. Do not mark deleted from source-only tests.

The independent **P0 physical retirement of superseded operational tables** before outsider launch remains separate. Universal original Work issuance must be tested against a properly native governed Ledger other than Feast Guild.
