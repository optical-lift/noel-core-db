# Production Current-State Recovery Observation Membrane v1

Candidate source for issue #909.

## Why this exists

The Rocket closed-loop specimen exposed a gap that normal execution adapters cannot solve safely:

- a historical Production task can be terminal while its structured biological result is missing;
- the old task cannot be reopened and replayed as if its historical result date were known;
- the downstream readiness task may never have been authored;
- present physical truth can nevertheless be observed now.

This membrane lets Atlas recover **present state from present evidence** without manufacturing the missing historical transition.

## V1 authority

The live recovery carrier already exists: the owner-led management task “Inspect + reclassify uncovered Grow Room propagation bodies.”

A lawful carrier must:
- be open/blocked;
- be explicitly owner reconciliation work;
- use the inspect_reconcile route;
- explicitly observe a crop cycle belonging to the target Production Lot.

V1 exposes an owner wrapper only. It does not infer Anna or any other worker responsibility.

## Supported current states

- seedling_care
- hardening
- transplant_ready
- failed

The command records an immutable production_lot_event with event_type=current_state_observed and preserves historicalTransitionDateInferred=false.

For hardening it projects:
- tray: hardening
- Production Lot: hardening
- crop cycle: hardening_off

It deliberately does **not** create hardening_start_date / hardening_started_date.

For transplant_ready / failed it also writes canonical production_readiness_observations. The readiness validator recognizes the governed recovery carrier and permits a new physical count to correct a stale prior viable-count projection.

After state projection, normal Production reconciliation runs. Existing crop-cycle triggers independently reconcile operation requirements.

## Boundary

This is not a historical backfill and not a new lifecycle engine.

It does not:
- alter the old task completion timestamp;
- create the missing old hardening/sowing result;
- infer a historical transition date;
- infer Worker responsibility;
- force recovery observations through the current schedule-oriented reforecast engine.

The later Rocket acceptance test still needs a general actual/state-delta → durable reforecast contract where material changes warrant it.
