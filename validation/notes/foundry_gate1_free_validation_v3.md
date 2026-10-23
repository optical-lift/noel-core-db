# Foundry Gate 1 protected clone validation V3 (no charge)

This candidate is **validation only; do not merge/deploy**.

The previous [V2 free local-clone validation run](https://github.com/optical-lift/noel-core-db/actions/runs/40034275745) successfully restored the production schema and applied all Gate 1 SQL (CREATE TABLE, two patched delegated-agent functions, pending-only human self API, EXECUTE ACL). All three structural postconditions passed. It then failed in the first rollback-only synthetic authorization test: the test's registry INSERT did not provide the new required `creation_request_id` introduced in registry PR #2093.

V3 retains the **same executable candidate SQL** as V2 and changes only the synthetic target-authority test fixture: the INSERT explicitly supplies `gen_random_uuid()` as the owner-scoped creation ID. The underlying fixture source on PR #2094 is corrected separately.

Running the already-established `.github/workflows/production-schema-clone-validation.yml` on this candidate must access production for schema and roles **read-only** and execute all candidate SQL in local disposable PostgreSQL on a standard public GitHub runner.

Required validation issue:

```
Production schema validation request: Shared 20261023225100

migration_version: 20261023225100
release_lane: shared
production_target: zirqkouammpwxlqfbsvf
candidate_sha: <exact head commit SHA of this PR>
```

The tests must prove authorizations and roll back the synthetic data; a passing workflow does not constitute real signed GoTrue or MCP authorization, ownership of a third-party subject, production deployment, or canonical Atlas write authority.
