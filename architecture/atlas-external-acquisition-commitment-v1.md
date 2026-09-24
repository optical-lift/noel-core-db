# Atlas External Acquisition Commitment v1

**Status:** universal candidate authority  
**Date:** 2026-09-24  
**Parents:** external supply offer, pooled fulfillment, Company Work coverage

## Purpose

Atlas already has sell-side Commercial Orders and occurred Organization Spend. It does not yet have a universal authority for this question:

> What has this organization actually committed to acquire from an external supplier, on what accepted terms, for what financial obligation, and which Company Work requirements does that commitment secure?

That missing authority is External Acquisition Commitment.

## Governing separation

Supplier quote is not acquisition commitment.

Acquisition commitment is not Spend.

Acquisition commitment is not received inventory.

Planned pooled share is not secured requirement coverage.

The authority begins only when the institution has actually committed to the external acquisition.

## Canonical source-owned structure

External Acquisition Commitment
- Commitment Lines
- Requirement Allocations
- Commitment Events

The commitment owns organization scope, supplier relationship, commitment identity, commitment occurrence time, expected external-fulfillment window, accepted terms, financial-obligation position, source evidence, and authorization basis.

A line owns supplier offering identity, accepted supplier line identity, ordered source quantity/unit, planned coverage-output quantity/unit, known line amount when known, and line terms.

A requirement allocation owns how much of one committed external line secures one existing Company Work Requirement. This is external-acquisition source truth, not a generic Atlas coverage row.

Events own append-only lifecycle changes such as cancelled, received, and closed.

V1 does not model partial receipt.

## Not Commercial Order

Production commercial_orders is explicitly the universal commercial commitment/sale record and carries customer meaning. External acquisition is the inverse direction: the Organization commits to a supplier, the supplier owes goods/services to the Organization, and the Organization incurs a financial obligation.

Do not overload sell-side semantics.

## Not Organization Spend

Production organization_spend_occurrences is explicitly canonical gross outlay occurrence.

A supplier commitment can exist before card settlement, ACH payment, invoice payment, reimbursement, or any other outlay.

Therefore supplier commitment today and payment next week must create External Acquisition Commitment today and Spend only when the outlay actually occurs.

V1 creates no Spend automatically.

## Supplier custody

Every commitment belongs to one existing external relationship carrying an active supplier role in the same organization/unit scope.

Every line references one durable external supplier offering belonging to that supplier relationship.

An accepted supplier observation may also be referenced when one supplied the accepted terms.

## Financial-obligation position

V1 distinguishes:

- known: full committed financial obligation is known;
- partially_known: a known committed portion exists but one or more required cost components remain unresolved;
- unresolved: no numeric financial obligation can yet be lawfully asserted.

Known and partially-known economics require a nonnegative knownCommittedAmount and currency.

Unresolved economics require knownCommittedAmount to be absent. Currency may still be known.

Unknown never becomes zero.

Accepted cost components remain commitment evidence; they are not the Spend ledger.

## Source quantity versus coverage output

A supplier can commit in one unit while Atlas covers requirements in another.

Examples:
- ordered 1 case, coverage output 100 stems;
- ordered 1 pallet, coverage output 100 boxes.

Each line preserves ordered source quantity/unit and coverage-output quantity/unit. The transformation basis belongs to line metadata/terms. Core does not invent it.

## Requirement allocations

Each allocation references one commitment line and one active quantified Company Work Requirement.

Rules:
1. Same organization scope.
2. Requirement must be active.
3. Allocation unit must equal Work Requirement unit.
4. Allocation unit must equal line coverage-output unit.
5. Quantity must be positive.
6. Total line allocations cannot exceed line coverage-output quantity.
7. One allocation cannot exceed the Work Requirement total quantity.
8. One Work Requirement appears at most once per commitment line in v1.

Existing secured coverage from other domains remains separately visible through universal coverage position.

## Authorization basis

Creating a supplier commitment is consequential.

V1 requires an explicit authorizationBasis object with:
- authorityRef;
- decisionRef;
- authorizedAt.

These are opaque references because purchasing authority varies by institution. Core requires the boundary; it does not invent the authority holder.

## Time

committedAt is the real-world time the institution became committed, not database insertion time.

Expected external fulfillment uses expectedFulfillmentFromAt and expectedFulfillmentByAt. For goods this can mean receipt; for services it can mean performance.

## Immutability and idempotency

Commitment, lines, allocations, and events are append-only/immutable.

One organization-scoped commitmentKey identifies one acquisition.

