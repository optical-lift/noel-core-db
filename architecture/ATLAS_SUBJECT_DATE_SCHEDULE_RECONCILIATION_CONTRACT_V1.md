# Atlas — Source-owned schedule discrepancy resolution contract v1

**Status:** Governing build contract; implementation NOT YET RELEASED.  
**Established:** October 22, 2026.  
**Authority:** Atlas Universal Temporal Field Constitution; Temporal Contribution Protocol; One Date + Subject Packet 0 audit; delegated-agent governance.  
**Build priority:** Addition 1, immediately after the read-only date-claims reconciliation adapter is validated.

## 1. The problem this contract actually solves

A single canonical Occurrence may have multiple authorized but unequal representations of its schedule. For example, an operational Organization event record and the Shared Intelligence occurrence can disagree about the name, start time or lifecycle. Displaying both without an adjudication path leaves the person unable to answer: **Which schedule will Atlas use when it prepares actual work or commitments?**

An Occurrence is *one source identity*. A calendar date is a temporal coordinate, not that identity. Two different Occurrences on the same civil date remain different subjects. A disagreement is an evidence condition, not authorization to choose a winner automatically.

**The new capability is a governed discrepancy-resolution command routed to the owning sources; it is not a writable Calendar and not a new Event store.**

## 2. Verified existing source anchors

- Canonical Occurrence: `local_intel.occurrences` (`id`, `title`, `status`, `start_at`, `end_at`, `updated_at`, `last_verified_at`).
- Institutional operational event: `atlas.community_events` (`id`, `occurrence_binding_id`, `title`, `status`, `event_date`, `start_local_time`, `end_local_time`, `timezone_name`, `visibility_scope`, `updated_at`).
- Join: `atlas.organization_occurrence_bindings`; Ledger relevance: `ledger.occurrence_calendar_bindings`. Person participation: `ledger.seats` (never a paid employee seat).
- Read candidate: `atlas.ledger_occurrence_date_evidence_self_api_v1` in the reviewed/generated, not-yet-released One Date build. It reports `differenceCandidates` and `not_adjudicated`, not a decision.
- Existing operational trigger `atlas.enforce_community_event_occurrence_binding_org_v1` synchronizes the Shared Intelligence record **on certain approved operational-writer-origin paths only**; it must not be assumed that every Organization event edit can rewrite every canonical Occurrence. A new correction command must prove its source authority instead of bypassing the trigger.

## 3. Governed operation

The person should be able to open either the subject or date, see an intelligible comparison, and say **“This is the correct schedule”** with an exact intended date/time, source authority, and reason.

### Reconciliation decision envelope — conceptual contract

```text
decisionKind: reconcile_source_schedule
actor: authenticated Person identity and exact active Ledger relation
scope: exact Ledger / Organization / canonical Occurrence
observedSources:
  canonicalOccurrence: id, compared fields, source version/update clock
  operationalAssertions: exact ids, field values, source version/update clocks
requestedEffect:
  agreed civil date, local start/end, valid IANA timezone
  interpretation of event status; title only if intentionally amended
  explanation and source of authority for the choice
targetWriters:
  enumerated lawful source-specific mutation operations
operationIdentity: stable idempotency key
preconditions:
  source versions still match what actor reviewed
  no prohibited affected reservation/resource commitments
  required higher-authority approval satisfied
result:
  accepted / rejected / still_unresolved / committed / partial_failure
  per-source command receipts and observed post-state
  append-only decision provenance
```

These are **contract fields**, not a new global SQL table or a claim that the required writer already exists. The actual carrier may reuse approved source-history/evidence tables if their custody rules fit; this must be audited before selecting storage.

### Required decision chain

