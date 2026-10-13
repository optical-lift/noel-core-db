# Atlas production read-only schema preflight — 2026-10-13

## Scope and authorization

The user authorized testing within the *existing production space*, expressly declining a paid Supabase branch. All operations were **read-only** against `noel-core` (`zirqkouammpwxlqfbsvf`). No DDL, migration, synthetic Auth user, task, purchase, or charge was created.

This is a production schema compatibility preflight, **not** production deployment or a transactionally rolled-back integration test.

## Results

- 38 of 38 required existing columns were present across canonical Principal, orientation events, Discovery answers/questions, notebook spreads and sessions.
- The candidate Index-selection CTE ran on production tables with nonexistent synthetic Principal and user UUIDs and returned an empty JSON array, as expected. Real SQL parsing, table columns, joins and JSON extraction worked with no customer row returned.
- `atlas.personal_atlas_access_status_self_api_v1()` exists and its live function definition provides `eligible`, `accessState`, `active` and `locked` keys needed by the proposed task authorization guard; it requires `auth.uid()`.
- The `authenticated` and `anon` database roles exist, and `auth.users.id` and existing Principal custody structures are present.
- The new `atlas.task_entries` table, proposed task index name, and proposed task read/write/completion RPC names are all unused in production. No collision was found.
- Existing `atlas.tasks` and the existing Index function remain in production unchanged.

## Independent isolated tests already passed

- [Ephemeral PostgreSQL 38337292544](https://github.com/optical-lift/noel-core-db/actions/runs/38337292544): task create/read/date/complete/undo/idempotency, cross-user isolation, orientation-derived and evidence-derived Index sections.
- [Atlas build + Chromium 38337642195](https://github.com/optical-lift/atlas/actions/runs/38337642195): TypeScript/Next build, browser checkout recovery after first failure without paying again, and task completed state after notebook reload using safe RPC fixtures.

## Not established

A read-only preflight cannot execute a new function not yet installed. It did not create a task in the real production database, deploy new SQL, test real Stripe/Auth or establish a full-schema migration-clone receipt.

The source remains in draft candidate PRs; generated and reviewed canonical database migrations must be explicitly authorized before production release.

**Result:** zero-additional-infrastructure-cost production schema preflight **PASS**; feature is **not yet production-live**.
