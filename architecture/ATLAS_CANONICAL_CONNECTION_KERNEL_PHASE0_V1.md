# Canonical Connection Kernel — Phase 0 Migration Readiness

**Status:** source-audited, architecture staged; no canonical writer or production migration.
**Direction authorized:** the same actual connection mechanism for every legitimate subject, rather than one UI command routed indefinitely to unrelated relationship authorities.
**Custody:** `reality` is a possible shared canonical relationship kernel; `ledger` is a distinct existing scope and permission carrier. Any cross-domain structural change is **shared-lane**, independently reviewed—not a unilateral `atlas_` table conversion.

## Real source findings (aggregates only; October 22, 2026)

| Fact | Live value |
| --- | ---: |
| Existing native Ledgers | 3 |
| Distinct `reality.entities` business subjects represented by those Ledgers | 2 |
| Native Person–Ledger seat rows | 10 (10 distinct pairs, all active) |
| Person/business pairs whose existing seats span multiple Ledgers | 4 |
| Existing Ledger–Ledger connection rows | 0 |
| Existing Reality relationship rows | 2,119 (all `contained_in`, established) |
| Registered `person → ledger_context` Reality relationship kinds | 0 |
| Canonical `ledger_context` entity rows | 0 |

The counts are source observations, not authority to backfill. They can change; rerun `architecture/audits/atlas_canonical_connection_phase0_readiness.sql` before each review. No client, person, business name, UUID, or sensitive basis/evidence is included in the report.

## Critical invariant: Ledger context ≠ owning business entity

`ledger.ledgers.subject_entity_id` identifies the business the Ledger concerns. It does NOT identify that **Ledger context** itself.

A naive transformation `ledger.seats.person_entity_id → ledger.ledgers.subject_entity_id` into a Person–Business Reality edge is **lossy**: four current Person/Business groups span more than one Ledger. Responsibility and record scope may differ even when the same canonical Person and Business appear. A migration that collapses these pairs is forbidden.

Before the first canonical seat reconciliation, establish a durable **separate Reality entity identity for each Ledger context**, keeping both:
- Ledger context identity: a canonical, uniquely bound `reality.entities` subject of future kind `ledger_context`;
- Ledger owning business: today's distinct `ledger.ledgers.subject_entity_id`.

A governed one-to-one Ledger ID ↔ Ledger-context Reality entity binding must be designed and tested before activation. **Do not infer it from business identity** or declare an application-generated UUID to be canonical. This is a proposed form awaiting review, not a released entity type.

## What one real Connection engine requires

1. **Identity.** Canonical endpoint references, including the source-owned Ledger context as a real addressable subject, do not change when an account is claimed. One Person and multiple Ledger contexts remain distinguishable.
2. **Connection kind.** Register source-validated relationship kinds through `reality.relationship_kinds`, including proposed `participates_in_ledger` (person → ledger_context), `ledger_summary_exposure` (ledger_context → ledger_context) only if actual semantics and source consent/operation bounds are approved. Do not reuse `contained_in` to fake participation.
3. **Establishment.** The existing Reality proposition → evidence → adjudication process may provide the canonical birth of a relationship. A seat's current `active` flag and membership in a database are NOT independent evidence of consent or sufficient warrant for a new relationship. Reconcile provenance and authority separately.
4. **One writer.** After a governed cutover, exactly one canonical relationship command authors existence, scope, alteration and termination. Ledger seat and Ledger-to-Ledger rows must become faithful **compatibility projections/receipts**, never a second source of the same connection truth. There must be no unguarded dual writes or circular trigger synchronization.
5. **Lifecycle.** Today's Ledger states `active/paused/ended` and Reality states `observed/established/disputed/retired` have **different meanings**. Model participation state and legal authority separately from ontological relationship existence. Preserve began/ended/effective times, disputes, explicit reasons, source lineage and original IDs. Ending a Ledger context never deletes the canonical Person.
6. **Access.** Existence of a relationship is not a grant to sensitive ledger/private health records. Record-level permission, source ownership, purpose, confidentiality and consent remain independently evaluated in the common Atlas operation policy. Do not expose Reality graph rows merely because someone appears as an endpoint.
7. **Retirement.** Inventory every present reader/writer of `ledger.seats` and `ledger.connections`, put source-directed compatibility under tests, reconcile historical state without rewriting it, prove non-health and practitioner contexts with signed-in negative tests, and retire old write authority only with verified receipts.

### Canonical relationship vs operational consequence

The canonical Relationship can answer **that** two actual subjects are connected, of which kind, with which evidence and effective history. It does not need to swallow individual task assignments, clinical records, appointments, bookings, payment obligations, or every consequence of the relationship. Those facts retain their actual domain truth owner and reference the canonical Connection with strictly authorized reads.

The product uses one normal connect/inspect/change/end interaction. Canonical commands decide lawful transitions; no client-specific connection wizard or permission engine.

## Source-only phase zero code

- The read-only SQL file queries **aggregate** readiness, including the 4 current lossy-collapse collision groups and missing canonical Ledger-context identity/kind; it writes nothing and includes no person IDs or patient data.
- Atlas's paired pure contract (`lib/canonical-connection-reconciliation.mjs`) only constructs held candidates. It requires exact original seat IDs, Ledger IDs, proposed distinct context IDs, original lifecycle, a registered relationship-kind proof and separately verified authority evidence. It NEVER issues Reality propositions or treats a candidate as established.
- Existing `reality.entity_relationships` rows remain canonical and are never cloned. A disclosure-specific authorization still gates inspection.

## Sequence and blockers

**Phase 0:** current evidence, source/lineage audit and anti-collapse unit tests (this work).
**Phase 1:** review canonical Ledger-context identity binding, relationship-kind validity, source consent/authority, revocation semantics, and migration receipt format. Shared-lane migration source, no live bulk writes.
**Phase 2:** disposable clone tests for one existing non-sensitive Person–Ledger seat, plus a second Ledger context of the same business. Prove no collapse, no change in ledger task authority, no ambiguous command ownership or unauthorized graph disclosure.
**Phase 3:** consent/authority-backed Reality proposals, original source lineage reconciliation, signed-in A/B positive and negative tests, reversible read shadow comparison.
**Phase 4:** canonical single-writer cutover guarded by authority tests, with Ledger compatibility projections; separately authorized release.
**Phase 5:** exactly the same connect/inspect/change/end interaction in a non-medical Ledger and an explicitly authorized practitioner/subject Ledger. Only after both pass may old write paths be retired.

### Blocking questions, not guessed defaults

- Can a Ledger context be a first-class `reality.entities` kind without changing Shared Directory identity laws?
- Which participant(s) may establish, contest, pause or end a particular connection, and what evidence constitutes their warrant?
- Which currently active seat histories must remain historical rather than adjudicated canonical relationships?
- Are private Ledger operational record scopes represented by general permission policy or source-attached consequence, without turning participation into automatic disclosure?
- Which existing seat writers and responsibility readers must be held until source/side effects are reconciled?

**Stop condition:** do not deploy a universal single-writer or migrate 10 seats while these remain unsettled. A source-only pilot is not a successful production migration.

## Superseded approach

The former inspector-first design was source-only: Atlas PR #363 and noel-core-db generated migration #2049; the latter passed a protected clone but was not deployed. Those drafts do not satisfy the approved **single actual connection authority** objective. Preserve their history as reviewed experiments, but do not release their multiple-authority dispatcher as a permanent architecture.
