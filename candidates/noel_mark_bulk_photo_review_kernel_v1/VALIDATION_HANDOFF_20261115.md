# Bulk photo review — exact protected validation handoff (2026-11-15)

**Current status (latest, 2026-11-15):** isolated PostgreSQL 17 synthetic migration and role-denial checks passed; protected full production-schema clone and real signed owner/outsider tests remain pending. No production schema mutation. This packet must not be treated as release approval.

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

## 2026-11-15 source audit and pre-clone corrections

The proposal branch was merged forward from canonical `main` without merging this candidate into `main`. It is now GitHub-mergeable and retains the five unrelated Atlas-side commits unchanged.

Closer inspection found a **real SQL parse defect**: two PL/pgSQL `AS` delimiters had been reduced to one dollar sign, and one closing delimiter was also incomplete. These were repaired; every one of seven trigger functions now has a matching `AS $$ ... $$;` pair. Previous superficial 16/16 checks did not detect this.

Review-event custody also required a stricter transactional seal. `mark.photo_owner_review_events.event_transaction_id` is now PostgreSQL `xid8`, stamped **by the server-side BEFORE INSERT trigger** via `pg_current_xact_id()`. A new decision may be attached only when its current transaction ID matches the header's original transaction ID. That prevents adding new decisions to an already committed event. The event trigger also acquires a catalogue row lock and verifies consecutive per-owner sequence numbers, preventing out-of-order or competing concurrent event insertions. Original source proposals remain immutable; any correction must be a new owner event.

The clone-only SQL postconditions now include a **third, separate transaction** that attempts to add a decision to an earlier committed event and demands an explicit rejection. They also attempt a sequence gap and require it to be refused. The empty ASSIGN test was corrected to sequence 1 so that the deferred 1-to-600-decision check, rather than the sequence guard, is what actually rejects it.

**Validation after these corrections:** 17/17 source-structure checks pass on the actual GitHub blob contents, including seven balanced PL/pgSQL delimiters, five FORCE RLS tables, 11 guards, no role grants, immutable source SHA, transaction seal and corresponding synthetic tests. This is **NOT a passing PostgreSQL execution**; the clone and signed-permission gates remain outstanding, as do owner acceptance, migration generation and any production release.

The live Noel project is PostgreSQL 17.6; the `xid8` and `pg_current_xact_id()` APIs are documented for that version. The original Isaiah source is byte verified, capture ID 13, with `record_status='draft'`; its canonical/semantic/training authority is not elevated by this metadata. Neither `main`, any database schema nor Write Now runtime permissions were changed.


## Isolated PostgreSQL execution now passed (2026-11-15)

After the initial static review, the actual live Noel capture schema disclosed
`mark.captures.capture_id` as `GENERATED ALWAYS AS IDENTITY`. The fictional
capture fixture was corrected to `OVERRIDING SYSTEM VALUE`, as required by
PostgreSQL 17 when explicitly assigning that synthetic ID.

An independent no-secret, no-production, PostgreSQL 17 container workflow in
`.github/workflows/noel-mark-bulk-synthetic-pg17.yml` now exercises:
- a minimal synthetic `mark.captures` registry and fictional capture row;
- actual candidate DDL (five private FORCE RLS tables, guard triggers, invoker view);
- all clone-only postconditions, including incomplete event rejection, source
  rectangle checks, late-attached review rejection, owner sequence continuity,
  reclassification and append-only undo;
- nine explicit denied SELECT probes as `anon`, `authenticated` and
  `service_role` across source proposals, event headers and current review view;
- nine local packet-verifier tests, with real 13,860-record private packet tested
  only in the assistant's isolated research runtime (not in GitHub Actions).

**Verified GitHub outcome:** [workflow run #43734180016](https://github.com/optical-lift/noel-core-db/actions/runs/43734180016)
all steps passed on commit `f06379b0c28d645bcca28dcb234e747c479e6347`.
[Database Custody CI run #43734180023](https://github.com/optical-lift/noel-core-db/actions/runs/43734180023)
also passed. The private packet verifier and tests were independently checked
to match their committed Git blobs byte-for-byte.

**Do not confuse these probes with owner authorization:** the test database has
neither live signed sessions nor full production schema/roles. The synthetic
fixture's authentication-receipt string is fictional; current app roles cannot
read `mark` directly by design. This is NOT production release authority.
Source review/approval, canonical migration generation, protected full-schema
clone, owner-vs-outsider signed identity proof, authenticated Write Now bridge
and separately authorized production import remain outstanding.
