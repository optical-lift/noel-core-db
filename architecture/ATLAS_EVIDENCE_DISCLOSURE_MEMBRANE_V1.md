# Atlas Evidence + Disclosure Membrane v1

## Purpose

Atlas must be able to ingest public reality aggressively without turning every obtainable fact into a directory field or an outreach lead.

The governing distinction is:

```text
what Atlas may know
        ≠
what Atlas may reveal
        ≠
what Atlas may act on
```

v1 establishes the membrane between evidence intake and downstream disclosure/action.

## Wide evidence intake, narrow action rights

A fact being publicly obtainable does not by itself make it appropriate for outreach.

Examples:

- an email explicitly published by a business for inquiries may be contactable;
- a legal address in a government registry may be directory-visible but not an outreach channel;
- a personal email appearing in a permit, parcel, court, or other public record may be useful for identity resolution while remaining `resolution_only`;
- Organization-private contact information does not enter Shared Intelligence merely because Atlas can use it to resolve identity.

The membrane therefore classifies each evidence claim independently by:

1. source class,
2. evidentiary strength,
3. disclosure posture,
4. permitted uses,
5. contact intent, when the claim is explicitly contactable.

## Evidence source classes

`local_intel.evidence_source_classes` defines conservative maximums for a class of source.

Initial classes include:

- `owner_verified_public`
- `self_published_business`
- `self_published_professional`
- `government_registry`
- `public_record_resolution`
- `third_party_directory`
- `legacy_unclassified`

A source class defines what a claim from that class may be used for at most. An ingestion process may always choose a more restrictive posture/use set; it may not silently exceed the source class ceiling.

For example:

```text
government_registry
  maximum disclosure: public_directory
  allowed uses:
    identity_resolution
    directory_display

public_record_resolution
  maximum disclosure: resolution_only
  allowed uses:
    identity_resolution

self_published_business
  maximum disclosure: public_contactable
  allowed uses:
    identity_resolution
    directory_display
    outreach
```

This prevents "public record" from becoming synonymous with "marketing lead."

## Claim-level evidence

`local_intel.entity_evidence_claims` stores source-backed claims about a canonical entity.

Examples:

```text
claim_kind = legal_name
claim_kind = email
claim_kind = phone
claim_kind = website
claim_kind = address
claim_kind = registration_number
```

A claim carries:

- the raw value and normalized match value;
- canonical entity;
- source / source class;
- evidentiary strength;
- disclosure posture;
- permitted uses;
- optional contact channel and contact intents;
- lifecycle state;
- observation/verification dates;
- metadata/provenance.

The canonical entity row remains the identity conclusion. Evidence claims are the support underneath that conclusion.

## Disclosure postures

v1 recognizes:

```text
public_contactable
public_directory
resolution_only
restricted
suppressed
```

### public_contactable

May be eligible for outreach only when:

- `outreach` is an explicitly permitted use;
- the requested contact intent matches the claim's contact intents or the claim allows `general`;
- no active suppression applies.

### public_directory

May be displayed where `directory_display` is permitted. It is not an outreach channel merely because it is visible.

### resolution_only

May participate in identity resolution. It must not appear in ordinary directory or contactability projections.

### restricted

Retained for governed internal/system use outside ordinary directory/contact workflows.

### suppressed

Retained only as required for suppression, provenance, or historical integrity. It is not returned for ordinary resolution/display/outreach.

## Contact intent

Contactability is purpose-sensitive.

A self-published contact point may declare intents such as:

```text
general
events
partnerships
vendor
wholesale
press
support
billing
employment
```

An email published specifically for billing is not automatically equivalent to an email published for partnerships.

v1 does not decide whether an outbound message is legally or contractually permissible in every jurisdiction. It establishes the data membrane required so later action services can enforce purpose-specific policy rather than selecting any known address.

## System-level suppression

`local_intel.entity_contact_suppressions` can suppress:

- one evidence claim, or
- an entire canonical entity

for:

- `outreach`
- `directory_display`
- `all_use`

Suppression is independent of an Organization's private "do not contact" state.

An Organization may privately decide not to contact someone. A system-level suppression means Atlas must prevent the governed shared-data pathway from producing that contact for the suppressed use.

## Read membranes

v1 exposes three service-level projections.

### Identity resolution

`local_intel.resolve_entities_by_evidence_value_service_v1`

Uses current claims permitted for `identity_resolution`, including `resolution_only` evidence.

It returns canonical identity candidates and match metadata, not the hidden claim value.

### Directory display

`local_intel.entity_directory_evidence_service_v1`

Returns only current evidence permitted for `directory_display` whose posture is `public_directory` or `public_contactable`, excluding active suppressions.

### Contactability

`local_intel.entity_contactable_evidence_service_v1`

Returns only current `public_contactable` claims that:

- explicitly permit `outreach`;
- have a contact channel;
- match the requested intent or `general`;
- are not actively suppressed for outreach/all-use.

Legacy columns such as `local_intel.entities.email`, `phone`, and `website_url` remain compatibility fields. Their presence alone is **not** authority for the governed contactability service.

## Private information

Organization-private information remains outside this shared evidence table.

The intended future private-contact path is:

```text
canonical entity
        ↓
Organization external_relationship
        ↓
Organization-private contact point
        ↓
restricted identity-resolution token if lawful
```

A private value may eventually assist identity resolution through a non-disclosing match mechanism, but it must not be copied into Shared Intelligence merely because an Organization knows it.

## Promotion rule

No evidence claim is promoted into a more permissive disclosure posture merely because:

- several Organizations know it;
- it appears in multiple datasets;
- it has high match confidence;
- it is technically accessible on the public web.

Promotion requires an appropriate source/disclosure basis.

Repeated private knowledge does not become public knowledge.

## Core law

```text
ingest broadly
resolve carefully
publish selectively
contact intentionally
```

Atlas should aim to understand reality comprehensively while revealing and acting on only the subset for which the evidence and disclosure posture provide a legitimate basis.
