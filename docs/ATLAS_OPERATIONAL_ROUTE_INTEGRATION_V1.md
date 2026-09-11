# Atlas Operational Route Integration v1

## Purpose

Routes are a spatial execution carrier inside Atlas. They are not a parallel task system, CRM, responsibility model, planning system, or policy store.

The universal flow is:

**Reality / domain need → Company Work → responsibility → manager plan → route materialization (when spatial execution is needed) → Worker Day / execution authority → route and worker results → result acceptance → Company Work completion → domain / Organization Ledger**

A reusable route pattern sits beside that flow as execution configuration. It contains the reusable topology of a route, but it has no authority to create work, assign a person, choose a work day, invent a customer relationship, or declare a business procedure.

## Authority map

| Concern | Atlas authority | Route layer behavior |
| --- | --- | --- |
| Need for work | `atlas.work_items` / domain requirement | Route cannot create the need merely because a pattern exists. |
| Responsibility | `atlas.work_allocations` and organization accountability structures | Route does not own a default worker. |
| Manager scheduling | `atlas.work_execution_plans` | Company Work-backed route date and assignee are inherited from the active plan. |
| Reusable spatial topology | `atlas.operational_route_patterns` + `atlas.operational_route_pattern_stops` | Stores ordered reusable route shape only. |
| Concrete dated route | `atlas.operational_routes` + `atlas.operational_route_stops` | Execution truth for this run. |
| Customer/vendor/service-party relationship | `atlas.external_relationships` and its domain projections | Pattern and concrete stop may point to the relationship; they do not copy its authority. |
| Current commercial/service obligation | Domain record + `atlas.operational_route_bindings` | Bind to the concrete run when known; never freeze dynamic obligations into the reusable pattern. |
| Durable company procedure or policy | `atlas.company_operating_knowledge` | Route/pattern supplies resolution context; procedure remains governed Operating Knowledge. |
| Worker presentation and execution authority | Company Work planning / Worker Day / execution lease machinery | Route becomes one structured execution object presented inside the existing worker authority chain. |
| Execution history | `atlas.operational_route_events`, worker results, domain results | Append execution facts; route events do not silently create commercial or service truth. |

## Reusable pattern boundary

An operational route pattern may remember things that are genuinely reusable spatial structure:

- ordered stops;
- route kind;
- operating unit scope;
- a universal external relationship for a recurring stop;
- a routing locator snapshot such as an address;
- context tags used to resolve current Operating Knowledge.

It must not become the authority for:

- who is responsible for the work;
- what day a worker is scheduled;
- a buyer's current status, last purchase, contact history, or buying cadence;
- current inventory, order quantity, delivery obligation, or service requirement;
- organization policy or stop-specific selling procedure;
- completion of Company Work.

Patterns are versioned. A concrete route points to the exact pattern version from which it was materialized, while the route itself retains the execution snapshot needed for historical truth.

## Company Work seam

`atlas.materialize_operational_route_pattern_for_company_work_self_v1(...)` is the governed seam for the new reusable-route path.

Materialization requires:

1. an active reusable route pattern;
2. open Company Work in the same organization;
3. existing Company Work scheduling authority for the caller;
4. an active manager plan;
5. an active responsible allocation matching the plan.

The route inherits the manager plan's assignee and exposure service date. The route layer cannot override them. It records the exact Work item and execution-plan provenance used to create the run.

Legacy and externally sourced operational routes remain valid. `atlas.v_operational_route_execution_position_v1` distinguishes `company_work_backed`, `external`, and `legacy_direct` routes instead of pretending all historical routes were created under the newer Company Work flow.

## Relationship composition at a stop

A stop should be rendered from current truth rather than a stale copied route note.

For a relationship-backed stop, the worker-facing packet can compose:

1. the stop's route topology and locator;
2. current `external_relationships` / commercial relationship position;
3. current domain obligations through `operational_route_bindings`;
4. established Company Operating Knowledge resolved from organization, unit, route, and relationship context;
5. the concrete route's execution state and events.

This is how an Elm florist stop can show the latest buyer name, prior outcome, current order, and company-specific handling instruction without making the generic route library a florist CRM.

## Elm is a specimen, not architecture

Elm's rotating Springfield/Nixa/Ozark florist loops are a first real specimen of this model. The same route pattern layer must support service calls, inspections, pickups, deliveries, territory visits, maintenance rounds, and handoff routes without schema changes.

Elm-specific territory rules, sales handling practices, and buyer intelligence therefore remain data in their proper universal authorities. They are not encoded as universal route-schema assumptions.
