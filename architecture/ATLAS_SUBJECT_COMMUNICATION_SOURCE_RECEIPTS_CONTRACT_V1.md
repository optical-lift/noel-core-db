# Atlas — Subject-related communication provenance and delivery evidence contract v1

**Status:** Governing build contract, no new transport source or Event mailbox authorized.  
**Established:** October 22, 2026.  
**Build priority:** Addition 3, after schedule-disposition and outcome-evidence contract are established.

## 1. What this capability answers

A Ledger participant opening a subject or date should be able to tell **what communications actually happened, through what system, and with what degree of confirmed result**.

Atlas must not convert plans, draft emails, clicks, keyword matches, recipient counts or user expectations into proof that a message was sent, delivered, read or answered.

The same source communication can appear through the Event, the Person's authorized correspondence, or the Ledger activity lens; **it stays one communication identity with source-owned evidence**. This is a relationship/read composition, not another Event mailbox.

## 2. Existing source machinery, observed boundaries

- Source-observed communication: `atlas.communication_events` (connected source, exact `source_event_ref`, happened/captured time, direction, body state, source authority and content/custody hash).
- Conversation continuity: `atlas.communication_conversation_events` and communication Conversations; compatibility institutional conversation may remain a distinct envelope, not a duplicate message.
- Outbound request and transport result: `atlas.communication_outbound_operations`, `atlas.communication_outbound_attempts`, `atlas.communication_outbound_event_links`. Operation state includes `authorized`, `leased`, `accepted`, `partially_accepted`, `temporary_failure`, `transport_uncertain`, `failed`, `cancelled`; transport attempt includes `accepted`, `partially_accepted`, `rejected`, `transport_error`, `unknown`. **Provider acceptance does not prove delivery or being read.**
- Authenticated send-intent command: `atlas.prepare_communication_email_send_self_api_v2`, which delegates to the canonical communication send machinery only after a distinct `message.send` authority check. Preparing/authorizing a send intent is not a provider acceptance or delivery receipt.
- Optional source relationships: `atlas.communication_identity_links` and `atlas.communication_derived_work_links` are established constructs with their own scope and purpose; **neither may be assumed to be the correct Event relationship writer without an owner/schema/privacy audit**.
- Canonical Event identity: `local_intel.occurrences.id`; exact institution bridge: `atlas.organization_occurrence_bindings`, `ledger.occurrence_calendar_bindings`.
- Event relationship candidates: `atlas.organization_occurrence_relationship_links` holds participant/vendor roles and engagement state, **not** proof that a message or invitation was transmitted.
- Current outbound attempt and operation counts in the earlier Atlas audit were zero. Absence of records in these tables is **unknown external activity**, not proof no one sent an email.

## 3. Establishing subject relation, not matching words

When a person chooses **Compose from this subject**, the source-owned communication operation should receive an exact permitted relation intent:

```text
subjectRelationIntent:
  relationKind: about | invited_for | confirming_for | followup_for | other governed key
  ledgerId: source-verified institutional context
  organizationId: source-bound to that Ledger, not guessed from Person seat
  occurrenceId: existing canonical Occurrence
  occurrenceBindingId: exact active institution↔Occurrence binding
  evidenceBasis: authored_in_subject | explicit_human_link | verified_source_relation
  actor: signed Person and sending/reading permission
  sourceActionId: stable idempotency key
```

An exact source operation ID or communication event ID must later attach to this relation using an authorized **Organization-private subject link**. The schema/writer may reuse an existing general-purpose relationship facility **only if its custody, authorization and uniqueness contracts fit**. Do not add generic `calendar_event_email` or `event_messages` copies.

If a reply arrives, it may inherit a relationship **only when exact provider thread/message ancestry and organization authority support it**. Same subject line, date or keyword does not prove the same Event. Historic messages may be manually linked; auto-match from a verified source edge may be admitted, while uncertain candidates stay unlinked pending confirmation.

## 4. Evidence vocabulary

Each displayed line must have a source-qualified state. These are **meaning distinctions**, not a demand to insert invented states into an existing enum.

| Display proposition | Minimum evidence | Must NOT infer |
| --- | --- | --- |
| Planned / needed | Work or communication intention | Drafted or sent |
| Draft composed | Saved draft / source content receipt | Authorized or dispatched |
| Send authorized | Authenticated approved operation | Provider accepted |
| Send attempted | Transport attempt with time | Sent successfully |
| Provider accepted | Source transport receipt for this exact attempt | Recipient delivery/read |
| Delivery confirmed | Independent provider delivery state or equivalent source observation | Open/read |
| Read/open observed | Provider-specific evidence with qualifiers and reliability | Human understood/accepted |
| Reply received | Exact source message/event with matched thread or permitted manual source link | Confirmed attendance |
| Commitment confirmed | Source-specific lawful booking/response/acceptance evidence | Payment received |
| Payment recorded | Payment source receipt with confirmed scope | Message delivered |

