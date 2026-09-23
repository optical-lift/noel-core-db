# Atlas Organization Purpose / Context Routing v1

## Status

Architecture contract only. No database migration is established by this document.

## Purpose

Atlas needs one durable way for an Organization to route the same canonical external-world reality into multiple internal uses without cloning that reality.

The governing pattern is:

```text
one canonical reality
→ one Organization-private Ledger binding
→ many Organization-owned purpose/context memberships
→ purpose-specific projections and workflows
```

This contract is the executable-design successor to the purpose/context rule in `SHARED_DIRECTORY_LEDGER_OVERLAY.md`.

## Reality boundaries

These truths remain distinct:

- canonical person / business / organization / place identity;
- one Atlas Organization's private relationship to that identity;
- canonical real-world occurrence identity;
- one Atlas Organization's private binding to that occurrence;
- a purpose/context inside that Organization;
- the referent's membership in that context;
- a projection such as a calendar, donor list, resource guide, campaign set, or program roster.

A context never becomes identity. A projection never becomes identity. A context-specific payload never becomes Shared Intelligence merely because it concerns a shared UUID.

## Existing entity seam

Canonical external entities remain owned by `local_intel.entities`.

The requesting Organization's private relationship remains represented by the existing Shared Directory / Ledger Overlay seam:

```text
local_intel.entities.id
→ atlas.identity_subject_external_identifiers
→ atlas.identity_subjects
→ atlas.external_relationships
```

Purpose routing must reuse `atlas.external_relationships.id`. It must not create another Atlas contact/business/person record.

## Missing occurrence seam

Canonical real-world occurrences are owned by `local_intel.occurrences`.

Atlas currently lacks an Organization-scoped occurrence binding equivalent to the entity relationship seam. The proposed carrier is:

### `atlas.organization_occurrence_bindings`

Minimum contract:

- `id uuid primary key`
- `organization_id uuid not null`
- `occurrence_id uuid not null` → `local_intel.occurrences(id)`
- `binding_state text not null` — initially `active | inactive`
- `metadata jsonb not null default '{}'`
- `created_by_membership_id uuid null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Required invariants:

- unique `(organization_id, occurrence_id)`;
- one Organization may bind a canonical occurrence once;
- many Organizations may bind the same canonical occurrence independently;
- deleting/inactivating one Organization's binding never deletes the canonical occurrence;
- another Organization cannot read or mutate this Organization's binding metadata.

This binding owns Organization-specific occurrence meaning that is broader than any one use/context. Context-specific facts do not belong here.

## Purpose contexts

The proposed durable context carrier is:

### `atlas.organization_purpose_contexts`

Minimum contract:

- `id uuid primary key`
- `organization_id uuid not null`
- `stable_key text not null`
- `context_kind text not null`
- `title text not null`
- `description text null`
- `context_state text not null` — initially `active | archived`
- `metadata jsonb not null default '{}'`
- `created_by_membership_id uuid null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Required invariants:

- unique `(organization_id, stable_key)`;
- a context belongs to exactly one Organization;
- `context_kind` is typed but extensible rather than farm-specific;
- context metadata is Organization-private;
- archiving a context does not alter canonical identities, occurrence identities, Organization relationships, or occurrence bindings.

Representative context kinds include, without making the list exhaustive:

- `program`
- `fundraiser`
- `campaign`
- `calendar`
- `resource_guide`
- `outreach_set`
- `donor_set`
- `roster`
- `custom`

A context kind describes how the Organization intends to use the set. It does not change the kind of the underlying reality.

## Purpose context memberships

The proposed routing carrier is:

### `atlas.organization_purpose_context_memberships`

Minimum contract:

- `id uuid primary key`
- `organization_id uuid not null`
- `context_id uuid not null`
- `member_kind text not null` — `external_relationship | occurrence_binding`
- `external_relationship_id uuid null`
- `occurrence_binding_id uuid null`
- `membership_state text not null` — initially `active | excluded | archived`
- `role_keys text[] not null default '{}'`
- `payload jsonb not null default '{}'`
- `provenance jsonb not null default '{}'`
- `created_by_membership_id uuid null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Exactly one referent must be present:

```text
member_kind = external_relationship
  → external_relationship_id is set
  → occurrence_binding_id is null

