# Atlas Reality / Ledger Temporal Enrichment + Occupancy Adapter v1

**Status:** staged source adapter beneath the Universal Temporal Field  
**Established:** September 26, 2026  
**Parent laws:**

- `architecture/ATLAS_REALITY_LEDGER_SCHEDULING_CONSTITUTION_V1.md`
- `architecture/ATLAS_UNIVERSAL_TEMPORAL_FIELD_CONSTITUTION_V1.md`
- `architecture/ATLAS_TEMPORAL_CONTRIBUTION_PROTOCOL_V1.md`
- `architecture/ATLAS_RECURRENCE_EXPECTATION_LIFECYCLE_ADAPTER_V1.md`

## 1. Purpose

Reality / Ledger scheduling already owns several different kinds of truth around time:

- canonical occurrence membership in a Ledger scheduling field;
- Ledger booking commitment around a canonical occurrence;
- explicit Resource occupancy claims;
- resource identity and hierarchy;
- booking references to external/commercial systems;
- current occupancy conflict evaluation.

The Universal Temporal Field must admit those truths without creating a second scheduling model and without turning every scheduling fact into an event.

The governing movement is:

```text
canonical Occurrence
  + Ledger calendar membership
  + Ledger booking state
  + explicit Resource occupancy claims
  -> source-preserving scheduling adapter
  -> canonical Occurrence enrichment
  + independent occupancy Temporal Contributions
  -> Ledger-scoped Temporal composer
```

This adapter is read-only. It creates no booking, Resource, claim, occurrence, calendar binding, or calendar-event identity.

## 2. Root law

> **Booking and calendar membership enrich an Occurrence. Resource Claim occupies time in its own right.**

A Booking does not own an independent time coordinate in the current kernel. It is a Ledger commitment around a canonical Occurrence.

A Resource Claim does own an explicit interval:

```text
starts_at
ends_at
```

and that interval may lawfully be wider than the visible occurrence interval for setup, teardown, preparation, cleanup, travel, or another real occupancy reason.

Therefore:

```text
Occurrence != Booking
Occurrence != Resource Claim
Booking != Resource Claim
Occurrence may be enriched by Booking + Ledger calendar meaning
Resource Claim may project independently as occupancy
```

## 3. Source authority

V1 reads only already-governed authorities:

- `ledger.ledgers`;
- `ledger.occurrence_calendar_bindings`;
- `ledger.bookings`;
- `ledger.booking_references`;
- `ledger.occurrence_resource_claims`;
- `reality.resources`;
- `reality.entities` for authorized display identity;
- `local_intel.occurrences` for canonical occurrence identity/timing;
- `ledger.resource_claim_availability_v1` for current conflict evidence.

The adapter does not copy these facts into a new table.

## 4. Two coordinated read products

### 4.1 Occurrence admissions / scheduling overlays

A Ledger scheduling source may make a canonical Occurrence relevant through any of these live conditions:

- active `ledger.occurrence_calendar_bindings` membership;
- non-cancelled Ledger booking;
- active (`tentative` or `confirmed`) Resource Claim.

The adapter returns an occurrence admission keyed by canonical `occurrenceId`.

That admission carries a Ledger scheduling overlay containing:

- calendar binding identity/state/role keys/metadata;
- all Ledger booking records around that occurrence, including terminal history visible in current booking state;
- typed booking references;
- customer Entity identity/display where already authorized inside the Ledger read;
- active Resource Claims;
- Resource identity/hierarchy/capacity facts;
- current occupancy classification (`unclassified`, `clear`, `conflict`);
- aggregate active occupancy window when claims exist.

The admission does **not** become a second occurrence contribution.

The Ledger composer asks the canonical Occurrence adapter for the same canonical occurrence and attaches the scheduling overlay additively.

### 4.2 Occupancy Temporal Contributions

Every active Resource Claim overlapping the requested interval may emit one independent Temporal Contribution.

Its identity remains the Resource Claim:

```text
projectionKey = ledger_resource_claim:<claim UUID>

sourceRef
  authority = ledger
  kind = occurrence_resource_claim
  id = <claim UUID>
```

Primary standing is:

- `scheduled` when the active claim currently has no blocking conflict;
- `conflict` when source-owned conflict evaluation says the active claim cannot coexist with current occupancy/resource state.

The claim coordinate is its own `starts_at` / `ends_at`, not the canonical occurrence coordinate.

This is not duplicate event identity. It is occupancy truth.

## 5. Why Booking is overlay, not another contribution

Current `ledger.bookings` has no independent start/end columns.

Its time-bearing relationship is:

```text
Booking
  -> occurrence_id
  -> canonical Occurrence time
```

Creating a second scheduled contribution merely because a booking exists would visually duplicate one real occurrence while adding no independent temporal coordinate.

Therefore V1 keeps Booking under the canonical Occurrence scheduling overlay.

If a future governed booking authority establishes independent booking windows, holds, or request windows with their own source-owned coordinates, those facts may later qualify for their own contribution type. V1 does not fabricate that future ontology now.

## 6. Why Resource Claim is not merely overlay

A Resource Claim has source-owned temporal coordinates independent of occurrence display time.

Example:

```text
Occurrence
  6:00–8:00 p.m.

Resource Claim
  Event Center
  4:30–9:30 p.m.
```

A Calendar event lens may show only the 6:00–8:00 occurrence.

A Resource lane or scheduling workbench must be able to show the 4:30–9:30 occupancy without rewriting the occurrence.

The independent occupancy contribution preserves that distinction.

## 7. Occupancy classification

The scheduling overlay classifies the occurrence's current occupancy state as:

### `unclassified`

No active Resource Claim exists for the occurrence in this Ledger.

This is incomplete scheduling truth, not an error and not permission to invent a Resource.

### `clear`

At least one active Resource Claim exists and current conflict evaluation reports no blocker for those claims.

### `conflict`

At least one active Resource Claim currently fails source-owned Resource availability/conflict evaluation.

Conflict remains visible. The adapter does not move, cancel, release, or rewrite either claim.

## 8. Resource Claim conflict standing

For each active claim the adapter reuses:

`ledger.resource_claim_availability_v1`

with the claim itself and its own occurrence excluded from self-conflict evaluation, matching the established Resource calendar semantics.

If the returned `available` value is false, the occupancy contribution projects primary standing `conflict` and retains the returned availability packet as conflict evidence.

If true, primary standing remains `scheduled`.

This does not promote availability evaluation into a new authority; it is current source-owned evidence about an already-existing claim.

## 9. Canonical occurrence preservation

The Ledger composer performs:

```text
Ledger scheduling adapter
  -> occurrenceAdmissions[]
  -> occupancyContributions[]

canonical Occurrence adapter
  <- admitted canonical occurrence IDs

composer
  -> canonical Occurrence contributions + scheduling overlay
  -> independent Resource Claim occupancy contributions
```

The composer must never emit:

```text
canonical occurrence
+ booking event identity
+ ledger-calendar event identity
```

for one real occurrence.

## 10. Additive contribution shape

The canonical Occurrence contribution remains owned by `local_intel` and retains its existing sourceRef/encounter.

The Ledger composer adds:

```text
scheduling[]
  ledgerId
  ledgerStableKey
  ledgerName
  calendarBinding
  bookings[]
  resourceClaims[]
  occupancyState
  occupancyWindow
```

This is authorized source enrichment, not source identity replacement.

The independent occupancy contribution uses the common Temporal Contribution envelope and keeps detailed claim/resource/occurrence/booking evidence in `sourceSnapshot`.

## 11. Epistemic and incomplete truth law

V1 must preserve:

- occurrence with no known Resource Claim;
- occurrence with known booking but no claim;
- occurrence with claims but no booking;
- active Resource Claim whose interval differs from occurrence time;
- Resource conflict;
- cancelled Booking history without treating it as active admission by itself;
- unknown occurrence end time without manufacturing one.

The adapter must not invent:

- Resource classification;
- booking state;
- customer identity;
- claim interval;
- capacity quantity;
- conflict resolution;
- occurrence duration.

## 12. Authorization

Internal adapter and composer functions are service-only.

The authenticated read seam is Ledger-scoped and requires:

```text
auth.uid()
+
atlas.current_active_ledger_seat_v1(ledger)
```

