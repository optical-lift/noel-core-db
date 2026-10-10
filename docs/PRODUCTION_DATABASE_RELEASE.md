# Production Database Release

`noel-core-db` owns canonical executable migration source after the frozen production-history fence at `20260825203448`.

Production release is intentionally separate from custody verification. The scheduled custody workflow proves that every live post-fence migration has exact source in this repository; it does not apply source-only migrations.

## Governed release path

Use the GitHub Actions workflow **Production Database Release** from `main`.

The workflow is manual-only and releases one exact migration version at a time. It requires:

- the migration file already merged to `main`;
- the exact 14-digit migration version as the workflow input;
- explicit confirmation of production project ref `zirqkouammpwxlqfbsvf`;
- the protected GitHub environment `production`;
- environment secret `NOEL_CORE_DATABASE_URL`, containing the production Postgres connection string;
- repository custody checks passing before release;
- live production custody passing before release.

The releaser executes the canonical migration inside the transaction already owned by that migration and inserts the Supabase migration-ledger receipt immediately before the terminal `COMMIT`. The receipt stores the exact canonical migration body. After commit, the releaser recomputes the live Git blob SHA-1 and requires it to equal `git hash-object` for the source file.

The scheduled custody workflow then independently verifies the same live/source equality through `shared_db_custody_release_packet_v1()`.

## What this workflow must never do

- It must not run automatically on `push`, pull request, or schedule.
- It must not use a service-role application key to bypass database deployment authority.
- It must not reset production.
- It must not synthesize a new migration timestamp at deployment time.
- It must not release a migration whose version or name is already present with different bytes.
- It must not accept a migration without the repository's current `BEGIN; ... COMMIT;` transaction convention.

## Required secret

Configure `NOEL_CORE_DATABASE_URL` only in the protected `production` GitHub environment. Do not commit the database password or connection string to the repository.

Supabase recommends using a database connection string for CLI/Postgres operations; the session pooler connection string is the preferred default when direct IPv6 connectivity is unavailable.

## Independent domain structural release decisions

The protected release selector accepts `noel`, `atlas`, `titus`, `wnph`, and `shared`. Noel-specific algorithm or table changes use `noel_`; ordinary dictionary research is not a release at all. The target lane must have exact live/source custody for its own changes plus shared and unclassified changes. Named unrelated domain source debt is still visible in the separately enforced global monitor but cannot alone veto a non-shared target release. Any actual interface/permission/identity contract touching more than one domain belongs in `shared_` and must meet global custody.

Global custody CI continues to **block main/scheduled/manual checks**, while pull requests run the same reconciler in report-only mode to avoid making existing unrelated legacy drift a blanket PR veto. This does **not** allow a developer to merge source-only data, replay historical SQL, publish founder research or skip the protected production release. See `docs/DOMAIN_WORK_ISOLATION_V1.md`.
