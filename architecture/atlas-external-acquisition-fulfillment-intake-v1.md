# Atlas External Acquisition Fulfillment Intake v1

**Status:** universal candidate authority  
**Date:** 2026-09-24  
**Parent:** `architecture/atlas-external-acquisition-commitment-v1.md`

## Purpose

External Acquisition Commitment answers what the institution has committed to acquire.

The missing next authority answers:

> What did the external supplier actually deliver or perform against that commitment, when, in what quantity and condition, what portion was accepted, rejected, or unresolved, and which Company Work Requirements does accepted output now secure?

This authority is External Acquisition Fulfillment Intake.

It handles both physical delivery and external service performance without creating a generic inventory system.

## Governing separation

External Acquisition Commitment is not External Acquisition Fulfillment.

External Acquisition Fulfillment is not inventory.

External Acquisition Fulfillment is not Organization Spend.

External Acquisition Fulfillment is not internal Company Work execution.

Accepted supplier output may later feed inventory, direct fulfillment, work-result evidence, or another domain adapter.

The intake owns only what actually crossed the external supplier fulfillment boundary.

## Canonical structure

External Acquisition Fulfillment
- Fulfillment Lines
- Accepted Requirement Allocations

A Fulfillment records one real supplier delivery/performance occurrence against one External Acquisition Commitment.

A Fulfillment Line records actual output against one acquisition commitment line.

An Accepted Requirement Allocation records how much accepted output from that real fulfillment is now assigned to one prior External Acquisition Requirement Allocation.

## Partial fulfillment is first-class

One acquisition commitment may be fulfilled in several occurrences.

Example:

Commitment allocation:
- Buyer A: 40 stems

First supplier delivery:
- 20 accepted stems allocated to Buyer A

Current coverage becomes:
- 20 secured by accepted fulfillment
- 20 still secured by the outstanding supplier commitment

Total current coverage remains exactly 40.

No double-counting and no handoff gap.

## Source quantity and coverage-output quantity

A fulfillment line can preserve both supplier/source quantity and evaluated coverage output.

Examples:
- source quantity: 1 case
- delivered coverage output: 100 stems

or:
- source quantity: 1 service visit
- delivered coverage output: 16 labor_hours

The source quantity/unit pair is optional.

Delivered output always uses the parent commitment line's coverage-output unit.

Core never invents a source-to-output conversion.

## Condition and disposition quantities

Every fulfillment line records:

- deliveredOutputQuantity;
- acceptedOutputQuantity;
- rejectedOutputQuantity;
- unresolvedOutputQuantity;
- coverageOutputUnit;
- condition/details object.

Invariant:

accepted + rejected + unresolved = delivered

All quantities are nonnegative.

Delivered quantity must be positive.

This supports:
- all accepted;
- all rejected;
- pending inspection;
- mixed condition.

Actual overdelivery is not blocked. Reality may exceed the planned commitment. Overdelivery is surfaced explicitly instead of silently capped.

## Accepted requirement allocations

Only accepted output can be allocated to Company Work coverage.

Each fulfillment allocation references one immutable External Acquisition Requirement Allocation from the same acquisition commitment.

Rules:
1. Allocation quantity > 0.
2. Unit equals fulfillment line output unit.
3. Total fulfillment allocations cannot exceed accepted output.
4. Cumulative fulfilled quantity against one commitment allocation cannot exceed that commitment allocation quantity in v1.
5. The associated Company Work Requirement remains the same requirement established by the commitment allocation.

Accepted excess may remain unallocated.

That excess remains real accepted source output and can later be handed into inventory/disposition truth.

## Coverage transfer law

For each External Acquisition Requirement Allocation with committed quantity Q:

acceptedFulfillmentQuantity = sum accepted fulfillment allocations tied to it

remainingSupplierCommitmentQuantity =
max(Q - acceptedFulfillmentQuantity, 0)

While the acquisition remains active:

- acceptedFulfillmentQuantity emits secured coverage from External Acquisition Fulfillment;
- remainingSupplierCommitmentQuantity emits secured coverage from External Acquisition Commitment.

If the acquisition is cancelled:

- accepted fulfillment coverage remains secured;
- remaining supplier commitment becomes released.

This means cancellation after partial delivery does not erase goods/services already accepted.

## Commitment state becomes derived from fulfillment

V1 no longer uses a free-standing received lifecycle event.

Supplier fulfillment is established only by External Acquisition Fulfillment records.

The commitment position derives:
- committed;
- partially_fulfilled;
- fulfillment_unresolved;
- fulfilled_with_exception;
- fulfilled;
- cancelled;
- closed.

