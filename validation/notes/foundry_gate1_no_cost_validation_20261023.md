# Zero-cost Foundry Gate 1 — protected production-schema clone validation

This **draft branch is NOT a production release**. It packages the reviewed source-only PRs
[#2093](https://github.com/optical-lift/noel-core-db/pull/2093),
[#2094](https://github.com/optical-lift/noel-core-db/pull/2094), and
[#2107](https://github.com/optical-lift/noel-core-db/pull/2107) into one immutable
SQL candidate for the repository's **existing public-repository GitHub Actions**
workflow `.github/workflows/production-schema-clone-validation.yml`.

**Candidate version:** `20261023222800`
**Release lane for cross-schema Foundry/Atlas authority:** `shared`.

The existing workflow is triggered by an owner-authored issue with:

```text
Production schema validation request: Shared 20261023222800

migration_version: 20261023222800
release_lane: shared
production_target: zirqkouammpwxlqfbsvf
candidate_sha: <exact immutable source commit>
```

It reads the **schema and custom roles only** from the protected production
environment, creates a fresh local disposable database on a GitHub-hosted
standard Ubuntu runner, applies the exact candidate **there only**, and runs
postconditions. No Supabase branch/project is created, so there is no hourly
database charge. For this **public** repo, standard GitHub-hosted runner minutes
are free. Production writes are prohibited by the existing protected workflow.

## Candidate and tests

- `supabase/migrations/20261023222800_shared_foundry_connected_workspace_gate1_validation_candidate_v1.sql` — registry, Foundry-target-specific delegated-agent checks, pending-only human workspace preparation; one transaction. **Not authorized for release**.
- `validation/migrations/20261023222800_shared_foundry_connected_workspace_gate1_validation_candidate_v1.sql` — registry/function/grant assertions plus synthetic negative/positive tests, each isolated with `ROLLBACK`. No customer data is needed.

The synthetic test matrices prove only database-side contracts. Signed GoTrue
transport, different human operators, real carrier MCP authentication,
production deployment, and David's subject consent remain separate gates.

## Important stop conditions

- The GitHub environment/secrets may be unavailable; do not bypass environment
  protection or substitute production execute_sql with BEGIN/ROLLBACK.
- If the protected schema snapshot fails, report the blocker; do not infer
  schema compatibility from successful static checks.
- No production migration, pre-Ledger authority grant, or new human/subject
  Person is created by validation.
- The five historical Foundry workspaces and 93 events remain intact.
