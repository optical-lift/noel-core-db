# Universal Program Import v2 — canonical source candidate

**Status:** source-only, unreleased. This is the persistence dependency for Atlas author-source import PR #408.

## First principle: one canonical author Program record
This candidate DOES NOT create another Program table, client Person, Goal engine, evidence engine, Today task or Program participant.

It reuses the already released, protected `atlas.personal_training_programs`, `atlas.personal_training_program_versions` and `atlas.personal_training_program_edit_receipts`, despite their first-domain names, preserving all existing version and security writer behavior. The v1 validator is extended to delegate **only** `personal_program_author_source_v2` packets to its separately guarded validator. The v1 packet remains valid and still passes original tests.

The four new `public.personal_program_author_*_self_api_v2` wrappers require the exact signed-in existing author/Principal and Personal Atlas entitlement; they use the **same v1 internal version writers** for create/save/review and the existing private storage. An author may have v1 and v2 Programs simultaneously. The v2 reader lists only v2 entries; a v2 edit or approval cannot overwrite a v1 item.

## Typed, reviewable source model
- Original source manifest with a SHA-256 of the author-selected source bytes, locator, title, and intended disclosure. The server stores the digest but **cannot independently authenticate Dropbox contents** without fetching the original source. No private source rows or Dropbox bearer tokens belong in public migrations.
- Separately keyed goals, intended success criteria and optional intended quantities.
- Source-cited components with intended functions, quantities/units, dated or unscheduled windows, prerequisites, and unresolved or author-labeled alternatives.
- Explicit separate author reconciliation proposals with original quote, source line, old/new statement, disposition, and rationale.
- No recipient, actual measurement, completion, participation or permission fact in authored versions.
- `author_intent` is not evidence that a method works; `proposed_disclosure` is not a permission grant; an author-approved alternative is not physiological equivalence.

This is the first generic source envelope but **not** automatic cross-domain abstraction promotion. A real second-domain author-to-recipient operation must prove the same mechanism before claiming universal implementation.

## Proof
- `candidate.sql`: source-only schema/RPC candidate, no rows and no migration version.
- `postconditions.sql`: no extra Program table, narrow four self-RPC grants, v1 RLS retained.
- `validation/atlas-universal-program-author-v2/test-author-v2.sql`: fictional household-budget and movement Program packets, v1/v2 cohabitation, immutable version history, replay, author-versus-outsider, and no invented actual results.
- `.github/workflows/atlas-universal-program-author-v2.yml`: isolated PostgreSQL 16 and 17 matrix only.

## Required continuation after candidate SQL passes
1. Reconcile repository owner review and mixed v1/v2 authoring-page routing. PR #408 has a local review preview but is not connected to canonical v2 RPCs yet.
2. Merge reviewed **candidate source** only under repository source custody rules, then use canonical migration generation `atlas_` with an exact owner issue.
3. Validate against a disposable production-schema clone, with **real signed GoTrue/PostgREST** author/foreign-Principal/entitlement-revocation tests for v2. Synthetic `SET ROLE` tests are not enough.
4. Separate exact-version protected production release, followed by source-authorized notebook save/review integration and real user observation.
5. Only after successful author review/import and a second-domain proof, decide whether to rename legacy first-domain table nomenclature without breaking callers.

**No production SQL, Program import, Katie account, recipient invitation, device access, or deployment is authorized by this draft.**
