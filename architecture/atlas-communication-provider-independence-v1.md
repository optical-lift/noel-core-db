# Atlas Communication Provider Independence v1

## Purpose

Atlas must own the durable grammar of communication without making Google, Microsoft, DreamHost, IMAP, SMTP, SMS carriers, or any other external provider the authority over human identity, institutional identity, relationship, conversation, attention, responsibility, or business truth.

The governing sequence is:

`Principal / Organization reality`
→ `Communication Endpoint`
→ `Connected Source`
→ `transport execution / synchronization`
→ `source evidence`
→ `durable Communication Conversation`
→ `attention / actionability`
→ `responsibility or other governed consequence`

A provider may carry communication. It does not own what the communication means or who the communicating parties are in Atlas.

## Governing laws

1. **Endpoint ≠ Identity.** An address, number, handle, mailbox, or provider account is an addressable communication endpoint, not the person or institution itself.
2. **Transport Does Not Own Relationship.** Provider-specific sender IDs, account IDs, thread IDs, mailbox folders, labels, and read flags are source evidence. They do not become Atlas relationship truth.
3. **Connected Source ≠ Endpoint.** `atlas.connected_sources` represents an externally authorized source account. `atlas.communication_endpoints` represents the durable addressable identity that the source presently carries.
4. **Runtime ≠ Connected Source.** Pollers, relays, webhooks, API subscriptions, IMAP sessions, SMTP workers, and other executors are transport/runtime mechanisms beneath a Connected Source. They are not additional provider accounts merely because receive and send use different mechanisms.
5. **Provider Thread ≠ Conversation.** `atlas.communication_threads` remains source-local. A durable Atlas conversation may bind one or more source threads across provider/account changes.
6. **Receipt Does Not Create Response Obligation.** Arrival creates evidence and may create attention. It does not by itself establish that a human response is required.
7. **Visibility ≠ Responsibility.** Opening, reading, searching, or observing a communication does not claim responsibility for it.
8. **Communication ≠ Canonical Business Truth.** A message may contain evidence about demand, sales, payments, commitments, tasks, or other state; those claims must cross the owning domain membrane.
9. **Send Authority Is Atlas Authority.** Provider credentials and transport capability do not grant authority to speak. An authenticated Atlas authority decision precedes transport execution.
10. **Transport Acceptance ≠ Delivery ≠ Read.** Each is separate evidence.
11. **Transport Uncertainty Fails Closed.** Ambiguous execution must not be blindly retried where duplicate consequential communication is possible.
12. **Provider Replacement Must Preserve Atlas Reality.** Moving an endpoint from one carrier to another must not replace its identity, relationship history, durable conversations, human attention history, or responsibility history.
13. **Personal and Institutional Custody Are Parallel.** A durable endpoint and conversation may belong to exactly one Principal or exactly one Organization custody root. Organization-unit custody exists only beneath Organization custody.
14. **Out-of-band Provider Activity Is Evidence, Not Invented Human Attribution.** If a message is sent outside Atlas and the provider does not prove which human acted, Atlas records the provider-observed send without inventing the actor.

## Existing authority retained

This change deliberately preserves the existing communication evidence spine:

- `atlas.connected_sources` remains the one registry of externally authorized accounts;
- `atlas.communication_threads` remains provider/source-local;
- `atlas.communication_events` remains immutable source evidence;
- `atlas.communication_identity_links` and participant relationship resolution remain the reconciliation seam;
- existing Institutional Conversation response/handoff/send authority remains authoritative for institutional responsibility until a later explicit cutover.

The new structures are additive foundations above or below those existing seams. They do not reinterpret historical events.

## Communication Endpoint custody

Before this release, durable Communication Endpoints are Organization-only even though the lower communication ledger already supports Principal-owned Connected Sources, Threads, Events, and Identity Links.

V1 closes that asymmetry by allowing exactly one endpoint custody root:

- `principal_id`, or
- `organization_id` (optionally with `organization_unit_id`).

A Principal-owned endpoint can therefore remain the same durable Atlas endpoint when its carrier changes.

Example:

```text
Nathan
  ├── endpoint A
  │     └── Google Connected Source today
  ├── endpoint B
  │     └── Google Connected Source today
  └── endpoint C
        └── another provider later
```

