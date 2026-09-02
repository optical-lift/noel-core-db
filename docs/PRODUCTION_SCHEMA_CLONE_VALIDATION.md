# Production Schema Clone Validation

This repository validates candidate database migrations against the current production user-schema graph without applying candidate DDL to production and without requiring a paid Supabase development branch.

## Authority boundary

The validator is `.github/workflows/production-schema-clone-validation.yml` on canonical `main`.

It may be triggered only by an open GitHub issue authored by the repository owner with the exact title:

`Production schema validation request: <Atlas|WNPH|Shared> <14-digit-version>`

The issue body must contain exactly resolved single-token fields for:

- `migration_version`
- `release_lane`
- `production_target`
- `candidate_sha`

`candidate_sha` must be an immutable 40-character commit SHA in this repository.

## Production read boundary

The job uses the protected `production` environment only so one step can read `NOEL_CORE_DATABASE_URL` and run the default schema-only `supabase db dump`.

The dump intentionally does not filter to only `atlas`. Atlas objects can depend on other user-owned schemas, so the disposable clone must preserve the complete user-schema dependency graph. Supabase-managed schemas remain excluded by the CLI's schema-dump contract. A separate password-free role snapshot preserves custom role identities and ACL targets; no production table data is requested.

That step is schema-only. It does not execute candidate SQL, `psql`, migration push/reset/up, or any production mutation command.

The production URL is not passed to candidate checkout, schema restore, migration execution, postcondition checks, lint, or advisor steps.

## Local execution boundary

After the schema snapshot is complete, the workflow checks out the immutable candidate SHA, resolves exactly one migration for the requested version, and verifies its release-lane ownership against canonical `main`.

It then calls `scripts/validate-production-schema-clone.sh`, the same inspectable command available in a repository workspace. The harness starts a disposable local Supabase database, restores the production role and user-schema graph into `127.0.0.1:54322`, captures a baseline Atlas schema lint report, applies the candidate migration only to that local database, runs any canonical `validation/migrations/<version>_*.sql` postconditions already present on `main`, and captures the migrated lint report.

The candidate gate compares individual lint findings before and after the migration. Any new or worsened Atlas lint error blocks the candidate. Pre-existing production lint debt remains visible in the baseline artifact but does not masquerade as a defect introduced by an unrelated candidate. If a candidate removes an existing error, the resolved finding is also recorded.

Every run writes raw command output, normalized baseline and candidate findings, a machine-readable delta, and a human-readable `summary.md`. GitHub uploads the entire diagnostics bundle even when validation fails and publishes the summary directly on the run.

The disposable database is stopped without backup at the end of the job.

## Local command

With Supabase CLI `2.116.0`, `psql`, and read-only schema/role snapshots available, run:

```bash
bash scripts/validate-production-schema-clone.sh \
  --migration-version 20260901223000 \
  --release-lane shared \
  --candidate-migration /absolute/path/to/candidate.sql \
  --roles-dump /absolute/path/to/production-custom-roles.sql \
  --schema-dump /absolute/path/to/production-user-schema.sql \
  --artifacts-dir /absolute/path/to/validation-artifacts
```

CI invokes this exact command after its protected read-only snapshot step. GitHub is therefore confirmation and artifact hosting, not the only place the validator can be diagnosed.

## Relationship to production release

Passing schema-clone validation does not release anything.

Production release remains owned exclusively by `.github/workflows/production-db-release.yml`, is main-only, and releases one exact canonical migration version through the existing protected release contract.

The schema-clone validator is therefore a pre-merge/pre-release proof lane, not a second release lane.
