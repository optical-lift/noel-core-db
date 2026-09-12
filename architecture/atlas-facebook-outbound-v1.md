# Atlas Facebook Outbound Transport v1

## Purpose

This candidate lets an authorized Ledger member reply to an existing Facebook Messenger conversation from Atlas without allowing Meta transport to become the authority for institutional responsibility or send intent.

The authority chain is:

1. Atlas already holds an incoming institutional conversation event.
2. A signed-in member with endpoint `send` authority explicitly replies in Atlas.
3. Atlas derives the Facebook recipient from the incoming source event; the caller does not supply an arbitrary PSID.
4. Atlas records an `authorized` outbound operation in the existing communication outbound queue.
5. A transport relay leases that operation.
6. The Facebook worker sends through Meta using the Page token held in Vault.
7. Only an explicit Meta acceptance containing a provider message ID allows Atlas to record the outbound Communication Event as sent.
8. Existing outbound responsibility machinery moves the institutional response case to `waiting_external` and keeps responsibility with the governed Atlas member.

Meta is transport. Atlas is the authority for who intended the reply, who had permission to send it, which Ledger conversation it belongs to, and who carries the resulting responsibility.

## Source versus direction

`atlas.connected_sources` is the provider-account custody object. Receive/send direction is governed by `atlas.communication_endpoint_source_bindings` with `receive`, `send`, or `send_receive` roles.

This candidate does not invent duplicate Page identities such as `page:receive` and `page:send`. A Page source may be authorized for one or both directions, while the endpoint binding remains the directional authority.

## Social reply intent

`prepare_institutional_social_reply_self_api_v1` is deliberately narrower than generic email composition.

It requires:

- an active `social` endpoint;
- active organization membership;
- endpoint `send` capability;
- an existing open institutional conversation associated with that endpoint;
- an incoming Communication Event already admitted to that conversation;
- the same Facebook Connected Source as the incoming event;
- an active `send` or `send_receive` binding for that source;
- source capability `communicationSend:true`;
- existing response responsibility/claim rules.

The Facebook Page-scoped recipient ID is derived from the incoming event's source-attributed speaker address. It is not accepted as caller input.

Version 1 is text-reply only. Arbitrary outbound initiation, attachments, templates, marketing sends, and caller-supplied PSIDs are outside this contract.

## Existing outbound queue

The candidate extends the existing `communication_outbound_operations.operation_kind` check from email-only to:

- `email_send`
- `social_reply`

It reuses the existing:

- outbound operation custody;
- lease semantics;
- transport payload projection;
- provider result history;
- exact canonical outbound event requirement;
- institutional conversation linking;
- responsibility transition after accepted outbound messages;
- expired-lease `transport_uncertain` state.

It does not create a second social-only send queue.

## Messenger policy boundary

Meta's current Send API requires a Page access token with `pages_messaging`. A normal reply is subject to Meta's messaging eligibility rules, including the standard response window unless another allowed opt-in/path applies.

Atlas authorizes institutional intent; it does not claim that provider policy permits transport. Meta remains authoritative for whether a particular request is accepted by its platform at that time.

An explicit Meta rejection is recorded as a transport failure, never as sent.

## Provider acceptance and uncertainty

The transport worker treats outcomes conservatively:

- HTTP success plus a Meta `message_id` = provider acceptance proven.
- HTTP 429 = explicit temporary failure; safe to return to retryable operation state.
- explicit non-5xx provider rejection = failed/rejected transport.
- network failure after request submission = outcome unknown.
- provider 5xx after request submission = outcome unknown.
- HTTP success without a provider `message_id` = outcome unknown.

Unknown outcomes are not recorded as simple failures because Meta may have accepted the message even if Atlas lost the response. The lease is left unresolved so the existing expired-lease reconciler marks it `transport_uncertain` with `automaticResendPermitted:false`.

Atlas therefore avoids duplicating a customer-facing reply merely because a network connection failed at an ambiguous moment.

## Canonical accepted event

On provider acceptance, the worker records an exact outbound `atlas_communication_event_v1` containing:

- Page ID as source account;
- Meta message ID as source event reference;
- existing provider thread continuity from the replied-to event;
- outgoing direction;
- Page as self speaker;
- exact body text;
- Page and PSID participants;
- reply-to provider message context;
- source authority `evidence_only`.

The content hash excludes Atlas `capturedAt`; capture time is provenance, not provider content identity.

The existing outbound result service then admits the event through institutional communication ingestion and invokes the existing response responsibility transition to `waiting_external`.

## Delivery/read truth

A successful Send API call proves provider acceptance, not recipient delivery or read.

The transport receipt therefore records:

- `deliveryProven:false`
- `readProven:false`

Future delivery/read webhook evidence may update observed transport state separately. It must not be inferred from the initial send response.

## Relay authentication

The worker does not expose a public drain endpoint. It authenticates an existing Atlas outbound transport relay using a relay key plus a secret whose SHA-256 digest is compared by the canonical relay authentication service.

The raw relay secret is not persisted by the worker.

## Deployment boundary

This candidate does not:

- deploy the Facebook outbound Edge Function;
- create a production transport relay;
- send a real Facebook message;
- read a real Page token;
- mutate production database state;
- alter the Atlas application repository;
- trigger Vercel.
