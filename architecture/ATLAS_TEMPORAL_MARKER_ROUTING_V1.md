# Atlas Temporal Marker Routing v1

## Purpose

Atlas must distinguish between:

1. a **thing** that exists,
2. an **occurrence** that happens in time, and
3. a **date or date range that itself carries meaning**.

A holiday, observance, blackout date, fiscal boundary, school break, season boundary, anniversary, deadline date, or "no programming" date must not be forced into the occurrence model merely because it appears on a calendar.

## Canonical temporal reality

Shared Intelligence owns canonical temporal markers in:

`local_intel.temporal_markers`

A temporal marker is date-native. It has a required `start_date`, optional inclusive `end_date`, marker kind, jurisdiction/scope metadata, provenance, and optional recurrence description.

A temporal marker does **not** require:

- host
- venue
- start time
- end time
- attendance
- registration
- occurrence status

Examples:

- Halloween 2026 — observance on 2026-10-31
- Thanksgiving 2026 — holiday on 2026-11-26
- Christmas 2026 — holiday on 2026-12-25

## Organization binding

An Atlas Organization that cares about a canonical temporal marker binds it through:

`atlas.organization_temporal_bindings`

This is analogous to `organization_occurrence_bindings`.

The binding does not copy the temporal marker. It records that this Organization is using/interpreting the canonical date marker.

## Purpose routing

`atlas.organization_purpose_context_memberships` supports three referent kinds:

- `external_relationship`
- `occurrence_binding`
- `temporal_binding`

Therefore the same Organization calendar context may lawfully contain both:

- things happening on dates, and
- dates carrying meaning even when nothing happens.

Example:

```text
Thanksgiving 2026
    canonical temporal marker
        ↓
Elm temporal binding
        ↓
community_calendar membership
        payload:
          holiday = true
          programmingClosure = true
          calendarNote = "No Thursday at Elm"
```

That is not an event cancellation masquerading as a holiday. The holiday exists independently as temporal reality; Elm's closure is Organization-owned interpretation.

## Core rule

```text
one temporal reality
        ↓
one canonical temporal marker
        ↓
one Organization temporal binding
        ↓
many Organization-owned uses
```

A calendar is therefore a projection across more than one reality class:

```text
occurrence bindings  ─┐
                      ├─→ calendar / timeline projection
temporal bindings   ──┘
```

## Non-goals

Temporal markers do not replace occurrences.

If a Christmas market happens on Christmas, Atlas represents:

- Christmas as a temporal marker, and
- the Christmas market as an occurrence.

The fact that they share a date does not merge their identities.

Likewise, a deadline may be modeled as a temporal marker even when there is no meeting or event at the deadline time.

## Initial Elm calendar use

The first canonical markers are:

- Halloween 2026
- Thanksgiving 2026
- Christmas 2026

Elm binds all three into `community_calendar`.

Thanksgiving carries an Elm-private calendar payload recording "No Thursday at Elm" / programming closure. Halloween and Christmas are date meaning only unless additional Organization-specific use is added later.
