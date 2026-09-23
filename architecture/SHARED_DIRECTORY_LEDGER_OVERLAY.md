# Shared Directory / Ledger Overlay

## Governing rule

A real-world person, organization, business, or place has one canonical Shared Intelligence identity. An Atlas Ledger never clones that identity merely because the referent matters to a different Organization.

The composition is:

```text
Shared Intelligence canonical entity
+ one Atlas Organization's private relationship overlay
= that Organization's directory entry
```

The public/shared layer may contain canonical name, aliases, public contact routes, public location, website, public hierarchy, source evidence, and verification state.

The Organization-private Atlas layer may contain relationship state, role tags, interactions, notes, follow-up, commercial profile, item preferences, correspondence, order history, sourcing history, and domain-specific extensions. Those facts do not become shared merely because they refer to a shared entity UUID.


## Mandatory operating gate for Atlas / Supabase directory work

This contract governs **every** Atlas or Supabase read, write, import, enrichment, contact lookup, directory lookup, business lookup, entity lookup, relationship update, and event/occurrence write involving an external-world person, organization, business, place, or event.

Before reading broadly or writing anything durable:

1. **Resolve canonical shared identity first.** Search Shared Intelligence for the real-world referent before consulting or creating Ledger-local records.
2. **Do not create a duplicate canonical entity because a different Ledger needs to know something about it.** An Atlas Organization attaches to the existing shared UUID.
3. **Classify each fact by custody before writing it.**
   - Public/world facts and source-backed identity facts belong with the canonical Shared Intelligence entity.
   - Organization-specific knowledge, notes, roles, preferences, interactions, judgments, commercial history, workflow state, and other private operating facts belong only in that Organization's Atlas overlay.
4. **Never use another Organization's overlay as shared truth.** Private Ledger facts are not promoted into the shared layer merely because they concern the same canonical entity.
5. **Never reconstruct a second directory from a domain table.** Buyer, vendor, venue, campaign, registration, calendar, outreach, contact, and other domain tables may extend or reference the canonical entity; they do not become independent identity authorities.
6. **If a legacy/domain row appears to represent an entity already present in Shared Intelligence, resolve/bind it rather than admitting another identity.**
7. **When gathering data for a user, retrieve Shared Directory + that user's authorized Ledger overlay first.** External research is enrichment only after stored reality has been checked.

If canonical resolution is uncertain, stop at the uncertainty boundary rather than creating a convenience duplicate.


## Canonical binding

Atlas already represents external parties through Organization-scoped `atlas.identity_subjects`. A subject is a contextual identity handle, not the universal identity.

The canonical bridge is the existing identifier form:

```text
provider_key = local_intel
identifier_type = entity_id
identifier_normalized = <local_intel.entities.id>
```

Shared Directory v1 promotes that seam into an invariant: within one Atlas Organization, one canonical Shared Intelligence entity may bind to only one current Identity Subject. One Shared Intelligence entity may still be bound independently by arbitrarily many Atlas Organizations.

## Directory behavior

Every Atlas Organization may search the same canonical Shared Intelligence corpus. Search is global across canonical entities and does not use `local_intel.entities.local_context_id` as an identity namespace.

The read projection returns canonical shared facts plus exactly the requesting Organization's overlay. It never returns another Organization's Atlas relationship data.

An Organization may attach an existing canonical entity to its Ledger with one or more relationship role tags such as buyer, supplier, customer, venue, or another governed role key. Attaching does not create a second business/person/place record.

Organization-private effort and notes are recorded against the Atlas external relationship. The canonical Shared Intelligence entity remains unchanged.

## Retrieval contract: directory first

For an Atlas-grounded request about known people, businesses, buyers, suppliers, vendors, farms, churches, venues, customers, or other external parties, retrieval order is:

1. Identify the requesting Atlas Organization/Ledger.
2. Search the Shared Directory.
3. Compose that Organization's private relationship overlay.
4. Read the owning domain extensions needed for the question (for example buyer profiles or commercial history) using the resolved relationship identity.
5. Answer from stored reality when it is sufficient.
6. Use external/web research only when stored reality is missing, stale for the requested purpose, or the user explicitly asks for new research.
7. Any useful external discovery must resolve against Shared Intelligence before a new canonical entity is admitted.

External search is therefore an acquisition/enrichment source, not the primary directory.


## Canonical occurrence / event extension

The same non-duplication law applies to real-world occurrences and events.

A real event happens once in reality. It must not acquire separate canonical records merely because multiple Atlas Ledgers care about it, publish it, register for it, host it, sell into it, attend it, or annotate it.

The composition is:

```text
Shared canonical occurrence
+ canonical participating / hosting / venue entities
+ one Atlas Organization's private occurrence overlay
= that Organization's event/calendar/relationship view
```

Therefore:

- a public community event should resolve to one canonical occurrence;
- the host, organizer, venue, participating businesses, and other real-world parties should resolve to canonical Shared Intelligence entity UUIDs;
- an Atlas Ledger may privately tag that occurrence with calendar inclusion, relevance, notes, follow-up, relationship meaning, internal status, campaign use, attendance, commercial context, or other organization-owned facts;
- another Atlas Ledger may independently attach its own private meaning to the same occurrence without seeing the first Ledger's overlay;
- publishing an event on an Elm, Organization, household, or personal calendar does **not** authorize creating another copy of the real event;
- registration, ticketing, program, attendance, and operational subsystems may reference or extend the canonical occurrence but must not silently become a second event-identity authority.

Where existing legacy tables contain event-like rows, future work must resolve whether they are canonical occurrence authority, a private overlay, or a compatibility carrier before adding more event data. New convenience duplication is prohibited.


## Privacy boundary

The Shared Directory self API authorizes by effective Organization membership. The `local_intel` tables remain private and are not directly granted to browser roles.

A member of Organization A may see:

- shared canonical/public facts for a Shared Intelligence entity; and
- Organization A's relationship overlay.

That member may not see Organization B's relationship state, interactions, notes, preferences, commercial history, correspondence, or other private operational facts.

## V1 executable surfaces

- `atlas.shared_directory_search_service_v1`
- `atlas.shared_directory_search_self_api_v1`
- `atlas.attach_shared_directory_entity_service_v1`
- `atlas.attach_shared_directory_entity_self_api_v1`
- `atlas.record_shared_directory_interaction_service_v1`
- `atlas.record_shared_directory_interaction_self_api_v1`

The read projection composes Shared Intelligence with generic Atlas relationship roles, commercial profile, item preferences, and latest interaction. Domain-specific extensions remain owned by their domains and can be composed after relationship resolution rather than copied into Shared Intelligence.

## Acceptance test

The architecture is not considered proven merely because the functions exist. The proving behavior is:

> A canonical business exists once in Shared Intelligence. Organization A attaches it as a buyer and records a private call note. Organization B may independently attach the same canonical UUID. Both Organizations see the same shared identity/public contact facts. Only Organization A sees Organization A's call note. No second canonical business record is created.

For the Feast Guild use case, a request such as “give Katie the best buyers to contact today” must begin from Shared Directory + Feast Guild relationship/domain overlays. It must not begin with web search.
