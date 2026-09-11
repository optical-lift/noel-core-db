# Atlas Facebook Historical Inbox Sync v1

## Purpose

This candidate reconstructs Facebook Page Messenger history after a Page has been explicitly selected and connected to Atlas. Historical provider data becomes source-attributed communication evidence. It does not pretend Atlas observed the messages live, and it does not retroactively manufacture response responsibility.

## Provider basis

Meta's current Conversations API supports:

- listing conversations for a Facebook Page or Instagram Professional account;
- listing messages within each conversation;
- message sender and sent-time details;
- inbox syncing on past conversations when an account is newly connected.

Meta also documents important coverage limits. In particular, Requests-folder conversations that have not been active for 30 days may not be returned. Atlas therefore records historical sync as provider-reported coverage and never asserts that the returned history is complete.

## Authorization

Historical sync is an explicit setup/configuration action.

`provider_history_sync_context_self_api_v1` authorizes only:

- the signed-in human who owns a human-custody source; or
- an actor who already has organization provider-connection authority for an organization-custody source.

The authorization RPC returns no provider credential.

The Edge Function obtains the selected Facebook Page credential through a service-role-only Vault read. The Page token is never returned to the browser and is not stored in Connected Source metadata.

## Pagination

The browser may provide and receive Meta's opaque `after` cursor to resume conversation-list pagination.

Atlas deliberately does not return Meta's `paging.next` URL because provider-generated paging URLs can contain the Page access token.

A single invocation is bounded by a caller-selectable conversation count capped at 100. Conversation message pagination is also bounded. If a conversation exceeds the bounded message fetch, the receipt marks that conversation as truncated rather than claiming complete capture.

## Canonical evidence

Each historical Messenger message becomes `atlas_communication_event_v1` evidence with:

- source kind `facebook`;
- Page ID as `accountRef`;
- provider message ID as immutable source event reference;
- provider conversation ID as source-local thread continuity;
- provider sent time as `occurredAt`;
- Atlas retrieval time as `capturedAt`;
- exact text when supplied by Meta;
- provider sender/recipient identities as source participants;
- provider attachment metadata retained as source payload evidence.

`captureMode` is `provider_sync`, not `provider_webhook`.

## Stable source hashing

Atlas capture time is provenance, not provider content. Historical event `contentHash` therefore excludes `capturedAt` and `contentHash` itself.

Re-fetching the same unchanged Meta message at a later Atlas capture time must remain idempotent rather than creating a false content conflict.

The same stable-source-hash rule should govern live provider normalization as well; live Facebook normalization is tracked separately so its already-open validation stack is not rewritten mid-gate.

## Organization history does not create response work

This candidate deliberately routes organization historical evidence through `ingest_organization_communication_events_service_v2`, not v3.

- v2 admits source evidence into the institutional conversation graph.
- v3 additionally creates/touches institutional response cases.

Using v3 for historical backfill would make an old inbound message appear to require a new response today. That is not justified by provider history alone.

Therefore historical organization sync stops at v2 and returns `responseWorkCreated:false`.

Reading, syncing, or importing historical messages does not claim responsibility, assign a person, or create a handoff.

## Principal history

For human-custody sources, the provider-history router dynamically invokes the Principal communication ingest seam when that governed dependency is present. The migration remains schema-valid without falsely assuming the stacked Principal provider candidate is already in production.

## Coverage receipt

Every sync response carries explicit coverage/truth fields including:

- `providerReportedOnly:true`
- `requestsFolderInactiveOver30DaysMayBeAbsent:true`
- `completenessNotAsserted:true`
- `historicalBackfill:true`
- `responseWorkCreated:false`
- `readStateInferred:false`
- `responsibilityInferred:false`

## Deployment boundary

This candidate does not:

- deploy the history Edge Function;
- connect or read a real Facebook Page;
- mutate the production database;
- configure Meta credentials or app review;
- alter the Atlas application repository;
- trigger Vercel.
