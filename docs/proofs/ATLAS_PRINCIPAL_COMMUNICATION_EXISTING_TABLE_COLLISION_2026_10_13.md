# Atlas Principal Communication migration collision — October 13, 2026

## Confirmed cause from production GitHub Action

[Production release run 38457058283](https://github.com/optical-lift/noel-core-db/actions/runs/38457058283), job 115502398156, passed repository custody, migration ownership, Atlas live release-lane custody, and global reconciliation. The **Release exact canonical migration** step failed at the original `20260911174500` unconditional CREATE TABLE with:

```
ERROR: relation "communication_conversation_events" already exists
```

PostgreSQL began `BEGIN`, executed the first function and grants, then aborted on the collision. The migration's terminal COMMIT and ledger receipt were not reached. Production query confirms there is still no version `20260911174500` receipt.

## Read-only live-state findings

- The existing `atlas.communication_conversation_events` holds **25 rows**.
- Its eight columns, column nullability/defaults, seven constraints, exact conversation-order index and custody-guard trigger match the source migration's intended schema as observed.
- Row-level security is enabled, with no direct browser role policies on this table.
- `atlas.guard_communication_conversation_event_v1()` already exists.
- The migration's provider registration, Principal conversation admission/ingestion, and Principal conversation reads were not present as live functions at inspection.
- We did not identify a live migration ledger receipt containing that `CREATE TABLE`, so its original creation/custody provenance remains an independent question. Do not invent it.

## Proposed fix: repair only unreleased source

Modify **unreleased** source file `supabase/migrations/20260911174500_atlas_principal_communication_provider_v1.sql` without changing its version, function contracts, table name, or existing rows:

1. Before conditional reuse, a DO guard validates all eight catalog column signatures, all seven exact constraint definitions, and the exact identity of any existing index/trigger.
2. `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` allow reuse **only after** structural checks pass; the guard fails closed if an incompatible table has the same name.
3. Create the trigger only when absent, using the existing correctly defined guard function. An incompatible same-name trigger aborts the transaction before the index/function DDL.
4. Preserve the original version's atomic `BEGIN; ... COMMIT;` and the production release script's exact source/receipt hash requirement. Never insert a fabricated receipt or manually patch the production schema.
5. Any subsequent discrepancy must fail the protected production-schema clone proof and stop the migration rather than alter customer/source data.

## Release authority

Run existing production-schema-clone validation on the exact repaired branch commit and inspect the existing versioned validation. If green, merge the source fix through reviewed PR, independently recheck Git/source custody and protected release controls, then owner may rerun **only migration `20260911174500`** through main's manual protected release. Confirm post-release source hash/receipt and 25-row membership count unchanged. The remaining Gmail dependencies `20260911174700`, `20260919233031`, and generated `20261013193350` remain blocked until independently proven.

No production DDL was issued by this diagnosis or source proposal.
