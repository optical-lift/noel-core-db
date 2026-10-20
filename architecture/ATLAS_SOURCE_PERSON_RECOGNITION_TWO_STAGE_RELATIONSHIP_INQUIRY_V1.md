# Atlas Source Person Recognition + Two-Stage Relationship Inquiry v1

**Status:** Owner-selected architecture direction, 2026-10-20 (**Option C**); specification only, not a released database or correspondence capability.  
**Scope:** Any source-observed name, contact endpoint, proposed human identity, or Person↔institution relationship.  
**Authority:** Existing Shared Intelligence identity, Reality identity/relationship, Atlas source evidence and Ledger overlays, claimant verification, and governed Correspondence; this document establishes no competing store.

## Governing selection

**Resolve source uncertainty at admission. When asking a human about an asserted relationship, establish who is answering first; ask what relationship actually exists in a separate second question; only then consider admitting any relationship.**

The following are independent facts:

```text
source label / email observed
  ≠ resolved canonical Person
  ≠ control of a contact route
  ≠ verified claimant identity
  ≠ recipient's relationship assertion
  ≠ requesting Ledger's relationship assertion
  ≠ admitted shared or Ledger-private relationship
  ≠ Ledger seat / account / employment / task / financial permission
```

This succeeds the temptation to issue a billable Organization employee invitation merely to determine whether a named human exists or has an affiliation.

## 1. Source admission before any promotion

A source-observed name, email, signature, sender, customer, `worker_key`, provider contact, or role label enters as **source evidence** with original record identity, owning Ledger/source, time, purpose, disclosure posture, and source custody. Preserve literal text and provenance; do not rewrite prior records.

Before a Person can be admitted or bound:

1. Classify what the observed label may designate: Person, institutional role/office, shared inbox, organization, other entity, or unresolved. A technical label such as `owner` is not a human identity.
2. Resolve against existing canonical Shared Intelligence identity **before** creating an entity, using the current v2 identifier semantics, temporal validity, admissible evidence and correlation controls. A matching display name or email is evidence, not proof of a unique human.
3. Keep private Ledger email, phone, role, personnel and notes inside the originating scope; use permitted shared evidence or private blind-match channels only through the governed resolver. Never use another Ledger's private identifiers as a discoverable address book.
4. If a unique canonical existing Person is adequately established, associate the source assertion with that identity and preserve the old source row. If genuinely new identity admission is warranted, use the existing Shared Intelligence → Reality admission gate, including its authorization/review requirements.
5. If ambiguous, conflicting, insufficient, or explicitly denied, retain an unresolved/reviewable case. Neither domain convenience nor repeated imports establishes a Person or relationship.

The `Atlas Smart Contacts` product remains a **projection** of Shared Intelligence + the requesting Ledger's lawful overlay; there is no second canonical Smart Contact Person store.

## 2. Request to find and contact a human

An authorized Atlas principal may express: "Search for the Person associated with this email, and—if the route is lawful—ask them whether they have a relationship with [Ledger] for [stated purpose]."

This is a **bounded contact-and-claim inquiry**, not account enrollment, Worker Day registration, a relationship grant, or an assertion that the recipient works for anyone.

- Preserve the exact requesting Organization/Ledger, requesting Person, stated purpose, supplied endpoint, proposed Person/relationship evidence, intended message, and explicit send authorization.
- The resolver returns only an authority-filtered action result. An unknown email, a protected private match, and a blocked contact route must not let the requester enumerate another Ledger's contacts or hidden canonical identity.
- Email lookup alone does not authorize sending. Before sending, check permitted contact intents, disclosure posture, route validity, suppression/opt-out, sender authority, anti-abuse limits, duplicates, rate limits, and applicable consent/communication rules.
- If a permitted route is available, preview one neutral, attributable message through governed Correspondence, then require the sender's authorized send action. Sending is never an automatic consequence of search or canonical matching.
- If no lawful route exists, return a non-disclosing blocked/unavailable outcome; do not enrich from private records, create an account, or send anyway.
- The recipient needs no Personal Atlas, employee seat, or normal Atlas login to answer. Any future one-time-response transport must be scoped, expiring, single-use or replay-safe, revocable, and must not grant broad database access.

**Relationship Delivery Membrane boundary:** That membrane requires an established source relationship for delivery grants; a pre-relationship identity inquiry does not fabricate such a relationship or delivery grant. Use separately governed Correspondence and a bounded claimant-response transport for this preliminary inquiry.

## 3. Stage one: who received the inquiry?

The first recipient encounter asks whether the intended human is answering, **before** describing or seeking assent to an alleged employment/operational affiliation.

Offer at least: `I am the intended person`, `Not me / wrong address`, and `I do not wish to respond`. Expiry/non-response is a separate state. Preserve exact response evidence and the verified channel/transport receipt.

A verified link or challenge may prove **possession of an email contact route**, not durable identity. A recipient saying "I am [name]" is a **self-assertion**, not sufficient by itself to bind that claimant to a canonical Person. Shared, role-based, recycled, delegated and temporarily controlled addresses may identify multiple humans or a function rather than the claimed Person.

Use the existing claimant-safe projection and `ATLAS_CLAIMANT_IDENTITY_VERIFICATION_CEREMONY_V1` for any **durable verified Atlas Person ↔ canonical-person binding**. That ceremony currently requires independent proof factors and the policy threshold; do not silently downgrade it for a convenient email experience. A one-time link may establish bounded correspondence with a claimant and permit collection of later evidence without pretending full identity verification.

On `not me` or an unsafe identity conflict, stop before the relationship question, retain the conflict for identity review, and prevent automatic retry to the same wrong recipient.

## 4. Stage two: what relationship, if any?

