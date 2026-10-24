# Foundry human source-custody production release candidate

**Prepared but not approved for production deployment.** This branch carries the identical migration bytes from immutable, protected no-cost candidate `20261024004500_shared_foundry_connected_workspace_gate1_signed_v1.sql` (validation PR #2135). It is not a replacement for release testing.

Feature scope: signed human-owned pending Foundry workspaces; private authority registry; public-to-private SECURITY INVOKER self RPCs; separate two-human evidence review and revocation; connected-People reviewer name selection, assigned-case inbox. A human review never elevates `workspace_authority_registry_v1.custody_review_state` to `reviewed`; no AI carrier commands or canonical Atlas People/Ledger changes.

**Dependencies before any merge/release**:
1. V3 free signed GoTrue/PostgREST protected clone run #2136 PASSES for this exact SQL.
2. All independent custody/grant/security reviews pass, including live source/lane custody.
3. Production release occurs only via canonical `main` and owner-triggered `Production release request: Shared 20261024004500` issue, protected `production` environment and DB migration receipt.
4. Atlas UI PRs #385 and #387 are server-gated and should only be released after database functions exist and signed smoke tests prove owner/reviewer operation. Feature flag stays OFF until app review.

No paid services or new production environments needed. Reviewers are existing signed-in Atlas Principals with a canonical active shared organization connection. If no reviewer is connected, user must connect another person first. Subject consent and AI source disclosure are separate later authorizations.
