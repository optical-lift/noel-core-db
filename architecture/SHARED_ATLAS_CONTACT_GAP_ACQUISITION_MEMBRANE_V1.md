# Shared Atlas Contact-Gap Acquisition Membrane v1

## Purpose

Provide the governed bridge between an Atlas `build_target_contact_set` execution gap and Shared Intelligence evidence acquisition.

This membrane exists because neither side may absorb the other's custody:

- Atlas owns the private request, execution run, and Ledger effects.
- Shared Intelligence owns public external-world identity, public contact facts, evidence, and identity resolution.
- The acquisition worker owns neither. It acquires evidence for one exact persisted gap.

## Governing motion

```text
Atlas contact execution run
        ↓
exact persisted gap
        ↓
Shared research context (provenance only)
        ↓
bounded search query + durable work item
        ↓
web-search worker
        ↓
machine-returned source set
        ↓
source-backed findings
        ↓
universal Shared Intelligence intake/resolver
        ↓
typed directory refresh
        ↓
ready | needs acquisition | partial
```

## Research context

Historical `local_intel.local_contexts` is retained as research provenance.

For Atlas acquisition, one deterministic research context is established per Atlas Organization / Organization Unit:

`atlas-research-<organization uuid>[-unit-<unit uuid>]`

This context means:

> this Atlas Organization caused or uses this research

It does not mean:

> this context owns the external-world identity

Canonical identity remains universal.

## Durable acquisition attempt

`atlas.contact_set_acquisition_attempts` is Organization-private working state.

Each row binds:

- one contact-set execution run;
- one exact gap fingerprint;
- the immutable gap payload;
- Shared research context;
- Shared search query;
- Shared discovery work item;
- acquisition status;
- provider/model provenance;
- the machine-returned source set;
- result summary.

Unique `(execution_run_id, gap_fingerprint)` makes one exact gap resumable and prevents blind repeated research.

## Queue contract

`atlas.queue_contact_gap_acquisition_service_v1` accepts an execution run and an exact gap.

It must prove the gap is currently present in the run's persisted `researchTargets`.

It then:

1. establishes/reuses the Organization research context;
2. derives the intended subject kind;
3. creates one `local_intel.search_queries` row with explicit research context;
4. creates one `local_intel.search_discovery_queue` work item;
5. stores Atlas run/request/gap provenance on both;
6. creates the private acquisition attempt.

It never creates canonical identity or public facts.

## Source-set contract

The application worker must preserve the source URLs returned by its web-search tool separately from model extraction.

`atlas.record_contact_gap_acquisition_service_v1` therefore receives:

- `sources`: the machine-returned source set;
- `findings`: extracted facts, each naming one `sourceUrl`;
- provider/model/response provenance;
- explicit outcome.

Every finding's `sourceUrl` must occur in the supplied source set. A model-generated URL that was not returned by search is rejected.

The database registers those URLs in `local_intel.sources`, then sends each supported finding through the existing universal `local_intel.ingest_search_discovery_evidence_v1` intake.

## Public contact publication consequence

This membrane acquires contact facts only from machine-returned public web sources. When an exact canonical-entity field gap is satisfied by such evidence, the resulting contact point is recorded as public evidence so the governed Shared Directory can consume the fact immediately.

For exact entity-field gaps, the contact route is direct to that canonical entity. The membrane's own provenance keys and publication semantics override any model-returned metadata; extraction cannot downgrade, rewrite, or spoof the machine source URL, attempt identity, visibility, or contact scope.

This does not make private or source-restricted contacts public. Only contact facts accepted through this bounded public-web acquisition membrane receive this consequence.

## Identity rules

### Existing canonical entity gap

For `entity_field_gap`, a finding may enrich only the persisted canonical `entityId`.

### Missing person at known organization

For `organization_person_gap`, a finding must identify a person and must retain the persisted canonical `organizationEntityId`.

The person may resolve to an existing universal identity or become a governed ingestion candidate.

### Population gap

A population-gap finding may introduce additional qualifying subjects, but it still passes through the universal resolver. The worker cannot create a canonical identity directly.

## Resolver behavior

After evidence intake, the membrane refreshes resolver recommendations.

It does not auto-approve identity matches or auto-merge duplicate candidates.

Existing resolver adjudication remains authoritative.

## Completion and refresh

Completing an acquisition attempt means only that the bounded research attempt finished.

Atlas then refreshes the typed directory:

- no remaining gaps → `ready`;
- remaining gaps with at least one not-yet-attempted exact gap → `needs_acquisition`;
- remaining gaps all already attempted and complete → `partial`.

A later change in the gap payload (for example a smaller remaining population shortfall) produces a new fingerprint and may justify another bounded attempt.

## Communication boundary

Acquisition can discover contactability.

It does not grant communication permission and never sends outreach.

## Acceptance proof

A rollback-only validation world has:

- one canonical bank;
- one canonical person at that bank;
- the person is missing email;
- one ready Atlas contact-set run with one `entity_field_gap`.

The proof must show:

1. queuing the exact gap creates one deterministic Organization research context;
2. retrying queue creation reuses the same attempt/work;
3. recording a finding whose source URL is outside the machine source set is rejected;
4. a source-backed email finding enriches the same canonical person UUID;
5. research context membership is added without rewriting the entity's legacy origin pointer;
6. no new canonical entity is created;
7. the acquisition attempt and Shared work/query complete;
8. refreshing the run makes it `ready`;
9. the requesting Ledger binds to the same canonical person;
10. no communication authority is created.
