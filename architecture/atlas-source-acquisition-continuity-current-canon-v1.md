# Atlas Source Acquisition Continuity — Current Canon v1

**Status:** Architecture contract for the second External Source Continuity implementation slice  
**Established:** September 19, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**Depends on:** atlas-provider-connection-activation-current-canon-v1  
**Does not supersede:** Connected Source custody, provider-specific adapters, Communication/Identity/Money/Work authority, or domain-specific conflict/adjudication.

## 1. Purpose

The first Source Continuity slice establishes lawful provider connection custody and activation.

The next cross-provider failure appears after connection: Atlas can repeatedly receive or fetch the same external object without one shared law for distinguishing:

- provider acquisition;
- repeated observation of the same provider revision;
- source coverage/checkpoint advancement;
- domain admission;
- domain conflict;
- downstream consequence.

If those collapse, every provider adapter can create its own retry, dedupe, checkpoint, and conflict rules.

This contract separates them before Google, Meta, Stripe, files, calendars, accounting systems, or other providers add new local continuity machinery.

## 2. Live production evidence

This contract is derived from current production behavior, not from unused generic abstractions.

### Apple Messages

Current production contains approximately:

- 4,183 Communication events;
- 1,171 ingest batches;
- live_capture acquisition;
- repeated deliveries often classified as already in custody.

The existing relay can recognize an event with the same source identity/content and avoid creating a second Communication Event.

### Email

Current production contains approximately:

- 25 admitted Communication events;
- 4,793 ingest batches since September 11;
- 4,766 conflict delivery attempts;
- one durable Communication conflict identity for the repeatedly conflicting source event.

From September 15 through September 19, the email relay admitted zero new events while continuing to submit hundreds of conflict attempts per day.

The Communication conflict table correctly deduplicates the conflict row. The acquisition path does not yet have a governed notion of:

> this provider object/revision has already been observed and is still an unresolved domain conflict; source coverage may advance without re-admitting it.

### Important negative evidence

Current production has zero live rows in:

- atlas.connected_source_observations;
- atlas.communication_source_sync_states;
- atlas.communication_mailbox_sync_checkpoints.

Those tables may contain useful prior design work, but zero live use means they are not promoted to shared authority merely because their names look generic.

The next shared contract must be derived from live acquisition behavior plus current domain custody.

## 3. Governing separations

The following are different facts:

    provider acquisition receipt
    != provider observation
    != source coverage/checkpoint
    != domain admission
    != domain conflict/adjudication
    != domain consequence

A provider adapter proving that Atlas saw an external object does not mean the owning domain accepted its interpretation.

A domain refusing or deferring an object does not mean the provider acquisition failed.

A source may safely advance coverage past a known object after durable observation identity is established, even when the object's current domain disposition is conflict/deferred/rejected.

## 4. Governing movement

    active Connected Source
    -> provider delivery/fetch
    -> acquisition identity established
    -> provider object revision observed idempotently
    -> owning domain receives bounded observation
    -> domain returns its own admission/disposition receipt
    -> source coverage/checkpoint advances independently where provider rules allow
    -> later provider revision or domain adjudication may produce new work

The shared rail ends at durable source acquisition/coverage custody.

It does not decide Communication truth, Identity truth, Money truth, Work truth, commerce truth, or institutional consequence.

## 5. Acquisition identity

Every adapter must establish a provider-side acquisition identity sufficient to recognize redelivery.

At minimum, a shared acquisition record needs:

- Connected Source id;
- provider object kind or stream kind;
- provider object key or delivery key;
- provider revision/version/content digest where available;
- first observed time;
- last observed time;
- observation/repeat count;
- acquisition channel/stream key when one source exposes multiple independent streams;
- bounded provider provenance;
- current handoff status/reference to the owning domain's receipt when applicable.

Provider object key is not Atlas domain identity.

Examples:

