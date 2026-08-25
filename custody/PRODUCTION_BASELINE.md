# Shared production baseline

This document defines the migration-authority fence for the physical `noel-core` Supabase project.

## Inherited history

Everything recorded in the production migration ledger from its first migration through and including:

- production version: `20260825203448`
- migration name: `state_progression_sales_inventory_version_drift_adjudication_v1`
- migration-body Git blob SHA-1: `d5907872292f8ad4bbe8c6b2b4bc282ce4dbea1b`
- full inherited ledger SHA-256: `f13deaef601b17928c14859d08367a790f6f1a12b717cd06784f45686baf4d6d`
- migration count at the fence: `2022`

constitutes inherited `noel-core` database history.

That history is **frozen inheritance**, not a second migration tree to reconstruct in this repository. Historical migration files may remain in product repositories as provenance. They must not be copied, renumbered, replayed, or treated as new canonical migrations here merely to reproduce the past.

## Authority after the fence

For every canonical database migration with a version later than `20260825203448`, `optical-lift/noel-core-db` is the single executable migration authority for the physical project.

Atlas, Noel, Write Now, and future application repositories may define database requirements and consume generated contracts, but they must not independently accumulate new canonical Supabase migration histories for this physical project.

A product repository may still merge source-custody repairs for migrations that are already inside the inherited fence. Such repairs are historical provenance only. Any change that would create a new production migration after the fence belongs here first.

## Ownership after the fence

New migration filenames must carry an explicit ownership prefix:

- `core` — Noel/core research infrastructure
- `atlas` — Atlas-owned schema changes
- `wnph` — Write Now Publishing House
- `shared` — deliberately cross-product database infrastructure
- `project` — physical-project administration that is not product semantic state

Sharing one physical Supabase project does not merge product semantics. Cross-schema dependencies remain explicit and minimal.

## Verification

`custody/production-baseline-v1.json` is the machine-readable fence. `scripts/read-production-baseline.sql` recomputes its production-ledger evidence. `scripts/check-custody.sh` prevents this repository from silently importing pre-fence migrations or accepting unowned post-fence migrations.

The fence itself makes no production DDL change. The first database architecture change after this baseline must originate as a migration in this repository.
