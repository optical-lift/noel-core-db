# Atlas Recurrence Expectation Lifecycle Adapter v1

**Status:** live and proven beneath the Universal Temporal Field and Temporal Contribution protocol  
**Established:** September 26, 2026  
**Live migrations:**

- `20260926172902_atlas_recurrence_expectation_lifecycle_adapter_v1`
- `20260926173050_atlas_recurrence_expectation_lifecycle_adapter_hardening_v1`

**Parent laws:**

- `architecture/ATLAS_UNIVERSAL_TEMPORAL_FIELD_CONSTITUTION_V1.md`
- `architecture/ATLAS_TEMPORAL_CONTRIBUTION_PROTOCOL_V1.md`

## 1. Purpose

Recurrence is not a collection of duplicate events.

It is a source-owned expectation lifecycle that connects a rule to an expected temporal instance, any current exception, and any canonical Occurrence that ultimately realizes that expectation.

The governing movement is:

```text
Recurrence Rule
  -> derived Expected Instance
  -> current effective exception, if any
  -> effective temporal coordinate
  -> optional canonical Occurrence realization
  -> Temporal Contribution / recurrence overlay
```

The adapter combines three concerns in one lifecycle read:

1. exception lineage;
2. expectation-to-realization reconciliation;
3. temporal pressure before realization.

It creates no new recurrence authority and performs no refresh/materialization write on read.

## 2. Root law

> **Expectation is temporal truth, but expectation is not occurrence truth.**

A recurrence rule can lawfully establish that an interval is expected before a canonical Occurrence exists.

When a canonical Occurrence exists, the recurrence expectation does not become a second event identity. Instead, its lifecycle becomes an overlay on the canonical Occurrence contribution.

Therefore:

```text
Expectation != Occurrence
Expectation may be realized by Occurrence
Realization does not erase expectation lineage
```

## 3. Additive Temporal Standing clarification

The Temporal Field standing vocabulary is extended additively with:

### `expected`

A source authority establishes a temporal expectation, but no stronger realized source object has superseded that expectation for presentation.

Primary first proof:

- an Organization recurrence rule projected into one expected instance.

`expected` is weaker than `scheduled` in ontological force. It must never be rendered as a confirmed Occurrence merely because it has a start/end interval.

An expected contribution can carry lifecycle state such as `expected`, `overridden`, `moved`, or `skipped` while preserving `expected` as the reason the source has temporal standing.

A realization conflict may instead project primary standing `conflict`.

This is projection vocabulary only. No source row receives a universal `temporal_standing` column.

## 4. Existing source authority

V1 reads the already-established Organization recurrence kernel:

- `atlas.organization_recurrence_rules`;
- `atlas.organization_recurrence_exceptions`;
- `atlas.organization_recurrence_instances`;
- `atlas.organization_occurrence_bindings`;
- `local_intel.occurrences`.

No new recurrence table is introduced.

The adapter treats `organization_recurrence_instances` as persisted operational evidence when present, but it does not require an instance row in order to derive an expected temporal projection from an active rule.

This matters because Calendar read completeness must not depend on a prior mutation job having materialized the requested range.

## 5. Read-only expectation derivation

For active rules, the adapter derives expected source dates using the same frequency vocabulary already governed by the recurrence kernel:

- `weekly`;
- `monthly_nth_weekday`.

It respects:

- interval count;
- effective start/end dates;
- weekdays;
- month ordinals;
- source timezone;
- local start/end times.

The adapter does not call `refresh_organization_recurrence_instances_service_v1` and does not insert/update recurrence instances.

Stored recurrence instances inside the requested interval remain admissible evidence even when a rule is paused or retired, so historical realization does not vanish merely because future generation is no longer active.

## 6. Current effective lineage

One expectation lifecycle records:

```text
rule
  -> sourceLocalDate
  -> origin coordinate
  -> current active exception, if any
  -> effectiveLocalDate / effective coordinate
```

Current exception actions are source-owned:

- `skip`;
- `override`;
- `move`.

The current schema does not preserve a revision chain of prior exception rows for the same rule/date. Therefore v1 explicitly reports **current effective lineage**, not fabricated historical revision lineage.

