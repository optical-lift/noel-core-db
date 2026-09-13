# Atlas Organization + Ledger Establishment v1

**Status:** Candidate implementation contract  
**Date:** 2026-09-13  
**Prerequisites:** Canonical Person v1; Person-first Principal/Membership resolution v1; First-Class Ledger v1 (`20260913190915`)  

## 1. Purpose

Establish the canonical noncommercial transaction by which an existing Atlas Principal creates a new institutional scope.

The governing law is:

> **Institutional existence and institutional authority are established by Atlas identity, not by purchase, entitlement, storefront session, or implementation workflow.**

First-Class Ledger v1 already guarantees that every Organization insert creates exactly one governing Ledger in the same database transaction. This tranche adds the missing Principal-authority transaction around that invariant.

## 2. Canonical transaction

```text
signed-in credential
  -> canonical Person
  -> existing Principal
  -> create Organization
  -> governing Ledger is born automatically
  -> create Principal -> Ledger root authority
  -> optionally establish owner membership
  -> optionally establish onboarding actor + reconstruction session
```

The Organization insert, governing Ledger birth, root authority, and any requested relationship/onboarding rows must either all commit or all roll back.

## 3. Identity and authority requirements

The self-service establishment path requires:

- an authenticated Atlas credential;
- a canonical Person resolved through `current_person_id_v1()`;
- an active Principal resolved through `current_principal_id_v1()`;
- the Principal's `person_id` to equal the authenticated Person.

A credential with no Principal may not create an institutional scope through this contract.

The new Organization does **not** become owned because the current user paid for something or holds a commercial entitlement. Ownership/governance is represented by an explicit active `principal_ledger_authorities` row with `authority_kind = root_governing`.

## 4. Internal establishment kernel

Introduce one internal transaction kernel, conceptually:

`establish_organization_ledger_for_principal_v1(...)`

Inputs are explicit identity/behavior facts, not commercial facts:

- Principal ID
- Person ID
- authenticated credential/user ID when a credential-bound compatibility row is required
- Organization name
- whether an owner Organization Membership should be established
- whether onboarding/reconstruction should begin
- establishment basis

The kernel must:

1. validate the Principal is active and belongs to the supplied Person;
2. validate credential->Person consistency when a credential ID is supplied;
3. generate a collision-safe Organization stable key using current conventions;
4. insert the Organization;
5. resolve the governing Ledger created by the First-Class Ledger invariant;
6. fail closed if that Ledger is absent;
7. create active root Principal->Ledger authority;
8. optionally create an owner Organization Membership with both `user_id` compatibility evidence and canonical `person_id`;
9. optionally create `organization_onboarding_actors` and a clean-room `reconstruction_sessions` row;
10. return one bounded institutional-establishment result.

The kernel is not directly browser executable.

## 5. Canonical self API

Introduce:

`establish_organization_ledger_self_api_v1(p_name text, p_create_owner_membership boolean default false, p_begin_onboarding boolean default true)`

This authenticated API resolves credential -> Person -> Principal and calls the internal kernel.

Return only bounded establishment facts:

- Organization ID/stable key/name/status/onboarding state
- Ledger ID/stable key/kind/status
- Principal ID
- root authority ID/kind
- membership ID/role when created
- reconstruction session ID when created
- booleans describing whether membership/onboarding were established

No commercial entitlement, purchase, Stripe, implementation-case, or billing fields belong in this result.

## 6. Membership is not ownership

Root Ledger authority and Organization Membership are separate facts.

A Principal may establish and govern a Ledger while Organization Membership remains intentionally unclaimed during clean-room onboarding.

If owner membership is requested, the membership must preserve current compatibility requirements:

- `user_id` remains populated while the legacy column is required;
- canonical `person_id` is also populated/validated;
- the existing membership compatibility trigger must reject any user/person contradiction.

No employee seat, billing row, or credential product is created merely because owner membership exists.

## 7. Onboarding is not ownership

If onboarding is requested, establishment may create:

- an active `organization_onboarding_actors` row for the authenticated credential;
- one clean-room `reconstruction_sessions` row targeting the new Organization;
- Organization onboarding state consistent with current onboarding semantics.

These rows allow the person to set up the institution. They are not the source of Principal authority.

## 8. Existing noncommercial entrypoints

Two current Organization-creation functions are noncommercial legacy entrypoints:

- `begin_organization_onboarding_self_api_v1(p_name text)`
- `establish_organization_self_api_v1(p_name text)`