1. **Read** the canonical Occurrence and lawful, visibility-scoped operational assertions with provenance and version/freshness. Do not disclose owner/management overlays to an ordinary Ledger participant.
2. **Differentiate** an actual clock/date disagreement from legitimately different meanings (e.g. `planned` vs `scheduled` may be domain-specific standing; different titles may represent branding). Do not equate field inequality with a proven factual error.
3. **Identify who may act.** Ledger visibility/work participation does not by itself grant authority to change a public advertised event, a binding, a booking or source-owned historical facts.
4. **Propose the exact mutation**, its source writer, and which connected commitments it could affect (venue/resource occupancy, ticket commitments, published invitations, Person commitments). Display affected source commitments when authorized.
5. **Preflight** the owning domain's schedule constraints and concurrent state. Use exact version checks and transaction-safe locking where the domain owns writes. A read-only discrepancy view may continue working during a conflict.
6. **Commit only through lawful writers**, maintaining original assertions/decisions as history. If multiple authorities cannot be changed atomically, return an explicitly partially reconciled state and recovery path; never report success on one writer's receipt alone.
7. **Re-read** both source projections after the writer commits; the Temporal Field reflects the new evidence. The calendar does not write directly.
8. **Report precisely** what changed, who authorized it, what remains unresolved, and whether downstream commitments require separate updates. A schedule change does not imply emails were sent or bookings updated.

## 4. Read and decision states

- `unexamined_difference`: reviewed source values differ; no adjudication.
- `under_review`: exact source/version pair submitted for lawful reconciliation.
- `current_schedule_supported`: a chosen effective current schedule has source-qualified evidence; it is not necessarily a mutually synchronized row set.
- `unresolved_material_conflict`: schedule-critical fields cannot yet be used for a new affected commitment.
- `resolved_by_source_writers`: lawful writer receipts and subsequent read prove convergence/explicit source-specific interpretation.
- `stale_decision`: a source changed after review, requiring new preflight.
- `partial_reconciliation`: some source writes occurred, others did not; no false all-clear.

These are **read/decision semantics**, not a directive to add a new persisted status column to either Event source.

## 5. User-chosen selective blocking (answer 9D)

- Work such as *Plan invitations* or *Find musician* remains usable when time is disputed.
- An action that **requires the precise start or end**—publishing the definitive start time, confirming a vendor for that time, or committing resource occupancy—must fail closed or obtain an authorized source override if the required fact is unresolved.
- The conflict surface explains **what exactly is blocked and why**; it must not freeze unrelated work.
- Do not infer who can adjudicate from being the task assignee, the owner of an unrelated Ledger, or possession of credentials.

## 6. Universal tests / release gates

1. One occurrence with different operational and canonical times shows **one subject**, both values, exact source IDs and provenance.
2. Two occurrences on one civil day show **two distinct subjects**, never a duplicate alias.
3. The source-specific writer is selected by authority and legal relationship, never simply by newest `updated_at`.
4. Invalid/ambiguous timezone, nonexistent local DST time, ambiguous DST fold, reversed/empty end and undated source remain unresolved until explicit policy resolves them.
5. Actor can create ordinary Ledger Work but lacks schedule-publication authority: can see eligible comparison evidence, cannot commit a schedule correction.
6. Owner/management-only operational source remains private to unauthorized persons, even when one shared canonical Occurrence is visible.
7. A stale version rejects concurrent correction; no lost update.
8. A material booking/venue conflict blocks only dependent schedule commitments, with a source-owned reason.
9. Prior data and disposition remain historically retrievable to authorized people; replay of the same operation does not create duplicate changes or decisions.
10. A failure in a second writer is not reported as reconciliation success; re-read shows partiality.
11. Date view and subject view show the same canonical ID, governing schedule evidence and unresolved facts.
12. Repeat against an unrelated Ledger and Organization with no farm, Event-name, date or Person hardcoding.

## 7. Required separation of build/release

**Gate A:** One Date read-only evidence adapter passes protected clone and true signed-session privacy tests.  
**Gate B:** Audit all lawful source writers and their history/version/approval contracts; decide the least-authority amendment mechanism.  
**Gate C:** Implement and clone-test the governed schedule-decision command, history and selective conflict preflight as a separate Atlas migration.  
**Gate D:** Add the subject and date notebook decision encounter with source receipts; three-Person and unrelated-Ledger negative proof.  
**Gate E:** Independent reviewed main merge and protected production release.

No part of this document authorizes direct production edits or resolves a specific October 30 start time.
