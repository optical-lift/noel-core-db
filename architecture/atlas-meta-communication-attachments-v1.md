# Atlas Meta communication attachments v1

## Purpose

Preserve the fact and provider identity of media/file attachments received through Facebook Messenger and Instagram messaging without claiming that Atlas already possesses the underlying bytes.

## Existing Atlas authority

The canonical communication-event contract already admits an `attachments` array, and organization communication ingestion already persists those records into `atlas.communication_attachments`. This candidate therefore changes provider normalization only; it does not create a parallel attachment store.

## Provider normalization

For each provider message attachment Atlas records:

- a deterministic `sourceAttachmentRef`, preferring a provider attachment identifier and otherwise using provider + message event ref + stable array index;
- provider media type as provider-attributed metadata;
- exact transfer/file name only when the webhook supplies one;
- attachment position within the provider message;
- whether a provider URL was present.

The message event also records `attachmentCount` in source payload evidence.

## Custody boundary

A provider URL is not Atlas custody. Provider URLs may be temporary, signed, credential-bearing, revocable, or otherwise unsuitable as durable institutional truth. Therefore v1 deliberately does **not** persist the raw provider URL into durable attachment metadata.

Until Atlas actually fetches and verifies the bytes:

- `custodyLocator` is null;
- `sourceContentHash` is null;
- `mimeType` is null unless a future capture path obtains exact evidence;
- metadata says `custodyState: provider_reference_only`.

The attachment row proves that the provider reported an attachment on that source message. It does not prove Atlas retained the media, that a URL remains usable, or that the bytes have any particular MIME type or hash.

## Future capture path

A later governed media-capture worker may, while authorized provider access is valid:

1. retrieve the provider attachment through the provider transport;
2. stream bytes into Atlas-controlled object storage without exposing provider credentials to clients;
3. compute a content hash while streaming;
4. derive exact MIME/name evidence where available;
5. update the attachment with an Atlas-owned custody locator and verified source content hash;
6. retain provider retrieval metadata as provenance, not authority.

That worker is intentionally outside this v1 candidate.

## Comments

A social comment's associated post/media is context, not automatically an attachment sent by the commenter. Facebook feed-comment and Instagram comment normalization therefore do not manufacture communication attachments from post/media references.

## Truth rules

- attachment existence may be provider evidence;
- provider media type is provider-attributed metadata, not MIME truth;
- raw provider URLs are not durable Atlas custody;
- ingesting an attachment never claims response responsibility;
- attachment evidence participates in the stable communication content hash, so retries with the same provider message content remain idempotent while materially different attachment evidence is detectable.
