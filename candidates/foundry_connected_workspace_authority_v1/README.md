# Foundry connected workspace — private authority registry source candidate

**Status:** source-only, not a release. **No production database change.**
**Base:** `optical-lift/noel-core-db@6ebde9a810152be9c5e51c674229df9f1483b004`
**Companion:** `optical-lift/atlas-ledger-foundry` Gate 0 PR #1 and Gate 1 PR #2.

## What this candidate deliberately does

`candidate.sql` creates a minimal private `foundry.workspace_authority_registry_v1`, referencing the **existing** canonical `atlas.principals` table for the human who controls Foundry workspace custody. It stores only the provisional subject label/field, an explicitly pending source-custody review, protocol, and provenance pointers.

**The owner Principal is not necessarily the subject Person.** External subjects require a separately adjudicated basis before their material is exposed to an external AI carrier. The provisional label is never treated as proof of identity. The registry contains no new Person, Auth, Ledger or carrier credential.

The data table is inaccessible to `anon`, `authenticated` and direct `service_role` table operations; no policies or public commands are installed. RLS is enabled, with no direct table policies. Only future separately reviewed secure server commands may populate/read it.

No existing Foundry event or snapshot is modified/backfilled. Five pre-existing streams include 20 legacy-shaped envelopes, so they cannot be auto-admitted by creating a registry row or guessing an owner.

## What this candidate does NOT do

It does **not** implement `start_workspace`, authenticate an MCP caller, authorize a target, issue carrier credentials, produce a session, create an event, or permit a canonical Atlas Reality write. It does not yet extend `atlas.agent_command_definitions.scope_kind` with a Foundry scope. No user may be told Foundry is connected because this source exists.

## Next source package: protected authority command

Once this schema is validated against the exact current production-shaped clone:

1. Install a narrowly authorized creation/review command. It must derive active owner Principal from verified human/Auth context or trusted delegated-agent invocation; never a supplied actor UUID.
2. Require a separately reviewed source-custody basis for `verified_self` or `documented_external`. A user/client-entered label or basis-ref string isn't sufficient.
3. Create a new registry row and a compliant `WORKSPACE_CREATED` Foundry event in **one** transaction, with server-generated workspace ID. Maintain idempotence and provenance.
4. Extend the existing Atlas delegated-agent command catalog/target validator for an explicit Foundry workspace target (or prove an equivalent existing semantic scope). The current catalog permits only Ledger commands, and target ID allowlists do not independently prove Foundry ownership.
5. Bind every read/write operation to its current workspace, owner, external subject authority receipt, active carrier grant, effective time and exact allowed operation; reject stale/revoked permission.
6. Do not admit a nonowner human operator until an independently governed human authorization route exists. First David pilot can have the onboarder as workspace owner and David as provisional subject.
7. Preserve legacy workspace streams unchanged; explicit compatibility/disposition is a separate activity.

## Validation

On a **disposable production-schema clone only**, execute `candidate.sql`, then `postconditions.sql`; run the current DB custody checks and a protected security review. The postconditions test schema and privilege properties without inserting customer data. This package has not passed production-schema clone validation and must not be promoted to a numbered migration yet.

**No migration generation, service registration or production release is authorized by this candidate.**
