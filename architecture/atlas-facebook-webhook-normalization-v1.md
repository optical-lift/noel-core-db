# Atlas Facebook Webhook Normalization v1

## Purpose

This candidate adds the live inbound Facebook Page transport edge above the explicit Facebook asset-selection layer. It converts supported provider notifications into source-attributed Atlas communication evidence without allowing Meta to define Atlas responsibility, durable conversation identity, or Ledger truth.

## Supported inbound evidence

### Messenger

For a selected Facebook Page Connected Source, `messages` webhook envelopes are normalized into `atlas_communication_event_v1` events.

- Page ID is the source account reference.
- Meta message `mid` is source-local event identity.
- Page-scoped sender/recipient IDs remain provider evidence identifiers.
- Atlas direction is derived relative to the selected Page.
- Provider thread continuity is represented beneath Atlas conversation authority as `messenger:<other-party-id>`.
- Text is preserved when Meta supplies exact text.
- Attachments without text are admitted as empty-body communication evidence rather than invented text.

### Page comments

`feed` webhook changes are admitted only when the provider item is a `comment`.

- Comment ID is the source-local event identity.
- Parent comment or Page post identity supplies provider-local continuity.
- Comment text and provider sender identity are retained as evidence.
- Page-authored comments are marked outgoing relative to the Page.
- Likes, reactions, and unrelated feed changes are deliberately ignored by the communication normalizer.

This prevents social engagement telemetry from automatically becoming an Atlas conversation.

## Signature and verification boundary

The adapter supports Meta webhook verification using the configured verification token and requires `X-Hub-Signature-256` HMAC validation with the Meta app secret before processing a webhook POST.

Invalid or absent signatures are rejected before source resolution or evidence ingestion.

## Source resolution

The webhook entry Page ID must resolve to exactly one connected `facebook` Connected Source. Ambiguous or missing custody fails closed through the provider-neutral source resolver.

The adapter does not infer Ledger ownership from a Facebook user, Page name, sender ID, or webhook payload.

## Replay protection

Each normalized event is passed through the provider-neutral webhook delivery rail.

- Messenger delivery key: provider message ID.
- Comment delivery key: provider comment ID plus provider verb.
- Same delivery identity with the same payload is retry-safe.
- Conflicting replay remains a provider-rail conflict rather than silently overwriting Atlas evidence.

## Authority boundary

Facebook webhook evidence may append source-attributed communication observations. It may not directly:

- claim responsibility;
- assign a person;
- hand work to another person;
- mark Company Work complete;
- declare a customer relationship;
- merge identities;
- move a conversation between custody roots;
- create business truth from a reaction or other non-communication feed event.

Reading the resulting evidence in Atlas still does not claim responsibility. Organization response ownership remains governed by the institutional conversation / Company Work responsibility machinery.

## Historical inbox sync

This candidate is live-webhook ingestion only. Meta's Conversations API can support historical inbox synchronization for newly connected Pages, but that is intentionally a separate backfill/sync candidate so historical import does not get confused with live webhook delivery semantics.

## Deployment boundary

This source candidate does not:

- deploy the Edge Function;
- configure a Meta webhook callback;
- create or configure a Meta developer app;
- connect a real Facebook Page;
- mutate production database state;
- modify the Atlas application repository;
- trigger Vercel.
