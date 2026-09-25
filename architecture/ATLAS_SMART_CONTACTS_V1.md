# Atlas Smart Contacts v1

## Status

Production read contract established on 2026-09-24.

## Product name

The user-facing and agent-facing product name is **Atlas Smart Contacts**.

The following names remain implementation vocabulary only:

- Shared Intelligence = canonical external-world truth authority;
- Shared Directory = lower-level canonical identity/directory primitives;
- Atlas Organization relationship = one Organization's private relationship overlay;
- buyer, campaign, outreach, flower, vendor, donor, event, and other domain tables = extensions or compatibility carriers, never independent contact authorities.

For ordinary contact discovery, retrieval, targeting, and enrichment requests, agents should begin with **Atlas Smart Contacts**, not by choosing among those implementation surfaces.

## Governing composition

```text
Shared Intelligence canonical entity
+ public evidence / semantic signals
+ canonical people and roles
+ unresolved but labeled person candidates
+ governed contact routes
+ exactly one requesting Organization overlay
= Atlas Smart Contact
```

A Smart Contact is a projection, not a second identity store.

## Official read contract

Canonical service:

`atlas.smart_contacts_search_service_v1(organization_id, query, limit)`

Authenticated wrapper:

`atlas.smart_contacts_search_self_api_v1(organization_id, query, limit)`

The lower-level `shared_directory_*` functions remain valid internals and compatibility primitives, but new product and agent contact discovery should use the Smart Contacts contract.

## Query vocabulary

The v1 query is a JSON object and may contain:

- `text`
- `entityTypes`
- `organizationKinds`
- `placeLabels`
- `signalKeys`
- `signalMode = all | any`
- `claimKinds`
- `personTerms`
- `requiredContactTypes`
- `requireNamedPerson`
- `requireContactable`
- `relationship = any | related | unrelated`
- `includeHistoricalSignals`

The query does not itself create a relationship, concept, campaign, or communication authority.

## Stable semantic signals

`local_intel.v_smart_contact_signals_v1` translates source-backed public evidence claims into search semantics.

Initial stable signals include:

- `commercial_buyer`
- `wholesale_buyer`
- `cut_flower_buyer`
- `local_sourcing`
- `fresh_flower_demand`
- `recurring_flower_demand`
- `commercial_supplier`
- `wholesale_supplier`
- `cut_flower_supplier`
- `distribution_capable`
- `ordering_process_known`
- `market_member`
- `decision_contact_known`
- `public_contact_route`
- `commercially_relevant`

Signals are derived from evidence. They are not Organization judgments such as "Feast Guild should contact this business."

## Standard result

Each Smart Contact result carries:

1. canonical entity identity;
2. geography and website;
3. identity verification state;
4. relevance score;
5. semantic signals and the evidence explaining the match;
6. canonical people/roles/authority when established;
7. person discovery candidates when useful but not yet canonicalized;
8. governed best contact routes and contactability state;
9. freshness state;
10. explicit research gaps;
11. exactly the requesting Organization's private relationship overlay.

The result must distinguish:

- canonical person truth from a discovery candidate;
- verified-current routes from merely observed routes;
- current evidence from historical/stale evidence;
- shared reality from Organization-private relationship state.

## Why a result qualified

A Smart Contacts answer should always be explainable from the returned evidence and signals.

For example:

```text
Queen City Blooms
→ current local-sourcing evidence
→ current florist/business identity
→ co-founder candidates known
→ current official email route
→ no Feast Guild relationship
```

"Should contact" remains a derived operational recommendation made for a requesting Organization. It is never stored as canonical external-world truth.

## People frontier

Smart Contacts may return unresolved person-discovery candidates, but they are explicitly marked `standing=discovery_candidate`.

A candidate does not become canonical merely because it is useful.

The next person work should promote sufficiently warranted candidates through the existing governed person identity/relationship machinery so Smart Contacts can increasingly return:

```text
canonical Person
→ current relationship to Organization
→ role title/function
→ authority scope
→ governed contact route
```

## Contactability vocabulary

Human-facing contactability should converge on a small vocabulary:

- `verified_current`
- `public_observed`
- `stale`
- `conflicted`
- `blocked`
- `missing`

