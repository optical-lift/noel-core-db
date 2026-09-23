# Atlas Observation → Canonical Admission Gate v1

## Purpose

The bulk-ingestion control plane can now preserve a source artifact, parse an observation, and decide whether that observation refers to an existing canonical party, a genuinely new candidate, an ambiguous case, or a rejected record.

This tranche establishes the only lawful bridge from those observations into canonical Shared Intelligence party truth.

```text
observation
    ↓
current resolution decision
    ↓
canonical admission gate
    ├── resolved_existing → admit source-backed evidence
    ├── new_entity_candidate + explicit human approval → create minimal canonical party + admit evidence
    ├── ambiguous → stop
    └── rejected → stop
```

## Source-record continuity

A recurring public dataset needs durable continuity across ingestion runs.

`local_intel.ingestion_source_entity_bindings` maps:

```text
(configured ingestion source, source record key)
        ↓
canonical entity
```

This prevents a later refresh of the same registry row from accidentally creating another canonical party.

A current source-record binding may not silently move from one canonical entity to another. A disagreement is an identity-resolution problem and must be adjudicated separately.

## Admission audit

`local_intel.ingestion_observation_admissions` records the durable admission receipt for one observation.

An observation may be admitted only once. Replaying the same admission returns the existing receipt rather than duplicating evidence or creating another entity.

The receipt preserves:

- target canonical entity;
- whether the entity was created by this admission;
- source class used;
- admitted evidence claim IDs/count;
- who explicitly approved a new entity creation;
- admission metadata and timestamp.

## Existing-party admission

When the current observation resolution is `resolved_existing`, the admission gate:

1. verifies the canonical entity still exists;
2. establishes or confirms the source-record continuity binding;
3. converts extracted candidate claims into governed `entity_evidence_claims`;
4. marks the observation `admitted`;
5. records the admission receipt.

Resolution alone still changes no canonical evidence.

## New-party creation gate

`new_entity_candidate` is not permission to manufacture a new canonical identity.

Creation requires an explicit admission call with:

- `create_new_entity = true`;
- an active `local_context_id`;
- a nonblank human/operator approval identity.

The new entity is intentionally minimal:

- canonical entity type;
- canonical name;
- deterministic source-derived stable key;
- local context;
- provenance metadata.

Email, phone, address, website, registration number, and other source facts are **not** copied into legacy scalar columns. They enter through governed evidence claims.

This keeps the canonical entity thin and preserves provenance/disclosure policy.

## Evidence admission policy

The configured ingestion source points to `local_intel.sources`, whose Evidence + Disclosure `source_class_key` governs admission.

If the source is unclassified, admission falls back conservatively to `legacy_unclassified`.

For each extracted claim:

- identity-resolution use is admitted only if the source class permits it;
- directory display is admitted only if the source class permits it;
- outreach is admitted only for a recognized contact channel and only when the source class permits `public_contactable` outreach;
- government/public-directory sources therefore do not become marketing channels merely because an email or phone appeared in the dataset.

Typical outcomes:

```text
government_registry name/address
    → public_directory
    → identity_resolution + directory_display

self_published_business email
    → public_contactable
    → identity_resolution + directory_display + outreach

unclassified legacy source
    → resolution_only
    → identity_resolution only
```

The existing `record_entity_evidence_claim_service_v1` remains the policy-enforcement membrane; this admission gate does not bypass it.

## Extracted claim contract

Each claim object must contain:

```json
{
  "claimKind": "email",
  "valueText": "hello@example.com"
}
```

Optional fields may include:

- `contactChannel`;
- `contactIntents`;
- `validFrom`;
- `validUntil`;
- `metadata`.

Malformed extracted claims fail the admission transaction rather than partially mutating canonical truth.

## Ambiguity/rejection boundary

`ambiguous` and `rejected` observations cannot be admitted.

The resolver/reviewer must establish a new current resolution before the admission gate can proceed.

## Core law

```text
source record continuity prevents duplicate identity
resolution chooses the referent
admission chooses whether source testimony becomes canonical evidence
new identity creation requires explicit human approval
```
