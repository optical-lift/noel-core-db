# Atlas communication source mutations v1

## Purpose

Represent later provider assertions that an already-admitted communication message was edited, deleted, or unsent without rewriting the immutable original communication event and without routing the later assertion through ordinary inbound-response admission.

## Why this is separate from existing source-state enrichment

`communication_event_source_observations` is intentionally for repeated observation of the same source content identity with richer custody/source state. The normal communication ingest path treats a changed `contentHash` for the same source event ref as a custody conflict.

A provider-declared edit/delete/unsend is a third semantic:

- it is not the original message again;
- it is not merely richer capture of unchanged source content;
- it is not necessarily a custody conflict;
- it is evidence that the provider now reports a later state transition concerning the original event.

V1 therefore gives those assertions their own append-only evidence rail.

## Data model

`atlas.communication_event_source_mutations` is tied to exactly one immutable `communication_events` row and carries the same custody root, Connected Source, and source event reference.

Supported mutation kinds in v1:

- `edited`
- `deleted`
- `unsent`

The table stores provider-attributed observed state, optional provider mutation reference/time, Atlas observation time, and a stable evidence SHA-256.

## Idempotency

Atlas does not assume a provider mutation identifier is globally unique or that every provider supplies one. Idempotency is based on:

`event_id + mutation_kind + mutation_evidence_sha256`

The evidence hash excludes Atlas capture time. Re-observing the same normalized provider assertion returns the existing mutation record; materially different edit evidence can append another observation.

## Custody / truth rules

- the original communication event is never overwritten;
- mutation rows are append-only and cannot be updated/deleted;
- the Connected Source must still be connected and authorized for communication capture when the observation is recorded;
- the parent event must already be in Atlas custody under that exact Connected Source/source event ref;
- provider secrets are rejected from observed-state evidence;
- mutation evidence is `evidence_only` and cannot set governing state;
- recording a source mutation creates no response case, Company Work, assignment, read state, or responsibility.

## Provider adapters

Provider adapters should call `record_communication_event_source_mutation_service_v1` only after the provider-specific mutation webhook/event shape has been verified. Atlas must not guess that an ordinary changed payload is an edit or unsend.

The generic rail can ship independently of Facebook/Instagram mutation parsing.

## Presentation

A future conversation projection may render current provider state (for example, “message unsent” or an edit history marker) from the immutable original event plus ordered source-mutation evidence. That projection must never erase the original custody record.