V1 currently emits `verified_current`, `public_observed`, or `missing` from governed best-route state. Later versions should expose stale/conflict/block states explicitly as the underlying contact membrane supports them.

## Legacy rule

Do not assemble a new contact set directly from:

- legacy buyer tables;
- campaign/outreach compatibility tables;
- raw Local Intel entity phone/email columns;
- domain-specific flower buyer tables;
- an arbitrary older `v_offering_buyer_context_vN` view;

when Atlas Smart Contacts can answer the request.

Domain extensions remain lawful after Smart Contacts has resolved the canonical entity/relationship identity required to join them.

## Truth boundaries

Smart Contacts search:

- does not create Shared Intelligence truth;
- does not establish an Organization relationship merely because an entity matched;
- does not authorize communication;
- does not promote person candidates;
- does not expose another Organization's overlay.

## Initial acceptance proof

Using Feast Guild as the requesting Organization and requiring:

- business entities;
- `local_sourcing`;
- `commercial_buyer`;
- a named person;
- email as a desired route;
- unrelated entities only;

the production contract returns evidence-backed businesses including Happy-Bee Flower Co, Sunday Flower Company, Cassidy Flower Co., Flora & Forge, Queen City Blooms, and Good Ground Floral.

The result correctly:

- explains why each business matched;
- labels non-canonical humans as discovery candidates;
- reports missing email/person-canonicalization gaps;
- returns no Feast Guild relationship overlay for unrelated entities;
- creates no Feast Guild relationship by searching.

## Regression questions

Smart Contacts should remain able to answer these classes of request without falling back to legacy contact stores:

1. Which businesses appear to buy locally grown cut flowers?
2. Which growers/wholesalers can supply cut flowers?
3. Who is the best-known human at each business and what is their standing?
4. Which qualifying businesses have a current official email?
5. Which have only source-observed contact coordinates?
6. Which contacts are already related to the requesting Organization?
7. Which are not yet related?
8. Why did each result qualify?
9. What research gap prevents a result from being action-ready?
10. What evidence is current versus historical?

## Core sentence

> **Atlas Smart Contacts is the one contact-discovery doorway: one shared reality, one requesting Organization overlay, explainable evidence, and no silent promotion of guesses into truth.**


## Person promotion membrane

Smart Contacts distinguishes discovery from canonical person truth.

Read-only warrant preview:

`local_intel.preview_person_discovery_candidate_promotion_v1(candidate_id)`

Service-only promotion:

`local_intel.promote_person_discovery_candidate_service_v1(candidate_id, expected_preview_fingerprint)`

Automatic promotion requires:

- candidate review state `pending`;
- a full person name rather than a first-name-only reference;
- confidence >= 0.960;
- a fresh strong source;
- for `official_source` / `owner_verified`: confidence >= 0.960;
- for `government_authoritative`: confidence >= 0.980;
- no unresolved person identity collision.

Exact-name reuse is allowed only when the existing Person has a second anchor such as a current relationship to the same organization or the same direct contact coordinate.

Promotion establishes only Shared Intelligence reality:

```text
person discovery candidate
→ canonical Person
→ source-backed current person↔organization relationship(s)
→ direct person contact route(s) only when already evidenced as direct
```

It does **not**:

- create an Elm, Feast Guild, or other Atlas Organization relationship;
- copy generic business inboxes or switchboards onto the Person;
- treat `local_context_id` as identity authority;
- auto-merge same-name people without a second anchor.

The compatibility `local_context_id` is inherited only because the current entity table still requires it; the promoted Person metadata explicitly records Shared Intelligence as identity authority.

### Initial flower proof

The first production pass promoted 15 high-warrant flower-industry people into canonical Shared Intelligence Persons across 14 businesses/organizations.

Examples include:

- Tricia Jackson — Faithful Spring Farm
- Cherrelle Hitchcock — Flora & Forge
- Kim Dove — Happy-Bee Flower Co
- Martha Louderback — Ladybug Floral
- Angela Morton — Meadow Stems Flower Farm
- Ginny Randall — Missouri Flower Exchange
- Theresa Suda — RosAmungThorns Flowers & Gifts
- Sarah Rein and Lisa Trevor — Rosewood Floral & Event Design
- Shannon Johnson and Jeff Johnson — Shannon's Custom Florals
- Anna Maria Desipris — Sun And Bloom Farms
- Beth Spillman — The Floral Element
- Pam Carroll and Raleigh Jones — Wickman's Garden Village

