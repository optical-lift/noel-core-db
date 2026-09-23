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

## Occurrence authority succession

The earlier Elm Local calendar implementation split canonical event identity by ownership:

- `atlas.community_events` for Elm-owned events; and
- `local_intel.occurrences` for outside-community events.

That split is retired as an authority model.

**Canonical occurrence identity is owned by `local_intel.occurrences` for all real-world events, regardless of who hosts, owns, programs, publishes, attends, sells into, registers for, or annotates them.**

`atlas.community_events` remains valid only as Atlas Organization program / operational context for an occurrence. It may carry Organization-owned program state such as farm/program membership, registration/participation context, capacity, visibility, operational preparation, internal status, and other Ledger-specific meaning, but it must not establish a second event identity.

The required dependency direction is:

```text
local_intel.occurrences
  = canonical real-world occurrence

local_intel.entities
  = canonical host / organizer / venue / participant identities

Atlas Organization-scoped event/program state
  = private or Organization-owned overlay bound to the canonical occurrence

public calendar / registration / program views
  = projections composed from canonical occurrence + authorized overlay
```

Accordingly:

1. Every new real-world event must first resolve or establish one canonical `local_intel.occurrences` row.
2. Every known host, organizer, venue, business, organization, or other participant must resolve to canonical Shared Intelligence entity identity rather than a duplicated event-local contact record.
3. Elm-owned status is a relationship/overlay fact, not an alternate occurrence identity class.
4. `atlas.community_events` must eventually bind explicitly to the canonical occurrence it operationalizes. Until that binding exists, it is transitional event/program state and must not be treated as independent canonical event truth.
5. `public.elm_local_calendar_events_v1` is non-canonical presentation/projection. Its legacy `source_system = 'atlas' | 'local_intel'` distinction does not define event authority and must not be used to justify duplicate occurrence records.
6. Registration, ticketing, staffing, preparation, hospitality, outreach, campaign, attendance, and commercial systems may extend the canonical occurrence through governed references, but none may create a competing event identity.
7. Existing Elm events represented only in `atlas.community_events` are succession debt: future work should reconcile them to canonical occurrences rather than perpetuate the split.
8. Existing external events already in `local_intel.occurrences` must not be recreated in `atlas.community_events` merely because Elm wants to display, track, or annotate them.

The succession target is one event reality with many lawful Organization-specific meanings, not parallel event databases partitioned by ownership.

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


## Organization purpose / context routing

Canonical identity and one Organization-private Ledger overlay are necessary, but they are not sufficient for real operation.

One Organization may need to use the same canonical entity or occurrence in many different internal purposes at the same time. Those uses must not create duplicate identities, duplicate contacts, duplicate donors, duplicate businesses, or duplicate occurrences.

The governing composition is:

```text
canonical Shared Intelligence reality
→ one requesting Organization's private binding / relationship
→ many Organization-owned purpose/context memberships
→ purpose-specific projections and workflows
```

Examples include:

- a mission organization relating to one canonical donor/business across a youth program, annual fundraiser, building project, and volunteer campaign;
- Elm relating to one canonical business as a wholesale buyer, educational-event host, local resource provider, outreach target, and participant in a specific public occurrence;
- one canonical occurrence appearing in an educational calendar, resource calendar, campaign, attendance plan, or operational program without being copied into a separate event database.

### Context is not identity

A purpose/context answers:

> Why is this already-resolved entity or occurrence relevant here?

It does **not** answer:

> Who/what is this in reality?

The canonical entity or occurrence owns identity. The Atlas Organization owns the context and the context-specific payload.

A context membership may therefore carry private, use-specific facts such as:

- role within that context;
- inclusion / exclusion state;
- category or display grouping;
- assigned person or team;
- sponsorship or donor status;
- invitation / outreach status;
- program-specific commitment;
- publication/display note;
- resource category;
- internal priority;
- attendance or participation intent;
- follow-up state;
- context-local notes;
- other structured metadata that is true only inside that Organization's use of the referent.

Those facts must not be written back onto the canonical Shared Intelligence entity merely because the entity is shared.

### One relationship, many uses

For canonical entities, the existing Shared Directory binding remains the Organization's identity/relationship seam. Purpose routing should reuse that Organization-scoped subject/relationship rather than admitting another contact row.

Conceptually:

```text
local_intel.entities
→ Atlas Organization identity binding / relationship overlay
→ Context A membership + Context A payload
→ Context B membership + Context B payload
→ Context C membership + Context C payload
```

Removing an entity from Context A must not remove the canonical entity, the Organization's broader relationship to it, or its membership in Context B or C.

### Occurrences follow the same law

For canonical occurrences, Atlas needs one Organization-scoped occurrence binding analogous to the existing Shared Directory entity binding.

Conceptually:

```text
local_intel.occurrences
→ Atlas Organization occurrence binding / overlay
→ Context A membership + Context A payload
→ Context B membership + Context B payload
```

A calendar is therefore a projection of occurrence memberships in a purpose/context, not an event identity store.

Likewise:

- a donor list is a projection of entity memberships in a fundraising context;
- a program roster is a projection of entity memberships in a program context;
- a resource guide is a projection of entity memberships in a resource context;
- an educational-events calendar is a projection of occurrence memberships selected for that context.

### Durable context vs. temporary contact-set working state

`atlas.contact_set_intent_requests` and `atlas.contact_set_execution_runs` are Intelligence working-state and execution-snapshot carriers. They may discover, resolve, and attach canonical entities, but they do not become the durable purpose/context routing system.

A durable purpose/context must survive the particular search or model operation that found its members and must remain usable by ordinary deterministic Atlas projections and workflows.

### Required properties of the routing layer

The eventual executable routing layer must preserve at least these invariants:

1. every context is owned by exactly one Atlas Organization;
2. context membership is Organization-private unless a separate governed publication projection exposes selected facts;
3. one canonical entity may belong to many contexts in the same Organization without duplication;
4. one canonical occurrence may belong to many contexts in the same Organization without duplication;
5. each membership may carry its own context-specific structured payload;
6. membership deletion removes only that use, not canonical identity or the broader Organization relationship/binding;
7. another Atlas Organization may create its own contexts and payloads against the same canonical identity without seeing the first Organization's data;
8. projections such as calendars, donor lists, resource directories, campaign sets, and program rosters consume context memberships rather than manufacturing new identity stores.

This establishes the durable pattern:

> **one reality → one Ledger binding → many lawful uses**

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