A cancelled commitment may still contain previously accepted fulfillment.

A fulfillment with rejected output may be complete as a delivery occurrence but still carry an exception.

## Lifecycle events

External Acquisition Commitment events are narrowed to:
- cancelled;
- closed.

Allowed transitions:
- any open acquisition -> cancelled;
- cancelled -> closed;
- fulfilled -> closed;
- fulfilled_with_exception -> closed.

A commitment with unresolved fulfillment cannot close.

There is no separate received event in v1 because that truth now belongs to Fulfillment Intake.

## Idempotency and immutability

Each fulfillment has one organization-scoped fulfillmentKey under its acquisition commitment.

The service stores a structural SHA-256.

Same key + same packet returns the same fulfillment.

Same key + different packet conflicts.

Fulfillment, fulfillment lines, and accepted allocations are immutable.

Later correction or disposition requires later source truth rather than history rewriting.

## Physical-goods example

Committed supplier line:
- 100 stems coverage output
- 90 stems allocated to customer Work Requirements

Two fulfillment occurrences:

First:
- 50 delivered
- 48 accepted
- 2 rejected
- 48 allocated to customer requirements

Second:
- 50 delivered
- 47 accepted
- 3 rejected
- 42 allocated to remaining customer requirements

Final source position:
- 100 delivered
- 95 accepted
- 5 rejected
- 0 unresolved
- 90 accepted output allocated to customer Work Requirements
- 5 accepted output unallocated
- 5 rejected output

The 5 accepted excess can later become inventory or other disposition truth.

The 5 rejected units do not become inventory.

## External-service example

Committed external service:
- 16 labor_hours

Fulfillment:
- 16 delivered labor_hours
- 16 accepted
- 0 rejected
- 0 unresolved
- 16 allocated to the associated Company Work Requirement

Same authority.

No flower vocabulary.

## Relationship to inventory

Fulfillment Intake does not create inventory.

For physical goods, a domain adapter may later consume accepted unallocated or accepted allocated output and establish:
- ready inventory;
- raw inventory;
- direct cross-dock custody;
- preparation input;
- another domain-specific resource.

Existing flower_external_intakes / flower_ready_inventory_lots remain flower-owned source truth.

The universal authority must not replace those tables with a generic inventory table.

## Relationship to external service results

Accepted external service performance may later support:
- Work Requirement satisfaction;
- Work Execution Result evidence;
- customer deliverable completion;
- other domain-specific outcome truth.

Fulfillment Intake itself does not close Company Work.

## Candidate functions

- `atlas.external_acquisition_fulfillment_preview_v1(jsonb)`
- `atlas.record_external_acquisition_fulfillment_service_v1(jsonb)`
- `atlas.external_acquisition_fulfillment_position_v1(uuid)`
- revised `atlas.external_acquisition_commitment_position_v1(uuid)`
- revised `atlas.external_acquisition_commitment_coverage_facts_v1(uuid)`

The fulfillment writer is consequential source recording:
- internal service only;
- SECURITY DEFINER with fixed search_path;
- browser roles denied;
- service_role may call writer but may not insert fulfillment tables directly.

## Required validation

V1 must prove:
1. fulfillment belongs to one acquisition commitment;
2. fulfillment line belongs to one commitment line;
3. occurredAt cannot predate commitment;
4. accepted + rejected + unresolved = delivered;
5. output unit matches commitment line output unit;
6. actual overdelivery is preserved, not capped;
7. accepted allocations cannot exceed accepted output;
8. cumulative accepted allocation cannot exceed original commitment allocation;
9. partial fulfillment splits coverage into accepted-source + remaining-commitment without double counting;
10. cancellation after partial fulfillment keeps accepted coverage and releases only residual commitment coverage;
11. full fulfillment transfers all allocated coverage from commitment to fulfillment source;
12. accepted excess remains explicit and unallocated;
13. rejected output never becomes secured coverage;
14. unresolved output remains explicit;
15. same-key idempotency and conflict detection;
16. fulfillment history is immutable;
17. no automatic Spend, payment, inventory, Commercial Order, or Work Requirement mutation;
18. external service performance uses the same authority;
19. browser roles cannot call writer or insert tables directly.

## Governing movement

External Acquisition Commitment
-> supplier delivers/performs
-> External Acquisition Fulfillment Intake
-> accepted output becomes source-owned coverage
-> residual commitment coverage shrinks
-> accepted excess remains explicit
-> downstream inventory / direct fulfillment / work-result adapters
-> Organization Spend remains separate when outlay occurs

The handoff is quantitative, partial, and lossless.
