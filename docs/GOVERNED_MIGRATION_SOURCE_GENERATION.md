# Governed Migration Source Generation

This repository can promote a reviewed candidate SQL packet into a real Supabase migration identity without requiring a developer's local checkout.

## Authority boundary

The generator is `.github/workflows/migration-source-generation.yml` on canonical `main`.

It runs only when the repository OWNER opens an issue with the exact title:

```
Migration generation request: <Atlas|WNPH|Shared> <migration_name>
```

The body must contain one token per field:

```
release_lane: atlas
migration_name: atlas_example_v1
candidate_sha: <40-character commit on main>
candidate_path: candidates/example/candidate.sql
fixture_path: candidates/example/fixture.sql
validation_path: candidates/example/postconditions.sql
```

Use `none` for an optional fixture or validation path.

## What it does

1. checks out canonical `main` with full history;
2. proves the immutable candidate SHA is already an ancestor of `main`;
3. proves every requested source file is inside `candidates/`;
4. installs the repository-pinned Supabase CLI version `2.116.0`;
5. runs `supabase migration new <migration_name>`;
6. copies the reviewed candidate SQL bytes into the CLI-generated migration path;
7. copies fixture/postcondition bytes into matching versioned validation paths;
8. verifies release-lane ownership;
9. creates an isolated `generated/...` branch;
10. opens a pull request and records the generated migration version on the request issue.

## What it cannot do

The generator:

- has no production database secret or production environment;
- cannot apply a migration;
- cannot release production;
- cannot accept unmerged candidate bytes;
- cannot generate from paths outside `candidates/`;
- cannot bypass the separate production-schema clone validation lane;
- cannot merge its own pull request.

Generation, validation, source merge, and production release remain separate authority events.
