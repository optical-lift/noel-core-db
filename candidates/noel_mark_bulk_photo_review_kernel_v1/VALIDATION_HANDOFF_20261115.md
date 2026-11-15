# Bulk photo review — exact protected validation handoff (2026-11-15)

**Current status:** source static checks passed; candidate and synthetic fixture have NOT yet been executed in PostgreSQL. No production schema mutation. This packet must not be treated as release approval.

## Candidate package on draft PR #2797

- `candidates/noel_mark_bulk_photo_review_kernel_v1/candidate.sql` — five private tables, seven invoker-only guard functions, 11 source-bound / immutable / complete-event triggers, forced RLS with no direct application grants, an invoker current-state view.
- `candidates/noel_mark_bulk_photo_review_kernel_v1/fixture.sql` — **one synthetic** `mark.captures` row, applied by the existing clone harness before candidate SQL; it contains no real original photo, private reviews or personal identifiers.
- `candidates/noel_mark_bulk_photo_review_kernel_v1/postconditions.sql` — PostgreSQL catalog assertions and synthetic lifecycle tests, applied AFTER candidate SQL, checking source integrity, incomplete census, out-of-bounds corrections, immutable proposals, refused unauthorized training flags, review/reclassification, outsider-key undo denial and legitimate append-only undo.

The fixture passed the existing `validate-production-schema-clone.sh` source-safety rule (INSERT-only; no DDL, procedural code, privilege changes or executable imports). A separate source static review checked 16 conditions including forced RLS on all five tables, absent broad grants, deferred event completeness and source SHA/dimension recheck on admission. **These are static results, not a successful database clone.**

## Owner-reviewed generation path

The repository's source generator requires the reviewed candidate files to be on **canonical `main`**. Do not open a generator issue from this unmerged draft PR. After explicit owner review and merge of exactly the candidate source:

```
Title:
Migration generation request: Noel noel_mark_bulk_photo_review_kernel_v1

Body:
release_lane: noel
migration_name: noel_mark_bulk_photo_review_kernel_v1
candidate_sha: <immutable 40-character SHA already on main>
candidate_path: candidates/noel_mark_bulk_photo_review_kernel_v1/candidate.sql
fixture_path: candidates/noel_mark_bulk_photo_review_kernel_v1/fixture.sql
validation_path: candidates/noel_mark_bulk_photo_review_kernel_v1/postconditions.sql
```

The protected workflow installs the pinned Supabase CLI `2.116.0` and generates the **real** 14-digit migration version. Do not invent a timestamp or bypass this identity gate. Supabase CLI v3 changed behavior in November 2026; the pinned source generator deliberately continues using v2.

After source generation, open a separate generated-package PR, review its exact SHA, and request a disposable full-schema test by an owner-authored issue:

```
Title:
Production schema validation request: Noel <14-digit-migration-version>

Body:
migration_version: <14-digit-migration-version>
release_lane: noel
production_target: zirqkouammpwxlqfbsvf
candidate_sha: <immutable generated-package commit SHA>
```

This validator reads the **schema and roles only** from the protected production snapshot and applies the candidate + synthetic fixture/postconditions exclusively on a disposable local PostgreSQL database. It reports baseline/candidate lint and attached diagnostic artifacts; it does NOT deploy anything.

## Signed authorization proof remains a separate mandatory gate

The SQL source never grants `anon`, `authenticated` or the generic `service_role` direct access to the `mark` schema. A real owner-accessible bridge is not yet implemented. The `owner_actor_key` and `verified_auth_receipt_key` columns are audit metadata and **not** authentication by themselves. PostgreSQL synthetic strings in the fixture are NOT verified owner sessions.

Before any production write enablement, implement a separately reviewed owner-scoped reader (read-only first), using actual verified signed sessions with explicit per-capture rights and revocation, then prove:

- real owner can read only authorized physical catalogue and matching review history;
- signed outsider, anonymous caller, invalid/expired/revoked session, forged owner key or source SHA cannot read or append;
- explicit source SHA and original-locator match; no untrusted actor ID, semantic label, full ink mask, model training approval, or client-provided authority accepted;
- idempotent, atomic 1–600 batch append and original-machine rectangle immutability; duplicate conflicting event payload denied;
- no source photo or derived original pixels in API, logs, Git or direct Data API roles.

Only after a passing disposable clone AND signed acceptance is a separately scoped **exact-version owner production approval** appropriate. Merging or generating source is not production authorization.

## Existing source readiness

The original 1QIsa(a) JPEG is already `mark.captures.capture_id=13`, byte verified, native 29696 × 5013 and matching the original SHA; its record state is still `draft`, not `frozen`. It must not be presented as final ink-boundary or model-training authority. The private importer has already staged 13,860 source-located component proposals, 9,908 grouped into 96 provisional bins, but no production rows were inserted.

## Local execution limitation of this work

The current assistant runtime does not contain `psql`, `postgres`, `supabase` CLI or Docker, and external package retrieval is unavailable. Running candidate DDL through a transaction against the **live production database**, even with an intended rollback, would violate this repository's protected release boundary. No substitute such execution was attempted.
