# Gate 2 signed GoTrue validation — disposable local clone

**Source-only validation candidate. DO NOT MERGE OR DEPLOY.**

The protected, no-cost local signed-auth validator is now in [Noel main PR #2115](https://github.com/optical-lift/noel-core-db/pull/2115), merge `1606ce0d240f16fe7904763877218fe446de0111`. It adds source-exact `shared_foundry_connected_workspace_gate1_signed_v1` dispatch and uses real local GoTrue + PostgREST with two independent owner/outsider signed Principals and one Auth user without a Principal.

Immutable candidate files:
- `supabase/migrations/20261023230500_shared_foundry_connected_workspace_gate1_signed_v1.sql`: private registry, existing delegated-agent Foundry scope, pending-only human intake and owner-only preparation inspection; both operations require an extant GoTrue session and explicitly return 42501 on denied human authority.
- `validation/fixtures/20261023230500_shared_foundry_connected_workspace_gate1_signed_v1.sql`: only fictional users/Principals.
- `validation/migrations/20261023230500_shared_foundry_connected_workspace_gate1_signed_v1.sql`: 3 structural postconditions and 2 transaction-rolled-back synthetic authorization suites.

The real signed Python test runs from **canonical main**, not this candidate, and proves:
- actual local JWT `sub` and `session_id` match DB sessions;
- owner can prepare a *pending* external-subject workspace; idempotent retries preserve its ID/event; changed payload is rejected;
- another signed Principal, no-Principal user and anonymous client are denied owner-only reads;
- editable `user_metadata` does not confer ownership;
- every workspace remains unreviewed with zero consent basis; no canonical Person, Ledger, Work or snapshot writes;
- removing `auth.sessions` revokes a still-unexpired real signed JWT.

Protected validation issue contract:
```text
Production schema validation request: Shared 20261023230500

migration_version: 20261023230500
release_lane: shared
production_target: zirqkouammpwxlqfbsvf
candidate_sha: <IMMUTABLE PR HEAD SHA>
```

The workflow reads the production schema/roles only, creates a disposable LOCAL Supabase database and Auth/REST stack on free public-repo GitHub Actions, and applies the candidate locally. It does not write production or create a billable Supabase branch.

**This is not a custody review/consent approval tool; `custody_review_state` remains pending.** No MCP/API external carrier is authorized by Gate 2.