Manual calls and in-person conversations are also eligible **only as explicit actor-attested contact observations** (date, person, channel, result), not fabricated provider-verified events. A phone note that a person said “maybe” does not become a confirmed vendor. External send through a personal account without a connected source must be tagged `reported_sent_unverified` or equivalent, not source-verified delivered.

## 5. Composition and exactly-once consequences

1. Use one governed source **send** command, a source-scoped idempotency key and the exact subject relation; no Event-specific email sender.
2. Validate sender identity/endpoint grants independently of whether a Person can open the Event workspace. Event participation is not automatically permission to send from the Ledger's mailbox.
3. Persist link intent transactionally with a lawful outbound operation or durable separately identified pending relationship. Confirm again against actual provider operation/event identity when that source event exists.
4. Represent each transport attempt separately from the outbound operation and confirmed source event. A retry is not a fresh communication relationship unless source identity proves another send. Do not double count to/cc/bcc recipients or attempts as unique messages.
5. Inbound replies are linked by verified conversation ancestry, or via explicitly established human association. Ambiguous candidates show a review queue, not current evidence.
6. Preserve exact actor, recipient eligibility, source timestamp and timezone, custody/receipt IDs, operational date and status meaning. Never expose restricted conversation content to all Ledger people merely because an Event title is shared.
7. For counts, state denominator and provenance: e.g. number of **provider-accepted operations**, not `emails sent` if transport is still uncertain. Separate named contacts, attempts, unique accepted operations, delivered recipients, replies and source-confirmed commitments.
8. Keep Work and communication distinct: `Email churches` Work can be Done when its Work result policy is satisfied, but that does not manufacture provider send receipts. Conversely an email accepted by provider is not evidence that a person agreed to perform a requested task.
9. A schedule correction may flag previously sent communications as potentially stale. It may generate **suggested follow-up Work**, but does not itself send another email or silently modify the old message.

## 6. Subject notebook read envelope — conceptual

```text
subject: exact Ledger + canonical Occurrence
coverage:
  admitted source families, permissions, timestamps, freshness, partiality
communicationActivity:
  sourceRef: canonical operation/event/conversation ID
  relationRef: exact authorized Event subject relationship
  whoActed: authenticated Person or source-observed sender (distinguished)
  audience: exposed only under source privacy law
  channel: email / phone-attested / in_person-attested / other
  occurredAt: source-qualified timestamp, not the Event's date
  evidenceState: draft / authorized / attempt / accepted / delivered /
                 response / confirmed / reported-unverified / unknown
  evidenceRef: provider operation/attempt/event/booking/payment, if any
  outcome: source-specific language only
  uncertainOrSuggested: explicit boolean
```

The subject workspace can summarize these entries without creating a second communication repository.

## 7. User-visible tests

1. Compose from an authorized Event: outbound intent retains exact Occurrence and Ledger source identities without copying messages to an Event mailbox.
2. Preparing the email produces **authorized/draft**, not `sent`; an actual provider acceptance advances only the corresponding transport evidence state.
3. Failed, unknown, partially accepted and retried transport report their actual states; send totals deduplicate by source operation IDs.
4. Source-confirmed delivery, read, reply and attendance are distinct and are not inferred from provider acceptance.
5. A manually recorded call is legibly **recorded by Person**, not presented as provider-observed.
6. A reply linked by exact source thread appears under the original subject; a matching phrase in an unrelated message is not silently linked.
7. One message concerning two canonical subjects preserves one message identity and distinct authorized subject links without duplicate counts in a selected subject.
8. Cross-Ledger actor, unauthenticated user, member lacking mailbox permission and Event viewer lacking content permission are correctly denied independent of the shared Work grant.
9. Personal correspondence stays private even if about a Ledger Event; employer/Organization mailbox rights never become Person Life rights.
10. Removing an erroneous subject link does not delete the source message or rewrite its transport receipt.
11. Source event arrives late/out of order or recipient revokes permission: the relationship remains historical and authorization/visibility is rechecked on each read.
12. Two completely unrelated businesses prove the workflow without Elm, church, florist, or named-Event hardcoding.

## 8. Separate build/release gates

**Gate A:** audit existing Conversation, identity-link and outbound-operation source permissions, provider event matching and Organization relationship contracts. Select lawful typed Event relation without duplicating any source.  
**Gate B:** implement provenance-preserving subject link and compose-with-subject intent as a narrow, idempotent source operation; transaction and authorization negative proof in disposable clone.  
**Gate C:** add source-qualified evidence read composer with explicit partiality and deduplicated counts; prove provider-accepted `≠` delivered `≠` replied `≠` confirmed.  
**Gate D:** integrate notebook with different status standing and visible communication evidence; test in two Ledgers and signed sessions.  
**Gate E:** independent review, source migration and guarded application release.

This contract does not authorize new email sending, contact outreach, external marketing, or changes to any real communication.
