# Atlas Reality Transition Receipt v1

**Status:** candidate projection contract  
**Date:** 2026-09-22  
**Parent law:** `architecture/atlas-reality-transition-protocol-v1.md`  
**Executable intent:** read-only composition only

## 1. Why this is now earned

The Reality Transition Protocol has been qualified against two structurally different live production domains:

### Company Work

`Execution Result → Result Acceptance → completed Work → Organization Ledger consequence`

### Commercial Financial Reality

`source-domain commercial truth → Commercial Order → Payment Event evidence → derived Financial Reality`

These are not the same workflow.

Company Work uses an explicit adjudication event before institutional completion becomes established.

Commercial Financial Reality derives current position from admitted transaction/payment evidence without an equivalent manager-acceptance step.

The shared architecture is therefore not “every domain has the same tables.”

The shared architecture is:

`source occurrence/evidence → domain-specific resolution → effective consequence → explainable continuation`.

That is sufficient to introduce a common read-only receipt grammar.

## 2. Receipt identity

A Reality Transition Receipt describes **one consequential transition**.

It is not:

- an object detail page;
- an event store;
- a workflow instance;
- a command envelope;
- a replacement for Claims/Evidence;
- a replacement for Operation Contract;
- a generic consequence store.

Each adapter owns its own source reads and renders them into the common receipt.

## 3. Contract

```json
{
  "contractVersion": "reality_transition_receipt_v1",
  "receiptKind": "domain_specific_transition_key",
  "source": {
    "domain": "...",
    "kind": "...",
    "ref": "...",
    "occurredAt": "..."
  },
  "subject": {
    "kind": "...",
    "ref": "...",
    "scope": {}
  },
  "interpretation": {
    "claimRefs": [],
    "proposedEffectRefs": [],
    "actualRefs": []
  },
  "resolution": {
    "state": "effective|rejected|unresolved|not_applicable",
    "resolver": "...",
    "basisRefs": [],
    "effectiveAt": "..."
  },
  "consequence": {
    "kind": "...",
    "ref": "...",
    "state": "..."
  },
  "execution": {},
  "continuation": {
    "reconsider": [],
    "blockers": []
  },
  "provenance": {}
}
```

Only `contractVersion`, `receiptKind`, `source`, `subject`, `resolution`, `continuation`, and `provenance` are universally required.

`interpretation`, `consequence`, and `execution` may be absent where the domain does not support them.

## 4. Normalizer boundary

`atlas.reality_transition_receipt_normalize_v1(jsonb)` validates and normalizes a domain-produced receipt.

It may verify:

- required object shape;
- required source/subject identity;
- allowed resolution states;
- array/object types;
- contract version.

It may not:

- query domain truth;
- infer authority;
- change a resolution;
- add a consequence;
- execute a command;
- persist the receipt.

The normalizer is schema law only.

## 5. First adapter: Company Work Result

`atlas.company_work_result_transition_receipt_v1(execution_result_id)`

Source transition:

```text
Work Execution Result
→ accepted/rejected/unresolved result adjudication
→ Work completion when accepted
→ established Organization Ledger consequence when projected
```

Important distinctions preserved:

- reported result is historical source reality;
- acceptance is a separate governed event;
- Work terminality is a separate current state;
- Ledger entry is a separate institutional consequence.

Resolution rules:

- accepted acceptance + established completion Ledger entry → `effective`;
- rejected acceptance → `rejected`;
- no acceptance → `unresolved`;
- accepted but expected completion consequence not yet present → `unresolved`.

The adapter does not decide the result.

## 6. Second adapter: Commercial Financial Position

`atlas.commercial_financial_transition_receipt_v1(commercial_order_id)`

Source transition:

```text
source-domain commercial truth
→ universal Commercial Order
→ Commercial Payment Event evidence
→ derived Commercial Financial Position
```

Resolution rules:

- `outside_canonical_custody` → `not_applicable`;
- `collection_unknown` → `unresolved`;
- `invariant_gap` → `unresolved`;
- all other derived Financial Reality states → `effective`.

The receipt preserves payment-event Actuals as evidence.

It does not collapse fulfillment into settlement.

A fulfilled order can still be financially open.
A paid order can exist without a fulfillment event.
Those are independent axes.

## 7. Continuation

Receipt continuation is advisory/read-only dependency information.

Company Work examples:

- unresolved result → reconsider result adjudication;
- accepted result without completion/Ledger consequence → reconsider completion/ledger projection;
- effective completion → no required transition continuation from this receipt.

Commercial examples:

- open / partially paid → reconsider collection/settlement;
- refund_due → reconsider refund resolution;
- collection_unknown / invariant_gap → reconsider financial reconciliation;
- paid / cancelled / not_required → no unresolved financial continuation.

Continuation does not run those actions.

## 8. Privacy / custody

V1 adapters are internal database functions.

No authenticated/anonymous browser execute grant is part of the candidate.

Later public/self reads require their own authority-specific membranes.

The common receipt must never become a route around:

- Organization/Ledger authority;
- communication privacy;
- Personal/Household privacy;
- domain-specific custody.

## 9. Runtime Proof

IMP-05 Runtime Proof may eventually consume these receipts.

A proof engine should ask the domain adapter for a receipt and inspect:

- resolution state;
- consequence;
- blockers;
- continuation;
- provenance.

It must not reimplement the domain resolver.

## 10. Promotion rule

Do not create generic transition storage.

Before migration promotion, clone proof must establish that:

1. the normalizer is read-only and fail-closed;
2. the Work adapter distinguishes report, acceptance, completion, and Ledger consequence;
3. the Commercial adapter derives rather than stores financial state;
4. Commercial payment events remain distinct from fulfillment;
5. neither adapter mutates source truth;
6. no browser role receives generic cross-domain read authority;
7. a third domain can later join by implementing the receipt grammar without changing either existing adapter.
