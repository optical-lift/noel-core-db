# Foundry human source-custody production release candidate

> **2026-10-24 governing correction — mandatory second code reviewer superseded.**
> This page is preserved as historical release evidence. Its earlier blanket
> requirement for a separate human developer to approve GitHub security,
> custody, or grant code is replaced by the [solo-owner source/security/custody
> review rule](SOLO_OWNER_RELEASE_REVIEW_20261024.md). The owner can record
> the source review and authorize the exact protected release after the
> required verification. No independent GitHub reviewer is required by the
> project. **Different signed humans for actual Foundry source review,
> genuine consent and independent sign-in tests are NOT waived.**
> This note does not assert that the particular original release candidate
> was newly reviewed, merged, or deployed.

**Prepared, clone-validated, but not approved for production deployment.** This draft branch carries migration `20261024010000_shared_foundry_connected_workspace_gate1_signed_v1.sql` byte-for-byte identical to the immutable validation PR #2139 at commit `fe817fe0ae9af6484ef238d3c25d57e5fc67498e` (Git blob `a1ffbafa3f43f52996d72ec9b8836390eec107d0`). The validation artifact is never merged or deployed.

## Protected no-cost validation evidence — 2026-10-24

- Original validation issue #2140 was cancelled during shared queue contention; no other run was preempted for this candidate.
- Retry #2146 applied the migration, fixture, and postconditions but stopped on a test-only Python `denied` NameError. The two assertions were corrected to use the existing `forbidden` helper in merged test-only PR #2147; the candidate migration and immutable SHA were unchanged.
- Owner-triggered retry issue #2148 completed successfully in protected GitHub Actions run [40053046692](https://github.com/optical-lift/noel-core-db/actions/runs/40053046692), using canonical main validator commit `d37fdd5329685ece5cec06f61db10d406aa140c8`.
- The disposable production-schema clone applied the exact candidate SQL and DML-safe fixture, passed SQL postconditions, and reported **zero new Atlas schema-lint errors** (14 pre-existing findings unchanged).
- Saved signed GoTrue/PostgREST receipts confirm owner-only workspace Index; real active connected reviewer selection; assigned reviewer inbox; distinct human approval and revocation; cross-Principal, anonymous, unbound, and revoked-session denial; stable retries; preserved original-source history; no canonical Person/Ledger mutation and **no AI carrier grant**.
- Production was read for structure and roles only. No production DDL, paid development branch, real subject files, or source-provider access occurred.

## Remaining independent gates — NOT SATISFIED by clone success

1. Human independent custody, grant, security, and live source/lane authorization review must explicitly approve the production release scope. This clone validates code behavior, not actual third-party consent or ownership of a source.
2. Keep this release PR #2137 **draft** until authorized. Merge the reviewed migration to canonical `main` only after approval; the immutable validation PR #2139 must remain unmerged.
3. Production migration must use a separately authorized owner-triggered `Production release request: Shared 20261024010000` issue, protected `production` environment, and a verified migration receipt. No validation issue is a release request.
4. Atlas notebook PRs #385 and #387 remain draft, with their server feature gate **OFF**, until the production database functions exist, app review and deployment are approved, and two independent signed browser sessions complete a live owner/reviewer smoke test. Do not call the feature live before all three receipts exist.

The feature supports human-owned provisional Foundry workspaces and bounded independent **human** source-scope review only. A human review never elevates `workspace_authority_registry_v1.custody_review_state` to `reviewed`; it never grants AI carrier commands, creates canonical Atlas People/Ledgers, or establishes subject consent. A reviewer must be an existing signed-in Atlas Principal with an active shared organization connection. If none exists, connect a real person first; do not invent a reviewer identity. Any later AI access to another person's material requires separate source-specific authorization.
