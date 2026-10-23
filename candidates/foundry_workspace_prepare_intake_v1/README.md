# Foundry Gate 1c — authenticated workspace preparation

**Status:** source-only, NOT deployed and NOT validated in a Postgres clone.  
**Dependency:** private workspace authority registry PR [#2093](https://github.com/optical-lift/noel-core-db/pull/2093), including its unique `(owner_principal_id,creation_request_id)` key.  
**Parallel dependent build:** delegated workspace-target authorization PR [#2094](https://github.com/optical-lift/noel-core-db/pull/2094).  
**Companion behavioral admission:** Foundry [PR #2](https://github.com/optical-lift/atlas-ledger-foundry/pull/2).

## Actual, deliberately limited behavior

A signed-in **non-anonymous** Atlas human with an active canonical `atlas.principals` row may prepare an **unreviewed** pre-Ledger Foundry workspace. The operation derives `auth.uid()` inside the protected database function; the caller cannot choose a Principal, workspace ID, Auth identity, canonical Person, Ledger, AI carrier, or authority decision. The client-supplied subject label, provisional field, and custody scope kind are plainly *provisional*.

`atlas.prepare_foundry_workspace_self_api_v1(request_id,subject_label,provisional_field,custody_scope_kind)`:

1. Authenticates the human and loads the active Principal from server-owned Auth/Atlas records.
2. Validates a stable request UUID and bounded provisional labels.
3. Serializes retries, checks an owner-scoped unique creation request, and either replays the **same** workspace or rejects a same-key changed payload.
4. Creates a server-generated Foundry workspace ID in a private **pending** custody registry. Even a `verified_self` *requested scope kind* remains unverified; subject identity stays `unresolved`.
5. In the **same Postgres transaction**, appends a compliant `WORKSPACE_CREATED` sequence-1 event to the existing `foundry.events` stream. Failure rolls the registry insert back.
6. Returns only the workspace ID and pending custody status, not a usable external-subject consent receipt, private document access, Ledger or AI permission.

No snapshot is written in Gate 1c: canonical event custody is source of truth; a future service must project event stream + snapshot correctly. Historic streams remain untouched and cannot be silently assigned this new owner.

This protected authenticated self-API is the minimum legitimate human initiation route. A **separate reviewed-custody ceremony**, built later, must verify evidence of permission and scope before any external AI carrier can read/record the third-party subject's material. A preparatory container does not itself confer authority to process someone else's private files.

## Required security boundaries

The function uses `SECURITY DEFINER` **only** because it must insert into private Foundry tables and atomically call the protected append function. It has a constrained schema search path, untrusted caller identity is not accepted as a parameter, and direct registry/event table access remains unavailable to `authenticated`/`anon`. Execute privileges are granted only to `authenticated` for this exact signature. The function also rejects Supabase anonymous sign-ins.

Before release, verify schema exposure, ACLs, anonymous sign-in handling, JWT provenance, active session/banned account behavior, rate limits/quota policy, negative isolation tests, and protected SQL SECURITY DEFINER review. This code has not yet passed those tests.

## Validation

Run the registry candidate SQL first, then this candidate SQL in an isolated **production-schema clone**. Execute `postconditions.sql` and the **rollback-only** `rollback_fixture_tests.sql`. Fixtures simulate `auth.uid()` by SQL session claims; these are not a substitute for authenticated client/real JWT tests. The fixture self-test deliberately leaves all synthetic data rolled back. Then run privilege/RLS security advisors and regression checks.

**No production change** is authorized by this source candidate. Full clone validation needs a disposable Supabase branch or the established isolated database CI lane; no direct production DDL, even with rollback.
