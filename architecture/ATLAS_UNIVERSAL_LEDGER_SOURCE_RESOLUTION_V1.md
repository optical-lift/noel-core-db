# Atlas Universal Ledger + Source Resolution Kernel v1

## Purpose

Atlas needs to unify contacts and counterparties across personal address books, company systems, payment systems, CRMs, accounting platforms, ministry lists, supplier systems, and future connectors without importing those systems' silos as new identity authorities.

The kernel establishes four distinct objects:

1. **Ledger** — who has custody of private knowledge;
2. **Source connection** — which authorized external system/account supplied a representation;
3. **Source party record** — how that external system represents a person, business, organization, or other party;
4. **Canonical resolution mapping** — which Shared Intelligence entity that source record refers to.

```text
one real party
    ↓
one canonical Shared Intelligence entity

many source-system representations
    ↓
each remains in its owning Ledger custody

many source records
    ↓
may resolve to the same canonical entity
```

Resolution unifies identity. It does not unify custody.

## Ledger

`atlas.ledgers` is already Atlas's governed-reality custody object. This kernel reuses it rather than inventing a second Ledger table.

Authority and participation already live beside it through `atlas.principal_ledger_authorities` and `atlas.ledger_organization_participations`. Existing establishment functions remain the lawful way to create/authorize Ledgers.

A Ledger answers **whose governed/private reality is this?** It does not answer **who is the real-world party?** That remains Shared Intelligence canonical identity.

This tranche does not rewrite existing Organization-scoped tables or manufacture replacement Ledgers. It gives any existing authorized Ledger a universal source-ingestion seam.

## Source connection

`atlas.ledger_source_connections` represents one authorized external account/system inside one Ledger, such as personal Google Contacts, company Salesforce, QuickBooks, Stripe, Mailchimp, or another future connector.

It stores no OAuth token, password, refresh secret, or provider credential. Credentials remain in the connector/secret layer. Atlas stores only provider/account identity, state, authority scope, and provenance.

## Source party record

`atlas.ledger_source_party_records` preserves how one connected source represents a party: Google contact ID, Salesforce contact ID, Stripe customer ID, QuickBooks vendor ID, Mailchimp subscriber ID, and so on.

The source record is not canonical identity. Its `source_payload` remains Ledger-private and does not become Shared Intelligence merely because the record resolves to a canonical entity.

## Canonical resolution mapping

`atlas.ledger_source_party_resolutions` connects a source party record to one canonical `local_intel.entities` identity.

Many source records, including records from different Ledgers, may resolve to the same canonical entity. The mapping stores resolution method, confidence, resolver version, basis, and current/superseded state.

When a user confirms that two source representations are the same Bob, Atlas preserves that decision as durable resolution evidence instead of asking repeatedly.

## Privacy boundary

Source records and payloads remain private to their Ledger. Resolution must not expose which other Ledgers have the same party, must not promote private source fields into Shared Intelligence, and must not reveal another Ledger's notes, history, or source data.

## Dependency direction

```text
source connection
        ↓
source party record
        ↓
canonical resolution mapping
        ↓
Shared Intelligence canonical entity
```

A Salesforce contact, Gmail contact, Stripe customer, QuickBooks vendor, Mailchimp subscriber, or phone address-book entry is a representation, not a competing identity authority.

## Lightweight operating model

Postgres keeps only durable custody and identity-continuity objects. Bulky raw files belong in object storage; staging/search/recommendation projections should remain disposable. Source-connection rows deliberately contain no provider credentials or refresh secrets.

## Core law

```text
canonical identity is universal
source representation is local
private knowledge keeps its custody
resolution joins identity without joining privacy
```

## Identity resolution engine

The source-record kernel is now paired with `architecture/ATLAS_IDENTITY_RESOLUTION_ENGINE_V1.md`.

A source-party record may contribute two resolver signal classes:

- a Ledger-private normalized identifier that may match only against Shared Intelligence evidence explicitly permitted for identity resolution;
- an opaque `private_blind_match` token computed outside Postgres with a versioned keyed HMAC.

Cleartext source identifiers are never cross-compared directly between Ledgers.

A human confirmation can bootstrap a previously unseen private blind identifier to a canonical entity. Later authorized Ledgers presenting the same opaque token may recover the same canonical identity without learning the original private value, the contributing Ledger, or how many other Ledgers know the party.

Resolver cases preserve `auto_resolvable`, `needs_review`, and `new_candidate` boundaries rather than silently creating duplicate identities.

