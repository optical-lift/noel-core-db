# Atlas Organization Connected Source Commands v1

## Purpose

`atlas.connected_sources` already provides the reusable storage/custody shape for external provider accounts, but Atlas currently lacks a governed command membrane for **organization-owned** connections.

That gap must be closed before Stripe or any other organization-level provider is added.

This is not a payment-specific contract. Communication, accounting, calendars, CRMs, payment processors, or future provider adapters may all reuse the same custody root when the source belongs to an organization.

## Current production reality — 2026-09-01

`atlas.connected_sources` supports exactly one custodian:

- `custodian_user_id`; or
- `custodian_organization_id`.

It already preserves:

- `provider_key`;
- `provider_account_key`;
- display/account hints;
- authorization state;
- granted scopes;
- capabilities;
- last sync;
- revocation;
- metadata;
- unique provider/account identity within a human or organization custody root.

However, the only production function that currently inserts `connected_sources` is:

```text
atlas.register_communication_relay_api_v1(...)
```

That path creates a **human-owned** communication source for the authenticated Principal.

There is no canonical organization-owned command for registration, authorization refresh, reauthorization-required state, revocation, or capability/scopes reconciliation.

A Stripe adapter must not solve that by inserting `connected_sources` directly or by inventing `stripe_accounts`.

## Custody authority

Version 1 organization connector writes require one of two explicit actor shapes:

### Organization owner

An authenticated human with active:

```text
organization_memberships.role = owner
```

for the target organization may authorize/manage an organization-owned connected source.

Ordinary `member` or `consultant` membership does not imply external-account connection authority.

### Active setup actor

An authenticated human may also carry setup on behalf of the organization while explicitly admitted through:

```text
organization_onboarding_actors
  actor_kind = setup_actor
  active = true
```

This supports governed onboarding without turning consultant membership itself into permanent connector authority.

The command derives the human from `auth.uid()`; callers do not nominate an arbitrary acting user.

## Canonical command shape

The organization command membrane should expose provider-neutral operations conceptually equivalent to:

```text
register / bind source
update authorization evidence
mark reauthorization required
revoke source
```

The provider adapter supplies provider facts, but the command verifies organization custody and allowed state transitions.

### Register/bind

Inputs need only provider-neutral custody evidence:

- target organization;
- provider key;
- provider account key;
- display label / account hint;
- authorization state;
- granted scopes;
- capabilities;
- provider-adapter metadata;
- idempotency key or equivalent deterministic provider/account identity.

The logical source identity already exists in the table's organization/provider/account unique key.

Retrying provider authorization for the same organization/provider/account must reuse the same source row rather than minting duplicates.

### Authorization-state transition

Supported storage states already exist:

```text
pending
connected
reauthorization_required
revoked
error
```

The command membrane must validate lawful transitions rather than letting adapters arbitrarily overwrite the row.

At minimum:

- a successful provider authorization may move pending/error/reauthorization-required to connected;
- a provider/auth failure may record error or reauthorization-required when evidence warrants it;
- explicit revocation moves the source to revoked and records `revoked_at`;
- a later fresh authorization may reuse the same provider/account logical source according to a deliberate reauthorization rule rather than silently clearing historical revocation evidence.

If preserving revocation history requires append-only authorization events before implementation, add that authority rather than pretending `authorization_state` alone is a complete audit ledger.

## Capability boundary

`capabilities` describes what this connection is authorized/configured to do inside Atlas.

For money collection, the generic capability is conceptually:

```json
{
  "moneyCollection": true
}
```

A Stripe adapter may preserve provider-specific details in metadata/capability subkeys, but the Money Collection Kernel depends only on:

- organization custody;
- source authorization state = connected;
- generic `moneyCollection` capability.

No source becomes payment-capable merely because `provider_key='stripe'`.

## Scope boundary

Granted provider scopes are evidence of authorization, not Atlas role permissions.

The organization connector command must not interpret a provider OAuth scope as authority to alter unrelated Atlas domains.

Atlas domain commands independently verify whether a connected source capability may be used for a specific operation.

## Secret boundary

`connected_sources` is provider-account custody metadata, not a credential vault.

OAuth refresh tokens, webhook secrets, API secret keys, and similar credentials must remain in an appropriate secret store/provider integration boundary. Do not put reusable provider secrets in `metadata`, `provider_account_key`, or other ordinary database fields.

The database may preserve non-secret provider identifiers and cryptographic digests needed for custody/reconciliation.

## Money integration

The Money Collection Kernel references an organization-owned `connected_sources.id`.

Before creating a provider-backed collection attempt, the canonical money command must verify:

```text
source.custodian_organization_id = obligation.organization_id
source.authorization_state = connected
source.capabilities.moneyCollection = true
```

This prevents an authenticated user from collecting one organization's receivable through another organization's provider account.

Stripe Checkout/session creation occurs only after that Atlas custody check.

## Read boundary

`connected_sources_self_api_v1()` already exposes organization-owned connected sources to authorized organization members/onboarding actors for read purposes.

Read visibility is not mutation authority.

A member being able to see that Stripe is connected does not grant permission to replace/revoke/rebind the account.

## Provider callback boundary

Provider webhooks are not connector-management commands.

A signed webhook may provide evidence that an authorization became invalid or an account state changed, but a governed provider-adapter command must translate that evidence into connected-source authorization state.

The webhook must not accept organization identity solely from request metadata when it can be resolved from the provider account/source binding.

## Verification contract

Implementation is incomplete unless it proves:

1. organization owner can register/reuse an organization-owned source;
2. active setup actor can register/reuse a source during governed setup;
3. ordinary organization member cannot create or rebind a source;
4. consultant membership alone cannot create or rebind a source;
5. same organization/provider/account retry is idempotent;
6. another organization may lawfully have its own row for the same provider account key only if provider semantics actually permit that identity; otherwise adapter validation rejects it;
7. connected-source custody is checked before money collection use;
8. `moneyCollection` capability is required independently of provider key;
9. revocation/reauthorization state is not silently ignored;
10. no provider secret is stored in ordinary connected-source metadata;
11. read visibility does not imply write authority;
12. provider adapters do not create parallel account tables.

## Reuse boundary

This contract generalizes **provider custody commands**, not provider business semantics.

Stripe authorization remains Stripe-adapter work.
Communication relay credentials remain communication work.
Accounting sync remains accounting-adapter work.

They converge only on the shared question:

> Which human or organization lawfully owns this external provider account connection, and what Atlas capabilities is that connection currently authorized to support?
