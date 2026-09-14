# Atlas Contacts + Correspondence Identity + Audience v1

**Status:** Architecture definition only; no schema, migration, provider, or production changes
**Date:** 2026-09-13
**Database authority:** `optical-lift/noel-core-db`
**App consumer:** `optical-lift/atlas`

## 1. Purpose

Atlas needs one coherent identity layer beneath Correspondence, address-book synchronization, social messaging, and Ledger-driven outbound communication.

The immediate product problems are:

- one human may own several email addresses associated with different companies, ministries, projects, or other endeavors;
- those endeavors need a stable visual mark in Correspondence without repeating a raw mailbox address on every row;
- Facebook Messenger, Instagram DMs, SMS, and future channels must enter the same Correspondence system without becoming separate product silos;
- Google Contacts, Apple/iCloud Contacts, CSV imports, observed correspondents, CRMs, and manual edits may disagree, duplicate one another, disappear, or change over time;
- Atlas must preserve where every contact fact came from and what changed instead of destructively flattening all providers into one mutable address card;
- Ledgers and other business/ministry workflows must refer to durable Contacts, not copied email strings;
- bulk communication must resolve an appropriate current contact point while honoring purpose-specific permission, suppression, bounce, and unsubscribe state.

The governing correction is:

> **A communication route is not the identity that uses it, and a provider address-book record is not the person or organization it describes. Atlas owns durable relationship identity, while endpoints and provider records remain attributed evidence.**

This architecture introduces two bounded product concepts above existing foundations:

1. **Correspondence Identity** — the recognizable Atlas-side persona/endeavor through which a Principal or institution communicates, including its chosen visual mark and the communication endpoints it is allowed to use.
2. **Contact Book** — a custody-scoped master relationship directory that reconciles many provider/source records into durable Contacts while preserving contact-point provenance and history.

It also defines the recipient/audience contract required for Ledger-driven business and ministry communication.

## 2. Existing architecture retained

This design builds on and does not replace the following existing contracts.

### 2.1 Canonical Person

`atlas.people` is the Atlas-wide human identity root. A human exists independently of authentication, Principal provisioning, organization membership, payment, or institutional identity.

Contacts may bind to a canonical Person when Atlas has enough evidence and authority to establish that relationship. A Contact does not create a Person automatically.

### 2.2 Core Identity Reconciliation

Atlas Core identity is evidence-first. Provider, imported, communication, legacy, and user-reported records remain source evidence. Ambiguity is not converted into a false match.

Contacts follows that same law. Display-name equality is never sufficient to merge Contacts.

### 2.3 Communication Provider Independence

The following laws remain controlling:

- Endpoint ≠ Identity.
- Connected Source ≠ Endpoint.
- provider thread ≠ durable Atlas conversation.
- provider replacement must preserve Atlas reality.
- send authority belongs to Atlas, not the transport provider.

Correspondence Identity sits **above** Communication Endpoints as a presentation/operational grouping. It does not replace the endpoint or the entity that owns the endpoint.

### 2.4 Addressability Resolver

Addressability answers which governed external interface may be resolved for an entity in a context. It is not a private master contact directory.

Contacts answers who this custodian knows, which source records contribute to that relationship, which contact points are believed current, and how that knowledge changed.

Contacts and Addressability may bind to one another, but neither owns the other.

## 3. Governing nouns

### 3.1 Correspondence Identity

A **Correspondence Identity** is the persona/endeavor a user recognizes while reading or sending correspondence.

Examples:

- Elm Farm
- Optical Lift
- Camp Duffel
- a ministry
- a personal identity

A Correspondence Identity may group several communication endpoints:

```text
Elm Farm
  mark: Elm Farm logo
  ├── hello@elmfarm.co        email
  ├── @elmfarm                Instagram
  ├── Elm Farm Page           Facebook Messenger
  └── +1 ...                  SMS later
```

The mark communicates *which endeavor/persona this correspondence belongs to*. The endpoint remains the route used to receive or send a specific message.

### 3.2 Contact

A **Contact** is a durable relationship entry inside one Atlas custody context.

A Contact may represent:

- a person;
- an organization;
- a household or group later;
- an unresolved/unknown correspondent that has not yet been classified.

A Contact may exist before Atlas can bind it to a canonical Person, institutional identity subject, or Addressable Subject.

