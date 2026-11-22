# First private MP3 delivery profile — held source extension

**Status:** source candidate only, not a migration or released RPC. This is the narrow prerequisite for the first authenticated Transcript Core native-audiobook receiving path and the existing private completion source. Keep this within the Noel Shared structural release lane and its existing protected clone/canonical migration process. No direct deployment or owner data creation.

## Existing canonical source

- Reuse existing private `transcript_core.delivery_profiles` table, unique `(workspace_id,profile_key,rule_version)`; no new table, Storage bucket, credential or content collection.
- Existing `public.transcript_core_create_manuscript_document`, `create_manuscript_revision`, `create_production`, `get_manuscript_revision` and `get_production` are already released under signed user/session and source workspace checks. Their actual original source requires independent byte and asset custody.
- Released internal `transcript_core.complete_verified_listening_production_v1` expects the exact versioned delivery profile and configuration for the same native workspace; it remains **unexposed and ungranted**.
- On first production rollout, no rows are seeded by this SQL; the user must select their existing canonical workspace and explicitly establish an exact profile while signed in as a current owner/editor.

## Fixed contract

`public.transcript_core_private_mp3_profile_self_api_v1(p_workspace_id uuid,p_establish boolean default false)`:

- The only recognized source profile is `private_audiobook_mp3` at `native_private_mp3_v1`.
- It records exact code-owned format requirements: MP3 / libmp3lame / 128k / mono / 48 kHz and `publication_approved=false`. The verified receiver must still independently check actual file bytes, audio format, original identity, export receipt and immutable private Storage object. The profile is **not** a content license or publishing grant.
- `false` is read-only for an already registered exact version, rejecting absence; `true` is a serial, idempotent establishment with one exact record; repeated requests return the same source receipt, not a new profile.
- Current `auth.uid()` and the signed nonanonymous JWT claims are compared against an active `auth.sessions` record, confirmed unbanned/unremoved user, unexpired session and current workspace owner/editor membership. No supplied Person, user, role or token override. Row locks guard the source during the transaction and expiry is rechecked.
- `anon`, `service_role`, and `PUBLIC` have no EXECUTE; `authenticated` only is granted the one exact RPC. The private delivery profile table retains its previous RLS and no direct client role table grants. The function uses a fixed safe `pg_catalog` search path, fixed SQL and no unbounded caller configuration or other RPC.
- Existing incompatible records under the same exact key/version fail with conflict; this API never edits them. Every return stays `publication_approved=false`.

## Proof and remaining gates

The existing `HELD listening delivery artifact isolated proof` workflow now runs the new source and fictional PostgreSQL 17 identity/ACL tests **in the same existing runner**. It must demonstrate idempotency, source conflict, authenticated owner/editor, denied anonymous/viewer/outsider, missing/mismatched/expired session, role revocation and service role denial; it must not seed production.

A local PostgreSQL fixture's `request.jwt.claims` values are NOT cryptographically signed. After isolated proof, use Noel's **existing protected signed GoTrue, immutable package admission and production-schema clone machinery** for an exact-source real identity/source/profile proof before canonical migration generation, protected rehearsal or a separately approved production release.

Do not use this held RPC as proof that the actual first original/production/profile source records already exist. The first selected private media transfer, library Publish operation, named subscription, Titus app release and independent listener acceptance are different gates.
