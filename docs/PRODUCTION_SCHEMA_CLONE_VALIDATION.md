# Production Schema Clone Validation

This repository validates candidate database migrations against the current production Atlas schema without applying candidate DDL to production and without requiring a paid Supabase development branch.

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

The job uses the protected `production` environment only so one step can read `NOEL_CORE_DATABASE_URL` and run `supabase db dump --schema atlas`.

That step is schema-only. It does not execute candidate SQL, `psql`, migration push/reset/up, or any production mutation command.

The production URL is not passed to candidate checkout, schema restore, migration execution, postcondition checks, lint, or advisor steps.

## Local execution boundary

After the schema snapshot is complete, the workflow checks out the immutable candidate SHA, resolves exactly one migration for the requested version, and verifies its release-lane ownership against canonical `main`.

It then starts a disposable local Supabase database, restores the production Atlas schema snapshot into `127.0.0.1:54322`, applies the candidate migration only to that local database, runs any canonical `validation/migrations/<version>_*.sql` postconditions already present on `main`, and runs Atlas schema lint.

The disposable database is stopped without backup at the end of the job.

## Relationship to production release

Passing schema-clone validation does not release anything.

Production release remains owned exclusively by `.github/workflows/production-db-release.yml`, is main-only, and releases one exact canonical migration version through the existing protected release contract.

The schema-clone validator is therefore a pre-merge/pre-release proof lane, not a second release lane.