### 3.3 Contact Point

A **Contact Point** is a normalized communication coordinate belonging to a Contact, such as:

- email address;
- phone number;
- Instagram handle/account identity;
- Facebook/Messenger identity;
- postal address;
- future communication route kinds.

A Contact Point is not assumed current merely because one provider still contains it.

### 3.4 Contact Source Record

A **Contact Source Record** is an externally observed/provider-owned record, such as:

- Google Contacts record;
- Apple/iCloud contact card;
- CSV row;
- CRM contact;
- observed communication participant;
- manually entered Atlas evidence;
- future directory/connector record.

The provider record is evidence about a Contact. It is not the Contact itself.

### 3.5 Audience Membership

An **Audience Membership** is a durable relationship between a Contact and a Ledger/purpose-driven outbound audience.

It stores *who belongs to the audience*. It must not store a copied email address as the identity of the member.

At send time Atlas resolves the appropriate Contact Point under the current permission/suppression rules.

## 4. Correspondence Identity model

### 4.1 Proposed root

Provisionally:

```text
atlas.correspondence_identities

id                    uuid primary key
principal_id          uuid null
organization_id       uuid null
organization_unit_id  uuid null
stable_key            text unique
name                  text
status                text -- active / retired
mark_kind             text -- uploaded_asset / system_icon / monogram
mark_asset_ref        text null
system_icon_key       text null
monogram               text null
created_at            timestamptz
updated_at            timestamptz
```

Custody follows the existing communication model:

- exactly one Principal, or
- exactly one Organization (optionally narrowed to one Organization Unit).

A Principal may have multiple Correspondence Identities for distinct endeavors even when those endeavors have not been modeled as organizations.

### 4.2 Endpoint binding

Provisionally:

```text
atlas.correspondence_identity_endpoints

correspondence_identity_id   uuid
communication_endpoint_id    uuid
status                       text -- active / retired
is_default_for_channel       boolean
variant_label                text null
variant_mark_kind            text null
variant_mark_asset_ref       text null
variant_icon_key             text null
bound_at                     timestamptz
retired_at                   timestamptz null
```

Rules:

1. the endpoint custody root must be compatible with the Correspondence Identity custody root;
2. an active endpoint has one default Correspondence Identity inside that custody context unless a later explicit multi-persona send model is introduced;
3. provider account identity remains below the endpoint in Connected Source/runtime custody;
4. binding or unbinding an endpoint never rewrites historical Communication Events;
5. historical events preserve the endpoint actually used.

### 4.3 Visual mark rules

Every Correspondence Identity must have a deliberate mark.

The user may choose:

- uploaded logo/artwork;
- Atlas-provided icon;
- monogram/initial fallback.

The uploaded logo is a presentation asset, not identity authority. Database rows should reference governed asset custody rather than storing arbitrary binary image bytes inline.

Visual hierarchy in Correspondence:

1. **Primary mark:** Correspondence Identity logo/icon.
2. **Secondary channel cue:** small email / Instagram / Messenger / SMS glyph when useful.
3. **Exact endpoint:** available in tooltip, accessible label, expanded message details, and composer routing controls; not repeated on every inbox row by default.

If one Correspondence Identity has multiple same-channel endpoints and the distinction matters, the endpoint may define a small variant mark/badge or variant label. Raw addresses remain discoverable but should not become permanent visual clutter.

### 4.4 UI behavior

Inbox row:

```text
[Elm logo + tiny IG glyph]  Katie                     1:11 PM
                            Are the dahlias available tomorrow?
                            Unassigned
```

Another identity:

```text
[Optical Lift mark]         Marshall                  12:36 PM
                            Revised proposal
                            Yours
```

The row does not need to print `Email · hello@elmfarm.co` repeatedly.

Right correspondence page:

- subject remains primary;
- Correspondence Identity mark appears near the sender/message header;
- channel microglyph remains visible;
- expanded `to me` / addressing disclosure reveals the exact endpoint;
- reply composer shows `Reply as` or `From` with the same mark and exact endpoint available on disclosure.

## 5. Canonical channel kind

Provider identity and communication medium must remain separate.

Communication Endpoint should ultimately expose a canonical channel kind such as:

```text
email
instagram_dm
facebook_messenger
sms
whatsapp
web_chat
voice
atlas_native
```

