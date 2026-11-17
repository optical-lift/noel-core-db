# Moonwell Noel schema handoff — source preflight and protected boundary

**Status:** source-only proposal; not an export authorization, handoff, migration, release, or approval to use production credentials on Moonwell.

**Current reason:** Moonwell's local November 8 schema-only archive restored all ten application schemas and 69 Atlas tables, but `atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)` is absent. Its held P3 source requires the read-only production `pg_get_functiondef` MD5 `774ad5c6728a615ada5bf4ea823c5498` captured November 6, 2026. The held client browser test is blocked on the *genuine current* schema, not merely a table count.

## Bounded outcome and authority

Create a **separate, one-time, owner-approved schema-and-roles-only handoff** to the protected, disposable Moonwell local validation environment, and prove the source fingerprint before any held U2/U4/P3 installation. This is distinct from the existing owner-controlled U2 signed-test request (#2626); **do not reuse its issue selectors or infer release permission from its passing test receipts.**

The source owner is Noel's protected `NOEL_CORE_DATABASE_URL` environment. The recipient is a private owner-controlled Moonwell local PG17/GoTrue/PostgREST test. The production database, users, application rows, existing release/migration custody, old signed-test workflow, and runner workspaces are all outside the write scope.

A schema snapshot can include private function bodies, RLS policy logic, operational identifiers, and role password verifiers. It is **sensitive** despite containing no table rows. Keep schema/roles together under private custody, with no GitHub log, PR attachment, Actions artifact (encrypted or unencrypted), repository commit, issue comment, or publicly accessible download.

## Source gate implemented in this increment

`scripts/check-moonwell-p3-source-readonly.py`:

- Requires a protected `NOEL_CORE_DATABASE_URL` environment variable; there is no default database, local credential lookup, host rewrite, or fallback.
- Executes **one fixed SELECT** with `psql -X -w` under a read-only transaction default and a statement/connect timeout. The connection string is passed through `PGDATABASE`, not a shell or command-line URL argument.
- Matches the **exact immutable** `pg_get_functiondef` MD5 source, returns one fixed PASS class only on that match, and fails closed on absent credentials, missing function, changed hash, unexpected output, SQL failure, or timeout.
- Emits no DSN, SQL definition, object contents, error details, names, user IDs, or tokens.
- **Does not** perform a dump, authorize a production run, or prove any other part of the schema. Future snapshot work still requires a separately reviewed protected runner and owner gate.

Run the source-only tests without a database or credentials:

```bash
python3 -m unittest tests/test_check_moonwell_p3_source_readonly.py -v
```

**The preflight must not be run against production by an ungated user command**. Its intended use is *after* owner authorization, *inside* the existing protected GitHub-hosted runner context. In the present PR it is not wired to any workflow.

## Required separate handoff gate (not implemented or authorized yet)

1. **Owner authorization:** a new dedicated owner-selected scope and issue/workflow trigger, separate from #2626, exactly one run, reviewable selectors and environment protection. This must be approved before any use of the production credential. No CI execution from an untrusted PR head or a Moonwell self-hosted runner with production credentials.
2. **Recipient and delivery:** establish a reviewed, fixed destination owned by the principal and a recipient-only encryption public key, independent of issue text and PR inputs. The principal must select/authorize the transfer carrier and any new credential/scope. No arbitrary URL or destination from workflow inputs. If no such route is established, **STOP**; do not choose Dropbox, GitHub artifacts, generic object storage, or an alternate cloud provider merely to avoid the blocker.
3. **Trusted read-only capture:** use the existing, pinned Supabase CLI schema/role-only dump mechanism inside the protected environment, with no `--data-only`, no table rows, no migration, no production DDL/permissions, and no production role credential on Moonwell. Inspect role output for password verifiers and treat the full snapshot as private.
4. **Source and transfer integrity:** run the exact evaluator fingerprint preflight against production *before* the export; verify the resulting archive is schema-only, encrypt before transmission, verify recipient ownership, and produce only non-sensitive digest/size and allowlisted status messages. Verify digest and schema/function signature after private receipt/decryption. Destroy runner temporary plaintext files even on failure.
5. **Local acceptance:** restore into a **new disposable test database**, not the current working local `postgres` database; verify role/auth compatibility without broad GRANT or overriding Supabase-owned auth. The exact evaluator fingerprint, RLS/ACL invariants, pinned source stages and signed fictional governor/worker behavior are separate gates. Only afterward consider enabling `ATLAS_UNI_OPS_C_HUMAN_FIRST_PROOF_ENABLED` for local browser testing. Never interpret this as production release.

## Current completion register

| Gate | Evidence | State |
| --- | --- | --- |
| Recover Moonwell local application structure | Ten selected schemas, 69 Atlas tables, zero users and zero Work; Work RLS enabled | PASS, structural only |
| Confirm P3 baseline fingerprint | `to_regprocedure` missing for the exact `atlas.evaluate_rhythm_binding_v1` signature | BLOCKED: needs current source |
| Add isolated source preflight | Exact read-only `psql` SELECT and fixed-class negative unit tests in this PR | READY FOR CI REVIEW |
| Select private recipient/delivery carrier | No approved external delivery path or encryption identity supplied in this task | **UNRESOLVED, owner gate** |
| Owner-authorized CI snapshot + private handoff | No new protected workflow or export run | NOT RUN |
| Local U2 → U4 → P3 installation and browser proof | Existing signed backend and frontend receipts are retained; live browser handoff still missing | NOT RUN |

**Next unfinished task:** the owner must select and authorize the *private delivery carrier* and intended recipient encryption identity. Only then should a separate PR wire this preflight into a one-time protected snapshot-and-delivery workflow. No second restore against the incomplete schema.
