# Authenticated RPC Registry Signature Resolver v2

Status: **inert candidate; not migration-identified, not clone-validated, not released**.

The live `atlas.authenticated_rpc_registry_drift_v1()` currently assumes every registry signature is directly parseable by PostgreSQL `regprocedure`.

That assumption is no longer true. The registry contains two legitimate historical signature forms:

1. type-only signatures, e.g. `atlas.foo(uuid,text)`;
2. PostgreSQL identity signatures with argument names, e.g. `atlas.foo(p_id uuid, p_kind text)`.

`to_regprocedure()` cannot parse the second form, so the current drift function aborts before it can report any drift.

This candidate adds an internal resolver:

`atlas.resolve_authenticated_rpc_registry_function_oid_v2(text)`

Resolution law:

- first try ordinary `to_regprocedure()`; this preserves type aliases, PostgreSQL identifier truncation semantics, and overloaded-function resolution;
- if parsing fails, compare against PostgreSQL's own `pg_get_function_identity_arguments()` representation;
- return NULL for a registry signature that no longer identifies a current function;
- fail closed if the identity-text fallback would match more than one current function.

The existing `authenticated_rpc_registry_drift_v1()` contract is then rebound to that resolver.

This candidate does **not**:

- rewrite registry rows;
- forgive genuine privilege drift;
- register any new endpoint;
- grant authenticated or anonymous access;
- change application behavior.

It restores the diagnostic's ability to *report* drift across the mixed historical registry format.

Production verification before candidate creation showed:

- named-identity registry signatures exist in current production;
- the current drift function errors on them;
- type-only signatures using aliases and >63-byte identifiers still resolve correctly through normal `to_regprocedure()`;
- the drift endpoint is service-only and SECURITY DEFINER.

Clone validation should prove the repaired function executes without parser failure and preserves that custody boundary.