`provider_key` continues to answer which adapter/provider carries the endpoint. It must not be the permanent semantic source for guessing the communication medium in application code.

Examples:

```text
channel_kind=email
provider_key=generic_email

channel_kind=instagram_dm
provider_key=meta

channel_kind=facebook_messenger
provider_key=meta
```

## 6. Unified Correspondence read

The current single-endpoint inbox model should evolve toward one governed aggregate read.

Target:

```text
authorized custody
  ↓
all readable Communication Endpoints
  ↓
Correspondence Identity bindings
  ↓
one governed inbox projection
  ↓
conversation + endpoint + Correspondence Identity + channel kind
```

The browser must not be responsible for fetching arbitrary endpoints and assembling authority itself.

Every unified inbox item should carry at minimum:

```text
communication_conversation_id
communication_endpoint_id
correspondence_identity_id
channel_kind
```

The user may filter by:

- all identities;
- one Correspondence Identity;
- one channel;
- one exact endpoint when needed.

Default view should be all readable sources.

Reply routing defaults to the exact endpoint on which the message/conversation arrived. Resolving the sender to the same Contact across email, Instagram, and Facebook does **not** silently authorize a cross-channel reply.

## 7. Contact Book custody

Contacts are relationship reality and therefore must have an explicit custody root.

A Contact belongs to exactly one Contact Book context, owned by:

- one Principal; or
- one Organization, optionally projected/narrowed through Organization Unit policy.

This avoids accidentally turning private address books into a globally enumerable directory.

A canonical Person can be known by several Contact Books without forcing those custodians to share all private relationship data.

## 8. Proposed Contact root

Provisionally:

```text
atlas.contacts

id                      uuid primary key
principal_id            uuid null
organization_id         uuid null
organization_unit_id    uuid null
contact_kind            text -- person / organization / unknown
stable_key              text unique
display_name            text
status                  text -- active / retired
canonical_person_id     uuid null
addressable_subject_id  uuid null
identity_subject_id     uuid null
created_at              timestamptz
updated_at              timestamptz
```

Rules:

1. a Contact may exist without any canonical binding;
2. display name is never an identity key;
3. canonical Person binding requires adjudicated evidence;
4. organization-local `identity_subject_id` must be scoped compatibly with Contact custody;
5. Addressable Subject binding is optional and does not make private contact facts public;
6. Contact retirement preserves historical correspondence/audience membership;
7. no provider deletion may physically delete the Contact.

## 9. Source records and revisions

Each connected address book/provider contributes source records.

Provisionally:

```text
atlas.contact_source_records

id                    uuid primary key
contact_id            uuid null
connected_source_id   uuid null
source_kind           text -- google_contacts / apple_contacts / csv / communication / manual / crm / ...
source_record_key     text
source_revision_key   text null
observed_at           timestamptz
source_modified_at    timestamptz null
source_deleted_at     timestamptz null
raw_hash              text null
metadata              jsonb
```

The source record binding to Contact is adjudicated/reconcilable. Provider identity is stable through `source_record_key`, not display name.

A source update creates a new observation/revision or appends a new revision record; it must not erase historical source state.

A provider deletion/tombstone means:

> **This source no longer asserts this record/fact.**

It does not mean:

> **Atlas now knows the human, phone number, or email ceased to exist.**

## 10. Contact-point provenance

Resolved Contact Points should be durable Atlas objects with source attribution beneath them.

Provisionally:

```text
atlas.contact_points

id             uuid primary key
contact_id     uuid
kind           text -- email / phone / instagram / facebook / postal / ...
normalized     text
presentation   text
label          text null -- personal / work / mobile / etc.
status         text -- current / historical / disputed / retired
created_at     timestamptz
updated_at     timestamptz
```

And source assertions:

```text
atlas.contact_point_observations

id                       uuid primary key
contact_point_id         uuid
contact_source_record_id uuid
assertion_state          text -- present / absent / changed / disputed
source_label             text null
observed_value           text
observed_at              timestamptz
source_modified_at       timestamptz null
metadata                  jsonb
```

Rules:

1. exact normalized contact-point equality is strong reconciliation evidence but not universal proof that two provider records represent the same human;
2. provider-specific labels remain attributed evidence;
3. Atlas may maintain an explicitly adjudicated preferred label/value projection;
4. user correction is recorded as Atlas-authored evidence/adjudication, not destructive replacement of provider history;
5. a Contact Point may be retained as historical after all providers stop asserting it;
6. duplicate provider assertions collapse in the current projection but remain separately attributable in provenance.

