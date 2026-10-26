# Personal 15K Program Invitation — live-catalog collision preflight

**Date:** 2026-10-12. **Status:** READ-ONLY AUDIT + UNRELEASED SQL SOURCE CANDIDATE. **Source issue:** [#1461](https://github.com/optical-lift/noel-core-db/issues/1461). **Atlas Product Map draft:** [PR #242](https://github.com/optical-lift/atlas/pull/242).

## Source observations (real production catalog, not assumptions)

| Actual reality | Live owner / function already in Atlas | Gap for this pilot |
| --- | --- | --- |
| Paid Personal Atlas access | `personal_atlas_purchases`, `personal_atlas_access_status_self_api_v1()` | Do not change purchase or allow pre-purchase invitation to create Auth user |
| Principal identity | `principals`, `current_principal_id_v1()`, `begin_personal_atlas_self_api_v1(...)` | Invitation recipient must bind only *after* verified Auth email and real Principal |
| Organization employee invitation | `organization_access_invitations`, typed prepare/list/accept/decline/revoke RPCs | These confer institution-scoped access, not personal training participation |
| Personal life/goal/rhythm | `person_life_definitions`, `person_goal_rhythm_bindings`, `person_rhythm_opportunities` and corresponding APIs | Use only after acceptance, for the person's own goal/schedule, not for invitation or shared authority |
| Commitment Plan | `commitment_plans` with explicit custody kind and recipient | Pilot must not masquerade as institutional/Worker Day plan |
| Claim/evidence | `claim_records`, `claim_evidence_links` | Source provenance and actual results remain separate from program and invitation |
| Farm/community Programs | `production_programs`, `community_programs` (farm-scoped) | Neither is a person-owned 15K training method or invitation |
| Bounded external delivery | Product Map Relationship Delivery Membrane | Proposed invitation is not a delivery grant, account, relationship, or work obligation |

`atlas.current_principal_id_v1()` returns uuid, `atlas.personal_atlas_access_status_self_api_v1()` returns jsonb, both are current security-definer functions. `auth.users` has `id`, `email`, and `email_confirmed_at`. These observations were checked read-only on 2026-10-12. No live Program Invitation RPC was found.

## Domain-local proposal — not horizontal engine promotion

Candidate source: `candidates/atlas_personal_training_invitation_v1/candidate.sql`. Three bounded Atlas-owned identities:
- reviewed, immutable first-version **personal 15K training program**, with source record; human-approved proposal, not automated clinical advice;
- **personal training invitation** from sender to exact recipient email, with strict lifecycle;
- **personal training participation**, where each Principal owns their own adopted relation and sharing defaults **off**.

Six proposed narrow self APIs: create a reviewed program, issue invite, read *my verified-email pending* invites, accept/decline, sender revoke, participant withdraw. The candidate stores no public training rows and creates no account, email, checkout, scheduled workouts or medical observation. Later source must add sender browse, program version-revision, private recipient plan/observations, explicit shared-progress writer and projected read, and email transport/checkout-lifecycle integration.

## Security findings and required clone verification

- All three tables need RLS enabled **and** direct `anon`/`authenticated` table privileges revoked.
- Only named RPCs granted to authenticated; each must resolve `auth.uid()`, canonical Principal and Personal Atlas access. Verified recipient email is checked server-side in `auth.users` not client/user metadata.
- Send/accept must be guarded by own Principal and exact recipient; wrong user, pending Principal, unverified email, locked access, revoked/expired invitation and missing source fail closed.
- Duplicate create/send/accept is idempotent; reused key with changed program data must error.
- Source-only review is not PostgreSQL execution proof. Run real disposable production-schema clone tests as issuer, recipient, stranger, anonymous, locked account and expired/revoked/declined states. Inspect `pg_proc.prosecdef`, ACL, RLS, search paths and regressions under actual `authenticated`/service roles.
- Check recipient can withdraw and private progress cannot leak before or after withdrawal.
- Do not interpret an invitation UUID as a bearer credential. The first pilot intentionally admits only authenticated recipient-bound reads, and a general unauthenticated preview must be separately designed.
- This is an `atlas_` candidate, not `shared_`, because it does not change global identity contracts or cross-schema grants. Escalate if future requirements do.

## Release gate

1. Review this audit against current active Build Spine/recovery invariant locks; do not open a competing active finish train.
2. Review candidate SQL for correctness and missing product operations.
3. Merge reviewed **candidate source only** to `noel-core-db` main; use its canonical *migration source generation issue workflow* to obtain the actual timestamped migration and validator.
4. Run disposable production-shaped clone validation with role-switched negative tests and security advisers; no live DDL in the preflight.
5. Separate release authorization, DB protected release, exact post-release RPC proof, Atlas notebook feature implementation, sandbox Stripe test, and explicit Preview/Production release.

**Current state:** source proposed on a draft branch; no production database mutation or new RPC is claimed.