- email: RFC Message-ID/source event ref plus source revision/content identity;
- Apple Messages: source event ref plus content/custody hash;
- Stripe: provider event/object id plus provider version/event identity;
- Google/Microsoft: resource id plus etag/history/delta revision as appropriate;
- file provider: file id plus revision/etag/content version.

The shared layer must not invent one provider-neutral semantic meaning for those objects.

## 6. Idempotent observation law

Re-observing the exact same provider object revision must not create another logical source observation.

It may update only bounded continuity facts such as:

- last observed time;
- repeat count;
- latest delivery provenance;
- latest provider transport receipt.

A genuinely changed provider revision may create a new observation identity.

The adapter must distinguish:

    same object + same revision
    same object + changed revision
    different object

A domain conflict does not alter these provider-side identity rules.

## 7. Domain admission law

After acquisition identity is established, the provider adapter may hand a bounded observation to the owning domain.

The domain owns the result.

Examples of domain-owned results include:

- admitted;
- already in custody;
- source-state enrichment;
- conflict;
- unresolved identity;
- ignored by domain policy;
- deferred for adjudication.

Those labels are not universal provider states.

The shared acquisition layer may retain a reference to the domain receipt and enough terminal/nonterminal information to avoid blind redelivery, but it must not become the owner of domain conflict semantics.

## 8. Known conflict law

A durable domain conflict is not evidence that the provider has failed to deliver the object.

If:

- acquisition identity is stable;
- the same provider revision is observed again;
- the owning domain already has a durable unresolved conflict for that revision;

then subsequent deliveries are repeated acquisition of known evidence, not new conflicts.

The provider continuity layer must be able to return a bounded result equivalent to:

    acquisitionKnown = true
    providerRevisionChanged = false
    domainDispositionAlreadyExists = true
    coverageMayAdvance = adapter/provider policy

without creating another logical conflict or forcing the connector to retry the same object forever.

## 9. Coverage/checkpoint law

Source coverage answers:

> Through what provider position/window/stream has Atlas safely observed?

It does not answer:

> Which domain facts are accepted?

A shared coverage position may preserve:

- Connected Source id;
- provider stream/channel key;
- opaque provider checkpoint/cursor/revision token;
- coverage window start/end where the provider is window-based;
- checkpoint observed/committed times;
- adapter/version basis;
- reset/reconciliation state;
- non-secret metadata.

Provider checkpoint values remain provider-specific and may be opaque.

The shared rail does not compare arbitrary provider cursors unless the provider adapter supplies the monotonicity/reset rule.

Coverage advancement must be service-side and must be based on durable acquisition custody, not on presentation/UI state.

## 10. Coverage may advance over domain conflict

The default law is:

    durable acquisition custody
    + provider-specific checkpoint rule satisfied
    -> coverage may advance

Domain admission success is not required merely to advance source observation coverage.

This prevents one domain conflict from causing infinite provider replay.

Exceptions are provider-specific and must be explicit: for example, if advancing a cursor would make it impossible to reacquire evidence that Atlas has not durably captured.

## 11. Raw evidence and payload custody

The shared rail should not duplicate domain-owned payload custody.

Where a provider object requires raw evidence preservation, the owning adapter/domain may retain raw bytes, payload hashes, storage locators, or normalized observation payloads under its existing custody.

The acquisition rail may retain hashes/identifiers needed for idempotency and proof.

Reusable credentials, authorization codes, refresh tokens, API keys, webhook secrets, or passwords remain forbidden outside Connected Source secret custody.

## 12. Communication remains a proof domain, not shared ownership

Communication currently has:

- communication_ingest_batches;
- communication_event_source_observations;
- communication_event_conflicts;
- communication_raw_message_custody;
- Communication Event/Conversation authority.

Those remain Communication-owned.

The Source Continuity tranche may factor out shared acquisition/coverage behavior beneath them, but it must not move Communication Event or conflict authority into a provider-generic table.

