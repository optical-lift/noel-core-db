# Atlas Commercial Ledger Binding v1

## Purpose

Complete the separation between institutional identity and commerce.

Canonical institutional reality is established independently:

`Person -> Principal -> Organization -> governing Ledger -> root Principal authority`

Commercial implementation may then attach paid capability to that already-existing Ledger. Payment, entitlement, practitioner workflow, or setup sponsorship must never create an Organization, Ledger, Principal, or root institutional authority.

## Governing law

> Commerce may bind capability to institutional reality. Commerce may not manufacture institutional reality.

## Canonical commercial sequence

`Implementation purchase -> implementation case -> verified setup sponsor -> sponsor Canonical Person -> sponsor Principal -> existing target Ledger under sponsor root authority -> entitlement binding`

The practitioner executes and records the commercial binding. The practitioner does not choose institutional ownership and does not confer Principal authority.

## Target authority

A target Organization/Ledger is eligible only when all are true:

- the Organization is active;
- the Ledger is the active governing Ledger of that Organization;
- the verified setup sponsor resolves through an active Person credential binding;
- that Person has an active Principal;
- that Principal has active `root_governing` authority over the target Ledger.

A practitioner knowing an Organization or Ledger UUID is never sufficient authority.

## Practitioner authority

The current practitioner must still:

- satisfy `implementation_practitioner_authorized_self_v1()`;
- be the active `practitioner` participant assigned to the implementation case;
- operate only against the entitlement belonging to that implementation case.

## Existing implementation evidence

The current established `institution` and `ledger_scope` implementation items remain prerequisites in v1. They describe what the implementation engagement has established commercially; they are not the source of the canonical Organization or Ledger.

## Binding operation

Introduce a canonical practitioner API that accepts:

- implementation case id;
- institution establishment item id;
- ledger-scope establishment item id;
- ledger entitlement id;
- target Organization id;
- target Ledger id.

It must:

1. authenticate and authorize the practitioner;
2. verify practitioner assignment;
3. require one active verified setup sponsor;
4. resolve the sponsor to Canonical Person and active Principal;
5. verify sponsor Principal root authority over the supplied Ledger;
6. verify Ledger <-> Organization identity and active state;
7. verify implementation establishment items;
8. lock and verify entitlement state;
9. preserve idempotency when the entitlement is already bound to the same target;
10. reject conflicting existing bindings;
11. insert `ledger_entitlement_bindings` with both `organization_id` and `ledger_id` explicitly;
12. mark the entitlement bound;
13. record commercial binding evidence on the implementation case;
14. return the existing institutional ids with `organizationCreated=false`, `principalCreated=false`, and `membershipCreated=false`.

## Historical commercial creator

`establish_implementation_organization_scope_self_api_v1(...)` currently creates a new Organization from implementation purchase state. There are no production implementation cases, entitlements, or bindings today, so no historical commercial data depends on that behavior.

The old endpoint must stop creating institutional identity. In v1 it remains only as a fail-closed compatibility endpoint:

- if a prior binding already exists, it may return that existing binding;
- otherwise it must refuse to create an Organization and direct callers to the new existing-Ledger binding API.

No browser or service caller may regain an Organization-creation path through commercial state.

## Idempotency and conflict

If an active binding already exists for the entitlement:

- same Organization + same Ledger -> return existing binding;
- different Organization or Ledger -> reject as a commercial scope conflict.

An entitlement may never be silently rebound by retry.

## Non-effects

This tranche must not:

- create or update `atlas.organizations`;
- create or update `atlas.ledgers` except ordinary referenced reads;
- create Principal or Person identity;
- create Principal -> Ledger authority;
- create Organization Membership;
- alter farm/Feast Guild institutional reality;
- change current pricing or billing amounts.

## Validation obligations

Production-schema clone validation must prove:

- binding to an existing sponsor-governed Ledger succeeds;
- no Organization, Ledger, Principal, authority, or membership counts increase during the binding;
- practitioner without assignment fails;
- unverified or absent sponsor fails;
- sponsor without Principal root authority over target Ledger fails;
- Organization/Ledger mismatch fails;
- entitlement from another case fails;
- same-target retry is idempotent;
- conflicting-target retry fails;
- the old commercial creator cannot create an Organization;
- direct browser table access remains denied;
- the new API is exposed only to the intended authenticated practitioner surface.

## Release boundary

This is a database contract tranche. No application rollout is required to make institutional identity safe. A frontend/practitioner workflow may adopt the new binding API after the governed database release.