First-name-only, lower-confidence, and third-party-only candidates remain unresolved rather than being force-promoted.

Only direct person/direct-role contact routes follow a promoted Person. Generic organization routes remain attached to the organization.


## Durable selection packet

Smart Contacts selection is now separated from contact-set execution.

The canonical flow is:

```text
literal request
→ contact-set intent
→ Atlas Smart Contacts search/rank/explain
→ Organization-private selection packet
→ operator/agent edits proposed selection
→ explicit confirmation
→ frozen packet
→ execution handoff
```

The packet is not Shared Intelligence truth. It is the requesting Organization's durable record of what Smart Contacts returned and what was actually selected at that moment.

### Core tables

- `atlas.contact_selection_packets`
- `atlas.contact_selection_packet_items`
- `atlas.contact_selection_packet_events`

A packet stores:
- the originating contact-set intent request;
- requesting Organization;
- exact Smart Contacts query;
- complete search snapshot;
- requested count;
- candidate count;
- selected count;
- revision and lifecycle state;
- confirmation and handoff timestamps.

Each packet item stores:
- canonical Shared Intelligence entity ID;
- rank/ordinal at packet creation;
- selected vs alternate state;
- full Smart Contact snapshot;
- the evidence/reason snapshot explaining qualification.

Packet events preserve:
- creation;
- selection edits;
- confirmation;
- execution handoff.

### Core service functions

Create from a ready intent request:

`atlas.create_contact_selection_packet_service_v1`

Edit the proposed set:

`atlas.set_contact_selection_packet_selection_service_v1`

Confirm/freeze:

`atlas.confirm_contact_selection_packet_service_v1`

Handoff to contact-set execution:

`atlas.prepare_contact_set_execution_from_selection_packet_service_v1`

Authenticated counterparts exist for product use and resolve the caller's effective Organization membership before calling the privileged service layer.

### Freeze boundary

While `packet_state=proposed`, selected items may be edited.

After confirmation:
- packet selection data is immutable;
- packet items cannot be changed;
- only the controlled `confirmed → handed_off` lifecycle transition is permitted.

The execution run receives the frozen packet contents. It does not rerun Smart Contacts and silently substitute today's results for yesterday's selection.

### Execution behavior

The packet handoff intentionally creates an execution run with:

- the confirmed selected entities only;
- `attachToLedger=false`;
- `communicationAuthorized=false`;
- the exact packet ID and confirmation timestamp;
- accepted research gaps preserved as context.

Selection therefore does not itself:
- create an Atlas Organization relationship;
- establish prospect/customer/supplier status;
- authorize communication;
- mutate Shared Intelligence.

The older `prepare_contact_set_execution_service_v1` remains as a compatibility path. New Smart Contacts product flows should not use it to select entities directly.

### Initial acceptance proof

A rollback-safe production proof used Feast Guild as the requesting Organization:

1. the request asked for 3 local-sourcing flower buyers;
2. Smart Contacts returned 6 evidence-backed candidates;
3. the packet selection was edited to 2 entities;
4. the packet was confirmed;
5. a direct post-confirm item mutation was rejected by the database freeze guard;
6. execution handoff produced a ready execution run containing exactly 2 entities;
7. ledger attachment remained false;
8. communication authorization remained false;
9. Feast Guild still had zero external relationships.

This proves that selection can be durable and organization-specific without becoming either canonical truth or relationship truth.


## Saved searches and dynamic audiences

Atlas Smart Contacts now has an Organization-private saved-search layer.

A saved search is not another identity or contact store. It is a reusable definition of the kind of external entity an Organization currently cares about.

```text
Shared Intelligence reality
        ↓
Atlas Smart Contacts query
        ↓
Organization-private saved search
        ↓
completed run = frozen audience snapshot
        ↓
delta from prior run
        ↓
new / updated / removed
```

### Core tables

- `atlas.smart_contact_saved_searches`
- `atlas.smart_contact_saved_search_runs`
- `atlas.smart_contact_saved_search_run_items`
- `atlas.smart_contact_saved_search_run_deltas`

