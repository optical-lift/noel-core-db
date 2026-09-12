# Atlas Personal Communication Provider v1

## Purpose

Prove that a person's existing communication account can enter Atlas without allowing the provider to define Atlas identity, endpoint identity, conversation identity, attention, responsibility, or business truth.

The first intended fixture is a personal Google/Gmail account, but this contract is provider-independent.

## Governing movement

`authenticated Principal`
→ `provider OAuth authorization`
→ `Principal-owned Connected Source`
→ `durable Principal Communication Endpoint`
→ `provider sync evidence`
→ `Communication Event`
→ `source-local Communication Thread`
→ `durable Communication Conversation`
→ `Personal Atlas read surface`

## Source versus endpoint

The provider account and email address are deliberately separate.

- Connected Source: the externally authorized provider account, keyed by the provider's stable account identifier where available.
- Communication Endpoint: the durable address, such as an email address, that belongs to the Principal's communication reality.

Changing a provider, provider account implementation, or transport runtime must not recreate the endpoint or erase Atlas conversation history.

## Generic Principal provider registration

`register_principal_connected_source_self_api_v1` is the person-owned counterpart to organization source registration. It does not create a communication relay credential. OAuth/API providers are not modeled as local-device relays merely because both eventually produce communication evidence.

The authenticated Principal may establish or refresh only a Connected Source whose custody root is their own authenticated user. Reusable provider tokens remain outside browser-readable tables and are stored through the existing Vault-backed service credential seam.

## Provider ingestion

`ingest_principal_communication_events_service_v1` is service-only. It accepts the same evidence-only canonical communication event grammar already used by Atlas communication custody:

- immutable provider event reference;
- provider/source-local thread reference;
- exact observed direction/speaker/body state;
- canonical participants;
- source payload/provenance;
- deterministic source hash.

Ingestion may create source evidence and durable conversation continuity. It may not create Tasks, Company Work, commitments, sales, payments, or response obligations.

## Durable personal conversation

`communication_conversation_events` explicitly binds Communication Events into the common provider-independent conversation root.

For a Principal-owned provider event, admission:

1. resolves the active Principal endpoint carried by the Connected Source;
2. reuses an already-bridged source thread when present;
3. otherwise creates a durable Principal Communication Conversation;
4. records the endpoint and source-thread bridges;
5. records event membership.

Provider thread identity is continuity evidence, not the durable Atlas conversation identity. Cross-provider conversation merging remains a later explicit reconciliation operation; V1 does not infer it from subject similarity.

## Personal Atlas read membrane

Authenticated Principal reads are exposed only through governed RPCs:

- endpoint/source inventory;
- bounded conversation list;
- conversation detail.

The browser does not receive provider refresh tokens, service credentials, raw internal table access, or provider-ingest authority.

## Google/Gmail fixture boundary

The first Google adapter should prove only:

1. OAuth authorization by the signed-in Principal;
2. provider account identity verification from Google rather than user-entered text;
3. Vault custody of reusable OAuth credentials;
4. Principal Connected Source registration;
5. durable email Endpoint creation/binding;
6. a bounded initial message sync;
7. readback through provider-independent personal conversations.

Push subscriptions, full-history import, provider read/archive mutation, send authority, and public OAuth verification are deliberately outside this first proof.

## Non-authority

This slice does not:

- make Google/Gmail an Atlas identity provider;
- treat an email address as the Principal;
- infer relationships merely from provider contacts;
- infer responsibility from incoming mail;
- grant send authority merely because OAuth permits sending;
- expose provider secrets to the authenticated browser;
- create a Gmail-specific canonical inbox;
- require a permanent provider runtime.

## Release boundary

Database migrations remain source candidates until the protected production-schema validation and release lanes approve the exact candidate SHA. Application code must remain gated on released RPCs and may not simulate missing database authority.