The endpoint belongs to Nathan's Atlas reality, not to Google.

## Common durable Conversation root

`atlas.communication_threads` intentionally remains source-local. A new additive `atlas.communication_conversations` root sits above source threads and supports exactly one Principal or Organization custody root.

Existing `atlas.institutional_conversations` are not replaced in V1. They are bridged one-to-one into the common conversation root so institutional response-case, work-allocation, handoff, and send-authority behavior remains unchanged.

This gives Atlas a stable place to later join:

- a conversation that moved from one provider to another;
- multiple personal mail accounts participating in one human conversation;
- future SMS / voice / Atlas-native communication evidence;
- source threads that are known to represent the same durable conversation.

No automatic cross-source merge is introduced by this release. Continuity must still be established by explicit evidence or a governed reconciliation operation.

## Generic transport synchronization state

Provider synchronization state must not be hard-coded to IMAP UID semantics.

`atlas.communication_source_sync_states` is a provider-neutral state envelope beneath a Connected Source. It can preserve provider-native cursor/subscription state without granting that state semantic authority.

Examples include:

- IMAP: UIDVALIDITY, finite UID checkpoint, mailbox/folder identity;
- Gmail: history ID, watch/subscription expiration, reconciliation watermark;
- Microsoft Graph: delta token, subscription ID/expiration;
- webhook/push systems: provider cursor or replay token;
- send reconciliation: provider-specific sent-item or submission checkpoint.

The payload remains source evidence. Provider adapters own how to interpret their own cursor state.

## Actionability before responsibility

A new append-only actionability assessment seam records whether an incoming Communication Event has been accepted as:

- `actionable`;
- `informational`;
- `automated`;
- `junk`;
- or remains `unknown`.

This release does **not** yet cut the live Institutional Response Case opener over to that seam. Existing behavior remains unchanged until the actionability classifier/adjudication UX and migration proof are complete.

The eventual required ordering is:

`incoming evidence → actionability → response case only when actionable`

An informational receipt, security notification, newsletter, delivery notice, or automated acknowledgement must not become Company Work merely because it arrived.

## Elm Farm transitional state

Elm Farm currently has two Connected Source records beneath `hello@elmfarm.co`: one used for inbound capture and one used for outbound transport. That is a transitional implementation shape, not the target ontology.

V1 does not collapse those live rows. Source-thread continuity is currently source-bound, so a premature source consolidation could split existing Institutional Conversation continuity.

The safe sequence is:

1. preserve the current two-source Elm arrangement while outbound proof is completed;
2. establish common conversation continuity above source threads;
3. prove cross-source continuation;
4. then normalize Elm so one DreamHost mailbox Connected Source owns multiple runtime mechanisms beneath it.

## Non-authority and non-scope

This release does not:

- connect Gmail or Microsoft;
- change Elm production bindings;
- merge or delete any Connected Source;
- alter existing Institutional Response Case behavior;
- create response responsibility from actionability inference;
- rewrite historical source threads or events;
- infer that two cross-provider threads are the same conversation;
- deploy a persistent communications gateway;
- change provider credentials or secrets;
- change Vercel deployment behavior;
- release any production DDL directly.

## Acceptance conditions

A valid implementation must prove at minimum:

1. existing Organization endpoints remain valid and unchanged;
2. an authenticated Principal can create/read only their own Principal endpoint through the governed API;
3. Principal endpoint ↔ Connected Source binding rejects a source owned by another human or an Organization;
4. Organization endpoint binding keeps its existing Organization/unit custody guard;
5. every Communication Conversation has exactly one custody root;
6. every bridged Institutional Conversation receives exactly one common conversation root;
7. existing source-thread links remain intact and bridge into the common root without rewriting provider thread identity;
8. provider-neutral sync state can represent IMAP, Gmail-style history/subscription, and Microsoft-style delta/subscription payloads without schema changes;
9. actionability assessment is append-only and does not itself create responsibility;
10. direct authenticated mutation of internal foundation tables remains closed except through explicit RPCs.

## Release boundary

This document and its candidate migration are source proposals only. Production release remains governed by the repository's protected validation/release machinery. A passing candidate validation does not itself authorize release.
