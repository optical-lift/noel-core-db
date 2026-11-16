# noel-core-db

> **P0 ATLAS OWNER LAUNCH BLOCKER (2026-11-16):** The new universal Atlas will **NOT launch with any legacy Atlas operational table still installed**. Legacy Task, farm-membership, release-queue and other superseded operational tables must be physically deleted after necessary actual/history is lawfully reconciled to canonical source; no permanent compatibility/shadow tables. Valid `atlas.work_items` and other canonical authorities stay, regardless of origin date. **No destructive migration or bypass is approved by this policy itself.** Noel owns reviewed `atlas_` source migrations, independent signed no-loss/denial and separately approved production `DROP ... RESTRICT` proof. See [owner P0 issue #532](https://github.com/optical-lift/atlas/issues/532) and [current Atlas prelaunch inventory](https://github.com/optical-lift/atlas/blob/main/docs/integration/ATLAS_PRELAUNCH_LEGACY_TABLE_RETIREMENT_20261116.md).

Executable database custody for the shared `noel-core` Supabase project.

This repository owns canonical database migrations, database custody tests, schema ownership boundaries, and generated database contracts for the physical Supabase project used by Noel, Atlas, Titus, and Write Now.

The inherited production history is now fenced in `custody/production-baseline-v1.json`. Everything in the production migration ledger through version `20260825203448` is frozen inherited history; it is not recopied into this repository. Canonical migrations after that fence originate here.

Planned schema ownership:

- `core`, `draft`, `intelligence` — Noel textual/manuscript evidence, Reality Pools and private research (existing inherited boundaries preserved)
- `titus` — private Titus formation/learner custody
- `atlas` — Atlas operational system
- `wnph` — Write Now publishing custody
- `wnph_api` — governed Write Now application surface

Application repositories may retain pre-fence migration files as provenance and may propose new database requirements, but they must not become competing post-fence migration authorities for the shared Supabase project.

Post-fence Atlas migrations use the `atlas_` logical-owner prefix, including incident repairs whose live migration identity is normalized to the canonical source filename before custody verification.

**Start here for domain-safe work:** [`AGENTS.md`](AGENTS.md), [`docs/DOMAIN_WORK_ISOLATION_V1.md`](docs/DOMAIN_WORK_ISOLATION_V1.md), [`docs/NOEL_RESEARCH_OPERATIONS.md`](docs/NOEL_RESEARCH_OPERATIONS.md), and [`docs/PRIVATE_RESEARCH_SOURCE_CUSTODY.md`](docs/PRIVATE_RESEARCH_SOURCE_CUSTODY.md). Ordinary dictionary/ledger records are private data transactions, **not migrations**. Structural releases use separately owned `noel_`, `atlas_`, `titus_`, `wnph_`, or `shared_` migrations. Global custody remains strict on canonical main/scheduled checks, while independent PRs report unrelated live source debt without inheriting it as a failure.

See `custody/PRODUCTION_BASELINE.md` for the cutover contract and `schemas/OWNERSHIP.md` for logical schema boundaries.

Production-shaped candidate migrations are validated through the same inspectable local/CI command documented in `docs/PRODUCTION_SCHEMA_CLONE_VALIDATION.md`. The gate records baseline and post-candidate Atlas lint reports, blocks only candidate-introduced errors, and uploads durable diagnostics for every run.
