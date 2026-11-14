# Connected Person Work — disposable local signed proof

**Authority:** Noel #2255 / draft PR #2263; Atlas #437 / draft PR #442.

**Status:** Structural source CI and offline safety tests can pass while actual SQL and independently signed GoTrue HTTP tests have NOT run. Neither a local result nor a source CI check independently certifies effective disclosure or authorizes Anna onboarding.

## Guarded local runner

The existing source package now includes:

- scripts/run-connected-person-local-proof.py
- scripts/test-connected-person-local-proof-safety.py
- scripts/validate-atlas-connected-person-work-signed-http.py
- The held SQL candidates, clone-only postconditions and synthetic C1 identity fixture

**Default / --preflight** checks required files, local Supabase Auth/REST and database endpoints, and identity/data isolation. It makes no database writes.

**--execute** runs only after preflight, then seeds *only the existing synthetic C1 fixture* into an otherwise empty disposable full-schema database (or uses an already complete synthetic fixture), applies held SQL in source-dependency order, executes clone-only postconditions, reloads the local REST schema, and invokes genuine signed local GoTrue/PostgREST tests. It cannot create a hosted branch or issue a production migration. The signed test is permitted to fail; this is not yet a signed PASS.

The runner refuses any remote database or HTTP service, missing exact local Postgres identity, or any real/non-fixture Auth users, organizations, Ledger records, People or original Work. It does not use employee memberships, a service-role session masquerading as a worker, live Anna details or real passwords.

## No-cost prerequisites — must already be available

1. A local Supabase project with a running local Auth/PostgREST/Postgres stack, a supabase/config.toml file and the **full Noel schema**. The user does not need to pay for a new cloud project or branch. Mac local Supabase can run via a compatible container runtime; ask the local commands and macOS version before prescribing installation.
2. Supabase CLI, PostgreSQL psql, and Python 3 installed on RiverSong.
3. Exact private Noel PR source at the tested SHA, available in an authenticated GitHub ZIP. The user previously used private ZIP downloads because authenticated Git cloning was unavailable.
4. Empty fixture-safe data: no real people's auth accounts, institution/work rows or production snapshot. Full schema does NOT mean production data.
5. The existing source-owned native Ledger and standing Work functions loaded locally before these held candidate functions. The runner does NOT rebuild thousands of migrations, pull hosted data, run supabase link, db push, db reset or initialize the local stack itself.

Use the source checkout folder that contains scripts and validation. Supply --stack-dir only if the already running local Supabase project has its supabase/config.toml elsewhere.

### Preflight (no SQL changes)

~~~bash
python3 scripts/test-connected-person-local-proof-safety.py
python3 scripts/validate-atlas-connected-person-gate0-source.py
python3 scripts/run-connected-person-local-proof.py --preflight \
  --stack-dir "/path/to/existing/local-supabase-project"
~~~

If the local stack is in the same checkout folder, omit --stack-dir. Stop if any prerequisite is missing; do not point this script at production or a local tunnel to real production data.

### Actual synthetic signed test — only after preflight passed

~~~bash
python3 scripts/run-connected-person-local-proof.py --execute \
  --stack-dir "/path/to/existing/local-supabase-project" \
  --receipt-dir "$HOME/atlas-local-security-receipts"
~~~

This command applies held SQL **only** to the verified disposable 127.0.0.1 test database. No remote writes, migrations, source-branch merges, invitations or public exposure. On success it saves source hashes and an explicit **NOT production certification** receipt locally, without keys. If a source candidate fails to install or a signed test fails, that is a stop condition: preserve the error and restart only in a new disposable environment according to its separate local setup procedure, not by resetting any live database.

## Verification scope

The local signing script checks four genuinely different synthetic GoTrue sessions (root governor, connected worker, outsider, no native Seat), exact native Work scope acceptance, real Work A allocation, unassigned Work B exclusion, default zero disclosure, exact title approval then separate instruction approval, hash mismatch and edit invalidate, idempotent grants, independent revocation, source change, direct approved-fields reader, existing My Work/Today/dated Work, native Seat ending, Work relevance withdrawal, and same-JWT auth-session deletion.

**Still excluded from this proof:** old farm-atlas eight GET paths, farm worker Day read/refresh/report/home, alternate Event/attention/notes readers, Index/search/export/media/cache, incomplete governor Effective Disclosure Review, historical completion/result disclosure, and Anna's real Bed 3 and Bed 4 independently completable Work. Those are separate required production acceptance gates; no positive local result can make Anna's account privacy-certified by itself.

## If RiverSong does not already have a local stack

Collect only the output of: whether supabase and psql exist, whether a container runtime is installed/running, and whether a disposable Noel full-schema local project already exists. Do not share keys, passwords, JWTs, real database URLs, or screenshots containing secrets. Do not install, link, import data or pay for a hosted project without a separate explicit step.
