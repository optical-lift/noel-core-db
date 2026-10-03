# Atlas Implementation Reality Identity Resolution v2

## Status

Source candidate only. Not released to production as of 2026-10-02.

Branch:

`architecture/implementation-reality-organization-unit-resolver-v2`

Candidate:

`candidates/atlas_implementation_reality_identity_resolution_v2.sql`

Validation:

`candidates/atlas_implementation_reality_identity_resolution_v2_validation.sql`

## Purpose

Remove the remaining raw-identity gap between the Implementation Reality Sentence Workbench and canonical Organization Unit truth.

The existing v1 identity membrane resolves case-scoped canonical:

- Organization
- Person
- Organization Position
- Organization Responsibility

It does not resolve Organization Unit, even though Position establishment requires a canonical Organization Unit and nested Unit establishment may name a canonical parent Unit.

v2 is deliberately additive. It does not replace or reinterpret the existing v1 semantics. For the four existing kinds, v2 delegates to v1 and upgrades only the response contract version. The only new lookup behavior is `organization_unit`.

## Organization Unit scope

An Organization Unit is eligible only when all of these are true:

1. the current user is the assigned practitioner for the open Implementation Case;
2. the Unit belongs to an active Organization already bound to that Implementation Case;
3. the binding is current and in `bound` or `activated` state;
4. the Unit itself is active.

The resolver returns canonical IDs from governed lookup results. It never accepts a raw canonical UUID from the operator as a substitute for resolution.

Returned Unit options preserve:

- canonical Unit ID;
- Unit label;
- Unit kind;
- owning Organization ID and label;
- parent Unit ID and label when one exists;
- match basis `case_bound_organization_unit`.

## Security boundary

The internal `atlas` function remains `STABLE SECURITY DEFINER` and is not executable by `anon`, `authenticated`, or `service_role` directly.

The `public` wrapper is the Data API membrane. It is executable by `authenticated` only and delegates immediately to the internal function.

The resolver performs no INSERT, UPDATE, DELETE, identity creation, merge, establishment, promotion, or other canonical mutation.

## Release order

Database before application:

1. validate this candidate in a disposable production-schema clone;
2. verify the v2 public/internal function ACLs and read-only contract;
3. release the resolver deliberately to Noel;
4. confirm the public RPC is callable by an assigned practitioner and returns only case-bound Units;
5. only then may the Atlas Workbench branch that consumes `implementation_reality_identity_options_self_api_v2` become deployment-eligible.

Do not deploy Atlas ahead of this database membrane. Do not use raw canonical UUID entry as a temporary workaround.

## Current verification limitation

The production database currently contains canonical Organization Units but no current `bound` or `activated` Implementation Case bindings. Therefore there is no honest live case against which to exercise the case-scoped Unit result set today. Runtime proof must use a disposable clone fixture or wait for a real bound case.
