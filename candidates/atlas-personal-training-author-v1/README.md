# Atlas Build 1 — author-owned training Program drafts and versions

**Status:** reviewed-source candidate, not a migration or release. **Date:** 2026-10-24.

Source follow-through for [Atlas rebased draft PR #398](https://github.com/optical-lift/atlas/pull/398) and [DB issue #2144](https://github.com/optical-lift/noel-core-db/issues/2144).
It supersedes the **author-program portion** of the unreleased, hardcoded-15K co-participant draft [DB PR #1462](https://github.com/optical-lift/noel-core-db/pull/1462), which MUST NOT be merged together with this candidate.

## Canonical roles

- **Program draft**: `atlas.personal_training_programs` is an *author-owned training* draft, not an accepted recipient undertaking; an idempotency key establishes the first draft and subsequent saves need an expected revision.
- **Edit idempotency receipt**: `atlas.personal_training_program_edit_receipts` preserves the original request key, expected/result revision, and packet digest for every successful edit; it is RLS-protected and has no direct authenticated table grants.
- **Reviewed version**: `atlas.personal_training_program_versions` contains an exact immutable approved author packet, its Postgres-side SHA-256 digest, approving signed-in Auth user, revision and timestamp.
- **Source manifest**: `sources[].locator` is author-declared provenance, not independent proof of source ownership or availability. `disclosure` expresses intended handling, **not a recipient grant**.
- **Functional statements**: `function.intendedChange` and `alternatives[].relation` preserve author intentions and claims, NOT medically/physiologically confirmed equivalence or a safety certification.
- **Recipient**: deliberately absent. No invitation, enrolled client, private body data, physical outcome, Goal, Task, or Clock write is possible here.

The packet contract matches the application preflight `personal_training_program_author_source_v1`. Explicit author review is a separately authenticated command with a digest + expected revision guard; a UI approval checkbox does not establish a durable review.

## Auth and custody

The four exposed `public.personal_training_author_{create,save,approve,read}_self_api_v1` functions use server-resolved `auth.uid()`, `atlas.current_principal_id_v1()`, and `atlas.personal_atlas_access_status_self_api_v1()`. Caller-supplied Person/Principal/owner IDs are never accepted. Tables have RLS enabled and no direct anonymous or authenticated access. Only authenticated callers may execute named public wrappers; all internal functions are revoked. Reviewed rows reject UPDATE/DELETE, including privileged ordinary writes.

The author reader currently returns their private source manifest and all version packets. **Do not reuse it as a recipient reader.** Later adoption must build a distinct source-filtered and permissioned projection.

## Source commands

1. `create(p_packet,p_request_key)` — authenticated author creates draft or idempotently returns existing creation identity.
2. `save(p_program_id,p_expected_revision,p_packet,p_request_key)` — authenticated author revises a draft, never edits approved versions. Every successful edit now writes a private durable idempotency receipt. Exact current-revision retries return their original outcome; a historical retry after later edits is rejected as stale, and a reused key with changed inputs is rejected as a conflict.
3. `approve(p_program_id,p_expected_revision,p_expected_digest,p_request_key)` — reviewed immutable version or idempotent replay, fail closed on stale digest/revision.
4. `read(p_program_id DEFAULT NULL)` — author-only listing (latest 100) or detailed source/version history; no recipient view.

**Authorization boundary:** Every command checks signed-in Principal and eligible Personal Atlas. Future valid access-state changes still require explicit release review.

## Proof files

- `candidate.sql`: source-only DDL/RPC and access rules, NOT executable migration custody.
- `postconditions.sql`: RLS/direct privileges/RPC structural checks.
- `validation/atlas-personal-training-author-v1/fixture-schema.sql`: isolated PostgreSQL 16 and 17 with two fictional users.
- `validation/atlas-personal-training-author-v1/test-author-lifecycle.sql`: create, retry, digest rejection, approval, draft revision, 2-version immutability, foreign user and locked-access denials.
- `.github/workflows/atlas-personal-training-author-v1.yml`: no-secrets isolated PostgreSQL 16/17 matrix, candidate-scoped checks only; not a production-shaped Supabase clone.

## Gates before release

1. Review concurrent Build 2 Person invitation/Foundry locks; preserve one source of truth for invitation and Program adoption.
2. Verify exact candidate source, isolated SQL and security checks pass before source merge. The canonical generator requires reviewed candidate bytes on `main`; after generation, perform the separately governed production-shaped clone and signed-user authorization tests (including wrong Principal, expired or revoked access, RLS/ACL and source disclosure) **before production release**. Do not mistake generation or synthetic tests for permission to deploy.
3. Review sensitive author source custody; Git fixtures are fictional, and the real Katie document must not be copied into public source.
4. Merge reviewed **candidate source** only after approval. Use the **owner-controlled canonical migration source generation workflow** to obtain an `atlas_` migration, then separately validate and authorize protected production release. No ad hoc live DDL.
5. Only after released RPC verification may `optical-lift/atlas` wire its existing Index/notebook authoring surface. The app source preflight is not canonical approval.

This candidate is **training-domain proof one**. No horizontal Program Kernel is declared until an unrelated recipient-executed second domain proves shared operations.

**Changes deliberately NOT performed:** No production SQL, migrations, account creation, invitations, email, payments, Notebook UI activation, health data reading, or deployment.
