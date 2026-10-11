# Atlas-owned authorization gate — Titus private Constellation

**Source-only candidate, not deployed.** No private user IDs, founder definitions, or research data enter this repository. It creates a read-only research capability grant keyed by the already-established `reality.entities` canonical Person and a backend-only Boolean authorization decision over a real, non-expired Supabase OAuth session, its exact client ID, the existing active `reality.auth_person_bindings`, and an independently recorded, active, reviewer-backed grant. **Zero grants are inserted.** Atlas account creation or OAuth consent does not imply research access. Revocation and expiry take effect on the next authenticated page request.

**Transport:** Atlas's existing Supabase Auth tenant serves as standard OAuth 2.1 / PKCE identity provider. The private Titus callback will verify the signed access token, request live authorization, and only then ask the two service-role-only Noel Scripture read RPCs. No browser/anonymous credentials can execute the private RPCs.

**Guardrails:** SQL is for governed migration generation/clone only. `auth.sessions` membership, `oauth_client_id` and expiry are checked fresh. A Titus preview OAuth client must be separately registered and configured; no client currently exists in the live project. Do not grant the user or Marshall access by guessing identities or by inserting temporary grants; human authorizing principal and evidence are required. The existing Session 11-specific handoff SQL remains on HOLD pending independent reconciliation. No Atlas/Titus main branch or production site is changed by this candidate.

**Negative test:** no permissions for anon/authenticated, no default grants, missing/foreign/null session denied, and schema under Atlas authority. Positive, revoked, expired, mismatched-client, and wrong-Person cases must be tested in isolated disposable fixtures before release.


## Atlas notebook native entry (October 11 addition)

This candidate now has **two access-status read functions over the same single Person/grant store**, not two login systems:

- `public.titus_constellation_viewer_allowed_v1(auth_user_id, session_id, oauth_client_id)`: standalone Titus OAuth-client-bound Auth session, as before.
- `public.titus_constellation_atlas_native_allowed_v1(auth_user_id, session_id)`: regular Atlas Auth session, where `auth.sessions.oauth_client_id IS NULL`. A valid ordinary Atlas session remains insufficient without an active `reality.auth_person_bindings`, canonical Person, explicit unexpired read-only grant and reviewer basis. The native function is service-role-only and fails closed. Neither path creates a grant.

Atlas native client branch: `optical-lift/atlas` PR #232. Atlas backend verifies the bearer with Supabase Auth before consulting the native service-only RPC. No browser can execute the RPC. The Atlas notebook Index is not a grant. The native Atlas host currently does not fetch private graph or Hebrew witnesses because the shared Titus-owned full-sky presenter is not yet integrated.

**Gate:** Both functions must be proven with positive/negative session fixtures including wrong Auth user, mismatched session, expired session, revoked or expired grant, active alternate user, unrelated OAuth client, inactive Person, and a dormant/empty grant store before migration generation/release. Production remains unchanged.
