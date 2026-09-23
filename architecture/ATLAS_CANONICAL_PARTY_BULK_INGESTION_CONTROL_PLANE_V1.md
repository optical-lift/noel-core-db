# Atlas Canonical Party Bulk Ingestion Control Plane v1

## Purpose

Atlas already has canonical Shared Intelligence entities, Evidence + Disclosure, source-party resolution for private Ledgers, and semantic identity resolution.

What is still missing for large public/canonical-contact ingestion is the industrial control plane that can receive a registry export, directory crawl, website snapshot, CSV, JSON feed, PDF, or similar source artifact and turn it into small, auditable observations without dumping the raw source into canonical tables.

v1 establishes:

```text
existing ingestion source
        ↓
ingestion run
        ↓
raw object manifest
        ↓
observation envelope
        ↓
resolution decision
```

It deliberately stops before canonical admission. A later tranche will convert resolved observations into governed evidence claims and, where necessary, newly created canonical entities.

## Existing source registry remains authoritative

`local_intel.ingestion_sources` already identifies configured ingestion sources and points to `local_intel.sources` for source/provenance classification.

This tranche reuses it. It does not create a second source registry.

## Ingestion run

`local_intel.ingestion_runs` records one bounded execution against one configured ingestion source.

It preserves:

- run key;
- parser key/version;
- optional acquisition method;
- source cursor/window at start and finish;
- state/timestamps;
- counts for seen, extracted, rejected, resolved, and admitted records;
- run metadata.

Runs are history, not mutable source truth. Re-running a source creates a new run.

## Raw object manifest

`local_intel.ingestion_raw_object_manifests` stores only custody metadata for raw artifacts.

Typical objects:

- downloaded CSV;
- registry JSON page;
- HTML snapshot;
- PDF;
- API response archive;
- compressed export.

The bytes belong in object storage. Postgres stores:

- storage URI;
- content hash + algorithm;
- MIME type;
- byte count;
- retrieval time;
- optional source object key;
- parser/acquisition metadata.

Raw objects are immutable evidence custody. They are not canonical truth.

## Observation envelope

`local_intel.ingestion_observations` is the generic adapter output.

A parser emits a small observation such as:

```text
source record key: MO-123456
observation kind: party_candidate
proposed entity type: business
proposed display name: Bob Mechanics LLC
source locator: row 812
extracted claims:
  registration_number = MO-123456
  name = Bob Mechanics LLC
  address = ...
```

`extracted_claims` is an array of claim-shaped objects, not evidence admission. The observation may be wrong. It is therefore immutable parser testimony, not a direct write to `local_intel.entities`.

Adapters should preserve a source locator sufficient to trace the observation back to its raw object.

## Resolution decision

`local_intel.ingestion_observation_resolutions` records the resolver/adjudication result for an observation.

States:

- `resolved_existing` — points to an existing canonical entity;
- `new_entity_candidate` — no adequate existing entity is known;
- `ambiguous` — multiple plausible entities or insufficient separation;
- `rejected` — source record should not become canonical party evidence.

A new current resolution supersedes the previous current resolution while preserving history.

Resolution does not itself admit claims into canonical Shared Intelligence.

## Idempotence

Within a run, one `(source_record_key, observation_kind)` is one observation.

Across runs, the same source record may appear again. That is intentional: source history changes and parsers evolve.

`payload_hash` and raw object `content_hash` make unchanged input detectable without making the database retain the original bytes.

## Canonical-contact law

```text
raw source bytes
    are not canonical identity

parser observations
    are not canonical identity

resolver decisions
    are not public disclosure authority

only governed admission
    may change Shared Intelligence truth
```

## Scale rule

Keep large raw artifacts out of Postgres.

Keep durable control metadata, observations worth resolving, resolution history, admitted evidence, and canonical identity in Postgres.

Everything else should be cheap to regenerate.

## Next seam

The next ingestion tranche should be **Observation → Canonical Admission**:

1. resolved-existing observation → evidence claim admission under source-class ceilings;
2. new-entity candidate → dedupe/creation gate → canonical entity;
3. ambiguous observation → review queue;
4. rejected observation → durable rejection reason.

That admission service should be the only path by which this bulk pipeline changes canonical party truth.