`revisionHistoryAvailable = false` is evidence about that boundary, not a defect hidden by the adapter.

## 7. Realization reconciliation

When a persisted recurrence instance points through an Organization occurrence binding to a canonical Occurrence, the lifecycle records:

```text
realization
  state
  occurrenceBindingId
  occurrenceId
  occurrence status
  occurrence start/end
```

Normal realized expectations do not emit a second calendar item.

Instead:

```text
canonical Occurrence Temporal Contribution
  + recurrenceLifecycle[]
```

The recurrence lifecycle can therefore explain why that Occurrence is in a recurring series without replacing its canonical identity.

If a realization is in source-owned `conflict` state, the expectation may remain independently visible with primary standing `conflict` while the canonical Occurrence remains visible at its own actual coordinate.

## 8. Context admission through recurrence

An Organization Purpose Context may select a recurrence rule directly.

That context membership lawfully admits:

- the rule's unrealized expected instances;
- canonical Occurrences realized by those expected instances.

A realized Occurrence therefore does not require a duplicate direct `occurrence_binding` context membership merely to remain visible through a context that selected the recurrence rule.

This closes the Elm Thanksgiving gap discovered in Temporal Contribution v1: the cancelled November 26 `Thursdays at Elm Seasonal Evening` Occurrence is reachable through recurrence even though its direct `community_calendar` occurrence membership is no longer active.

## 9. Temporal pressure

The lifecycle carries read-only `temporalPressure` evidence.

V1 classes are:

### `expectation`

The expectation is active and unrealized.

It identifies an interval that a later conflict/availability authority may consider.

The recurrence adapter does **not** itself block a Resource, create a hold, or establish a booking.

### `delegated_to_realization`

A canonical Occurrence now realizes the expectation.

The recurrence expectation no longer competes as a second temporal claimant. Stronger occurrence/scheduling authorities own actual occupancy/commitment semantics.

### `none`

The expectation is skipped/retired or its realized Occurrence is cancelled in a way that leaves no active recurrence pressure.

### `conflict`

The recurrence kernel already records a realization mismatch. The adapter preserves that conflict rather than silently choosing the expected or actual coordinate.

These classes are evidence for later planning/conflict adapters. They are not universal priority numbers and do not encode booking authority.

## 10. Effective interval semantics

For ordinary expectations:

```text
source date + rule local time + rule timezone
```

For `override`:

```text
source date + override times + rule timezone
```

For `move`:

```text
replacement date + override/rule times + rule timezone
```

For overnight intervals, an end time earlier than the start time means the effective end falls on the following civil date, matching the existing recurrence refresh service.

A Temporal Contribution preserves both origin and effective coordinates when an exception changes the expectation.

## 11. Adapter output

The recurrence adapter returns two coordinated read products.

### Standalone expectation contributions

Used when no canonical Occurrence realizes the expectation, or when a source-owned realization conflict requires the expected coordinate to remain separately visible.

Their source remains the recurrence rule:

```text
sourceRef
  authority = atlas
  kind = recurrence_rule
  id = <rule UUID>

projectionKey
  recurrence_expectation:<rule UUID>:<source local date>
```

The projection key distinguishes expected instances without manufacturing canonical identity.

### Occurrence admissions / lifecycle overlays

Used when a canonical Occurrence realizes the expectation.

They carry:

- canonical occurrence ID;
- recurrence lifecycle;
- rule/source-date lineage;
- exception evidence;
- realization state;
- temporal pressure class.

The composer uses these admissions to request the canonical Occurrence adapter and attach recurrence lineage to the returned canonical contribution.

## 12. Composer v2

Organization-context Temporal Composer v2 performs:

```text
Organization Context overlay v2
  -> canonical occurrence refs
  -> canonical temporal-marker refs
  -> recurrence-rule refs

recurrence adapter
  -> standalone expectations
  -> canonical occurrence admissions
  -> lifecycle overlays

canonical Occurrence adapter
canonical Temporal Marker adapter

composer
  -> one source-preserving contribution set
```

A realized recurrence instance therefore resolves to one canonical Occurrence contribution, not one Occurrence plus one recurrence-instance event.

## 13. Coverage law

Composer v2 is complete for Organization purpose-context member kinds:

- `occurrence_binding`;
- `temporal_binding`;
- `recurrence_rule`.

Other member kinds remain explicitly unsupported/partial.

The recurrence adapter also reports:

- requested vs resolved rules;
- returned lifecycle count;
- whether its bounded result was truncated;
- derived expectations without persisted instance rows;
- realized occurrence admissions;
- standalone expectations;
- realization conflicts.

Truncation or missing rule resolution makes coverage partial.

## 14. Elm acceptance

### October 1 through November 30, 2026

Composer v2 must recover complete Elm `community_calendar` temporal reality as:

```text
25 canonical Occurrence contributions
2 canonical Temporal Marker contributions
0 duplicate recurrence-instance event identities
```

The cancelled November 26 recurrence realization must be included through recurrence-rule context admission and retain its skip/cancel lineage.

Coverage must no longer be partial merely because recurrence is present.

### December 2026

The recurrence adapter must derive four Elm expectations from the active rules even though no December recurrence-instance rows currently exist:

```text
Dec 3  Community Morning
Dec 10 Seasonal Evening
Dec 17 Community Morning
Dec 24 Seasonal Evening
```

Those expected contributions must carry active `expectation` temporal pressure and must not create recurrence-instance rows as a side effect.

### Move proof

A rollback-only temporary `move` exception must prove:

```text
source date remains in lineage
replacement date becomes effective coordinate
pressure follows the effective coordinate
no persisted test exception remains
```

These acceptance conditions were proven against the live Noel Core database on September 26, 2026. The permanent executable form is preserved at:

- `validation/recurrence_expectation_lifecycle_adapter_v1.sql`

## 15. Non-collapse rules

### Rule != expectation identity

One rule can generate many projection instances.

### Projection key != canonical identity

A derived expectation key exists only for read composition.

### Expectation != Occurrence

An expectation can exist before an Occurrence and can be skipped without one.

### Realization != duplication

A realized expectation enriches/adopts the canonical Occurrence contribution; it does not create another event.

### Temporal pressure != Resource claim

Expectation pressure is planning evidence, not occupancy, booking, hold, or claim truth.

### Exception != alternate event

A move/override/skip changes expectation lineage; it does not mint a second canonical event identity.

### Composer != recurrence engine

The recurrence adapter owns recurrence interpretation. The composer only combines its output with other source adapters.

## 16. Live implementation and custody

The live implementation is now repository-custodied by the exact applied migrations:

- `supabase/migrations/20260926172902_atlas_recurrence_expectation_lifecycle_adapter_v1.sql`
- `supabase/migrations/20260926173050_atlas_recurrence_expectation_lifecycle_adapter_hardening_v1.sql`

The first migration established the read-only adapter/composer contract. The second migration did not rewrite the applied first migration; it hardened `derivedWithoutPersistedInstanceCount` so JSON `null` is counted correctly when no persisted recurrence instance exists.

The implementation remains read-only with respect to recurrence/calendar state. No recurrence-instance materialization, canonical Occurrence creation, or alternate event identity is performed during composition.

The candidate file remains as implementation provenance:

- `candidates/atlas-recurrence-expectation-lifecycle-adapter-v1/candidate.sql`

## 17. Performance advisor classification

The post-implementation Supabase performance advisor contains **no finding introduced by the recurrence expectation lifecycle adapter migrations**.

The two live migrations create or replace functions and grants/comments only. They add no tables, indexes, foreign keys, RLS policies, or new stored recurrence-instance write path.

The advisor does report pre-existing optimization debt on recurrence backing tables, including unused recurrence-rule and recurrence-override indexes. Those findings belong to the older persistence layer and are not a regression caused by this read-model tranche.

Classification for this tranche:

```text
recurrence-adapter-specific performance blocker: none
new recurrence-adapter advisor regression: none
pre-existing recurrence backing-table optimization debt: present, non-blocking here
```

## 18. Next boundary

With this lifecycle adapter live and proven, the Elm `community_calendar` is the first complete multi-source proof of the adapter-first Temporal Field.

The next independent source adapter should be Reality/Ledger scheduling enrichment and occupancy, followed by Company Work timing/conflicts, Person Life/Principal Clock, and Communication consequences.