member_kind = occurrence_binding
  → occurrence_binding_id is set
  → external_relationship_id is null
```

Required uniqueness:

- one active membership per `(context_id, external_relationship_id)`;
- one active membership per `(context_id, occurrence_binding_id)`.

A later role-specific child relation may be introduced only if real usage proves that one membership needs independently governed role lifecycles. V1 keeps roles as bounded membership attributes rather than manufacturing another kernel prematurely.

## Context-specific payload

`payload` is deliberately local to one context membership.

Examples:

For one canonical donor/business in a fundraiser context:

```json
{
  "sponsorshipStatus": "invited",
  "tableCount": 1,
  "assignedCaller": "Katie",
  "followUp": "Ask about matching gift"
}
```

The same canonical business in a youth-program context may carry:

```json
{
  "programRole": "donor",
  "annualCommitment": 2500,
  "recognitionName": "Smith Construction"
}
```

For one canonical occurrence in an educational-events calendar:

```json
{
  "include": true,
  "category": "art",
  "audience": "families",
  "displayPriority": 20
}
```

These payloads are not canonical public facts and are not copied onto `local_intel.entities` or `local_intel.occurrences`.

## Organization isolation

The routing kernel must enforce Organization ownership structurally, not by application convention alone.

The migration should use Organization-consistent composite constraints/foreign keys or equivalent governed write functions so that:

- a context cannot accept a relationship from another Organization;
- a context cannot accept an occurrence binding from another Organization;
- one Organization cannot read another Organization's context payload;
- client roles do not receive direct broad table access;
- authenticated mutation occurs through Organization-authorized self APIs;
- service writers validate Organization scope before mutation.

## Community-event succession

`atlas.community_events` remains an operational/program carrier, not canonical occurrence identity.

The succession target is for each real `atlas.community_events` row to bind to the Organization's `organization_occurrence_bindings` row for the canonical `local_intel.occurrences` occurrence it operationalizes.

The exact migration may add an occurrence-binding reference to `atlas.community_events`, but it must preserve these rules:

- no second canonical event identity;
- the bound occurrence is the source of real-world occurrence identity;
- community-program data remains Atlas operational state;
- removing a program/context membership does not delete the occurrence;
- public calendar projection composes canonical occurrence truth with authorized Organization context rather than selecting an identity authority by ownership.

## Projection semantics

A projection is selected use, not storage authority.

Examples:

```text
Educational Events Calendar
= active occurrence memberships in context "educational_events"
  + canonical occurrence facts
  + permitted canonical entity facts
  + selected publishable membership payload
```

```text
Local Business Resources
= active entity memberships in context "local_business_resources"
  + canonical entity facts
  + selected publishable membership payload
```

```text
Annual Fundraiser Contact List
= active entity memberships in context "annual_fundraiser"
  + canonical entity facts
  + requesting Organization's private relationship overlay
  + fundraiser-specific membership payload
```

The projection must never create or become another contact/event directory.

## Deletion semantics

Deletion must preserve reality boundaries:

- deleting a context membership removes only that use;
- archiving a context removes no canonical entity, occurrence, relationship, or occurrence binding;
- ending an Organization relationship does not delete Shared Intelligence identity;
- inactivating an occurrence binding does not delete the canonical occurrence;
- canonical deletion/retirement remains owned by the canonical Shared Intelligence authority.

## Relationship to contact-set Intelligence

Contact-set intents/execution runs may populate or propose memberships only through a governed purpose-routing write seam.

They remain temporary Intelligence working state and do not become the durable context or membership merely because they discovered the candidate.

## Acceptance proof

The kernel is proven when all of the following hold:

1. one canonical business is shared by two Atlas Organizations;
2. Organization A has one private external relationship to it;
3. Organization A routes that same relationship into at least two contexts with different payloads;
4. removing one membership leaves the other membership and the relationship intact;
5. Organization B sees the same canonical business but none of Organization A's relationship/context payload;
6. one canonical occurrence is bound by Organization A and routed into two different contexts without a second occurrence row;
7. an Elm-owned program event binds to that canonical occurrence rather than becoming another event authority;
8. a calendar/resource/donor projection can be built entirely from canonical reality + authorized Organization overlay/context memberships.