## 11. Additional contact facts

V1 should focus on facts needed to resolve and communicate with contacts:

- display/preferred name;
- aliases;
- organization/role affiliation;
- email;
- phone;
- social handles/provider identities;
- postal address;
- source labels and current/historical status.

Birthdays, notes, household relationships, anniversaries, and richer CRM data may be added later, but they must follow the same source-observation/adjudication pattern rather than becoming untraceable mutable columns.

## 12. Reconciliation and duplicate handling

Atlas must never silently merge Contacts solely because names match.

Signals may include:

- same provider record key: exact source continuity;
- same normalized verified email/phone: strong candidate evidence;
- provider-native linked account identity: strong source evidence;
- known canonical Person binding: authoritative if valid in custody context;
- same organization + similar name: candidate evidence only;
- same display name: weak evidence only.

Resolution states should distinguish:

- same;
- different;
- unresolved / not enough evidence.

When ambiguous, Atlas creates or preserves separate Contacts and raises a reconciliation candidate rather than manufacturing certainty.

A mistaken source-record binding must be reversible without erasing historical evidence. Prefer rebinding/adjudication history over irreversible physical merges.

## 13. Observed correspondents become Contact evidence

Incoming communications are themselves a source of Contact evidence.

When Atlas receives an email/DM/text from a previously unknown coordinate:

1. preserve the Communication Event and participant coordinate as immutable communication evidence;
2. resolve the normalized coordinate against known Contact Points inside the authorized Contact Book;
3. if exactly one governed match exists, relate the participant to that Contact;
4. if none exists, create an unresolved/candidate Contact or source record under policy;
5. if multiple matches/ambiguity exist, fail closed into reconciliation;
6. never mutate the communication event to pretend a later Contact resolution existed at receipt time.

Correspondence may display the latest resolved Contact name while preserving original sender evidence underneath.

## 14. Contact synchronization contract

### 14.1 Inbound-first

Initial Google/Apple/CSV/CRM integration should be inbound synchronization into Atlas.

Atlas becomes the governed master projection, but providers remain attributed sources.

No provider is allowed to overwrite the whole Atlas Contact simply because its sync ran last.

### 14.2 Source cursor/state

Provider-native sync cursors belong to Connected Source synchronization state, consistent with Communication Provider Independence.

Examples:

- Google Contacts sync token;
- Apple/iCloud/CardDAV sync token or collection revision;
- CRM pagination/delta cursor.

The cursor is transport state, not Contact truth.

### 14.3 Historical change semantics

For every imported field Atlas should be able to answer:

- which source asserted it;
- first observed time;
- latest observed time;
- source-modified time when available;
- whether the source later removed/changed it;
- whether Atlas/user adjudication overrode the preferred projection;
- which current Contact Point/attribute it contributes to.

### 14.4 Write-back later

Bidirectional sync is deliberately not required for the first Contact kernel.

If introduced later, write-back must be explicit and connector-specific. Atlas must never assume that changing a master Contact authorizes mutation of every connected Google/Apple/CRM address book.

## 15. Contacts as a durable Atlas spread

Contacts should become a first-class composed spread, not merely a settings page.

The spread should support:

- People / Organizations views;
- fast search;
- duplicate/reconciliation queue;
- contact detail;
- current contact points;
- historical contact points;
- source provenance/history;
- organization/relationship affiliations;
- Correspondence history;
- Ledger/audience memberships;
- communication permission/suppression state;
- connected-source health as secondary information.

The user should work with Contacts. Google/Apple/CRM connectors are the pipes behind it.

## 16. Audience and Ledger contract

A Ledger must not treat an email address as the durable member identity.

Wrong:

```text
Ministry Updates
  jane@gmail.com
  bob@yahoo.com
```

Target:

```text
Ministry Updates
  Contact: Jane Smith
  Contact: Bob Jones
```

Audience membership should preserve:

```text
contact_id
ledger/audience context
membership status
purpose/role
joined_at
left_at
provenance/basis
```

At send time, Atlas resolves eligible current Contact Points.

This allows Jane to change email providers without requiring every Ledger/list to be edited manually.