Same key plus same structural packet returns the same commitment.

Same key plus different structural packet conflicts.

## Lifecycle

Initial state is committed.

Allowed transitions:
- committed -> cancelled
- committed -> received
- cancelled -> closed
- received -> closed

No transition follows closed.

V1 received means the whole acquisition crossed the external receipt/performance boundary.

## Coverage adapter

Committed allocations emit normalized secured coverage facts.

Cancelled allocations emit released coverage facts.

Received allocations emit unresolved coverage facts with a handoff-required marker. Current coverage must then come from receiving/inventory/performance truth, which avoids double-counting supplier commitment and received assets as two resources.

Closed follows the substantive terminal event: cancelled remains released; received remains handoff-required.

## Pooled wholesale proof

Three Work Requirements require 40, 30, and 20 units.

One authorized supplier commitment orders a 100-unit source pool and records three requirement allocations: 40, 30, and 20.

Those 90 units become secured source coverage.

The remaining 10 units remain unallocated acquisition output and later move into receiving/inventory/excess-disposition truth.

## Financial proof

A known $38 supplier commitment means the Organization is financially committed for $38.

It does not mean Organization Spend has occurred.

## Candidate functions

- atlas.external_acquisition_commitment_preview_v1(jsonb): read-only validation.
- atlas.record_external_acquisition_commitment_service_v1(jsonb): immutable service writer.
- atlas.external_acquisition_commitment_position_v1(uuid): current read-only lifecycle/economic position.
- atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb): append-only lifecycle event.
- atlas.external_acquisition_commitment_coverage_facts_v1(uuid): normalized Company Work coverage adapter.

## No implicit downstream effects

Recording an acquisition commitment creates no Spend, payment, owned inventory, receiving record, Commercial Order, sell-side offer, Work Requirement, Work Item, or supplier-portal action.

The service records the commitment after an authorized external action or source-backed confirmation has made it real.

## Architecture truth authority

Canonical question:

> What external acquisition has this organization actually committed to, on what accepted terms, for what financial obligation, and which Company Work requirements does it currently secure?

Canonical relations:
- atlas.external_acquisition_commitments
- atlas.external_acquisition_commitment_lines
- atlas.external_acquisition_requirement_allocations
- atlas.external_acquisition_commitment_events

Supplier observations, Commercial Orders, Organization Spend, inventory, production reservations, and work allocations remain separate authorities.

## Required validation

V1 must prove supplier-role/scope enforcement, offering and observation custody, mandatory authorization basis, source-backed commitment time, known/partial/unresolved economics, idempotency/conflict behavior, 40/30/20 allocation from one 100-unit commitment, explicit 10-unit remainder, allocation caps and unit matching, no cross-organization allocation, no Spend/inventory/payment/order/work side effects, secured/released/receipt-handoff coverage states, lifecycle enforcement, immutability, browser-role denial, and a non-flower leak test.

## Governing movement

supplier terms observed
-> candidate qualification
-> pooled/ordinary planning
-> governed decision
-> authorized external action
-> External Acquisition Commitment
-> source-owned Requirement Allocations
-> secured Company Work coverage
-> later receipt/performance handoff
-> later Spend when outlay occurs

Planning no longer pretends to be purchasing, and purchasing no longer pretends to be Spend.


---

## Fulfillment refinement — 2026-09-24

The later External Acquisition Fulfillment Intake authority refines this contract.

The coarse V1 lifecycle idea:

`received`

is retired as a free-standing acquisition event.

Actual receipt/performance now belongs to source-owned fulfillment records:

- `atlas.external_acquisition_fulfillments`;
- `atlas.external_acquisition_fulfillment_lines`;
- `atlas.external_acquisition_fulfillment_allocations`.

The acquisition lifecycle event writer is therefore narrowed to:

- `cancelled`;
- `closed`.

Current coverage transfers quantitatively.

For one committed requirement allocation of 40 units:

~~~text
20 accepted through actual fulfillment
+
20 still outstanding under supplier commitment
=
40 secured
~~~

When the remaining 20 are later accepted:

~~~text
40 accepted fulfillment coverage
+
0 residual supplier commitment
=
40 secured
~~~

If the commitment is cancelled after only 20 are accepted:

~~~text
20 accepted fulfillment coverage
+
20 released supplier commitment
=
20 currently secured
~~~

This is the governing handoff law.

Cancellation does not erase accepted reality.

Receipt/performance does not create inventory.

A fulfilled acquisition may close only after actual fulfillment records establish the fitting state.