This is intentionally different from the Organization-context Temporal composer, which uses Organization membership.

A Ledger Seat grants access to the Ledger-scoped Temporal read. It does not grant every scheduling mutation capability.

Mutation authority remains governed by the existing scheduling self APIs and responsibility/capability checks.

## 13. Coverage

The adapter reports independent limits for:

- occurrence admissions;
- occupancy contributions.

Coverage is partial when either source set exceeds the requested bounded limit.

The composer must propagate that partiality.

V1 does not claim complete scheduling coverage for:

- Reality availability windows;
- booking request/approval/hold windows;
- Offering possibility/evaluation;
- Ledger recurrence expectation;
- named calendar collections;
- free/busy transparency;
- first-class participant roles.

Those remain separate authorities/tranches.

## 14. Elm acceptance oracle

Elm Farm Venue Ledger is the first adopter because it already carries real Resource/Booking/Claim state without requiring a synthetic domain.

For September 1 through December 31, 2026 the current Ledger Resource Calendar contains:

```text
30 admitted canonical Occurrences
29 active Resource Claim occupancies
1 unclassified canonical Occurrence
1 canonical Occurrence with a confirmed Booking
0 current Resource conflicts
```

Named controls:

### Confirmed Booking control

`John Gray Private Rental`

Must remain:

```text
1 canonical Occurrence contribution
+ Ledger scheduling overlay
  bookingState = confirmed
  Event Center Resource Claim = confirmed/exclusive
+ 1 independent Event Center occupancy contribution
```

The booking must not create another event identity.

### Incomplete occupancy control

`Soap Making with Katie Langenberg`

Must remain:

```text
canonical Occurrence contribution
+ Ledger scheduling overlay
  occupancyState = unclassified
+ 0 invented Resource Claim contributions
```

Unknown Resource occupancy must remain unknown.

## 15. Rollback-only conflict proof

A transaction-only acceptance fixture may establish a temporary active claim whose interval conflicts with an already-confirmed Resource occupancy while `p_allow_conflict=true` is used solely for the proof.

The adapter must then report:

```text
Resource Claim contribution
  standing = conflict
  sourceSnapshot.availability.available = false
  blockingClaims[] non-empty
```

The fixture must be rolled back and leave no claim row behind.

This proves conflict projection without mutating canonical production truth.

## 16. Rollback-only independent interval proof

A transaction-only claim may use an interval wider than its occurrence solely to prove that:

```text
occurrence coordinate remains canonical occurrence time
occupancy coordinate remains Resource Claim time
```

The composer must not widen the occurrence merely because occupancy is wider.

The fixture must be rolled back.

## 17. Non-collapse rules

### Ledger calendar binding != occurrence

It says why the occurrence belongs in this Ledger scheduling field.

### Booking != occurrence

It is a Ledger commitment around the occurrence.

### Booking != payment

Typed references may be shown, but money remains Commercial / Financial Reality truth.

### Resource Claim != occurrence

It is explicit occupancy and owns its own interval.

### Resource != Resource Claim

The capacity-bearing thing is not the act of occupying it.

### Occupancy != availability

Actual committed consumption is not ordinary schedule fitness.

### Conflict != cancellation

Conflict evidence does not silently alter source lifecycle.

### Scheduling overlay != canonical identity

It may enrich a contribution without replacing its sourceRef.

### Temporal contribution != persisted event

No contribution becomes a new calendar table row.

## 18. Implementation boundary

V1 should establish three read functions:

```text
atlas.ledger_scheduling_temporal_adapter_v1
atlas.ledger_temporal_composer_service_v1
atlas.ledger_temporal_composer_self_api_v1
```

No new tables or source columns are required.

The implementation should remain a read-only adapter/composer membrane over the already-live scheduling kernel.

## 19. Next boundary

After this adapter is live and proven, Reality/Ledger scheduling has a lawful Temporal Field voice for current occurrence meaning and active occupancy.

The next independent source adapter remains Company Work time contracts and planning conflicts.

Availability may later enter as its own Reality/Ledger temporal source because `availability != occupancy`; it should not be smuggled into this occupancy tranche merely because both mention Resources.