The latest completed run is the saved search's current dynamic audience.

Completed runs and their items/deltas are immutable. Refreshing a saved search creates a new run; it never rewrites history.

### Core contracts

Create:

`atlas.create_smart_contact_saved_search_service_v1`

Edit definition/watch configuration:

`atlas.update_smart_contact_saved_search_service_v1`

Refresh:

`atlas.run_smart_contact_saved_search_service_v1`

Read one:

`atlas.smart_contact_saved_search_service_v1`

List an Organization's saved searches:

`atlas.smart_contact_saved_searches_service_v1`

Authenticated product callers use the matching `*_self_api_v1` wrappers.

### Delta semantics

Each completed run compares against the prior completed run and records:

- `new` — entity matches now but did not match previously;
- `updated` — entity still matches, but its frozen Smart Contact snapshot materially changed;
- `removed` — entity matched previously but no longer matches.

If the saved-search definition itself changed between runs, the run records `searchDefinitionChanged=true`. This keeps "the world changed" distinguishable from "the audience definition changed."

### Watch configuration

A saved search may be marked for:

- hourly;
- daily;
- weekly;
- manual

refresh.

`atlas.smart_contact_saved_search_watch_queue_service_v1` exposes which watched searches are due.

`atlas.run_due_smart_contact_saved_searches_service_v1` executes due searches with an advisory lock so overlapping clock ticks cannot run the watch worker concurrently.

Production Supabase Cron job `atlas-smart-contacts-watch-v1` runs once a week and refreshes watched searches whose cadence is due.

This makes watch refresh live without GitHub Actions. Human notification delivery is still a separate downstream layer.

The saved search also carries a watch policy such as:

`{"notifyOn":["new","updated","removed"]}`

Notification delivery remains a later downstream concern.

### Saved search → selection packet

A contact-set request can now consume an exact completed saved-search run through:

`atlas.create_contact_selection_packet_from_saved_search_run_service_v1`

That function does **not** rerun Smart Contacts.

It freezes the already completed run into the Organization-private selection packet, so:

```text
saved search run at T1
→ packet created from exactly T1
→ selection edited/confirmed
→ execution
```

Later changes to Shared Intelligence or to the saved search cannot silently replace what the Organization selected.

### Ledger readiness rule

Saved Smart Contacts searches are Organization-private operating objects and therefore require a properly established Atlas Ledger context. An `atlas.organizations` row, compatibility participation, or other partial institutional placeholder is not sufficient by itself.

Until an Organization is properly established as a real operating Ledger, Atlas may still use Shared Intelligence and Smart Contacts for read-only intelligence work where lawful, but it must not persist Organization-owned saved searches, dynamic audiences, watch subscriptions, selection ownership, or other Ledger-private operating state for that Organization.

Feast Guild currently does **not** satisfy that stronger operational Ledger-readiness standard. The two prematurely-created Feast Guild saved searches (`local-flower-buyers` and `wholesale-flower-suppliers`) and all of their run/item/delta history were removed. No downstream selection packet referenced those runs.

### Acceptance proofs

Rollback-safe proofs against the Smart Contacts data path established:

- first run of a new local-buyer audience: `6 new / 0 updated / 0 removed`;
- immediate identical second run: `0 / 0 / 0`;
- changing the definition to wholesale suppliers: `5 new / 0 updated / 6 removed`;
- that definition-change run explicitly reported `searchDefinitionChanged=true`;
- attempts to edit a completed run item were rejected;
- packet creation from a saved-search run preserved the exact source run ID;
- a request for 3 selected exactly 3 of the frozen 6 candidates;
- packet handoff still created no Feast Guild relationship and authorized no communication.

## Apollo-like boundary

The saved-search layer provides the first Apollo-like product behavior without changing Atlas custody:

- reusable prospect definitions;
- dynamic audience membership;
- "new since last run";
- material contact updates;
- removed/no-longer-matching entities;
- watch cadence configuration;
- exact audience snapshot → selection packet handoff.

Organization-specific fit scoring, automated enrichment waterfalls, person-at-account drill-down, and notification delivery remain later layers. They should build on this saved-search/run history rather than creating parallel contact stores.
