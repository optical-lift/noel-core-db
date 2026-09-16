# Shared Intelligence Identity Custody

## Purpose

`local_intel` is the shared external-world intelligence layer for the `noel-core` physical database. It is not an Elm Farm directory, a Feast Guild directory, or an Atlas tenant-owned contact store.

Its canonical entity graph represents real-world referents that may be relevant to many products, organizations, ledgers, and operational contexts without being cloned for each use.

The governing invariant is:

> One external-world referent has one canonical Shared Intelligence entity. Contexts establish relationships to that entity; they do not own or duplicate the identity.

## Identity and context are distinct

`local_intel.entities` is the canonical Shared Intelligence identity surface for external people, organizations/businesses, places, and other supported referents.

A Local context answers a different question: why is this entity known, discoverable, relevant, curated, or usable in a particular operating context?

Those meanings are represented by `local_intel.entity_context_memberships`.

Examples:

- Elm Farm may know a florist as a buyer prospect.
- Feast Guild may know the same florist as a wholesale buyer.
- Another Atlas organization may know the same florist as a vendor or partner.

Those contextual relationships do not create three florist identities. They all resolve to the same canonical `local_intel.entities.id`.

## Canonical identity versus operational reality

Shared Intelligence may hold source-custodied external facts such as:

- public name and aliases;
- public contact points;
- public website and location;
- organization hierarchy and operating-unit identity;
- publicly evidenced people/organization relationships;
- offerings, signals, market attributes, and other externally observed intelligence;
- source provenance, verification state, conflicts, and adjudication history.

Product- or organization-private reality does not become universal merely because it refers to the same entity. Examples include:

- private commentary;
- sales and purchasing history;
- negotiated pricing;
- account-specific preferences;
- correspondence;
- private evaluations;
- work, commitments, and operational records.

Those remain in the owning product/organization domain and reference the canonical external identity through an explicit governed bridge.

## Person, organization, and place remain distinct

A business, its owner, and its storefront/farm location are not interchangeable identities.

For example, a future complete representation may contain:

- an organization entity for a flower farm business;
- person entities for its owners/operators;
- a place entity for the physical farm or storefront;
- explicit relationships among them.

Shared labels do not justify collapsing distinct referents.

## Context-membership transition

Inherited `local_intel.entities` requires `local_context_id`, and inherited readers and writers frequently treat that column as an identity boundary. Removing or repurposing it in place would break existing behavior.

Shared Intelligence v1 therefore introduces an additive transition:

1. Every existing entity keeps its UUID and existing `local_context_id`.
2. Every existing entity receives an `entity_context_memberships` row for that inherited context.
3. New legacy-path entity inserts/updates automatically mirror the compatibility pointer into the membership relation.
4. `entities.local_context_id` is explicitly reclassified as a legacy compatibility/discovery-origin pointer, not identity ownership.
5. Existing context-bound resolvers and research guards remain unchanged in this package.
6. Later packages may transition those readers/guards to membership-aware resolution after production-shaped tests prove equivalent behavior for the existing context.
7. Only after all inherited dependencies have moved may the legacy pointer be relaxed or retired.

The migration intentionally does not delete an old membership if `entities.local_context_id` changes. Membership is non-exclusive; moving a compatibility pointer must not erase the fact that another context already knows the same canonical entity.

## Admission and duplicate prevention

The target admission rule is:

> Resolve against the universal Shared Intelligence corpus before establishing a new canonical entity.

The existing ingestion-candidate, resolver-recommendation, source-evidence, and human-adjudication machinery should be reused for that purpose. Ambiguous identity evidence must not be converted into an automatic merge merely to achieve a lower duplicate count.

The v1 context-membership package does not yet change the inherited context-bound resolution functions. That transition is intentionally isolated as a later package because it changes runtime behavior rather than storage semantics.

## Atlas boundary

Atlas remains the owner of operational institution, Ledger, Identity Subject, external relationship, commercial, communication, work, and other Atlas-specific reality.

The intended future seam is explicit rather than implicit:

- an Atlas organization may bind to the canonical Shared Intelligence organization it represents;
- an organization-scoped Atlas Identity Subject may resolve to a canonical Shared Intelligence external entity;
- Atlas-specific relationships, commentary, transactions, correspondence, and operational history remain Atlas-custodied.

An Atlas organization must not acquire another Atlas organization's private observations merely because both reference the same Shared Intelligence entity.

## Future organization claim/onboarding

A future Atlas onboarding flow should resolve the proposed organization against Shared Intelligence before creating an unbound institutional identity. When public evidence suggests an existing business, Atlas can present appropriate public identity/contact data for confirmation and establish a governed representation binding after verification.

This package does not change Atlas onboarding.

## Access boundary

`local_intel` remains private database custody. The v1 membership table is RLS-enabled and grants no direct access to `anon`, `authenticated`, or `service_role`. This package does not create a new Data API or application query surface.

Any future application access requires an explicit governed read/write seam rather than direct table exposure.

## Out of scope for v1

This package deliberately does not:

- modify the `atlas` schema;
- modify the Atlas application repository;
- change Atlas onboarding or organization establishment;
- rewrite Atlas Identity Subjects;
- merge suspected historical duplicates;
- globally reclassify organization/place identity (including Elm Farm's inherited representation);
- change inherited business-census, search-discovery, or research context guards;
- populate the Feast Guild grower/buyer directory;
- release anything to production.

Those are follow-on packages after this storage/custody seam is reviewed and rebased onto the actual production migration tail.
