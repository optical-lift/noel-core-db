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
