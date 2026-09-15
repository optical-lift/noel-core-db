# Atlas Commercial Financial Reality v1

## Status

Package 5 hybrid candidate built from exact `noel-core-db/main` base:

`d10b7efed09e3bd24d10a96ce650249a74a06dee`

Canonical migration identity generated with pinned Supabase CLI v2.116.0:

`20260915224342_atlas_commercial_financial_reality_v1.sql`

This candidate is not merged or released.

## Governing decision

Package 5 does **not** introduce a parallel Money Collection graph yet.

Current Atlas already has a universal commerce layer:

```text
domain commercial truth
  -> Commercial Order
  -> Commercial Payment
  -> Commercial Payment Event
  -> derived Financial Reality
```

The following distinctions remain canonical:

```text
price / commercial commitment
!= payment evidence
!= refund / reversal evidence
!= fulfillment
!= bank settlement
```

A separate obligation authority remains available later only if real business cases prove that a Commercial Order's committed amount and the collectible obligation must diverge.

## Why this supersedes the executable direction of PR #304

PR #304 identified real distinctions between what is owed, attempted collection, received money, allocation, and refund. But current Atlas changed substantially after that branch was designed:

- universal `commercial_orders`, `commercial_payments`, and payment events are live;
- Community Registration is already bridged into universal commerce;
- historical Elm Flower Sales are already bridged into universal commerce;
- current Package 4 Flower Sale v2 is live and must not be overwritten;
- current institutional truth is Ledger-custodied and may differ from physical historical Organization ids;
- Waiting Room is explicitly archived test scope.

Creating `money_obligations`, `money_receipts`, and receipt-allocation rows now would duplicate present commercial/payment truth before Atlas has encountered a real case that requires the extra layer.

The old PR remains architectural source material, not a release candidate.

## Source domains remain authoritative

Flower owns:

- whether a Sale exists;
- Sale lines and prices;
- tax/tip;
- cancellation;
- fulfillment.

Community Registration owns:

- whether a Registration exists;
- offering fee/currency;
- Registration status;
- legacy Registration payment evidence.

The universal commerce layer owns the common commercial/payment representation used for Financial Reality. It does not replace either source domain.

## Forward synchronization

### Flower

A new Flower Sale consequence creates a universal Commercial Order only when the Sale's farm resolves to canonical Organization + Ledger custody.

The Sale row remains the source transaction. Package 5 does not replace `record_flower_sale_core_v2`.

Flower cancellation appends a Commercial Order cancellation event. Cancellation does not fabricate a payment refund and does not alter fulfillment history.

Flower line detail stays authoritative in the Flower domain in this tranche. Financial Reality requires the committed Sale total, not a second line-level product model.

### Community Registration

A new Registration creates a universal Commercial Order when its farm resolves to canonical Organization + Ledger custody.

A Registration payment creates/reuses a universal Commercial Payment and appends payment evidence:

- `paid` -> succeeded amount;
- `refunded` with a known timestamp -> full negative refund evidence;
- `partially_refunded` without an amount -> explicit unresolved evidence, never an invented amount;
- ambiguous paid/refunded states without required timestamps -> explicit invariant gap evidence.

Existing Registration/commercial bridges remain immutable and are reused.

## Historical coverage

Package 5 must not convert every historical Commercial Order with no Payment row into a current receivable.

Current production contains historical Elm Flower Commercial Orders whose collection outcome is not represented in Atlas. Their Financial Reality is therefore:

`collection_unknown`

not:

`open`

Orders born through the new governed Flower/Registration synchronization carry `financialRealityCoverage = governed_from_order_birth` and may derive an `open` position when no payment evidence exists.

Historical orders that do have admitted payment evidence may derive a paid/refunded position from that evidence.

## Test boundary

Waiting Room Farm is adjudicated `archived` with basis `waiting_room_test_scope` and no canonical Organization/Ledger target.

Therefore the Package 4 `$12.34` proof Sale remains valid test-domain evidence but does not produce a canonical Commercial Order or Financial Reality position.

The rule is structural:

> Source reality must resolve to canonical Ledger custody before a commercial consequence may participate in canonical Financial Reality.

No downstream `testMode` metadata is required to make that decision.

## Derived Financial Reality

`atlas.commercial_financial_position_v1` derives per Commercial Order:

- committed amount;
- gross collected amount;
- returned amount;
- net collected amount;
- open amount when coverage is known;
- overpaid amount;
- payment count/timing;
- effective Organization/Ledger custody;
- coverage basis;
- financial state.

Current states are derived rather than stored as a competing mutable clock:

- `outside_canonical_custody`
- `not_required`
- `collection_unknown`
- `open`
- `partially_paid`
- `paid`
- `overpaid`
- `cancelled`
- `refund_due`
- `invariant_gap`

Historical collection uncertainty produces `open_amount = null`, not a fabricated receivable balance.

## Read boundary

`atlas.commercial_financial_position_self_api_v1(ledger_id)` is the only authenticated browser surface introduced by this tranche.

It requires:

- an authenticated user;
- a current canonical Principal;
- active root authority over the requested Ledger.

Direct authenticated/anonymous access to the underlying view remains revoked.

No payment mutation/provider API is exposed by this tranche.

## Provider boundary

Stripe, Square, banks, and accounting systems remain evidence carriers.

Existing historical Stripe identifiers on Registration payments remain evidence. Package 5 does not manufacture retroactive Connected Source custody for them.

Future provider ingestion must use current Connected Sources and Financial Reality reconciliation rather than allowing provider state to directly mutate source-domain truth.

## Package 5 sequence after this tranche

```text
Commercial Financial Reality
  -> provider-neutral external Financial Reality / Economic Events
  -> organization Spend
  -> reporting contract
  -> provider adapters / reconciliation
  -> Atlas financial notebook surfaces
```

PR #312, #464, and #466 remain source material to replay against the then-current main in that order; they are not safe to merge wholesale from their old bases.

## Release gates

The exact candidate must pass:

1. Database Custody CI;
2. production-schema clone validation against the live schema;
3. proof that archived test Sale creates no canonical commercial consequence;
4. proof that historical bridged Flower collection remains unknown rather than open;
5. proof that paid Registration evidence derives paid Financial Reality;
6. proof that a post-cutover governed Sale synchronizes and derives open state;
7. proof that cancellation changes the financial position without inventing a refund;
8. proof that Package 4 Flower v2 remains unchanged;
9. privilege and Ledger-authority checks;
10. advisors/lint with no unreviewed regression.

Only after those gates may the migration merge and enter the separate protected production release lane.
