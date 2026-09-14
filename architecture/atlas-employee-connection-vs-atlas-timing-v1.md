# Atlas Employee Connection vs Atlas Timing v1

## Status

Architecture contract only. No schema, migration, timer runtime, payroll system, employee time clock, or production behavior is created by this document.

## Governing distinction

**An employee connection is an access/commercial relationship to institutional reality. Timing is an Atlas capability of the Person. Employment does not create a timer.**

Therefore:

```text
employee connection
  -> may admit the Person to the institution's Ledger projection
  -> may expose work the Person carries
  -> may permit work reports and completion reports
  -> may carry required structured result evidence

employee connection
  -/-> Start/Stop timer
  -/-> active-attention clock
  -/-> timesheet
  -/-> payroll clock
  -/-> automatic duration measurement
```

A scheduled time such as `Deliver harvest at 1:00 PM` is part of the work definition and may appear in an employee projection. It is not a timer and does not imply time tracking.

## Employee Worker Day

An employee-facing Worker Day may support effects concerning the work the Person actually carries, including:

```text
Done / completion report
Reopen a completion report when the governing work contract permits it
report unscheduled work actually performed
submit structured completion/result evidence required by the work
```

These are work-state and evidence effects. They do not require a Start/Stop clock.

The employee projection should therefore not be modeled as:

```text
employee seat -> Start -> Stop -> elapsed time -> Done
```

It should be modeled as:

```text
Person + institution relationship + current responsibility
        ↓
work appears in the Person-specific institutional projection
        ↓
Person performs work in reality
        ↓
Person may report completion / result evidence
        ↓
Atlas resolves the report against the governing work reality
```

## Atlas timing capability

Atlas may separately support execution timing, focus sessions, elapsed-time observation, active-attention state, or other temporal instrumentation.

That capability belongs to Atlas and the Person's use of Atlas. It is not conferred by an employee seat, employment affiliation, employer payment, or organization connection.

If a Person chooses to use Atlas timing while carrying institutional work, the timing event remains an Atlas/Person event that may reference the same work. The institutional employee relationship does not become the source of the timing capability.

Conceptually:

```text
Person uses Atlas timing
        ↓
Atlas timing event references work W
        ↓
W may happen to be Elm work carried by that Person
```

not:

```text
Elm employee seat
        ↓
Elm gains a timer over the Person
```

## Employer visibility does not follow automatically

The existence of Atlas timing data does not imply that an employer can see it.

Any projection of timing data into institutional reality requires its own governed visibility, custody, purpose, and effect conditions. Employment alone is insufficient.

This prevents a personal Atlas capability from silently becoming employee surveillance or a payroll/timekeeping system.

## Relationship to employee-seat architecture

This contract sharpens the existing rule that seat, credential, connection, and entitlement are access/commercial/runtime mechanics rather than institutional ontology.

Employee connection remains distinct from:

```text
responsibility
visibility
institutional source
completion evidence
resource custody
timing
```

A connection may enable entry into an institution's Ledger. It does not create any of those facts by itself.

## `/anna` implication

The employee-facing `/anna` projection should expose the work Anna carries, scheduled work times that are part of the work definition, completion/reporting affordances, and required result evidence.

It should not expose Start/Stop or behave as a time clock merely because Anna is connected to Elm as an employee.

If Anna separately uses Atlas timing, that is an Atlas capability associated with Anna the Person, not an Elm employee-seat feature.

## Resulting law

> Employee connection answers, "Which institutional reality can this Person enter and participate in?" Atlas timing answers, "Is this Person using Atlas to observe or structure time around something they are doing?" The first must never imply the second.