# Foundry source custody — free signed clone validation only

**DO NOT MERGE OR DEPLOY THIS VALIDATION MIGRATION.** This is a disposable full production-schema-clone candidate, not a new production release.

Combined with the already [signed-Gate-2 verified candidate](https://github.com/optical-lift/noel-core-db/actions/runs/40039317502), this adds the [source-only human custody case](https://github.com/optical-lift/noel-core-db/pull/2121). It retains exact source references, operator attestation, bounded human-only actions, and a separate designated reviewer, plus signed decision and revocation through public SECURITY INVOKER wrappers.

The existing protected GitHub `Production Schema Clone Validation` workflow reads the production schema/roles read-only and runs this candidate with synthetic data in local Supabase (Postgres, GoTrue, PostgREST). The main-validator upgrade [PR #2120](https://github.com/optical-lift/noel-core-db/pull/2120) must merge first so this candidate's signed proof also tests independently signed reviewer/owner/cross-Principal isolation.

Tests must prove:
- distinct signed active owner/reviewer/outsider sessions;
- changed request / duplicate / forged user metadata fail to bypass owner/reviewer authority;
- anonymous/no-Principal/cross-owner operations denied;
- approved only by explicitly designated independent human, with exact source refs and review basis;
- revoked by owner/reviewer, with append-preserved change history;
- removed GoTrue session denied;
- private registry `custody_review_state='pending'` EVEN AFTER human approval, no AI authority;
- no new canonical Atlas Person, Ledger, task or Foundry snapshot mutations.

**An approved human review is evidence that a reviewer accepted a claimed source scope. It is not independently verified external consent, does not authenticate an original document, and does not grant AI carrier access or source-provider credentials.** Those require subsequent distinct controls.

Immutable candidate version `20261023235900`, lane `shared`, target `zirqkouammpwxlqfbsvf`, no paid Supabase branch.
