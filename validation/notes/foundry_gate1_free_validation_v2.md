# Foundry Gate 1 free schema clone — corrected immutable V2

The protected [first validation run](https://github.com/optical-lift/noel-core-db/actions/runs/40033486128) failed at **candidate migration SQL parsing** because the composed delegated-agent function bodies lacked closing SQL statement semicolons after `$function$`. It restored the complete production schema into a disposable local Postgres database and made **no production writes**. This V2 candidate terminates both function declarations explicitly.

The underlying source candidate was also corrected in PR #2094. This immutable candidate contains the complete three-part pre-Ledger Gate 1 delta in one transactional SQL file: private workspace registry (PR #2093), existing delegated target authority extension (PR #2094), and the pending-only human workspace preparation function (PR #2107).

The matching `validation/migrations/20261023223900_shared_foundry_connected_workspace_gate1_local_validation_v2.sql` runs RLS, privilege, schema, source and two rollback-only synthetic authorization suites against the **local disposable database**. This PR is solely a schema clone validation artifact and **must not be merged or deployed**.

Request the existing no-cost, owner-triggered `.github/workflows/production-schema-clone-validation.yml` with:
- title `Production schema validation request: Shared 20261023223900`
- body `migration_version: 20261023223900`, `release_lane: shared`, `production_target: zirqkouammpwxlqfbsvf`, and the **exact head SHA** of this candidate.

Only report the local validation successful after inspecting the workflow logs and test artifacts.
