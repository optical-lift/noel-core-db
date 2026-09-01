# Atlas Principal Decision Packet v1

## Purpose

Atlas needs one reusable way to answer a narrow question across every domain:

> Has an unresolved source condition actually earned the Principal's attention, and if so, what canonical decision is being asked of them?

The answer cannot be inferred from a task being unfinished, a date existing, a demand being allocated, or a notebook card being visible.

The Principal Decision Packet is a **projection contract**, not a new source-of-truth system.

## Existing authorities remain separate

```text
canonical domain truth
  -> explicit authority / threshold / consequence evidence
  -> Principal Decision Packet evaluator
  -> Principal projection
  -> optional canonical command descriptor
  -> domain-owned command
  -> canonical domain resolution
```

Existing Atlas systems keep their current jobs:

- **Company Work** owns what an organization owes.
- **Allocation** owns who is responsible for Company Work.
- **Operational Escalation** can preserve explicit evidence that delegated operational reality crossed into Principal jurisdiction.
- **Commitment Ledger** preserves plans Atlas has committed to a human. It is not a decision queue.
- **Clock** arbitrates temporal attention among already-warranted claims. It does not make the underlying condition true and does not create Principal authority.
- **Journal / notebook spreads** are projections over canonical facts. They do not resolve source truth by themselves.

## Generic packet contract

A domain adapter supplies a packet with independent identities for:

1. `principalId` — which Principal projection is in question.
2. `scope` — custody/context, such as person, household, organization, or portfolio unit.
3. `source` — canonical domain/kind/id and optional current source state.
4. `authority` — whether Principal responsibility is actually established and on what basis.
5. `admission` — explicit right-to-floor evidence, consequence, and reason.
6. `resolution` — source-derived `unresolved`, `resolved`, or `unknown` state.
7. `decision` — the decision kind, prompt, options, and optional opaque command descriptor.
8. `timing` — only timing independently warranted by the source/admission layer.

The evaluator returns one of four states:

- `candidate` — Principal responsibility, admission, unresolved source state, and translation are all established.
- `contained` — the source remains real but has not earned Principal admission.
- `resolved` — canonical source truth says the decision is no longer outstanding.
- `translation_required` — Atlas lacks source identity, resolution certainty, admission certainty, or sufficient Principal-language translation.

Unknown never silently becomes unresolved. Unresolved never silently becomes Principal work.

## Candidate identity

Candidate identity is deterministic from:

```text
source domain
+ source kind
+ source id
+ decision kind
```

A second projection of the same unresolved decision therefore does not mint a second logical Principal decision.

The candidate key is a projection identity, not a substitute for the canonical source identifier.

## Command boundary

A packet may expose an opaque command descriptor:

```json
{
  "kind": "domain_command_key",
  "contractVersion": "canonical_domain_command_v1",
  "targetKind": "canonical_source_kind",
  "targetId": "canonical-source-id"
}
```

The generic evaluator never executes it.

The application/domain adapter maps that descriptor to the same governed command used by management or other authorized surfaces. This prevents a Principal UI from creating a second mutation path.

Idempotency remains the responsibility of the canonical domain command.

## Resolution boundary

A Principal card does not own a mutable `done` bit for the underlying decision.

Resolution must come back from canonical source truth. If a manager resolves the source from another surface, the Principal projection must resolve from that same source fact. A stale Principal card may still be clicked, but the canonical command must deduplicate safely.

## First proof: Flower Demand -> Sale

The first adapter is deliberately domain-specific beneath the generic evaluator:

```text
Flower Demand order
  -> committed demand
  -> fully covered by active allocations
  -> established line prices
  -> explicit Principal operational escalation
  -> generic Principal Decision Packet
  -> command descriptor: flower_demand_commit_to_sale
  -> canonical record_flower_sale_from_demand_core_v1
  -> flower_demand_sale_order_link
  -> Principal escalation resolves from canonical Sale linkage
```

The adapter refuses to emit a Sale-commitment candidate when:

- no explicit Principal escalation exists;
- the demand is not committed;
- coverage is not complete;
- prices are not established;
- the demand is cancelled;
- the canonical Sale already exists.

This means ordinary allocated demand remains in management/operations. Allocation alone does not put anything on the Principal's floor.

The adapter does not duplicate buyer, allocation, Sale, fulfillment, or payment authority. Its command descriptor points at `record_flower_sale_from_demand_core_v1`, which already enforces owner/manager authority, atomic allocation release, durable allocation -> demand line/order -> Sale lineage, and idempotent reuse of an existing active Sale.

## Constitutional constraints

1. Domain facts remain domain-owned.
2. An unresolved fact is not automatically Principal work.
3. Principal admission must be explicitly warranted.
4. Missing admission or resolution evidence remains unknown/contained.
5. A Principal projection never creates Company Work, Allocation, Sale, fulfillment, payment, or Commitment Ledger truth merely by being visible.
6. Clock placement never establishes authority or source truth.
7. Command descriptors are inert; canonical domain commands remain mutation authority.
8. Resolution returns from canonical source truth.
9. Deterministic candidate identity prevents one source decision from becoming multiple logical Principal decisions.
10. Domain adapters may add vocabulary, but they may not weaken the generic truth boundary.
