# Atlas Program author margin notes v1 — reviewed-source candidate

**Status:** Draft structural candidate; **not migrated, deployed or live**. Owner source and custody review, disposable production-shaped clone tests, independently signed authorization tests, canonical migration generation, and separate protected Atlas release remain outstanding.

**Owning schema/release lane:** `atlas` / `atlas_`.

## Real outcome

An authenticated author can attach a private note to a program or exact component of an already approved authored Program, reopen it, edit its wording, mark it resolved or superseded, and inspect the actual history without modifying the approved Program. In the notebook, the author should type naturally; the application passes underlying identities without showing a database form.

No participation, patient record, task, Today obligation, recipient relationship or notification is created.

## Existing authority reused

- `atlas.personal_training_programs` and `atlas.personal_training_program_versions` remain the only canonical author Program and immutable approved version stores.
- `atlas.personal_training_author_guard_v1()` is the established signed-in Personal Atlas principal/entitlement guard.
- The new private note event table has a real Program FK and version FK. Every create checks the requested version belongs to that Program and that a component key occurs in the immutable approved packet.
- Authorization follows the **existing author-owned Principal** reader, not a new seat/employee role or access grant.
- Per-note historical revisions retain the *original component key and version*, allowing later component moves/rewrites without orphan deletion.
- The optional passage quote must literally occur in original approved instructions or the original source excerpt.
- No positional character offsets are used as sole anchor.

## Proposed RPC contract

Three authenticated, author-only wrappers in `public`:
- `personal_program_author_note_create_self_api_v1(program_id, anchor_version_id, component_key, anchor_excerpt, body, request_key)`.
- `personal_program_author_note_revise_self_api_v1(program_id, note_id, expected_revision, body, standing, request_key)`.
- `personal_program_author_notes_read_self_api_v1(program_id)`.

All source rights remain inside the private `atlas` functions; wrappers cannot independently grant visibility. `request_key` supports bounded deduplication. Updates are append-only and conflict on stale expected revision. `resolved`, `open` and `superseded` are note states only; they do not describe a participant, assignment, clinical result, approval, or Program version.

The read API returns the latest notes (up to 200) and the most recent 50 revisions for each, explicitly reporting truncation. Follow-on pagination or per-note full archival read is required before implying completeness for a larger record.

## Data authority & privacy

Table `atlas.personal_program_author_note_events` is private; RLS is enabled and forced; `anon`, `authenticated` and `service_role` have no direct table grant; internal functions are not callable by application roles. Three public wrappers grant execution only to `authenticated`, and each delegates to guarded owner-checked internals. No reader-role projection and no blanket organization seat grants.

Do not use notes in an eventual reader preview. Even where Program source metadata says `proposed_disclosure`, nothing grants a participant access to source material or annotation events.

## Source/tests

- `candidate.sql`: new note-event structure and three governed API operations, **no data rows**, wrapped in transaction.
- `fixture.sql`: fictional cross-domain learning example, retry and stale-revision tests, readback, approved Program immutability and second-author denial. Run only in a disposable clone, not in production. Its fake JWT contexts are **not equivalent** to independently signed GoTrue/PostgREST sessions.
- `postconditions.sql`: private table RLS, grants and API shape checks.
- No new deployment, CI definition, production grant, table or receipt has been made by committing these source files.

## Required full verification and release path

1. Review exact SQL against current `main` and the canonical Program author APIs; test in a disposable **production-shaped** clone. Include both PostgreSQL version and permission context, and verify the candidate does not break existing author v1/v2 behavior.
2. Independently signed author/other-author/unentitled/anonymous access tests, and entitlement revocation. Test concurrent idempotent create and conflicting revision writes, and compare Program version bytes/history before and after.
3. Record owner source/security/custody review. Merge *candidate source only* through the permitted Atlas lane if review passes.
4. Request migration generation through `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md` using an exact, already-merged candidate SHA and `atlas_` migration name; validate generated migration independently.
5. Owner authorization for an exact protected production database release under `docs/PRODUCTION_DATABASE_RELEASE.md`. Do **not** infer permission to release from this candidate PR.
6. After verified live receipt, implement the notebook UI/adapter against these real RPCs, including failed-save recovery and a signed desktop/mobile acceptance scenario on W1-B.

**Never put Katie's Program data, her private source files, or real margin-note text in SQL fixtures or Git.**
