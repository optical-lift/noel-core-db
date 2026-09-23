# Atlas Combined Temporal Projection v1

## Purpose

Atlas calendars must render multiple kinds of time-bearing reality without pretending they are the same thing.

The combined temporal projection is a **read contract**, not a storage model.

It composes:

- canonical occurrences already routed into an Organization purpose context,
- canonical temporal markers already routed into that context,
- Organization recurrence instances whose recurrence rules are routed into that context.

## Projection item kinds

Every returned item has an explicit `itemType`:

- `occurrence`
- `temporal_marker`
- `recurrence_instance`

Consumers must branch on `itemType`. A holiday is not an event. A recurrence expectation is not an event. An occurrence remains canonical event reality.

## Recurrence display behavior

When a recurrence instance is cleanly realized by a canonical occurrence, the projection returns the recurrence instance with the canonical occurrence nested inside it and suppresses the duplicate standalone occurrence card.

When recurrence expectation and occurrence reality disagree, the recurrence instance has `realizationState='conflict'` and the projection returns **both**:

- the recurrence expectation at its effective schedule coordinate, and
- the standalone canonical occurrence at its actual coordinate.

That makes the conflict visible without rewriting either side.

Skipped/cancelled recurrence instances likewise remain recurrence items, with their linked exception and temporal marker visible.

Example:

```text
Nov. 26
├── temporal_marker: Thanksgiving
└── recurrence_instance: Thursdays at Elm Seasonal Evening
      scheduleState: skipped
      exception: Thanksgiving — No Thursday at Elm
      canonicalOccurrence:
        status: cancelled
```

## Purpose-context routing

Recurrence rules are Organization-private schedule law and can be routed into purpose contexts independently of occurrences or temporal markers.

`atlas.organization_purpose_context_memberships.member_kind` therefore supports:

- `external_relationship`
- `occurrence_binding`
- `temporal_binding`
- `recurrence_rule`

This preserves the same governing rule used elsewhere in Atlas:

```text
one reality / schedule law
        ↓
one Organization binding or rule
        ↓
many Organization-owned uses
```

A recurrence rule can therefore appear in one calendar context without globally becoming a calendar item for every Organization use.

## Date window and timezone

The combined projection accepts a local date window and a timezone.

If the caller does not provide a timezone, Atlas uses the Organization's current Membership calendar context timezone. Atlas does not invent a local timezone if neither source exists.

Temporal markers remain date-native. Occurrences are converted into the projection timezone only for windowing and sort-date purposes. Their canonical timestamps remain unchanged.

## Non-goals

The projection does not:

- create occurrences,
- generate recurrence instances,
- mutate exceptions,
- reconcile conflicts,
- turn temporal markers into events,
- turn recurrence expectations into canonical reality.

Those are separate governed operations.

## Initial Elm use

Elm's `community_calendar` receives both Thursdays-at-Elm recurrence rules:

- `thursdays_community_mornings`
- `thursdays_seasonal_evenings`

A combined read can therefore render ordinary community events, Halloween/Thanksgiving/Christmas date markers, recurrence expectations, the Thanksgiving skip, and any recurrence/occurrence conflicts in one chronological stream.
