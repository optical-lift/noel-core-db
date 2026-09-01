# Atlas Effective Position Authority v1

## Purpose

Atlas increasingly preserves durable source facts as an immutable base record plus append-only events that advance, supersede, cancel, release, or otherwise qualify that record.

That shape creates a system-level distinction that must remain explicit:

```text
birth/source evidence != effective current position
```

A base row may answer what was originally recorded. Once an authoritative transition event can change the operative meaning of that row, the base field is no longer a lawful general-purpose current-state reader.

This contract establishes one reusable rule:

> When a domain can advance state through append-only authority events, downstream decision, readiness, protection, conversion, and presentation consumers must read one canonical effective-position authority rather than reconstructing current state independently from the birth row.

This is a read-authority rule. It does not create new domain truth and does not replace the append-only source facts that establish that truth.

## Authority shape

```text
immutable source/birth record
+ authoritative transition / supersession events
+ cancellation / terminal facts where applicable
        |
        v
canonical effective-position projection
        |
        +--> domain conversion gates
        +--> Principal admission / withdrawal
        +--> inventory or resource protection
        +--> operational readiness
        +--> reporting / presentation
```

The projection is derived. The source record and its lawful events remain the evidence authority.

## Constitutional rule

Once an append-only transition is capable of changing a field's operative meaning:

1. The immutable source field remains valid as historical/birth evidence.
2. Mutation commands may inspect the source field when validating a transition from its recorded origin.
3. Materializers may intentionally create a source row already in a terminal or advanced birth state when that is the domain contract.
4. Current-state consumers must not treat the source field alone as effective state.
5. Current-state consumers must not each duplicate their own `CASE`, `EXISTS`, or event-precedence formula.
6. One canonical effective-position projection must own the read semantics.
7. All decision, conversion, protection, readiness, and presentation consumers must use that projection or an explicitly declared helper that delegates to the same semantics.
8. Effective-position projection must be side-effect free.
9. Projection failure or missing evidence must not be promoted into a stronger state.
10. The architecture truth-authority catalog must identify both the source facts and the effective read authority.

This rule prevents a domain from having two simultaneous answers to the question, "What state is this thing in now?"

## First proof: Flower Demand strength

Flower Demand now has exactly this shape.

Source facts:

- `atlas.flower_demand_orders.demand_strength` records the order's birth strength.
- `atlas.flower_demand_commitment_events` records an explicit requested -> committed acceptance without mutating the birth row.
- cancellation, allocation, Sale, fulfillment, Worker work, and payment remain separate authorities.

Effective strength therefore means:

```text
committed
  when the order was born committed
  OR a lawful commitment event advanced it to committed

otherwise
  the recorded birth strength
```

A commitment event does not reserve supply, create a Sale, create fulfillment work, schedule Worker time, or record payment.

### Consumers that must agree

The following Flower Demand consumers answer questions that depend on effective commitment rather than historical birth evidence and therefore must share one authority:

- Flower Demand line/current-position reads;
- Flower Demand coverage/current-position reads;
- canonical Demand -> Sale conversion readiness;
- Principal Sale-decision adapter;
- Principal Sale-decision admission firewall;
- Principal Sale-decision source-withdrawal/revalidation;
- inventory reality/protection expression for allocated demand.

The commitment transition command itself is a legitimate reader of birth state because it is validating and recording the transition. Standing-demand materialization is also allowed to create a row born `committed` when the standing-demand contract warrants that source fact.

## Current divergence this contract closes

At the time this contract was written, production had already advanced the canonical Demand -> Sale converter to honor `atlas.flower_demand_commitment_events`, while several Principal and inventory consumers still inspected `atlas.flower_demand_orders.demand_strength` directly.

That allowed a logically impossible split:

```text
canonical Sale authority: committed / executable
Principal governance:       requested / not executable
inventory protection:       requested semantics
```

No known production Flower Demand order had yet exercised requested-born -> committed-event state at the audit point, so this was a latent authority divergence rather than evidence of already-corrupted business rows. The repair is still required before that transition is relied upon operationally.

## Flower Demand target read authority

The implementation should establish one order-level effective-position projection for Flower Demand. Its exact SQL name is implementation-owned, but it must expose at least:

- canonical demand order identity;
- farm / organization custody needed by consumers;
- birth demand strength as historical evidence where useful;
- effective demand strength as the only general current-strength answer;
- cancellation/current-state facts needed to prevent consumers from reconstructing competing semantics.

Line and coverage projections should consume this order-level projection rather than repeat commitment-event precedence themselves.

Procedural consumers may use an exact helper only when it delegates to the same effective-position semantics; a helper must not become a second authority.

## Principal boundary

The Principal Decision Packet remains a projection contract, not Flower Demand truth authority.

Therefore:

```text
Flower Demand source facts
  -> Flower Demand effective position
  -> Flower Demand Sale-readiness facts
  -> explicit Principal escalation/admission
  -> Principal Decision Packet
  -> inert command descriptor
  -> canonical Demand -> Sale command
```

The Principal adapter, admission firewall, and source-withdrawal path must all agree on the same effective Flower Demand position. They may impose stricter Principal-admission conditions, but they may not downgrade or reinterpret source-domain state by reading an obsolete birth field.

## Inventory protection boundary

Reservation remains separate from commitment. Atlas may preserve an allocation even when demand was born requested.

When an allocation is reported or protected, however, the expression that describes its claim strength and displacement authority must use the demand's effective strength. Otherwise an explicitly committed order can remain mislabeled as requested and be assigned the wrong protection semantics.

This rule does not change allocation authority or require commitment before reservation. It only requires truthful reading of the commitment state that actually exists.

## Architecture catalog requirement

The executable repair must add Flower Demand effective strength to `atlas.architecture_truth_authorities` so future audits can answer cheaply:

> What owns the current strength of a Flower Demand order?

The catalog entry should distinguish:

- source facts: Flower Demand order + commitment events;
- canonical read authority: effective Flower Demand order position;
- lawful mutation authority: explicit commitment transition;
- downstream consumers: coverage, Sale conversion, Principal decision governance, inventory reality;
- known competitor: direct use of birth `flower_demand_orders.demand_strength` as current state.

The catalog is metadata only; it does not become the business authority itself.

## Verification contract

The executable implementation is incomplete unless it proves all of the following:

1. requested-born with no commitment event remains effectively requested;
2. requested-born with a lawful commitment event is effectively committed;
3. born-committed remains effectively committed;
4. cancellation remains separate from effective commitment strength;
5. Demand -> Sale uses the effective authority;
6. Principal adapter uses the effective authority;
7. Principal admission validation uses the effective authority;
8. Principal source withdrawal/revalidation uses the effective authority;
9. inventory reality/protection uses the effective authority;
10. line and coverage reads delegate to the same effective order projection;
11. no projection creates allocation, Sale, fulfillment, Worker, or payment truth;
12. direct raw-strength reads remain only where historical birth evidence or transition validation explicitly requires them.

## Broader reuse

Flower Demand is the first explicit proof of this rule, not a flower-only exception.

Any Atlas domain that adopts immutable source rows plus append-only state advancement must either:

- declare an existing canonical effective-position authority, or
- create one before multiple downstream consumers begin reconstructing state independently.

That keeps append-only custody from producing semantic forks as Atlas grows across organizations and domains.