The existing IMAP-specific mailbox checkpoint carrier is transitional unless separately proven. It must not become the template for Gmail/Microsoft/Meta/file/accounting checkpoint tables.

## 13. Existing provider-neutral observation table

atlas.connected_source_observations currently provides a useful provider-object identity shape:

    connected_source_id
    + provider_object_kind
    + provider_object_key
    + payload_sha256

and idempotent insertion by that identity.

However, current production has no live rows in this table.

Therefore this contract does not declare it canonical simply by name.

Implementation may reuse/factor it only if production-shaped validation proves it can satisfy the acquisition laws without absorbing domain authority or requiring provider payload duplication.

## 14. Required first implementation slice

The next implementation should be deliberately small.

It should provide one governed source-acquisition seam that can prove:

1. stable Connected Source is required;
2. provider object identity/revision can be recorded idempotently;
3. exact redelivery is recognized without minting another logical observation;
4. changed provider revision is distinguishable;
5. the owning domain can return/retain its own disposition;
6. known unresolved domain conflict does not become a new conflict on redelivery;
7. source coverage/checkpoint can advance independently from domain admission;
8. checkpoint advancement cannot silently regress except through explicit reset/reconciliation;
9. retries do not widen Connected Source custody or provider capabilities;
10. no provider credential enters acquisition/checkpoint metadata.

The first proof should use current Communication paths because Apple Messages and email already exhibit two different acquisition patterns.

## 15. Explicit non-scope

Do not add yet:

- universal webhook event semantics;
- universal normalized provider object schema;
- universal domain conflict table;
- universal source health score;
- provider-specific Gmail/Meta/Stripe domain mapping;
- provider scheduler/orchestrator;
- generalized event bus;
- provider-side mutation/outbound execution;
- source-to-domain AI interpretation;
- automatic conflict adjudication.

Those require later proof.

## 16. Repair target exposed by current email behavior

The current email relay repeatedly delivers the same source event whose incoming content/custody identity conflicts with an existing Communication Event.

Communication correctly retains one durable conflict row through its uniqueness constraint.

The ingest batch still reports each redelivery as another conflict attempt, and the provider relay continues retrying it.

The Source Continuity repair must permit the relay to distinguish:

- first discovery of conflict;
- exact redelivery of already-known conflict;
- genuinely changed provider revision that deserves fresh domain consideration.

Only the third should behave like new evidence.

## 17. Validation evidence required before release

A production-schema clone validation for the first acquisition/coverage implementation must prove at minimum:

1. inactive/revoked Connected Source cannot acquire;
2. same provider object + same revision is idempotent;
3. same provider object + changed revision is distinguishable;
4. exact redelivery increments bounded repeat/last-seen evidence rather than minting logical duplicates;
5. acquisition record contains no reusable secret;
6. domain receipt is referenced without becoming provider identity;
7. domain conflict remains owned by the domain;
8. known conflict redelivery does not create another logical conflict;
9. known conflict redelivery may advance coverage when adapter rule permits;
10. coverage position is source/stream-specific;
11. provider checkpoint is opaque to shared infrastructure;
12. checkpoint cannot silently move backward;
13. explicit reset/reconciliation can replace an invalidated checkpoint;
14. retry does not change Connected Source custody;
15. retry does not widen provider scopes/Atlas capabilities;
16. Communication Apple Messages acquisition still behaves idempotently;
17. Communication email conflict behavior becomes bounded;
18. existing domain events/conflicts remain byte/identity stable;
19. no unused generic table is promoted without live/proof evidence;
20. no production release is implied by source merge.

## 18. Next proof fixture after this slice

Once acquisition/coverage is canonical, replay one concrete modern provider adapter against it.

Google/Gmail remains a useful fixture because it exercises OAuth connection, provider account identity, history/delta style coverage, changed-message state, and Communication mapping without requiring the shared rail to know Gmail semantics.

Meta and Stripe remain later fixtures with different provider-object and mutation patterns.
