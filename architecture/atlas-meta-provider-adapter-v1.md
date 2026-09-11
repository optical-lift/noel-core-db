# Atlas Meta Provider Adapter v1

## Purpose

This adapter is the first concrete social-provider implementation on top of the provider-neutral Atlas communication rail. It proves that a real external social account can be authorized, placed into the correct Atlas custody root, and normalized into Atlas communication evidence without allowing Meta to define durable Atlas identity, conversation identity, responsibility, or business truth.

## First supported path: Instagram Login

The first concrete adapter uses Instagram Login for an Instagram professional account.

The adapter is responsible for transport concerns only:

1. Build the provider authorization URL.
2. Correlate the callback to a short-lived Atlas provider connection session.
3. Validate the callback state against the digest stored in Atlas.
4. Exchange the provider authorization code for provider tokens.
5. Discover the provider account identity returned by Instagram.
6. Complete the pending Atlas Connected Source identity.
7. Put the reusable access token into Supabase Vault through the provider secret custody service.
8. Activate the Connected Source only after durable credential custody exists.
9. Subscribe the selected Instagram account to supported webhook fields.
10. Verify webhook signatures before accepting provider evidence.
11. Normalize supported messages/comments into `atlas_communication_event_v1` evidence.
12. Route those normalized events through the existing custody-aware provider ingest seam.

## Custody

A provider connection session chooses custody before provider authorization begins:

- `human` means the Connected Source belongs to the signed-in Principal's Atlas custody root.
- `organization` means the Connected Source belongs to the explicitly authorized Ledger/organization custody root.

A provider callback cannot change that custody choice.

The same external provider account must not be silently resolved into multiple Atlas custody roots. Webhook source resolution fails closed if the provider account is ambiguous.

## OAuth state

The browser-visible OAuth `state` value is not stored raw in Atlas. Atlas stores only its SHA-256 digest in the short-lived connection session.

The provider callback carries a state value shaped so that the gateway can recover the Atlas connection session identifier. The gateway hashes the complete returned state and a service-only database function proves that the digest exactly matches the pending session before any provider identity is accepted.

The raw OAuth state, authorization code, PKCE verifier, provider client secret, reusable access token, and webhook verification secret are not communication evidence and are not stored in Connected Source metadata.

## Credential custody

Reusable provider credentials are stored through Supabase Vault and referenced through `atlas.connected_source_secret_refs`.

A source remains `pending` after provider identity is known. It becomes `connected` only after the required reusable credential is confirmed to exist in Vault custody.

This prevents an interrupted OAuth callback from creating a source that falsely appears connected.

## Webhook boundary

Provider webhook signatures are verified at the adapter edge before an idempotent Atlas delivery receipt is created.

The adapter then:

- resolves the external account to exactly one connected Atlas source;
- produces canonical evidence-only events;
- computes source content hashes;
- records provider delivery identity for replay protection;
- invokes the provider-neutral custody router.

A duplicate provider delivery with the same content is retry-safe. Reuse of the same provider delivery identity with conflicting content is not silently accepted.

## Evidence only

Meta payloads may contribute source-attributed evidence. They may not directly:

- create Atlas responsibility;
- claim work for a person;
- hand work to another person;
- mark Company Work complete;
- create or alter a Ledger business fact merely because Meta emitted a payload;
- define the durable Atlas conversation root;
- merge two provider identities into one person;
- move a conversation between custody roots.

Those effects remain governed by Atlas authority above the transport adapter.

## Instagram messages and comments

The first adapter normalizes supported Instagram direct-message and comment notifications.

Provider-local message IDs and comment IDs remain source evidence identifiers. Provider-local thread continuity is evidence beneath Atlas's provider-independent Communication Conversation.

Reading an Instagram event in Atlas does not claim responsibility. Organization responsibility continues to use the existing institutional response-case / Company Work responsibility machinery.

## Deliberately deferred: Facebook Login asset fan-out

Facebook Login is not represented as one Connected Source merely because one Facebook user authorized Atlas.

A Facebook user authorization can expose multiple Page assets and linked Instagram professional accounts. Those assets may belong to different Ledgers or may not belong in Atlas at all.

Therefore a future Facebook Login adapter must implement an explicit discovery and selection stage:

1. authorize the human Facebook account;
2. discover administrable Page / linked Instagram assets;
3. display those discovered assets as candidates, not connected truth;
4. let the authorized Atlas actor select which assets belong to the intended custody root;
5. create separate Connected Sources/endpoints for the selected business assets;
6. preserve the authorization relationship separately from each asset's durable Atlas identity.

The adapter must never collapse multiple Pages or Instagram accounts into one Connected Source simply because they were discovered from the same Facebook login.

## Deployment boundary

This source candidate does not:

- create a Meta developer application;
- configure production Meta credentials;
- connect Elm Farm or any real Instagram/Facebook account;
- deploy the Edge Function;
- mutate the production database;
- modify the Atlas application repository;
- trigger a Vercel deployment.

Deployment and real-account authorization require separate explicit authority after schema and source validation.