This tranche should preserve their signatures while routing their creation semantics through the new kernel where their current authority model permits it.

### `begin_organization_onboarding_self_api_v1`

Preserve its current product behavior:

- authenticated caller;
- no automatic Organization Membership;
- setup actor created;
- clean-room reconstruction begun.

New behavior added by this tranche:

- caller must resolve to an existing active Principal;
- the new Organization's governing Ledger is returned/available canonically;
- explicit root Principal->Ledger authority is established in the same transaction.

### `establish_organization_self_api_v1`

Preserve its compatibility intent of creating owner membership plus reconstruction when called under a real authenticated identity context.

It must no longer independently implement Organization birth. It should delegate to the same kernel with owner-membership and onboarding enabled.

Its existing service-only grant may remain for compatibility, but service-role capability does not bypass the requirement for a real credential -> Person -> Principal identity when this self-oriented function is used.

## 9. Commercial / practitioner establishment is explicitly separate

`establish_implementation_organization_scope_self_api_v1(...)` currently creates an Organization from implementation/practitioner and Ledger-entitlement evidence.

This tranche does **not** silently redefine that commercial workflow as Principal authority.

First-Class Ledger v1 already guarantees that an Organization created there receives a governing Ledger. However, the implementation pathway remains a transitional exception until the later commercial-adoption tranche changes the flow to:

```text
institution already exists
  -> commercial implementation/entitlement attaches to it
```

rather than:

```text
purchase/implementation
  -> manufactures institutional identity
```

The exception must remain visible in architecture and tests. It may not be used as precedent for the canonical establishment contract.

## 10. No commercial dependency

The canonical kernel and self API must not read or require:

- `ledger_entitlements`
- `ledger_entitlement_bindings`
- `implementation_purchases`
- Stripe checkout/payment state
- personal Atlas purchases
- employee-seat billing
- storefront/session state

A Principal with legitimate Atlas identity may establish a new Organization + Ledger independent of those commercial tables.

## 11. Stable-key and Ledger identity

The Organization stable-key collision behavior should remain compatible with existing creation functions.

The Ledger is not created manually by the new kernel. The Organization insert invokes the already-live invariant trigger `organizations_establish_governing_ledger_v1`, and the kernel resolves the resulting Ledger with `primary_ledger_for_organization_v1()`.

If the governing Ledger cannot be resolved after Organization insert, the transaction fails closed.

## 12. Security

- self API: `authenticated` executable, `anon` denied;
- internal kernel: direct `anon` and `authenticated` execution denied;
- no direct browser table grants are widened;
- all security-definer functions pin `search_path`;
- credential IDs are compatibility/access evidence, not Person identity;
- Principal authority is written only after canonical Person/Principal consistency is proven.

## 13. Required production-schema-clone proof

Validation must prove:

1. a credential-backed Person with an active Principal can establish an Organization;
2. the Organization has exactly one active governing Ledger immediately;
3. the same transaction creates active root Principal->Ledger authority;
4. default establishment may begin onboarding without creating Organization Membership;
5. owner-membership mode creates exactly one active owner membership with matching `user_id` and `person_id`;
6. membership is not required for root Ledger authority;
7. no entitlement, entitlement binding, implementation purchase, or billing row is required;
8. a signed-in Person with no active Principal fails closed;
9. a credential/Person/Principal contradiction fails closed;
10. `begin_organization_onboarding_self_api_v1` preserves its external signature and no-membership onboarding behavior while gaining canonical root authority;
11. `establish_organization_self_api_v1` preserves its external signature and owner-membership behavior while delegating institutional birth;
12. direct browser execution of the internal kernel is denied;
13. the commercial practitioner establishment function remains present but is not called by the canonical self API/kernel.

## 14. Explicit non-scope

This tranche does not:

- separate Elm from historical Feast Guild scope;
- change Stripe checkout;
- change implementation pricing;
- change Ledger entitlement semantics;
- attach a paid implementation to an already-existing Organization;
- create pre-auth Organization ownership;
- remove `organization_memberships.user_id`;
- remove `principals.organization_id` compatibility;
- migrate employee seats/connections;
- change public Atlas onboarding UI.

## 15. Next tranche

Once this transaction is live, the next institutional-commerce tranche can safely change paid Organization acquisition so commerce attaches to an already-established Organization/Ledger and never serves as the source of institutional identity or Principal authority.
