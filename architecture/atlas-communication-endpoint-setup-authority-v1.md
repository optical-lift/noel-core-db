# Atlas Communication Endpoint Setup Authority v1

## Problem

Atlas already distinguishes organization provider setup authority from ordinary organization membership.

`organization_connected_source_authorized_self_v1` permits:

- an active organization owner; or
- an active organization onboarding actor with `actor_kind='setup_actor'`.

The existing communication endpoint setup RPCs, however, were owner-only. That created an authority mismatch: a legitimate implementation/setup actor could connect and select the organization's provider asset but fail when Atlas attempted to create/bind the Ledger communication endpoint.

## Resolution

This candidate introduces `organization_communication_endpoint_setup_authorized_self_v1(organization_id)` and aligns these infrastructure RPCs to it:

- `upsert_communication_endpoint_self_api_v1`
- `bind_communication_endpoint_source_self_api_v1`

Communication endpoint setup authority is therefore:

- active owner, or
- active organization onboarding `setup_actor`.

The source/endpoint binding trigger remains authoritative for organization/unit custody equality.

## What this does not grant

This candidate does **not** broaden operational communication access.

`set_communication_endpoint_member_capability_self_api_v1` remains owner-only. A setup actor cannot decide that Katie, Marshall, or another organization member may:

- view a channel;
- send from it;
- claim its conversations;
- hand off its conversations;
- close communication work; or
- administer the endpoint.

Infrastructure configuration and member entitlement remain separate authorities.

## Connection ordering

The Meta provider completion path uses this authority before marking an organization source connected:

1. Create/reuse the organization-custodied Connected Source in `pending` state.
2. Store the provider credential in Vault.
3. Subscribe provider webhooks.
4. Create/upsert the Ledger `social` Communication Endpoint.
5. Bind the source as `receive` or `send_receive`.
6. Activate the source/selection as connected.

If endpoint setup fails, the selection remains retryable rather than falsely appearing fully connected.

## Boundaries

This candidate does not:

- grant endpoint member capabilities;
- mutate production;
- deploy an Edge Function;
- connect a real provider account;
- send or receive a real message;
- change the Atlas/Vercel application.