Only after a successful, scoped Stage-one contact-and-claimant check and permissible recipient disclosure may Atlas ask the **separate question**: "What is your actual relationship with [named requesting Ledger or institution]?"

Never present merely "Yes, I work there" as the sole positive option. A lawful encounter allows the recipient to indicate, for example:

- currently carries some work/role for the institution, with their own description and optional effective period;
- occasionally helps, supplies, volunteers, consults, or otherwise has a non-employee connection;
- formerly had a relationship, with approximate ending date if known;
- knows the institution but has no such working relationship;
- no relationship / wrong institution / disputed claim / prefer not to answer.

These are **respondent claims**, not personnel classification. Preserve the literal answer, response scope, claimant assurance, timestamps, transport evidence, and the private requesting Ledger context. Do not turn a self-described role into an employee seat or grant access.

A respondent cannot read private source allegations from other Ledgers, nor can their answer overwrite the requesting Ledger's prior testimony.

## 5. Adjudication and consequence

Admit a durable connection only after **both stages** and the governing identity, source, relationship and authorization requirements for that exact consequence are met:

```text
source observation / Ledger assertion
→ Stage-one channel evidence + identity claim / independent verification as required
→ Stage-two recipient-described relationship
→ compare claims, scope, dates and conflicts
→ governed Relationship Proposition + append-only evidence
→ authorized adjudication
→ canonical relationship or private Ledger relationship, if warranted
```

The existing `reality.relationship_propositions`, proposition evidence, adjudications and `reality.entity_relationships` remain authority for **shared canonical** relationship truth when the relationship kind and evidence permit sharing. Internal Organization/Person participation, role, preferences and private work context remain in the authorized **Atlas Ledger overlay** and their own governing source. Do not publish an internal staffing statement as a world-public relationship just because it was affirmed in a private email.

Even bilateral assent is not universal permission: a canonical Person binding may require stronger proof; accepting a relationship is not accepting a Work allocation; Ledger seat activation, privileges, Company Work, employee classification, and Auth entitlement each need independent commands. A respondent's "No" challenges the proposition, not the existence of the Person. A silent/expired inquiry leaves the claim unresolved, not rejected.

Conflicts create review obligations, not automatic duplicate People or silent reversal of historical decisions. Corrections append supersession/retirement history; never destructively merge original evidence.

## 6. Minimum contract for future implementation

Use existing evidence/proposition/communication/identity owners before considering a new durable carrier. A future inquiry command and projection, if required, must provide:

- exact requester scope + purpose + source observation/identity resolution references;
- safe permitted-route matching and reply destination without cross-Ledger disclosure;
- separate issuance, transport receipts, Stage-one response, Stage-two response, and adjudication evidence;
- stage gating, immutable response receipts, provenance, expiry, revocation, deduplication/idempotency, replay protection and anti-spam controls;
- explicit blocked, ambiguous, wrong-human, shared-address, expired, unsubscribed, denied, and conflicting-result states;
- no privilege expansion via service-role execution or untrusted email links.

The product surface must be designed through the Atlas Product Map and semantic interaction rules; no source-specific button may directly write canonical Person or relationship truth.

## 7. Required proofs before declaring this live

1. A role label `owner` from an old farm record remains a role; an existing authenticated Person can be recognized without creating an `owner` Person.
2. Two legacy spellings/records for the same human resolve to one canonical Person while retaining both source histories; no duplicate Person or credential is manufactured.
3. A valid recipient with **no Atlas account** answers the two separate questions; no paid access or employee seat is created.
4. Stage-one `not me` stops Stage two; no canonical identity or relationship commit occurs.
5. Stage-one `me` plus email possession **alone** cannot pass the durable claimant-verification threshold; a role-inbox/recycled/shared-email false match also fails closed.
6. An affirmative Stage-one response without Stage-two relationship detail does not create a connection.
7. A Stage-two negative, former or contradictory relationship response is retained without overwriting owner/source evidence.
8. Another Ledger's private route or relationship is not enumerated or disclosed by lookup, error, delivery, or preview.
9. Suppressed/no-contact/expired/duplicate/replayed requests cannot send repeatedly or bind identity.
10. A two-stage affirmative outcome without proper adjudication grants no Ledger seat, task, permission, account, pay or finance access; domain-specific actual responsibility remains separate.
11. The same mechanism works with non-employment personal/institutional connections, not only Elm.
12. No external mail or account invitation is sent by a database migration, a read query, or a document/PR merge.

## References and implementation boundary

- `architecture/SHARED_DIRECTORY_LEDGER_OVERLAY.md`
- `architecture/ATLAS_OBSERVATION_CANONICAL_ADMISSION_GATE_V1.md`
- `architecture/ATLAS_IDENTITY_RESOLUTION_ENGINE_V1.md` + `ATLAS_IDENTIFIER_SEMANTICS_TEMPORAL_RESOLUTION_V2.md`
- `architecture/ATLAS_CLAIMANT_SAFE_IDENTITY_DISCLOSURE_V1.md`
- `architecture/ATLAS_CLAIMANT_IDENTITY_VERIFICATION_CEREMONY_V1.md`
- `architecture/ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1.md`
- `architecture/ATLAS_SMART_CONTACTS_V1.md`
- Atlas Product Map: `05-ENTRY-IDENTITY.md`, `205-CORRESPONDENCE.md`, `RELATIONSHIP-DELIVERY-MEMBRANE.md`, `999-DECISION-LOG.md`.

**Not implemented by this decision:** a new table, RPC, UI, outbound message, canonical admission, identity assertion, credential, migration, or production release. Future schema/mutation work belongs to `optical-lift/noel-core-db` and must follow governed migration generation, independent schema-clone validation, and protected release.