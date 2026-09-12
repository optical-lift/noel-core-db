# Atlas Outbound Transport Relay Provisioning v1

## Purpose

This candidate removes an infrastructure setup gap in the Communication outbound rail. The database already authenticates outbound transport relays but production has no governed provisioning function; the existing email relay was therefore provisioned out-of-band.

This candidate adds a service-only provisioning seam for an endpoint/source binding that is already governed by Atlas.

## Authority boundary

Relay provisioning does not create communication authority.

Before any relay row can be inserted or updated, the existing table trigger `communication_outbound_transport_relay_guard_v1` remains authoritative for:

- Connected Source existence and custody.
- Communication Endpoint existence and custody.
- Organization/unit equality between source and endpoint.
- Active endpoint/source binding with `send` or `send_receive` direction.
- Provider/endpoint/transport compatibility supplied by the parent outbound candidate.

For Facebook Messenger that parent guard requires:

- a `social` endpoint;
- a Facebook Connected Source;
- transport kind `facebook_messenger`.

The provisioning function is not an alternative permission path around those checks.

## Credential boundary

The provisioning API accepts only a SHA-256 digest of the relay secret.

- Plaintext relay secrets are not stored in Atlas tables.
- Plaintext relay secrets are not accepted in metadata.
- Plaintext relay secrets are not returned by the function.
- The infrastructure process that generates the secret must keep the plaintext in infrastructure secret custody and supply only its digest to this service.
- The existing relay authenticator continues comparing a supplied digest to the stored digest.

## Provision / rotation behavior

The provisioning identity is `(connected source, communication endpoint, transport kind)`.

- No current row: create one active relay.
- Same relay key: update/rotate the secret digest in place; clear `last_authenticated_at` when the digest changes.
- New relay key: mark the prior current relay `rotated`, preserve it as history, then create the new active relay.
- More than one current `active/disabled` relay for one provisioning identity fails closed as ambiguous custody.

Relay keys remain globally unique under the existing table constraint.

## Disable behavior

A service-only disable function changes relay state to `disabled` and retains the source/endpoint relationship and history. It does not delete a Connected Source, endpoint, outbound operation, or transport attempt.

## Why service-only

A relay is transport infrastructure, not a human communication entitlement. A signed-in Atlas member should never receive the relay credential simply because they have endpoint `send` capability.

Human authority is exercised when Atlas creates an authorized outbound operation. Transport workers then authenticate separately through this relay boundary.

## Deployment boundary

This source candidate does not:

- provision any production relay;
- generate or store a plaintext relay secret;
- mutate production database state;
- deploy an Edge Function;
- connect a Facebook Page;
- send a message;
- change the Atlas application/Vercel project.