## 17. Communication permission and suppression

Contactability and permission are separate.

Knowing an email exists does not automatically mean every Ledger may send every category of communication to it.

Atlas needs purpose-scoped communication eligibility, provisionally:

```text
contact_id
contact_point_id null
purpose_key
channel_kind
state -- allowed / suppressed / unknown
basis -- explicit_opt_in / relationship / transactional / manual_authority / imported_evidence / other
source_record/evidence
established_at
retired_at
```

A separate suppression seam should support at least:

- explicit unsubscribe;
- manual suppression;
- hard bounce / invalid address;
- abuse/complaint signal;
- temporary delivery hold when appropriate;
- purpose-scoped vs global suppression.

Global suppression wins over audience membership.

Purpose-scoped permission means the same Contact can legitimately be eligible for one audience and not another.

Example:

```text
Sarah Johnson
  Feast Guild florist availability -> allowed -> work email
  Elm Farm event announcements      -> allowed -> personal email
  Ministry updates                  -> unknown/suppressed
```

This architecture stores evidence and state; it does not itself decide the legal basis required for a particular jurisdiction or message type.

## 18. Recipient resolution at send time

Bulk or Ledger-originated send must resolve recipients just before authorization.

Target sequence:

```text
Ledger audience membership
  ↓
Contact
  ↓
purpose/channel permission
  ↓
current eligible Contact Point
  ↓
suppression/bounce checks
  ↓
resolved recipient set
  ↓
Atlas send authority
  ↓
transport
```

The resolved recipient coordinates used for a particular outbound operation must then be snapshotted into that operation/evidence. Historical sends must not appear to have gone to a newly edited address.

Recipient resolution failures should be explicit:

- no eligible contact point;
- ambiguous preferred point;
- suppressed;
- invalid/bounced;
- permission unknown where policy requires affirmative eligibility.

## 19. Facebook and Instagram integration

Meta transport should enter existing Communication foundations, not create a separate social inbox ontology.

Initial scope:

- Facebook Messenger private Page messages;
- Instagram DMs;
- story replies/mentions only after explicit product policy decides whether they belong in Correspondence;
- public comments remain a distinct interaction type because they carry public audience/moderation semantics.

Each social endpoint binds to a Correspondence Identity.

Provider adapter preserves:

- provider page/account ID;
- provider conversation/thread ID;
- provider message ID;
- sender/provider participant ID;
- text/body/media evidence;
- timestamps;
- webhook/replay state;
- provider reply constraints/capabilities.

The sender's social identity becomes Contact Point evidence and may reconcile to an existing Contact, but that does not merge the Facebook/Instagram conversation into an email conversation automatically.

## 20. Cross-channel person continuity

If Atlas determines:

```text
Sarah's email
Sarah's Instagram
Sarah's Facebook identity
```

belong to one Contact/person, the result is:

```text
Contact: Sarah
  ├── email Contact Point
  ├── Instagram Contact Point
  └── Facebook Contact Point
```

It is **not** permission to create one synthetic conversation thread spanning all three channels.

Conversation continuity remains separately governed because provider/channel reply rules and context differ.

## 21. Composer routing

Reply composer must always expose the selected Correspondence Identity and underlying route.

Default rules:

1. reply through the exact originating endpoint;
2. show the Correspondence Identity mark prominently;
3. exact address/handle available in `From` / `Reply as` disclosure;
4. switching endpoint is allowed only among endpoints the actor is authorized to use;
5. switching channel may create a new conversation/communication context rather than silently mutating the existing thread;
6. contact resolution never grants send authority by itself.

## 22. Security and privacy

Contacts are private relationship data by default.

Required laws:

- no anonymous enumeration;
- Contact Books remain custody-scoped;
- source credentials/secrets remain in Connected Source/provider custody, never Contact rows;
- raw provider payloads are not broadly browser-readable;
- browser reads use governed projections/RPCs;
- canonical Person binding does not expose another custodian's private Contact Book;
- Correspondence Identity marks do not grant endpoint send authority;
- contact source provenance is visible only to authorized custodians;
- audience membership does not override suppression/permission checks;
- provider source deletion never cascades to erase canonical communication or relationship history.

## 23. Non-goals for v1

This architecture does not yet authorize:

- Google Contacts connection;
- Apple/iCloud/CardDAV connection;
- Meta/Facebook/Instagram provider connection;
- CRM connection;
- production DDL;
- automatic global person matching;
- contact write-back to external providers;
- automatic cross-channel conversation merge;
- legal/marketing-consent inference;
- bulk-email campaign UI;
- public contact directory;
- replacement of Canonical Person, Core Identity, Addressability, or Communication Endpoint.

## 24. Staged implementation sequence

### Stage A — Correspondence Identity presentation seam

1. establish Correspondence Identity root and mark configuration;
2. bind existing Communication Endpoints;
3. add governed read projection returning identity mark + endpoint + channel;
4. update Mailroom rows/header/composer to use identity marks;
5. add uploaded logo + curated icon selection UI;
6. preserve exact endpoint in accessible/expanded details.

No all-source inbox is required to prove Stage A, though the data model must support it.

### Stage B — Unified inbox projection

1. add canonical endpoint `channel_kind`;
2. add governed aggregate Correspondence read across authorized endpoints;
3. include endpoint and Correspondence Identity IDs on every list item;
4. filter by identity/channel/endpoint;
5. preserve reply routing to originating endpoint.

### Stage C — Contact Book kernel

1. Contact root with custody;
2. Contact Source Record/revision seam;
3. Contact Points + observations;
4. basic reconciliation/adjudication;
5. observed Correspondence participants as one source;
6. Contacts composed spread read APIs.

### Stage D — Address-book connectors

1. Google Contacts inbound sync;
2. Apple/iCloud/CardDAV inbound sync;
3. CSV/import adapter;
4. source change/tombstone history;
5. duplicate queue and review UX;
6. no write-back initially.

### Stage E — Audience/Ledger recipient contract

1. Ledger membership by Contact ID;
2. purpose-scoped communication eligibility;
3. suppression/bounce seam;
4. recipient resolver;
5. operation-time recipient snapshot;
6. audience health report for missing/suppressed/unresolved Contacts.

### Stage F — Social transport

1. Meta Connected Source/provider authorization;
2. Instagram DM endpoint;
3. Facebook Messenger endpoint;
4. webhook/cursor ingestion;
5. participant/contact-point evidence;
6. outbound reply routing under Atlas send authority.

## 25. Acceptance conditions

A complete implementation across stages must prove at minimum:

1. one Correspondence Identity can own an uploaded logo or chosen Atlas icon;
2. one Correspondence Identity can group multiple email/social endpoints without erasing exact endpoint identity;
3. inbox rows can communicate endeavor identity without printing raw mailbox text on every row;
4. exact endpoint remains available and accessible;
5. one unified inbox can return conversations across all authorized endpoints through one governed read;
6. replying uses the originating endpoint by default;
7. Facebook/Instagram transport cannot become identity authority;
8. one Contact can aggregate Google, Apple, communication-observed, CSV, and manual source records;
9. source deletion is recorded as source history rather than destructive Contact deletion;
10. Contact-point provenance can explain where each current value came from;
11. same-name records do not auto-merge;
12. an adjudicated canonical Person binding remains separate from source evidence;
13. a Ledger/audience stores Contact membership rather than copied email strings;
14. recipient resolution happens at send time and snapshots the exact chosen route into outbound evidence;
15. suppression/permission can exclude a Contact even when the Contact remains an audience member;
16. historical sends remain historically accurate after later Contact edits;
17. private Contact data is never broadened merely because a Person or Addressable Subject exists elsewhere in Atlas.

## 26. Product outcome

The target user experience is:

- Correspondence feels like one calm omnichannel inbox;
- each endeavor is recognized by its logo or selected mark rather than repeated mailbox text;
- social channels are visually obvious through a small channel cue without taking over the row;
- Contacts becomes the one master relationship book regardless of whether Google, Apple, email history, Instagram, a CRM, or a Ledger supplied the evidence;
- duplicates are reconciled with evidence rather than flattened blindly;
- the user can inspect how a phone number/email changed over time and which sources still assert it;
- Ledgers can safely refer to people/organizations while Atlas resolves the right current delivery coordinate at send time;
- changing an email address does not require editing every list;
- unsubscribes, suppressions, and purpose-specific communication eligibility remain attached to the durable relationship rather than a fragile spreadsheet row.

That makes Correspondence, Contacts, and Ledgers three views over one governed relationship reality rather than three separate address lists.